import Foundation
import CryptoKit

public enum BackupError: LocalizedError {
    case invalidCode, unreadable, tooLarge
    public var errorDescription: String? {
        switch self {
        case .invalidCode: "Enter the complete 64-character recovery code supplied when this backup was created."
        case .unreadable: "The backup could not be verified. Check the recovery code and file. Your current journal has not been changed."
        case .tooLarge: "This backup exceeds its supported size limits. Streaming backups support 2 GB total, 16 MB of metadata, and 30 MB per attachment; legacy backups support 250 MB."
        }
    }
}
public enum NotebookBackup {
    private static let header = Data("ROAM-BACKUP-1\n".utf8)
    public static let maximumBytes = 250_000_000
    public static func recoveryCode() -> String {
        SymmetricKey(size: .bits256).withUnsafeBytes { $0.map { String(format: "%02X", $0) }.joined() }
    }
    static func key(_ code: String) throws -> SymmetricKey {
        let text = code.filter { !$0.isWhitespace && $0 != "-" }
        guard text.count == 64, text.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { throw BackupError.invalidCode }
        var bytes = Data(); var start = text.startIndex
        for _ in 0..<32 {
            let end = text.index(start, offsetBy: 2)
            guard let byte = UInt8(text[start..<end], radix: 16) else { throw BackupError.invalidCode }
            bytes.append(byte); start = end
        }
        return SymmetricKey(data: bytes)
    }
    public static func seal(_ notebook: TravelNotebook, code: String) throws -> Data {
        var copy = try notebook.validated(); copy.syncState = nil
        guard copy.attachmentReferences.isEmpty else { throw BackupError.unreadable }
        let plain = try JSONEncoder().encode(copy)
        guard plain.count < maximumBytes - 100 else { throw BackupError.tooLarge }
        return header + (try AES.GCM.seal(plain, using: key(code), authenticating: header).combined!)
    }
    public static func open(_ data: Data, code: String) throws -> TravelNotebook {
        guard data.count <= maximumBytes else { throw BackupError.tooLarge }
        let key = try key(code)
        guard data.starts(with: header) else { throw BackupError.unreadable }
        do {
            let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: Data(data.dropFirst(header.count))), using: key, authenticating: header)
            var book = try JSONDecoder().decode(TravelNotebook.self, from: plain).validated(); book.syncState = nil
            guard book.attachmentReferences.isEmpty else { throw BackupError.unreadable }
            return book
        } catch { throw BackupError.unreadable }
    }
    /// Keeps local recovery records and their parent links while assigning new identities.
    public static func contentForRestore(_ notebook: TravelNotebook) throws -> TravelNotebook {
        let source = try notebook.validated()
        var parents: [UUID: UUID] = [:]
        func parent(_ id: UUID) -> UUID { if let value = parents[id] { return value }; let value = UUID(); parents[id] = value; return value }
        func tripCopy(_ source: TravelTrip) -> TravelTrip {
            var trip = source; trip.id = parent(source.id)
            trip.entries = source.entries.map { var entry = $0; entry.id = UUID(); return entry }; return trip
        }
        var result = TravelNotebook(trips: source.trips.map(tripCopy))
        result.deletedTrips = source.deletedTrips?.map { DeletedTrip(trip: tripCopy($0.trip), deletedAt: $0.deletedAt) }
        result.deletedEntries = source.deletedEntries?.map { record in
            var entry = record.entry; entry.id = UUID()
            return DeletedEntry(tripID: parent(record.tripID), entry: entry, deletedAt: record.deletedAt)
        }
        result.packingTemplates = source.packingTemplates?.map { PackingTemplate(name: $0.name, items: $0.items) }
        result.purgeExpiredDeletions(); return result
    }
    /// Restores as additional trips, so existing notes, sync tombstones and IDs cannot be overwritten.
    public static func copiesForRestore(_ notebook: TravelNotebook) throws -> [TravelTrip] {
        try notebook.validated().trips.map { source in
            var trip = source; trip.id = UUID()
            trip.entries = source.entries.map { source in var entry = source; entry.id = UUID(); return entry }
            return trip
        }
    }
}
