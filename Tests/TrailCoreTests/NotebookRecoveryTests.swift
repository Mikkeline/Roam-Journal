import XCTest
import CryptoKit
@testable import TrailCore

final class NotebookRecoveryTests: XCTestCase {
    private func fixture() -> TravelNotebook {
        var trip = TravelTrip(destination: "Private destination", entries: [TravelEntry(title: "Memory", photo: Data("private photo".utf8))])
        trip.essentials = TripEssentials()
        trip.essentials?.documents = [TripDocument(name: "ticket.txt", type: "text", data: Data("secret ticket".utf8))]
        return TravelNotebook(trips: [trip])
    }
    private func temporaryArchive() -> (URL, NotebookArchive) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (folder, NotebookArchive(fileURL: folder.appendingPathComponent("notebook.vault"), key: SymmetricKey(size: .bits256)))
    }
    func testBackupRoundTripOnIndependentDeviceAndKey() throws {
        let code = NotebookBackup.recoveryCode(); let book = fixture()
        let sealed = try NotebookBackup.seal(book, code: code)
        XCTAssertEqual(try NotebookBackup.open(sealed, code: code), book)
        XCTAssertNil(sealed.range(of: Data("Private destination".utf8)))
        XCTAssertNil(sealed.range(of: Data(code.utf8)))
        XCTAssertNotEqual(try NotebookBackup.seal(book, code: code), sealed)
        let (folder, archive) = temporaryArchive(); defer { try? FileManager.default.removeItem(at: folder) }
        try archive.save(NotebookBackup.open(sealed, code: code))
        XCTAssertEqual(try archive.load(), book)
    }
    func testWrongCodeTamperingAndMalformedBackupRejected() throws {
        let code = NotebookBackup.recoveryCode(); let data = try NotebookBackup.seal(fixture(), code: code)
        XCTAssertThrowsError(try NotebookBackup.open(data, code: NotebookBackup.recoveryCode()))
        XCTAssertThrowsError(try NotebookBackup.open(data, code: "123"))
        var tampered = data; tampered[tampered.count - 1] ^= 1
        XCTAssertThrowsError(try NotebookBackup.open(tampered, code: code))
        XCTAssertThrowsError(try NotebookBackup.open(Data("bad file".utf8), code: code))
        XCTAssertThrowsError(try NotebookBackup.open(Data(data.dropLast(15)), code: code))
    }
    func testBackupStripsCloudAccountAndRestoreUsesFreshIDs() throws {
        var book = fixture(); var state = NotebookSyncState(accountID: "private-cloud-account"); try state.seed(book); book.syncState = state
        let code = NotebookBackup.recoveryCode()
        let decoded = try NotebookBackup.open(NotebookBackup.seal(book, code: code), code: code)
        XCTAssertNil(decoded.syncState)
        let copies = try NotebookBackup.copiesForRestore(decoded)
        XCTAssertNotEqual(copies[0].id, book.trips[0].id)
        XCTAssertNotEqual(copies[0].entries[0].id, book.trips[0].entries[0].id)
        XCTAssertEqual(copies[0].essentials, book.trips[0].essentials)
        XCTAssertEqual(copies[0].entries[0].photo, book.trips[0].entries[0].photo)
        _ = try TravelNotebook(trips: book.trips + copies).validated()
    }
    func testV2AttachmentsEncryptedAndReusedAcrossMetadataSaves() throws {
        let (folder, archive) = temporaryArchive(); defer { try? FileManager.default.removeItem(at: folder) }
        var book = fixture(); try archive.save(book)
        let files = try FileManager.default.contentsOfDirectory(at: archive.attachmentsURL, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 2)
        let old = try Dictionary(uniqueKeysWithValues: files.map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
        for bytes in old.values { XCTAssertNil(bytes.range(of: Data("secret ticket".utf8))) }
        XCTAssertLessThan(try Data(contentsOf: archive.fileURL).count, 3000)
        book.trips[0].destination = "Edited destination"; try archive.save(book)
        XCTAssertEqual(try archive.load(), book)
        for file in files { XCTAssertEqual(try Data(contentsOf: file), old[file.lastPathComponent]) }
    }
    func testLegacyArchiveMigratesWithoutChangingItsContent() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let key = SymmetricKey(size: .bits256); let path = folder.appendingPathComponent("notebook.vault")
        let book = fixture()
        let old = try AES.GCM.seal(JSONEncoder().encode(book), using: key).combined!
        try old.write(to: path)
        let archive = NotebookArchive(fileURL: path, key: key)
        let loaded = try archive.load(); XCTAssertEqual(loaded, book)
        try archive.save(loaded)
        XCTAssertEqual(try archive.load(), book)
        XCTAssertEqual(try Data(contentsOf: path.appendingPathExtension("legacy-backup")), old)
    }
    func testMissingOrTamperedSidecarFailsClosed() throws {
        let (folder, archive) = temporaryArchive(); defer { try? FileManager.default.removeItem(at: folder) }
        try archive.save(fixture())
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: archive.attachmentsURL, includingPropertiesForKeys: nil).first)
        let original = try Data(contentsOf: file); var broken = original; broken[broken.count - 1] ^= 1
        try broken.write(to: file)
        XCTAssertThrowsError(try archive.load())
        try FileManager.default.removeItem(at: file)
        XCTAssertThrowsError(try archive.load())
    }
    func testFailedSaveLeavesExistingArchiveReadable() throws {
        let (folder, archive) = temporaryArchive(); defer { try? FileManager.default.removeItem(at: folder) }
        let book = fixture(); try archive.save(book)
        var invalid = book; invalid.trips[0].destination = ""
        XCTAssertThrowsError(try archive.save(invalid))
        XCTAssertEqual(try archive.load(), book)
    }
    func testAttachmentCleanupKeepsPreviousSnapshot() throws {
        let (folder, archive) = temporaryArchive(); defer { try? FileManager.default.removeItem(at: folder) }
        let book = fixture(); try archive.save(book)
        var empty = book; empty.trips[0].entries[0].photo = nil; empty.trips[0].essentials?.documents = []
        try archive.save(empty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: archive.attachmentsURL, includingPropertiesForKeys: nil).count, 2)
        try archive.save(empty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(at: archive.attachmentsURL, includingPropertiesForKeys: nil).isEmpty)
        XCTAssertEqual(try archive.load(), empty)
    }
    func testStaleTripAndDeletedTripCannotOverwriteOrResurrect() throws {
        let original = fixture().trips[0]
        var current = original; current.essentials?.outbound.number = "MH123"
        let book = TravelNotebook(trips: [current])
        var draft = original; draft.destination = "New name"
        XCTAssertThrowsError(try book.editingTrip(draft, expected: original))
        XCTAssertThrowsError(try TravelNotebook().editingTrip(draft, expected: original))
        XCTAssertEqual(book.trips[0].essentials?.outbound.number, "MH123")
    }
    func testTripEditsPreserveEntriesAddedInAnotherWindow() throws {
        let original = fixture().trips[0]; var current = original
        current.entries.append(TravelEntry(title: "Added elsewhere"))
        var draft = original; draft.destination = "Renamed"
        let edited = try TravelNotebook(trips: [current]).editingTrip(draft, expected: original)
        XCTAssertEqual(edited.trips[0].entries, current.entries)
        XCTAssertEqual(edited.trips[0].destination, "Renamed")
    }
    func testStaleAndDeletedEntryCannotBeOverwritten() throws {
        var trip = fixture().trips[0]; let original = trip.entries[0]
        trip.entries[0].text = "Other window edit"
        XCTAssertThrowsError(try TravelNotebook(trips: [trip]).editingEntry(original, tripID: trip.id, expected: original))
        trip.entries = []
        XCTAssertThrowsError(try TravelNotebook(trips: [trip]).editingEntry(original, tripID: trip.id, expected: original))
    }
    func testWriteFailureBeforeMetadataReplacementPreservesOldJournal() throws {
        let (folder, archive) = temporaryArchive(); defer { try? FileManager.default.removeItem(at: folder) }
        let book = fixture(); try archive.save(book)
        // A blocked rolling-snapshot path forces an actual filesystem failure before the atomic commit.
        try FileManager.default.createDirectory(at: archive.previousURL, withIntermediateDirectories: true)
        var changed = book; changed.trips[0].destination = "Unsaved change"
        XCTAssertThrowsError(try archive.save(changed))
        XCTAssertEqual(try archive.load(), book)
    }

}
