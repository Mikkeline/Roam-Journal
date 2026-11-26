import Foundation

public struct FlightDetails: Codable, Equatable, Sendable {
    public var number = ""
    public var airline = ""
    public var automaticallyDetectedAirline: String?
    public var from = ""
    public var to = ""
    public var departure: Date?
    public var bookingReference = ""
    public var arrival: Date?
    public var departureTimeZoneID: String?
    public var arrivalTimeZoneID: String?
    public var departureTerminal: String?
    public var arrivalTerminal: String?
    public init() {}
}
public struct PackingItem: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var title: String
    public var packed = false
    public init(title: String) { self.title = title }
}
public struct TripDocument: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var type: String
    public var data: Data
    public var attachment: AttachmentReference?
    public var category: DocumentCategory?
    public var byteCount: Int { attachment?.byteCount ?? data.count }
    public init(name: String, type: String, data: Data) { self.name = name; self.type = type; self.data = data }
}
public struct TripEssentials: Codable, Equatable, Sendable {
    public var outbound = FlightDetails()
    public var returning = FlightDetails()
    public var packing: [PackingItem] = []
    public var documents: [TripDocument] = []
    public var outboundConnections: [FlightLeg]?
    public var returnConnections: [FlightLeg]?
    public init() {}
    public var isValid: Bool {
        flights.isValid
        && Set(packing.map(\.id)).count == packing.count
        && packing.allSatisfy { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        && Set(documents.map(\.id)).count == documents.count
        && documents.count <= 20
        && documents.allSatisfy { !$0.name.isEmpty && ($0.attachment?.isValid ?? !$0.data.isEmpty) && $0.byteCount <= 10_000_000 && ["pdf", "image", "text"].contains($0.type) }
        && documents.reduce(0, { $0 + $1.byteCount }) <= 30_000_000
    }
    public static let suggestedPacking = ["Passport / ID", "Visa / entry documents", "Tickets and hotel bookings", "Wallet and payment cards", "Phone and charger", "Power bank", "Travel adapter", "Medication", "Travel insurance", "Clothes and toiletries", "Comfortable shoes", "Sunscreen and umbrella"]
}
