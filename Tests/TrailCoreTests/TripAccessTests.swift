import XCTest
@testable import TrailCore
final class TripAccessTests: XCTestCase {
    func testTripsStartLocked() { let session = TripAccessSession(); XCTAssertFalse(session.allows(UUID())); XCTAssertNil(session.challengeID) }
    func testSuccessUnlocksOnlyRequestedTrip() {
        var session = TripAccessSession(); let trip = UUID(), other = UUID(), token = session.begin(trip)
        XCTAssertFalse(session.allows(trip)); XCTAssertTrue(session.complete(token, tripID: trip, succeeded: true))
        XCTAssertTrue(session.allows(trip)); XCTAssertFalse(session.allows(other)); XCTAssertNil(session.challengeID)
    }
    func testFailureOrCancellationLeavesTripLocked() {
        var s = TripAccessSession(); let trip = UUID(), token = s.begin(trip)
        XCTAssertFalse(s.complete(token, tripID: trip, succeeded: false)); XCTAssertFalse(s.allows(trip))
        XCTAssertFalse(s.complete(token, tripID: trip, succeeded: true)); XCTAssertFalse(s.allows(trip))
    }
    func testBackgroundOrExitInvalidatesPendingSuccess() {
        var s = TripAccessSession(); let trip = UUID(), token = s.begin(trip); s.lock()
        XCTAssertFalse(s.complete(token, tripID: trip, succeeded: true)); XCTAssertFalse(s.allows(trip))
    }
    func testSwitchingTripsRejectsOldAndMismatchedCallbacks() {
        var s = TripAccessSession(); let a = UUID(), b = UUID(), old = s.begin(a), current = s.begin(b)
        XCTAssertFalse(s.complete(old, tripID: a, succeeded: true)); XCTAssertFalse(s.complete(current, tripID: a, succeeded: true))
        XCTAssertFalse(s.allows(a)); XCTAssertFalse(s.allows(b)); XCTAssertTrue(s.complete(current, tripID: b, succeeded: true))
    }
    func testLockRevokesAccessAndRequiresNewChallenge() {
        var s = TripAccessSession(); let trip = UUID(), token = s.begin(trip)
        s.complete(token, tripID: trip, succeeded: true); s.lock(); XCTAssertFalse(s.allows(trip))
        XCTAssertFalse(s.complete(token, tripID: trip, succeeded: true)); XCTAssertTrue(s.complete(s.begin(trip), tripID: trip, succeeded: true))
    }
}
