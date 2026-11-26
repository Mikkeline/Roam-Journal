import XCTest
import CryptoKit
@testable import TrailCore

final class ReleaseReliabilityTests: XCTestCase {
    private func book() -> TravelNotebook {
        var trip = TravelTrip(destination: "Private trip", entries: [TravelEntry(title: "Photo", photo: Data(repeating: 7, count: 4096))])
        trip.essentials = TripEssentials(); trip.essentials?.documents = [TripDocument(name: "ticket.txt", type: "text", data: Data("private ticket text".utf8))]
        return TravelNotebook(trips: [trip])
    }
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
    }
    func testMetadataLoadDoesNotReadOrHoldAttachmentBytes() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let archive = NotebookArchive(fileURL: root.appendingPathComponent("journal"), key: SymmetricKey(size: .bits256))
        let original = book(); try archive.save(original)
        let metadata = try archive.loadMetadata()
        XCTAssertNil(metadata.trips[0].entries[0].photo); XCTAssertNotNil(metadata.trips[0].entries[0].photoReference)
        XCTAssertTrue(metadata.trips[0].essentials!.documents[0].data.isEmpty)
        XCTAssertEqual(metadata.trips[0].essentials!.documents[0].byteCount, "private ticket text".utf8.count)
        let photo = metadata.trips[0].entries[0].photoReference!
        try FileManager.default.removeItem(at: archive.attachmentsURL.appendingPathComponent(photo.blobID))
        XCTAssertNoThrow(try archive.loadMetadata()); XCTAssertThrowsError(try archive.read(photo))
    }
    func testVersionTwoReferenceMetadataUpgradesWithoutLoadingPayload() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let key = SymmetricKey(size: .bits256)
        let archive = NotebookArchive(fileURL: root.appendingPathComponent("journal"), key: key)
        let original = book(); try archive.save(original)
        let metadata = try archive.loadMetadata()
        func legacy(_ value: Any) -> Any {
            if let array = value as? [Any] { return array.map(legacy) }
            guard var object = value as? [String: Any] else { return value }
            for (reference, field) in [("photoReference", "photo"), ("attachment", "data")] {
                if let ref = object.removeValue(forKey: reference) as? [String: Any], let id = ref["blobID"] as? String { object[field] = "roam-blob-v1:" + id }
            }
            return object.mapValues(legacy)
        }
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(metadata))
        let payload = try JSONSerialization.data(withJSONObject: legacy(json))
        try (Data("RJAR2\n".utf8) + AES.GCM.seal(payload, using: key).combined!).write(to: archive.fileURL)
        XCTAssertEqual(try archive.load(), original)
        XCTAssertEqual(try archive.loadMetadata(), metadata)
        try archive.save(metadata)
        XCTAssertTrue(try Data(contentsOf: archive.fileURL).starts(with: Data("RJAR3\n".utf8)))
        XCTAssertEqual(try archive.load(), original)
    }
    func testFailedStreamingExportRemovesPartialFile() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let archive = NotebookArchive(fileURL: root.appendingPathComponent("journal"), key: SymmetricKey(size: .bits256)); try archive.save(book())
        let url = root.appendingPathComponent("backup")
        XCTAssertThrowsError(try StreamingBackup.write(archive.loadMetadata(), code: NotebookBackup.recoveryCode(), to: url) { _ in throw NotebookError.invalidContent })
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
    func testStreamingBackupRoundTripAcrossArchiveKeys() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let original = book(); let source = NotebookArchive(fileURL: root.appendingPathComponent("source"), key: SymmetricKey(size: .bits256)); try source.save(original)
        let url = root.appendingPathComponent("backup"); let code = NotebookBackup.recoveryCode()
        try StreamingBackup.write(source.loadMetadata(), code: code, to: url, readAttachment: source.read)
        let preview = try StreamingBackup.read(url, code: code); XCTAssertNil(preview.trips[0].entries[0].photo)
        let destination = NotebookArchive(fileURL: root.appendingPathComponent("destination"), key: SymmetricKey(size: .bits256))
        let imported = try StreamingBackup.read(url, code: code, storeAttachment: destination.store)
        try destination.save(imported); XCTAssertEqual(try destination.load(), original)
        let ciphertext = try Data(contentsOf: url); XCTAssertNil(ciphertext.range(of: Data("private ticket text".utf8)))
    }
    func testStreamingBackupRejectsWrongCodeCorruptionTruncationAndExtraRecords() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let archive = NotebookArchive(fileURL: root.appendingPathComponent("journal"), key: SymmetricKey(size: .bits256)); try archive.save(book())
        let url = root.appendingPathComponent("backup"); let code = NotebookBackup.recoveryCode()
        try StreamingBackup.write(archive.loadMetadata(), code: code, to: url, readAttachment: archive.read)
        let original = try Data(contentsOf: url)
        XCTAssertThrowsError(try StreamingBackup.read(url, code: NotebookBackup.recoveryCode()))
        var damaged = original; damaged[damaged.count - 1] ^= 1; try damaged.write(to: url)
        XCTAssertThrowsError(try StreamingBackup.read(url, code: code))
        try original.dropLast(20).write(to: url); XCTAssertThrowsError(try StreamingBackup.read(url, code: code))
        try (original + Data([0])).write(to: url); XCTAssertThrowsError(try StreamingBackup.read(url, code: code))
    }
    func testRecoveryPreservesDamagedFileAndPromotesOnlyVerifiedArchive() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let damaged = root.appendingPathComponent("damaged"); try Data("corrupt journal".utf8).write(to: damaged)
        let pointer = root.appendingPathComponent("active"); try Data("old".utf8).write(to: pointer)
        let name = UUID().uuidString; let new = NotebookArchive(fileURL: root.appendingPathComponent(name), key: SymmetricKey(size: .bits256))
        var invalid = book(); invalid.trips[0].destination = ""
        XCTAssertThrowsError(try JournalRecovery.install(invalid, into: new, pointer: pointer, directory: name))
        XCTAssertEqual(try String(contentsOf: pointer, encoding: .utf8), "old")
        _ = try JournalRecovery.install(book(), into: new, pointer: pointer, directory: name)
        XCTAssertEqual(try String(contentsOf: pointer, encoding: .utf8), name)
        XCTAssertEqual(try String(contentsOf: damaged, encoding: .utf8), "corrupt journal")
    }
    func testRecentlyDeletedExpiryPreservesLiveTripsAndRecentCopies() throws {
        let now = Date(); var book = book(); let trip = book.trips[0]
        book.deletedTrips = [DeletedTrip(trip: trip, deletedAt: now.addingTimeInterval(-31 * 86400)), DeletedTrip(trip: trip, deletedAt: now)]
        book.deletedEntries = [DeletedEntry(tripID: trip.id, entry: trip.entries[0], deletedAt: now.addingTimeInterval(-31 * 86400))]
        book.purgeExpiredDeletions(now: now)
        XCTAssertEqual(book.trips, [trip]); XCTAssertEqual(book.deletedTrips?.count, 1); XCTAssertEqual(book.deletedEntries?.count, 0)
    }
    func testAdditiveRestoreKeepsRecoveryParentLinksWithNewIdentities() throws {
        var source = book(); let trip = source.trips[0]
        source.deletedEntries = [DeletedEntry(tripID: trip.id, entry: trip.entries[0])]
        let restored = try NotebookBackup.contentForRestore(source)
        XCTAssertNotEqual(restored.trips[0].id, trip.id)
        XCTAssertEqual(restored.deletedEntries?.first?.tripID, restored.trips[0].id)
        XCTAssertNotEqual(restored.deletedEntries?.first?.entry.id, trip.entries[0].id)
    }
    func testDeletedPayloadsSurviveLazyArchiveAndStreamingBackup() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        var book = book(); book.deletedTrips = [DeletedTrip(trip: book.trips.removeFirst())]
        let archive = NotebookArchive(fileURL: root.appendingPathComponent("journal"), key: SymmetricKey(size: .bits256)); try archive.save(book)
        XCTAssertEqual(try archive.load(), book)
        let url = root.appendingPathComponent("backup"); let code = NotebookBackup.recoveryCode()
        try StreamingBackup.write(archive.loadMetadata(), code: code, to: url, readAttachment: archive.read)
        XCTAssertEqual(try StreamingBackup.read(url, code: code).deletedTrips?.count, 1)
    }
    func testTicketParserOffersOnlyKnownCandidatesAndUnambiguousDates() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let airlines = AirlineCatalog(airlines: try JSONDecoder().decode([Airline].self, from: Data(contentsOf: root.appendingPathComponent("RoamJournal/Resources/AirlineCatalog.json"))))
        let airports = AirportCatalog(airports: try JSONDecoder().decode([Airport].self, from: Data(contentsOf: root.appendingPathComponent("RoamJournal/Resources/AirportCatalog.json"))))
        let result = TicketParser.parse("MU8642 KUL PVG 2026-11-30 16:20 31 OCT 2026 14:00 PNR: ABC123 12/11/26 ZZ123", airlines: airlines, airports: airports)
        XCTAssertEqual(result.flightNumbers, ["MU8642"]); XCTAssertTrue(result.airportCodes.contains("KUL")); XCTAssertEqual(result.bookingReference, "ABC123"); XCTAssertEqual(result.dateTimes.count, 2)
        XCTAssertNotNil(result.dateTimes[0].date(in: TimeZone(identifier: "Asia/Kuala_Lumpur")!))
    }
    @MainActor func testQueuedMutationsReadSuccessiveState() async {
        let gate = MutationGate(); let probe = CounterProbe()
        let tasks = (0..<100).map { _ in Task { @MainActor in
            await gate.acquire(); defer { gate.release() }
            let before = probe.count; await Task.yield(); probe.count = before + 1
        } }
        for task in tasks { await task.value }
        XCTAssertEqual(probe.count, 100)
    }
    @MainActor private final class CounterProbe { var count = 0 }
}
