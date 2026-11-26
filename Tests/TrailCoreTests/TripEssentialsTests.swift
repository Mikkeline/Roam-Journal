import XCTest
import CryptoKit
@testable import TrailCore

final class TripEssentialsTests: XCTestCase {
    func testOldTripWithoutEssentialsStillDecodes() throws {
        let trip = TravelTrip(destination: "Shanghai")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(trip)) as? [String: Any])
        json.removeValue(forKey: "essentials")
        let restored = try JSONDecoder().decode(TravelTrip.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(restored.essentials)
        XCTAssertEqual(restored.destination, "Shanghai")
    }
    func testEssentialsEncryptedArchiveRoundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let archive = NotebookArchive(fileURL: folder.appendingPathComponent("journal.vault"), key: SymmetricKey(size: .bits256))
        var trip = TravelTrip(destination: "Shanghai")
        var details = TripEssentials()
        details.outbound.number = "MU8642"; details.returning.number = "MU1234"
        details.packing = [PackingItem(title: "Passport")]; details.packing[0].packed = true
        details.documents = [TripDocument(name: "booking.txt", type: "text", data: Data("private booking confirmation".utf8))]
        trip.essentials = details
        let book = TravelNotebook(trips: [trip]); try archive.save(book)
        XCTAssertEqual(try archive.load(), book)
        let ciphertext = try Data(contentsOf: archive.fileURL)
        XCTAssertNil(ciphertext.range(of: Data("private booking confirmation".utf8)))
        XCTAssertNil(ciphertext.range(of: Data("MU8642".utf8)))
    }
    func testEssentialsSurviveSyncAndEntryChanges() throws {
        var trip = TravelTrip(destination: "Kunming"); trip.essentials = TripEssentials()
        trip.essentials?.returning.number = "MH123"
        trip.essentials?.documents = [TripDocument(name: "ticket.txt", type: "text", data: Data("ticket".utf8))]
        var source = NotebookSyncState(accountID: "owner"); try source.seed(TravelNotebook(trips: [trip]))
        var remote = NotebookSyncState(accountID: "owner"); try remote.merge(Array(source.records.values))
        let entry = TravelEntry(title: "Arrival")
        try remote.write(.entry(tripID: trip.id, entry: entry))
        try source.merge(Array(remote.records.values))
        let restored = try XCTUnwrap(source.materialized().first)
        XCTAssertEqual(restored.essentials, trip.essentials)
        XCTAssertEqual(restored.entries, [entry])
    }
    func testInvalidAttachmentsRejectedByArchiveAndSync() throws {
        var trip = TravelTrip(destination: "Trip"); trip.essentials = TripEssentials()
        trip.essentials?.documents = [TripDocument(name: "empty.pdf", type: "pdf", data: Data())]
        XCTAssertThrowsError(try TravelNotebook(trips: [trip]).validated())
        XCTAssertThrowsError(try SyncContent.trip(trip).validated())
        trip.essentials?.documents = [TripDocument(name: "large.pdf", type: "pdf", data: Data(repeating: 1, count: 10_000_001))]
        XCTAssertThrowsError(try TravelNotebook(trips: [trip]).validated())
    }
    func testDuplicatePackingIDsAndTotalDocumentLimitRejected() {
        var details = TripEssentials(); let item = PackingItem(title: "Charger")
        details.packing = [item, item]; XCTAssertFalse(details.isValid)
        details.packing = []
        details.documents = (0..<4).map { TripDocument(name: "\($0).pdf", type: "pdf", data: Data(repeating: 1, count: 8_000_000)) }
        XCTAssertFalse(details.isValid)
    }
}
