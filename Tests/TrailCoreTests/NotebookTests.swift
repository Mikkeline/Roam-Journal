import XCTest
import CryptoKit
@testable import TrailCore
final class NotebookTests: XCTestCase {
    private func location() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: folder) }
        return folder.appendingPathComponent("notebook.vault")
    }
    private func sample() -> TravelNotebook {
        TravelNotebook(trips: [TravelTrip(destination: "上海 • Shanghai", entries: [TravelEntry(title: "A quiet morning", text: "Walk along the river", photo: Data([0,1,2,3])), TravelEntry(kind: .place, title: "豫园", text: "Visit early")])])
    }
    func testFreshNotebookAndEncryptedRoundTrip() throws {
        let url = try location(), key = SymmetricKey(size: .bits256)
        let archive = NotebookArchive(fileURL: url, key: key)
        XCTAssertEqual(try archive.load(), TravelNotebook())
        let value = sample(); try archive.save(value)
        XCTAssertEqual(try archive.load(), value)
        XCTAssertNil(try Data(contentsOf: url).range(of: Data("Walk along the river".utf8)))
    }
    func testWrongKeyAndTamperingPreserveExistingFile() throws {
        let url = try location(), key = SymmetricKey(size: .bits256)
        let archive = NotebookArchive(fileURL: url, key: key); try archive.save(sample())
        let original = try Data(contentsOf: url)
        XCTAssertThrowsError(try NotebookArchive(fileURL: url, key: SymmetricKey(size: .bits256)).load())
        XCTAssertEqual(try Data(contentsOf: url), original)
        var changed = original; changed[changed.count - 1] ^= 1; try changed.write(to: url)
        XCTAssertThrowsError(try archive.load()); XCTAssertEqual(try Data(contentsOf: url), changed)
    }
    func testTruncatedAndUnsupportedArchivesFailClosed() throws {
        let url = try location(), key = SymmetricKey(size: .bits256)
        let archive = NotebookArchive(fileURL: url, key: key)
        try Data([1,2,3]).write(to: url); XCTAssertThrowsError(try archive.load())
        var future = sample(); future.version = 2
        let bytes = try AES.GCM.seal(JSONEncoder().encode(future), using: key).combined!
        try bytes.write(to: url); XCTAssertThrowsError(try archive.load()); XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
    func testInvalidSaveDoesNotReplacePreviousNotebook() throws {
        let archive = NotebookArchive(fileURL: try location(), key: SymmetricKey(size: .bits256)), original = sample()
        try archive.save(original)
        var invalid = original; invalid.trips[0].destination = " \n "; XCTAssertThrowsError(try archive.save(invalid))
        invalid = original; invalid.trips[0].endDate = invalid.trips[0].startDate.addingTimeInterval(-1); XCTAssertThrowsError(try archive.save(invalid))
        invalid = original; invalid.trips.append(invalid.trips[0]); XCTAssertThrowsError(try archive.save(invalid))
        invalid = original; invalid.trips[0].entries[0].title = " "; XCTAssertThrowsError(try archive.save(invalid))
        XCTAssertEqual(try archive.load(), original)
    }
    func testEditsAndDeletionSurviveReopening() throws {
        let url = try location(), key = SymmetricKey(size: .bits256)
        let archive = NotebookArchive(fileURL: url, key: key)
        var notebook = sample(); try archive.save(notebook)
        notebook.trips[0].entries[0].text = "Updated plan"; notebook.trips[0].entries.removeLast(); try archive.save(notebook)
        XCTAssertEqual(try NotebookArchive(fileURL: url, key: key).load(), notebook)
        notebook.trips.removeAll(); try archive.save(notebook); XCTAssertEqual(try archive.load().trips, [])
    }
    func testSearchFindsDestinationsTitlesAndBodies() {
        let trip = sample().trips[0]
        for query in ["上海", "SHANGHAI", "quiet", "river", "豫园", "\n early  ", ""] { XCTAssertTrue(trip.matches(query), query) }
        XCTAssertFalse(trip.matches("not in this notebook"))
    }
    func testTextSharingIncludesEntriesAndExcludesPhotoBytes() {
        let trip = sample().trips[0], text = sample().trips[0].exportText
        XCTAssertTrue(text.contains("上海")); XCTAssertTrue(text.contains("A quiet morning")); XCTAssertTrue(text.contains("Visit early"))
        XCTAssertFalse(text.contains(trip.entries[0].photo!.base64EncodedString()))
    }
}
