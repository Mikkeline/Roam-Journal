import Foundation
import CloudKit
import CryptoKit

enum CloudBuild {
    static var available: Bool { Bundle.main.object(forInfoDictionaryKey: "RoamCloudBuildEnabled") as? Bool == true }
    static var identifier: String? { available ? Bundle.main.object(forInfoDictionaryKey: "RoamCloudContainerIdentifier") as? String : nil }
}
struct CloudSyncResult: Sendable { let accountID: String; let items: [SyncItem] }
actor CloudJournalService {
    private let identifier: String?
    private let zoneID = CKRecordZone.ID(zoneName: "RoamJournalV1", ownerName: CKCurrentUserDefaultName)
    private var running = false
    private var cachedAccount: String?
    private var cachedRecords: [String: CKRecord] = [:]
    private var cachedItems: [String: SyncItem] = [:]
    private var changeToken: CKServerChangeToken?
    init(identifier: String?) { self.identifier = identifier }
    private func container() throws -> CKContainer {
        guard let identifier, !identifier.isEmpty else { throw SyncError.setupRequired }
        return CKContainer(identifier: identifier)
    }
    func accountID() async throws -> String {
        let container = try container()
        guard try await container.accountStatus() == .available else { throw CloudSyncError.noAccount }
        return try await container.userRecordID().recordName
    }
    func exchange(_ local: NotebookSyncState, allowCreatingZone: Bool) async throws -> CloudSyncResult {
        guard !running else { throw CloudSyncError.retry }
        running = true
        defer { running = false }
        let container = try container()
        guard try await accountID() == local.accountID else { throw SyncError.accountChanged }
        let database = container.privateCloudDatabase
        do { _ = try await database.recordZone(for: zoneID) }
        catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            guard allowCreatingZone else { throw SyncError.cloudReset }
            _ = try await database.save(CKRecordZone(zoneID: zoneID))
            cachedRecords = [:]; cachedItems = [:]; changeToken = nil
        }
        if cachedAccount != local.accountID {
            cachedAccount = local.accountID; cachedRecords = [:]; cachedItems = [:]; changeToken = nil
        }
        do { try await fetchChanges(database, accountID: local.accountID) }
        catch let error as CKError where error.code == .changeTokenExpired {
            cachedRecords = [:]; cachedItems = [:]; changeToken = nil
            try await fetchChanges(database, accountID: local.accountID)
        }
        var remote = cachedRecords, remoteItems = cachedItems
        var merged = local
        try merged.merge(Array(remoteItems.values))
        for _ in 0..<4 {
            try Task.checkCancellation()
            guard try await accountID() == local.accountID else { throw SyncError.accountChanged }
            let changed = merged.records.values.filter { remoteItems[$0.recordName] != $0 }.sorted { $0.recordName < $1.recordName }
            if changed.isEmpty {
                try Task.checkCancellation()
                cachedRecords = remote; cachedItems = remoteItems
                return CloudSyncResult(accountID: local.accountID, items: Array(merged.records.values))
            }
            for offset in stride(from: 0, to: changed.count, by: 40) {
                try Task.checkCancellation()
                guard try await accountID() == local.accountID else { throw SyncError.accountChanged }
                let batch = Array(changed[offset..<min(offset + 40, changed.count)])
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RoamSync-" + UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: directory) }
                let records = try batch.map { try encode($0, existing: remote[$0.recordName], directory: directory, accountID: local.accountID) }
                let response = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: false)
                for record in records {
                    guard let result = response.saveResults[record.recordID] else { throw CloudSyncError.retry }
                    switch result {
                    case .success(let saved):
                        remote[saved.recordID.recordName] = saved
                        remoteItems[saved.recordID.recordName] = batch.first { $0.recordName == saved.recordID.recordName }
                    case .failure(let error):
                        guard let conflict = error as? CKError, conflict.code == .serverRecordChanged else { throw error }
                        let server = try await database.record(for: record.recordID)
                        let item = try decode(server, accountID: local.accountID)
                        try merged.merge([item])
                        remote[server.recordID.recordName] = server
                        remoteItems[server.recordID.recordName] = item
                    }
                }
            }
        }
        throw CloudSyncError.retry
    }
    private func fetchChanges(_ database: CKDatabase, accountID: String) async throws {
        var records = cachedRecords, items = cachedItems
        var token = changeToken
        while true {
            try Task.checkCancellation()
            let page = try await database.recordZoneChanges(inZoneWith: zoneID, since: token, resultsLimit: 100)
            guard page.deletions.isEmpty else { throw SyncError.cloudReset }
            for result in page.modificationResultsByID.values {
                let record = try result.get().record
                guard record.recordType == "JournalItemV1" else { throw SyncError.invalidRecord }
                let item = try decode(record, accountID: accountID)
                records[record.recordID.recordName] = record; items[item.recordName] = item
            }
            token = page.changeToken
            if !page.moreComing {
                try Task.checkCancellation()
                cachedRecords = records; cachedItems = items; changeToken = token
                return
            }
        }
    }
    private func encode(_ item: SyncItem, existing: CKRecord?, directory: URL, accountID: String) throws -> CKRecord {
        let record = existing ?? CKRecord(recordType: "JournalItemV1", recordID: CKRecord.ID(recordName: item.recordName, zoneID: zoneID))
        let key = SymmetricKey(size: .bits256)
        let bytes = try AES.GCM.seal(JSONEncoder().encode(item), using: key).combined!
        guard bytes.count <= 24_000_000 else { throw CloudSyncError.tooLarge }
        let file = directory.appendingPathComponent(UUID().uuidString + ".encrypted")
        try bytes.write(to: file, options: [.atomic, .completeFileProtection])
        record["encryptedPayload"] = CKAsset(fileURL: file)
        record.encryptedValues["payloadKey"] = key.withUnsafeBytes { Data($0) } as NSData
        record.encryptedValues["ownerID"] = accountID as NSString
        return record
    }
    private func decode(_ record: CKRecord, accountID: String) throws -> SyncItem {
        guard record.encryptedValues["ownerID"] as? String == accountID,
              let key = record.encryptedValues["payloadKey"] as? Data, key.count == 32,
              let asset = record["encryptedPayload"] as? CKAsset, let file = asset.fileURL,
              let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 24_000_000 else { throw SyncError.invalidRecord }
        let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: Data(contentsOf: file)), using: SymmetricKey(data: key))
        let item = try JSONDecoder().decode(SyncItem.self, from: plain)
        guard item.recordName == record.recordID.recordName else { throw SyncError.invalidRecord }
        try item.validated()
        return item
    }
}
enum CloudSyncError: LocalizedError {
    case noAccount, retry, tooLarge
    var errorDescription: String? {
        switch self {
        case .noAccount: "Sign in to iCloud in device Settings, then try again."
        case .retry: "Other changes arrived while syncing. Your edits are saved here. Try Sync now again."
        case .tooLarge: "An entry is too large to sync. Its local copy is safe. Shorten it or use a smaller photo."
        }
    }
    static func message(_ error: Error) -> String {
        guard let error = error as? CKError else { return error.localizedDescription }
        switch error.code {
        case .notAuthenticated: return noAccount.localizedDescription
        case .networkFailure, .networkUnavailable: return "You’re offline. Edits are saved here and will sync when you reconnect."
        case .quotaExceeded: return "iCloud storage is full. Local changes are safe. Free some iCloud space, then retry."
        case .missingEntitlement, .badContainer, .badDatabase, .permissionFailure: return SyncError.setupRequired.localizedDescription
        case .zoneNotFound, .userDeletedZone: return SyncError.cloudReset.localizedDescription
        case .serviceUnavailable, .requestRateLimited, .zoneBusy: return "iCloud is busy. Changes are saved here. Try again shortly."
        default: return "iCloud couldn’t finish syncing. Edits are saved here. Try again later."
        }
    }
}
