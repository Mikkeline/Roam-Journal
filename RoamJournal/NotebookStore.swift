import Foundation
import Combine
import CryptoKit
import Security
import LocalAuthentication

private enum StorageError: LocalizedError {
    case keychain(OSStatus), missingKey, tripLocked, faceIDRequired, saving
    var errorDescription: String? {
        switch self {
        case .saving: "A save is already in progress. Wait for it to finish, then try again."
        case .keychain: "The device could not access the notebook key. Unlock your device and try again."
        case .missingKey: "The key for this notebook is missing. The saved file has been kept and cannot be opened with a new key."
        case .tripLocked: "Unlock this trip with Face ID before accessing it."
        case .faceIDRequired: "Face ID is required. Set it up on this device before continuing."
        }
    }
}
private enum NotebookKey {
    static func load(createIfMissing: Bool, account: String = "archive-key-v1") throws -> SymmetricKey {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "TrailVault") + ".notebook",
            kSecAttrAccount as String: account]
        var lookup = query
        lookup[kSecReturnData as String] = true; lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        if status == errSecSuccess {
            guard let bytes = item as? Data, bytes.count == 32 else { throw StorageError.missingKey }
            return SymmetricKey(data: bytes)
        }
        guard status == errSecItemNotFound else { throw StorageError.keychain(status) }
        guard createIfMissing else { throw StorageError.missingKey }
        let key = SymmetricKey(size: .bits256)
        var insert = query
        insert[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let result = SecItemAdd(insert as CFDictionary, nil)
        if result == errSecDuplicateItem { return try load(createIfMissing: false, account: account) }
        guard result == errSecSuccess else { throw StorageError.keychain(result) }
        return key
    }
}
@MainActor final class NotebookStore: ObservableObject {
    @Published private(set) var notebook = TravelNotebook()
    @Published private(set) var isReady = false
    @Published private(set) var loadError: String?
    private let writeGate = MutationGate()
    private let persistence = NotebookPersistence()
    @Published private(set) var isSaving = false
    @Published private(set) var isOpening = false
    @Published private(set) var navigationResetID = UUID()
    @Published private(set) var tripAccess = TripAccessSession()
    @Published private(set) var authenticationMessage: String?
    @Published private(set) var sceneInactive = false
    @Published private(set) var requiresReauthentication = false
    private(set) var protectedTripID: UUID?
    private var authenticationContext: LAContext?
    private var inBackground = false
    private var backupAuthContext: LAContext?
    private var backupAuthGeneration = UUID()
    private var scenes: [UUID: Int] = [:]
    var isAuthenticating: Bool { tripAccess.challengeID != nil }
    var cloudAvailable: Bool { CloudBuild.available }
    @Published private(set) var cloudEnabled = false
    @Published private(set) var isSyncing = false
    @Published private(set) var cloudHasPendingChanges = true
    @Published private(set) var hasDeferredCloudChanges = false
    @Published private(set) var cloudMessage: String?
    @Published private(set) var lastCloudSync: Date?
    private var deferredCloudItems: [SyncItem]?
    private let cloud = CloudJournalService(identifier: CloudBuild.identifier)
    private var syncConsentContext: LAContext?
    private var syncTask: Task<Void, Never>?
    private var syncGeneration = UUID()
    private var syncAgain = false
    init() {
        cloudEnabled = CloudBuild.available && UserDefaults.standard.bool(forKey: "roam.cloud.enabled")
        if !CloudBuild.available { UserDefaults.standard.set(false, forKey: "roam.cloud.enabled") }
        lastCloudSync = UserDefaults.standard.object(forKey: "roam.cloud.lastSync") as? Date
        Task { await open() }
    }
    private func storageBase() throws -> URL {
        var base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-roam-ui-test-session"), args.indices.contains(index + 1), let session = UUID(uuidString: args[index + 1]) { base = base.appendingPathComponent("UITestJournals/" + session.uuidString) }
        #endif
        return base
    }
    func open() async {
        guard !isReady, !isOpening else { return }
        isOpening = true; defer { isOpening = false }
        do {
            let base = try storageBase()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-roam-ui-test-corrupt"), ProcessInfo.processInfo.arguments.contains("-roam-ui-test-session") {
                let folder = base.appendingPathComponent("PrivateNotebook"); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let file = folder.appendingPathComponent("notebook.vault")
                if !FileManager.default.fileExists(atPath: file.path) { try Data("invalid test archive".utf8).write(to: file) }
            }
            #endif
            let pointer = base.appendingPathComponent("roam-active-journal")
            let name = (try? String(contentsOf: pointer, encoding: .utf8)) ?? "PrivateNotebook"
            guard name == "PrivateNotebook" || UUID(uuidString: name) != nil else { throw NotebookError.invalidContent }
            var folder = base.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var values = URLResourceValues(); values.isExcludedFromBackup = true; try folder.setResourceValues(values)
            let file = folder.appendingPathComponent("notebook.vault")
            let key = try NotebookKey.load(createIfMissing: !FileManager.default.fileExists(atPath: file.path) && !FileManager.default.fileExists(atPath: file.appendingPathExtension("previous").path), account: name == "PrivateNotebook" ? "archive-key-v1" : "archive-key-" + name)
            let archive = NotebookArchive(fileURL: file, key: key)
            let loaded = try await persistence.load(archive)
            var checked = loaded; checked.purgeExpiredDeletions(); notebook = checked
            if loaded.syncState == nil {
                cloudEnabled = false; UserDefaults.standard.set(false, forKey: "roam.cloud.enabled")
                lastCloudSync = nil; UserDefaults.standard.removeObject(forKey: "roam.cloud.lastSync")
            }
            isReady = true; loadError = nil
        } catch { loadError = "Your notebook could not be opened. Your saved file has not been changed.\n\n" + error.localizedDescription }
    }
    private func commit(_ candidate: TravelNotebook, scheduleSync: Bool = true) async throws {
        guard isReady else { throw StorageError.missingKey }
        guard !isSaving else { throw StorageError.saving }
        isSaving = true; defer { isSaving = false }
        var candidate = candidate; candidate.purgeExpiredDeletions()
        notebook = try await persistence.save(candidate)
        if scheduleSync { Task { await Task.yield(); self.requestCloudSync() } }
    }
    private func requireAccess(_ id: UUID) throws {
        guard tripAccess.allows(id), !inBackground else { throw StorageError.tripLocked }
    }
    func saveTrip(_ trip: TravelTrip, replacing original: TravelTrip? = nil) async throws {
        await writeGate.acquire(); defer { writeGate.release() }; try Task.checkCancellation()
        if notebook.trips.contains(where: { $0.id == trip.id }) { try requireAccess(trip.id) }
        var next = try notebook.editingTrip(trip, expected: original)
        var metadata = trip; metadata.entries = []
        try next.syncState?.write(.trip(metadata)); try await commit(next)
    }
    func updateEssentials(_ change: EssentialsChange, tripID: UUID) async throws {
        await writeGate.acquire(); defer { writeGate.release() }; try Task.checkCancellation()
        try requireAccess(tripID)
        var next = try notebook.changingEssentials(change, tripID: tripID)
        guard var trip = next.trips.first(where: { $0.id == tripID }) else { throw NotebookEditError.changed }
        trip.entries = []; try next.syncState?.write(.trip(trip))
        try await commit(next)
    }
    func savePackingTemplate(name: String, tripID: UUID) async throws {
        await writeGate.acquire(); defer { writeGate.release() }; try Task.checkCancellation()
        try requireAccess(tripID)
        let items = notebook.trips.first(where: { $0.id == tripID })?.essentials?.packing.map(\.title) ?? []
        let template = PackingTemplate(name: name.trimmingCharacters(in: .whitespacesAndNewlines), items: items)
        guard template.isValid else { throw NotebookError.invalidContent }
        var next = notebook; next.packingTemplates = (next.packingTemplates ?? []) + [template]
        try await commit(next, scheduleSync: false)
    }
    func deletePackingTemplate(_ id: UUID, tripID: UUID) async throws {
        await writeGate.acquire(); defer { writeGate.release() }; try Task.checkCancellation()
        try requireAccess(tripID)
        var next = notebook; next.packingTemplates?.removeAll { $0.id == id }
        try await commit(next, scheduleSync: false)
    }
    func deleteTrip(_ id: UUID) async throws {
        await writeGate.acquire(); defer { writeGate.release() }; try Task.checkCancellation()
        try requireAccess(id)
        var next = notebook
        for entry in next.trips.first(where: { $0.id == id })?.entries ?? [] { try next.syncState?.write(.deletedEntry(tripID: id, entryID: entry.id)) }
        try next.syncState?.write(.deletedTrip(id)); next.deletedTrips = (next.deletedTrips ?? []) + next.trips.filter { $0.id == id }.map { DeletedTrip(trip: $0) }; next.trips.removeAll { $0.id == id }; try await commit(next)
        if protectedTripID == id { leaveTrip() }
    }
    func saveEntry(_ entry: TravelEntry, tripID: UUID, replacing original: TravelEntry? = nil) async throws {
        await writeGate.acquire(); defer { writeGate.release() }; try Task.checkCancellation()
        try requireAccess(tripID)
        var next = try notebook.editingEntry(entry, tripID: tripID, expected: original)
        try next.syncState?.write(.entry(tripID: tripID, entry: entry)); try await commit(next)
    }
    func deleteEntry(_ id: UUID, tripID: UUID) async throws {
        await writeGate.acquire(); defer { writeGate.release() }; try Task.checkCancellation()
        try requireAccess(tripID)
        var next = notebook
        guard let i = next.trips.firstIndex(where: { $0.id == tripID }) else { throw NotebookError.invalidContent }
        next.deletedEntries = (next.deletedEntries ?? []) + next.trips[i].entries.filter { $0.id == id }.map { DeletedEntry(tripID: tripID, entry: $0) }
        next.trips[i].entries.removeAll { $0.id == id }
        try next.syncState?.write(.deletedEntry(tripID: tripID, entryID: id)); try await commit(next)
    }
    func attachmentData(_ data: Data?, reference: AttachmentReference?, tripID: UUID) async throws -> Data? {
        try requireAccess(tripID)
        let bytes = try await reference.mapAsync { try await self.persistence.read($0) } ?? data
        try Task.checkCancellation(); try requireAccess(tripID); return bytes
    }
    func portableNotebook() async throws -> TravelNotebook { try await persistence.materialize(notebook) }
    func exportBackup(code: String, to url: URL) async throws {
        await writeGate.acquire(); defer { writeGate.release() }
        try Task.checkCancellation(); guard !inBackground, isReady else { throw StorageError.tripLocked }
        try await persistence.export(notebook, code: code, to: url)
    }
    func restoreBackupFile(_ url: URL, code: String) async throws {
        try await authorizeBackup(); let authorization = backupAuthGeneration
        if !isReady { try await recoverJournal(nil, backupFile: url, code: code); return }
        await writeGate.acquire(); defer { writeGate.release() }
        try Task.checkCancellation()
        guard !inBackground, authorization == backupAuthGeneration else { throw StorageError.tripLocked }
        let backup = try await persistence.importFile(url, code: code)
        try Task.checkCancellation(); guard !inBackground, authorization == backupAuthGeneration else { throw StorageError.tripLocked }
        var next = notebook
        let restored = try NotebookBackup.contentForRestore(backup)
        next.trips += restored.trips
        next.deletedTrips = (next.deletedTrips ?? []) + (restored.deletedTrips ?? [])
        next.deletedEntries = (next.deletedEntries ?? []) + (restored.deletedEntries ?? [])
        next.packingTemplates = (next.packingTemplates ?? []) + (restored.packingTemplates ?? [])
        for trip in next.trips where !notebook.trips.contains(where: { $0.id == trip.id }) {
            var metadata = trip; metadata.entries = []; try next.syncState?.write(.trip(metadata))
            for entry in trip.entries { try next.syncState?.write(.entry(tripID: trip.id, entry: entry)) }
        }
        try await commit(next); navigationResetID = UUID(); leaveTrip()
    }
    func recoverJournal(_ backup: TravelNotebook?, backupFile: URL? = nil, code: String = "") async throws {
        let authorization = backupAuthGeneration
        await writeGate.acquire(); defer { writeGate.release() }
        try Task.checkCancellation()
        guard !inBackground, authorization == backupAuthGeneration else { throw StorageError.tripLocked }
        let base = try storageBase()
        let name = UUID().uuidString
        var directory = base.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true; try directory.setResourceValues(values)
        let key = try NotebookKey.load(createIfMissing: true, account: "archive-key-" + name)
        let archive = NotebookArchive(fileURL: directory.appendingPathComponent("notebook.vault"), key: key)
        var book = backup ?? TravelNotebook(); book.syncState = nil
        isSaving = true; defer { isSaving = false }
        if let backupFile { notebook = try await persistence.installFile(backupFile, code: code, archive: archive, pointer: base.appendingPathComponent("roam-active-journal"), directory: name) }
        else { notebook = try await persistence.install(book, archive: archive, pointer: base.appendingPathComponent("roam-active-journal"), directory: name) }
        disableCloudSync(); loadError = nil; isReady = true; navigationResetID = UUID(); leaveTrip()
    }
    func restoreDeletedTrip(_ id: UUID) async throws {
        try await authorizeBackup(); let authorization = backupAuthGeneration
        await writeGate.acquire(); defer { writeGate.release() }
        try Task.checkCancellation(); guard !inBackground, authorization == backupAuthGeneration else { throw StorageError.tripLocked }
        guard let record = notebook.deletedTrips?.first(where: { $0.id == id }) else { throw NotebookEditError.changed }
        var next = notebook
        let copy = try NotebookBackup.copiesForRestore(TravelNotebook(trips: [record.trip]))[0]
        next.trips.append(copy); next.deletedTrips?.removeAll { $0.id == id }
        next.deletedEntries = next.deletedEntries?.map { source in var source = source; if source.tripID == record.trip.id { source.tripID = copy.id }; return source }
        var metadata = copy; metadata.entries = []; try next.syncState?.write(.trip(metadata))
        for entry in copy.entries { try next.syncState?.write(.entry(tripID: copy.id, entry: entry)) }
        try await commit(next)
    }
    func restoreDeletedEntry(_ id: UUID) async throws {
        try await authorizeBackup(); let authorization = backupAuthGeneration
        await writeGate.acquire(); defer { writeGate.release() }
        try Task.checkCancellation(); guard !inBackground, authorization == backupAuthGeneration else { throw StorageError.tripLocked }
        guard let record = notebook.deletedEntries?.first(where: { $0.id == id }) else { throw NotebookEditError.changed }
        var next = notebook
        guard let index = next.trips.firstIndex(where: { $0.id == record.tripID }) else { throw NotebookEditError.changed }
        var entry = record.entry; entry.id = UUID(); next.trips[index].entries.append(entry)
        try next.syncState?.write(.entry(tripID: record.tripID, entry: entry)); next.deletedEntries?.removeAll { $0.id == id }
        try await commit(next)
    }
    func eraseDeleted() async throws {
        try await authorizeBackup(); let authorization = backupAuthGeneration; await writeGate.acquire(); defer { writeGate.release() }
        try Task.checkCancellation(); guard !inBackground, authorization == backupAuthGeneration else { throw StorageError.tripLocked }
        var next = notebook; next.deletedTrips = nil; next.deletedEntries = nil; try await commit(next)
    }
    func authorizeBackup() async throws {
        guard !inBackground, !isSaving else { throw StorageError.saving }
        let context = LAContext(); context.localizedFallbackTitle = ""
        backupAuthContext?.invalidate(); backupAuthContext = context
        let token = UUID(); backupAuthGeneration = token
        defer { context.invalidate(); if backupAuthGeneration == token { backupAuthContext = nil } }
        context.touchIDAuthenticationAllowableReuseDuration = 0
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error), context.biometryType == .faceID else { throw StorageError.faceIDRequired }
        let accepted = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Manage an encrypted journal backup.")
        try Task.checkCancellation()
        guard accepted, !inBackground, backupAuthGeneration == token else { throw StorageError.tripLocked }
        guard !isSaving else { throw StorageError.saving }
    }
    func restoreCopies(_ backup: TravelNotebook) async throws {
        try await authorizeBackup(); let authorization = backupAuthGeneration
        try Task.checkCancellation()
        if !isReady { try await recoverJournal(backup); return }
        await writeGate.acquire(); defer { writeGate.release() }
        try Task.checkCancellation(); guard !inBackground, authorization == backupAuthGeneration else { throw StorageError.tripLocked }
        var next = notebook
        let restored = try NotebookBackup.contentForRestore(backup)
        next.packingTemplates = (next.packingTemplates ?? []) + (restored.packingTemplates ?? [])
        next.deletedTrips = (next.deletedTrips ?? []) + (restored.deletedTrips ?? [])
        next.deletedEntries = (next.deletedEntries ?? []) + (restored.deletedEntries ?? [])
        for trip in restored.trips {
            next.trips.append(trip)
            var metadata = trip; metadata.entries = []
            try next.syncState?.write(.trip(metadata))
            for entry in trip.entries { try next.syncState?.write(.entry(tripID: trip.id, entry: entry)) }
        }
        try await commit(next)
        navigationResetID = UUID(); leaveTrip()
    }
    func authenticateTrip(_ id: UUID) {
        guard isReady, !inBackground, !isAuthenticating, notebook.trips.contains(where: { $0.id == id }) else { return }
        let context = LAContext(); context.localizedFallbackTitle = ""; context.localizedCancelTitle = "Cancel"; context.touchIDAuthenticationAllowableReuseDuration = 0
        var error: NSError?
        let available = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        guard context.biometryType == .faceID else { authenticationMessage = "Face ID is required. Use a Face ID-enabled device and set it up in Settings."; return }
        guard available else { authenticationMessage = Self.authenticationError(error); return }
        authenticationContext?.invalidate(); authenticationContext = context; authenticationMessage = nil
        let challenge = tripAccess.begin(id)
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Open your private travel trip.") { [weak self] success, error in
            let message = error.map { Self.authenticationError($0) }
            Task { @MainActor [weak self] in
                guard let self, self.tripAccess.challengeID == challenge, !self.inBackground else { return }
                self.authenticationContext = nil
                if self.tripAccess.complete(challenge, tripID: id, succeeded: success) {
                    self.protectedTripID = id; self.requiresReauthentication = false; self.authenticationMessage = nil
                } else { self.authenticationMessage = message ?? "Face ID did not verify your identity. Try again." }
            }
        }
    }
    nonisolated private static func authenticationError(_ error: Error?) -> String {
        guard let error = error as? LAError else { return "Face ID is unavailable. Check device Settings and try again." }
        return switch error.code {
        case .userCancel, .appCancel, .systemCancel: "The trip is still locked. Use Face ID when you’re ready."
        case .biometryNotEnrolled: "Set up Face ID in device Settings before opening this trip."
        case .biometryLockout: "Face ID is temporarily locked by iOS. Unlock your device to re-enable Face ID, then return and retry."
        case .authenticationFailed: "Face ID did not recognise you. The trip is still locked."
        default: "Face ID is unavailable. Check device Settings and try again."
        }
    }
    func updateScene(_ id: UUID, active: Bool, background: Bool) {
        scenes[id] = active ? 0 : background ? 2 : 1
        if background { lockTrip(); backupAuthGeneration = UUID(); backupAuthContext?.invalidate() }
        updateScenePresence()
    }
    func removeScene(_ id: UUID) { scenes.removeValue(forKey: id); lockTrip(); updateScenePresence() }
    private func updateScenePresence() {
        if scenes.values.contains(0) { sceneBecameActive() }
        else if scenes.isEmpty || scenes.values.allSatisfy({ $0 == 2 }) { sceneEnteredBackground() }
        else { sceneResignedActive() }
    }
    func sceneResignedActive() { sceneInactive = true }
    func sceneBecameActive() { inBackground = false; sceneInactive = false; requestCloudSync() }
    func sceneEnteredBackground() {
        backupAuthGeneration = UUID(); backupAuthContext?.invalidate(); backupAuthContext = nil
        inBackground = true; sceneInactive = true
        Task { await persistence.clearCache() }
        if !cloudEnabled, isSyncing { disableCloudSync() }
        lockTrip()
    }
    func lockTrip() {
        authenticationContext?.invalidate(); authenticationContext = nil; tripAccess.lock()
        requiresReauthentication = protectedTripID != nil; authenticationMessage = nil
    }
    func leaveTrip() { protectedTripID = nil; lockTrip(); Task { await applyDeferredCloudChanges() } }
    func closeProtectedTrip() { navigationResetID = UUID(); leaveTrip() }
    func remoteDeletionMessage(tripID: UUID, entryID: UUID? = nil) -> String? {
        guard let items = deferredCloudItems else { return nil }
        if items.contains(where: { if case .deletedTrip(let id) = $0.content { return id == tripID }; return false }) {
            return "This trip was deleted on another device. Copy anything you want to keep before closing; the deletion applies when the trip refreshes."
        }
        if let entryID, items.contains(where: { if case .deletedEntry(let parent, let id) = $0.content { return parent == tripID && id == entryID }; return false }) {
            return "This entry was deleted on another device. Copy this draft into a new entry before closing if you want to keep it."
        }
        return nil
    }
    private func applyDeferredCloudChanges() async {
        guard !isSaving else { return }
        await writeGate.acquire(); defer { writeGate.release() }
        guard let items = deferredCloudItems, protectedTripID == nil else { return }
        do {
            let portable = try await persistence.materialize(notebook)
            guard var state = portable.syncState else { return }
            try state.merge(items)
            var next = portable; next.syncState = state; next.trips = try state.materialized()
            try await commit(next, scheduleSync: false)
            deferredCloudItems = nil; hasDeferredCloudChanges = false; cloudMessage = nil; requestCloudSync()
        } catch { cloudMessage = CloudSyncError.message(error) }
    }
    func enableCloudSync() async {
        guard cloudAvailable else { cloudMessage = SyncError.setupRequired.localizedDescription; return }
        guard isReady, !isSyncing, !inBackground else { return }
        let generation = UUID(); syncGeneration = generation; isSyncing = true; cloudMessage = nil
        do {
            let account = try await cloud.accountID()
            guard syncGeneration == generation, !inBackground else { return }
            let context = LAContext(); context.localizedFallbackTitle = ""; context.touchIDAuthenticationAllowableReuseDuration = 0
            var error: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error), context.biometryType == .faceID else { throw StorageError.faceIDRequired }
            syncConsentContext = context
            let accepted = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Enable iCloud sync for your private travel journal.")
            guard accepted, syncGeneration == generation, !inBackground else { throw StorageError.faceIDRequired }
            syncConsentContext = nil
            await writeGate.acquire(); defer { writeGate.release() }
            guard syncGeneration == generation, !inBackground else { throw StorageError.tripLocked }
            var next = notebook
            if let state = next.syncState { guard state.accountID == account else { throw SyncError.accountChanged } }
            else { var state = NotebookSyncState(accountID: account); try state.seed(next); next.syncState = state; try await commit(next, scheduleSync: false) }
            cloudEnabled = true; UserDefaults.standard.set(true, forKey: "roam.cloud.enabled"); isSyncing = false
            requestCloudSync(allowCreatingZone: true)
        } catch {
            guard syncGeneration == generation else { return }
            syncConsentContext = nil; isSyncing = false
            cloudMessage = error is LAError ? "iCloud sync wasn’t enabled. Complete Face ID authentication to continue." : CloudSyncError.message(error)
        }
    }
    func disableCloudSync() {
        syncGeneration = UUID(); syncConsentContext?.invalidate(); syncConsentContext = nil; syncTask?.cancel(); syncTask = nil
        syncAgain = false; isSyncing = false; cloudEnabled = false; deferredCloudItems = nil; hasDeferredCloudChanges = false
        UserDefaults.standard.set(false, forKey: "roam.cloud.enabled"); cloudMessage = nil
    }
    func cloudAccountChanged() {
        guard cloudEnabled else { return }
        disableCloudSync(); cloudMessage = "The iCloud account changed. Sync is paused; local trips are kept. Review the account before enabling again."
    }
    func requestCloudSync(allowCreatingZone: Bool = false) {
        guard cloudAvailable, cloudEnabled, isReady, !inBackground, !isSaving else { return }
        cloudHasPendingChanges = true
        if isSyncing { syncAgain = true; return }
        syncTask?.cancel(); let generation = UUID(); syncGeneration = generation
        syncTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
            guard let self, !Task.isCancelled, !self.inBackground, self.syncGeneration == generation, let state = self.notebook.syncState else { return }
            self.isSyncing = true; self.cloudMessage = nil
            do {
                let outgoing = try await self.persistence.materialize(self.notebook).syncState ?? state
                let result = try await self.cloud.exchange(outgoing, allowCreatingZone: allowCreatingZone)
                await self.writeGate.acquire(); defer { self.writeGate.release() }
                let portable = try await self.persistence.materialize(self.notebook)
                try Task.checkCancellation()
                guard self.syncGeneration == generation, self.cloudEnabled, var current = portable.syncState, current.accountID == result.accountID else { return }
                guard !self.isSaving else { self.isSyncing = false; self.syncTask = nil; self.syncAgain = false; return }
                try current.merge(result.items)
                var next = portable; next.syncState = current; next.trips = try current.materialized()
                let affectsOpenTrip = self.protectedTripID.map { id in next.trips.first(where: { $0.id == id }) != portable.trips.first(where: { $0.id == id }) } ?? false
                if affectsOpenTrip {
                    self.deferredCloudItems = Array(current.records.values); self.hasDeferredCloudChanges = true
                    self.cloudMessage = "iCloud changes are waiting. Close this trip to refresh them; your draft stays open."
                } else if next != portable { try await self.commit(next, scheduleSync: false) }
                let synced = Dictionary(uniqueKeysWithValues: result.items.map { ($0.recordName, $0) })
                self.cloudHasPendingChanges = self.hasDeferredCloudChanges || self.syncAgain || current.records != synced
                if current.records != synced { self.syncAgain = true }
                self.lastCloudSync = .now; UserDefaults.standard.set(self.lastCloudSync, forKey: "roam.cloud.lastSync")
            } catch { if !Task.isCancelled, self.syncGeneration == generation { self.cloudMessage = CloudSyncError.message(error) } }
            guard self.syncGeneration == generation else { return }
            self.isSyncing = false; self.syncTask = nil
            if self.syncAgain { self.syncAgain = false; self.requestCloudSync() }
        }
    }
}

private extension Optional where Wrapped == AttachmentReference {
    func mapAsync(_ transform: (AttachmentReference) async throws -> Data) async rethrows -> Data? {
        guard let self else { return nil }; return try await transform(self)
    }
}
