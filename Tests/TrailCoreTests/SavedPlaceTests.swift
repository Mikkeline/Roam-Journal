import XCTest
import CryptoKit
@testable import TrailCore

final class SavedPlaceTests: XCTestCase {
    private var place: SavedPlace { SavedPlace(name: "Sample cafe", address: "Kyoto, Japan", latitude: 35.01, longitude: 135.76) }
    func testLegacyEntryWithoutLocationStillDecodes() throws {
        let entry = TravelEntry(kind: .place, title: "Manual place", text: "Meet here")
        let bytes = try JSONEncoder().encode(entry)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertNil(object["place"])
        XCTAssertEqual(try JSONDecoder().decode(TravelEntry.self, from: bytes), entry)
    }
    func testLocationSurvivesEncryptedArchiveAndSync() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let entry = TravelEntry(kind: .place, title: place.name, text: "Visit after lunch", place: place)
        let trip = TravelTrip(destination: "Kyoto", entries: [entry])
        let notebook = TravelNotebook(trips: [trip])
        let file = directory.appendingPathComponent("notebook.vault")
        let archive = NotebookArchive(fileURL: file, key: SymmetricKey(size: .bits256))
        try archive.save(notebook)
        XCTAssertEqual(try archive.load(), notebook)
        XCTAssertNil(try Data(contentsOf: file).range(of: Data(place.address.utf8)))
        var sender = NotebookSyncState(accountID: "account")
        try sender.seed(notebook)
        var receiver = NotebookSyncState(accountID: "account")
        try receiver.merge(Array(sender.records.values))
        XCTAssertEqual(try receiver.materialized(), [trip])
        XCTAssertTrue(notebook.trips[0].exportText.contains(place.address))
        XCTAssertTrue(notebook.trips[0].exportText.contains("maps.apple.com"))
    }
    func testInvalidCoordinatesAndWrongEntryTypeAreRejected() throws {
        for (lat, lon) in [(91.0,0.0),(-91.0,0.0),(0.0,181.0),(0.0,-181.0),(Double.nan,0.0),(0.0,Double.infinity)] {
            let invalid = SavedPlace(name: "Place", address: "", latitude: lat, longitude: lon)
            XCTAssertFalse(invalid.isValid)
            XCTAssertNil(invalid.mapsURL)
            let trip = TravelTrip(destination: "Trip", entries: [TravelEntry(kind: .place, title: "Place", place: invalid)])
            XCTAssertThrowsError(try TravelNotebook(trips: [trip]).validated())
        }
        let trip = TravelTrip(destination: "Trip", entries: [TravelEntry(kind: .note, title: "Note", place: place)])
        XCTAssertThrowsError(try TravelNotebook(trips: [trip]).validated())
    }
    func testMapsURLSafelyEncodesNamesAndSearchesAddress() throws {
        var special = place
        special.name = "Cafe & Tea / 咖啡 #1?"
        let url = try XCTUnwrap(special.mapsURL)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "maps.apple.com")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "q" })?.value, special.name)
        XCTAssertEqual(components.queryItems?.count, 2)
        XCTAssertTrue(TravelEntry(kind: .place, title: "Lunch", place: place).matches("KYOTO"))
    }
    func testSyncRejectsMalformedPlaceAndPreservesCompetingLocations() throws {
        let parent = TravelTrip(destination: "Trip")
        var a = NotebookSyncState(accountID: "a"), b = NotebookSyncState(accountID: "a")
        let entry = TravelEntry(kind: .place, title: "Cafe", place: place)
        try a.seed(TravelNotebook(trips: [parent])); try a.write(.entry(tripID: parent.id, entry: entry)); try b.merge(Array(a.records.values))
        var first = entry, second = entry
        first.place?.address = "First address"; second.place?.address = "Second address"
        try a.write(.entry(tripID: parent.id, entry: first)); try b.write(.entry(tripID: parent.id, entry: second))
        try a.merge(Array(b.records.values))
        XCTAssertEqual(Set(try a.materialized()[0].entries.compactMap { $0.place?.address }), ["First address", "Second address"])
        let invalid = SavedPlace(name: "Bad", address: "", latitude: 100, longitude: 10)
        XCTAssertThrowsError(try SyncContent.entry(tripID: parent.id, entry: TravelEntry(kind: .place, title: "Bad", place: invalid)).validated())
    }
}
