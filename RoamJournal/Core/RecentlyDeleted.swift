import Foundation

public struct DeletedTrip: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var trip: TravelTrip
    public var deletedAt: Date
    public init(trip: TravelTrip, deletedAt: Date = .now) { self.trip = trip; self.deletedAt = deletedAt }
}
public struct DeletedEntry: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var tripID: UUID
    public var entry: TravelEntry
    public var deletedAt: Date
    public init(tripID: UUID, entry: TravelEntry, deletedAt: Date = .now) { self.tripID = tripID; self.entry = entry; self.deletedAt = deletedAt }
}
extension TravelNotebook {
    public mutating func purgeExpiredDeletions(now: Date = .now) {
        let cutoff = now.addingTimeInterval(-30 * 86400)
        deletedTrips?.removeAll { $0.deletedAt < cutoff }; deletedEntries?.removeAll { $0.deletedAt < cutoff }
    }
}
