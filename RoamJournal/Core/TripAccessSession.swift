import Foundation
public struct TripAccessSession: Equatable, Sendable {
    public private(set) var unlockedTripID: UUID?
    public private(set) var challengeID: UUID?
    public private(set) var pendingTripID: UUID?
    public init() {}
    public func allows(_ tripID: UUID) -> Bool { unlockedTripID == tripID }
    public mutating func begin(_ tripID: UUID) -> UUID {
        lock()
        let id = UUID(); challengeID = id; pendingTripID = tripID
        return id
    }
    @discardableResult
    public mutating func complete(_ challenge: UUID, tripID: UUID, succeeded: Bool) -> Bool {
        guard challengeID == challenge, pendingTripID == tripID else { return false }
        challengeID = nil; pendingTripID = nil
        if succeeded { unlockedTripID = tripID }
        return succeeded
    }
    public mutating func lock() { unlockedTripID = nil; challengeID = nil; pendingTripID = nil }
}
