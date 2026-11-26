import XCTest
@testable import TrailCore
final class NotebookSyncTests: XCTestCase {
    func testOldNotebookWithoutSyncMetadataStillDecodes() throws {
        let value = TravelNotebook(trips: [TravelTrip(destination: "Kyoto")]), data = try JSONEncoder().encode(value)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("syncState")); XCTAssertEqual(try JSONDecoder().decode(TravelNotebook.self, from: data), value)
    }
    func testSeedingPreservesTripsEntriesAndPhotos() throws {
        let trip = TravelTrip(destination: "Yunnan", entries: [TravelEntry(title: "Lake", text: "Morning walk", photo: Data([1,2,3]))])
        var state = NotebookSyncState(accountID: "a"); try state.seed(TravelNotebook(trips: [trip]))
        XCTAssertEqual(try state.materialized(), [trip]); XCTAssertEqual(try JSONDecoder().decode(NotebookSyncState.self, from: JSONEncoder().encode(state)), state)
    }
    func testDuplicateEntryIDsCannotBeSilentlySynced() throws {
        let note = TravelEntry(title: "Duplicate"), notebook = TravelNotebook(trips: [TravelTrip(destination: "A", entries: [note]), TravelTrip(destination: "B", entries: [note])])
        var state = NotebookSyncState(accountID: "a"); XCTAssertThrowsError(try state.seed(notebook)); XCTAssertTrue(state.records.isEmpty)
    }
    func testChangesToDifferentEntriesMergeAcrossDevices() throws {
        let trip = TravelTrip(destination: "Shanghai"); var a = NotebookSyncState(accountID: "a"), b = NotebookSyncState(accountID: "a")
        try a.seed(TravelNotebook(trips: [trip])); try b.merge(Array(a.records.values))
        let first = TravelEntry(title: "Museum"), second = TravelEntry(kind: .place, title: "Cafe")
        try a.write(.entry(tripID: trip.id, entry: first)); try b.write(.entry(tripID: trip.id, entry: second))
        try a.merge(Array(b.records.values)); try b.merge(Array(a.records.values)); XCTAssertEqual(a.records, b.records)
        XCTAssertEqual(Set(try a.materialized()[0].entries.map(\.id)), [first.id,second.id])
    }
    func testConcurrentEditsConvergeRegardlessOfOrder() throws {
        let parent = UUID(), low = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, high = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        var note = TravelEntry(title: "Note"); let a = SyncItem(revision: SyncRevision(counter: 5, author: low), content: .entry(tripID: parent, entry: note))
        note.text = "Concurrent version"; let b = SyncItem(revision: SyncRevision(counter: 5, author: high), content: .entry(tripID: parent, entry: note))
        XCTAssertEqual(try a.merging(b).content, b.content); XCTAssertEqual(try a.merging(b), try b.merging(a))
    }
    func testConflictCopiesArePreservedAndIdempotent() throws {
        let trip = TravelTrip(destination: "Trip"), original = TravelEntry(title: "Morning", text: "Original")
        var a = NotebookSyncState(accountID: "a"), b = NotebookSyncState(accountID: "a")
        try a.seed(TravelNotebook(trips: [trip])); try a.write(.entry(tripID: trip.id, entry: original)); try b.merge(Array(a.records.values))
        var first = original, second = original; first.text = "From A"; second.text = "From B"
        try a.write(.entry(tripID: trip.id, entry: first)); try b.write(.entry(tripID: trip.id, entry: second))
        let oldA = Array(a.records.values), oldB = Array(b.records.values)
        try a.merge(oldB); try b.merge(oldA); XCTAssertEqual(a.records, b.records)
        XCTAssertEqual(Set(try a.materialized()[0].entries.map(\.text)), [first.text,second.text]); try a.merge(oldB)
        XCTAssertEqual(try a.materialized()[0].entries.count, 2)
    }
    func testSequentialEditsDoNotCreateConflictCopies() throws {
        let trip = TravelTrip(destination: "Trip"); var note = TravelEntry(title: "Note", text: "First"), state = NotebookSyncState(accountID: "a")
        try state.seed(TravelNotebook(trips: [trip])); try state.write(.entry(tripID: trip.id, entry: note)); let old = Array(state.records.values)
        note.text = "Second"; try state.write(.entry(tripID: trip.id, entry: note)); try state.merge(old)
        XCTAssertEqual(try state.materialized()[0].entries, [note])
    }
    func testDeletionWinsAndCannotBeResurrected() throws {
        let parent = UUID(), note = TravelEntry(title: "Note")
        let deleted = SyncItem(revision: SyncRevision(counter: 2, author: UUID()), content: .deletedEntry(tripID: parent, entryID: note.id))
        let edited = SyncItem(revision: SyncRevision(counter: 20, author: UUID()), content: .entry(tripID: parent, entry: note))
        XCTAssertEqual(try deleted.merging(edited), deleted); XCTAssertEqual(try edited.merging(deleted), deleted)
        var state = NotebookSyncState(accountID: "a"); try state.merge([deleted,edited]); XCTAssertThrowsError(try state.write(.entry(tripID: parent, entry: note)))
    }
    func testTripDeletionHidesOfflineEntries() throws {
        let trip = TravelTrip(destination: "Trip", entries: [TravelEntry(title: "Private")]); var state = NotebookSyncState(accountID: "a")
        try state.seed(TravelNotebook(trips: [trip])); try state.write(.deletedTrip(trip.id)); XCTAssertEqual(try state.materialized(), [])
    }
    func testReceivedRevisionsAdvanceLocalClock() throws {
        let trip = TravelTrip(destination: "Trip"); var state = NotebookSyncState(accountID: "a")
        try state.merge([SyncItem(revision: SyncRevision(counter: 100, author: UUID()), content: .trip(trip))]); try state.write(.entry(tripID: trip.id, entry: TravelEntry(title: "Note"))); XCTAssertEqual(state.counter, 101)
    }
    func testCorruptOrCrossParentRecordsAreRejected() throws {
        let note = TravelEntry(title: "Note"), revision = SyncRevision(counter: 1, author: UUID())
        let a = SyncItem(revision: revision, content: .entry(tripID: UUID(), entry: note)), b = SyncItem(revision: revision, content: .entry(tripID: UUID(), entry: note))
        XCTAssertThrowsError(try a.merging(b)); var changed = note; changed.text = "Different payload"
        XCTAssertThrowsError(try a.merging(SyncItem(revision: revision, content: .entry(tripID: a.content.tripID, entry: changed))))
    }
}
