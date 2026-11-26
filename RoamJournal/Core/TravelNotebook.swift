import Foundation
import CryptoKit

public enum EntryKind: String, Codable, CaseIterable, Sendable {
    case note, place
    public var title: String { self == .note ? "Note" : "Place" }
    public var symbol: String { self == .note ? "text.alignleft" : "mappin.and.ellipse" }
}
public struct TravelEntry: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var kind: EntryKind
    public var title: String
    public var text: String
    public var date: Date
    public var photo: Data?
    public var photoReference: AttachmentReference?
    public var place: SavedPlace?
    public init(kind: EntryKind = .note, title: String, text: String = "", date: Date = .now, photo: Data? = nil, place: SavedPlace? = nil) {
        self.kind = kind; self.title = title; self.text = text; self.date = date; self.photo = photo; self.place = place
    }
    public func matches(_ query: String) -> Bool {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty || title.localizedStandardContains(term) || text.localizedStandardContains(term) || (place?.name.localizedStandardContains(term) ?? false) || (place?.address.localizedStandardContains(term) ?? false)
    }
}
public struct TravelTrip: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var destination: String
    public var startDate: Date
    public var endDate: Date
    public var entries: [TravelEntry]
    public var essentials: TripEssentials?
    public init(destination: String, startDate: Date = .now, endDate: Date = .now, entries: [TravelEntry] = []) {
        self.destination = destination; self.startDate = startDate; self.endDate = endDate; self.entries = entries
    }
    public func matches(_ query: String) -> Bool {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty || destination.localizedStandardContains(term) || entries.contains { $0.matches(term) }
    }
    public var exportText: String {
        let dates = "\(startDate.formatted(date: .abbreviated, time: .omitted)) – \(endDate.formatted(date: .abbreviated, time: .omitted))"
        let notes = entries.sorted { $0.date < $1.date }.map { entry in
            var text = "\(entry.kind.title): \(entry.title)\n\(entry.date.formatted(date: .abbreviated, time: .omitted))\n\(entry.text)"
            if let place = entry.place { text += "\n\(place.name)\n\(place.address)\n\(place.mapsURL?.absoluteString ?? "")" }
            return text
        }.joined(separator: "\n\n")
        return "\(destination)\n\(dates)\n\n\(notes)"
    }
}
public struct TravelNotebook: Codable, Equatable, Sendable {
    public var syncState: NotebookSyncState?
    public var deletedTrips: [DeletedTrip]?
    public var deletedEntries: [DeletedEntry]?
    public var packingTemplates: [PackingTemplate]?
    public var version = 1
    public var trips: [TravelTrip] = []
    public init(trips: [TravelTrip] = []) { self.trips = trips }
    public func validated() throws -> Self {
        guard version == 1 else { throw NotebookError.unsupportedVersion }
        guard (packingTemplates ?? []).allSatisfy(\.isValid), Set((packingTemplates ?? []).map(\.id)).count == (packingTemplates ?? []).count else { throw NotebookError.invalidContent }
        let entries = trips.flatMap(\.entries)
        guard Set(entries.map(\.id)).count == entries.count,
              Set(trips.map(\.id)).count == trips.count,
              trips.allSatisfy({ trip in
                  !trip.destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  && trip.endDate >= trip.startDate
                  && (trip.essentials?.isValid ?? true)
                  && trip.entries.allSatisfy { ($0.photoReference?.isValid ?? true) && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && ($0.place?.isValid ?? true) && ($0.place == nil || $0.kind == .place) }
              }) else { throw NotebookError.invalidContent }
        if let deletedTrips { for record in deletedTrips { _ = try TravelNotebook(trips: [record.trip]).validated() } }
        if let deletedEntries { for record in deletedEntries { _ = try TravelNotebook(trips: [TravelTrip(destination: "Deleted", entries: [record.entry])]).validated() } }
        try syncState?.validated()
        return self
    }
}
public enum NotebookError: LocalizedError {
    case unsupportedVersion, invalidContent
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion: "This notebook uses an unsupported format. Update Roam Journal before opening it."
        case .invalidContent: "The notebook contains invalid trips or entries. Your saved file has not been replaced."
        }
    }
}
