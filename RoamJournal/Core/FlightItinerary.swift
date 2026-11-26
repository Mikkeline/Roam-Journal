import Foundation

public struct FlightLeg: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var details: FlightDetails
    public init(details: FlightDetails = FlightDetails()) { self.details = details }
}
public struct FlightItinerary: Equatable, Sendable {
    public var outbound: FlightDetails
    public var returning: FlightDetails
    public var outboundConnections: [FlightLeg]
    public var returnConnections: [FlightLeg]
    public var validationMessage: String? {
        for route in [[outbound] + outboundConnections.map(\.details), [returning] + returnConnections.map(\.details)] {
            for flight in route {
                if let zone = flight.departureTimeZoneID, TimeZone(identifier: zone) == nil { return "Choose a valid departure time zone." }
                if let zone = flight.arrivalTimeZoneID, TimeZone(identifier: zone) == nil { return "Choose a valid arrival time zone." }
                if let departure = flight.departure, let arrival = flight.arrival, arrival < departure { return "Arrival must be after departure, accounting for airport time zones." }
            }
            for (previous, next) in zip(route, route.dropFirst()) {
                if let arrival = previous.arrival, let departure = next.departure, departure < arrival { return "A connecting flight cannot depart before the previous flight arrives." }
            }
        }
        let legs = outboundConnections + returnConnections
        if legs.contains(where: { $0.details.number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { return "Add a flight number for each connection, or remove the unused connection." }
        if outboundConnections.count > 8 || returnConnections.count > 8 { return "Use up to eight connections in each direction." }
        if Set(legs.map(\.id)).count != legs.count { return "Connecting flights must have unique identities." }
        return nil
    }
    public var isValid: Bool { validationMessage == nil }
}
extension TripEssentials {
    public var flights: FlightItinerary {
        get { FlightItinerary(outbound: outbound, returning: returning, outboundConnections: outboundConnections ?? [], returnConnections: returnConnections ?? []) }
        set {
            outbound = newValue.outbound; returning = newValue.returning
            outboundConnections = newValue.outboundConnections.isEmpty ? nil : newValue.outboundConnections
            returnConnections = newValue.returnConnections.isEmpty ? nil : newValue.returnConnections
        }
    }
}
