import Foundation

public struct PackingTemplate: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var items: [String]
    public init(name: String, items: [String]) { self.name = name; self.items = items }
    public var isValid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !items.isEmpty && items.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
}
/// Each command updates one responsibility and preserves other essentials and journal entries.
public enum EssentialsChange: Sendable {
    case flights(FlightItinerary, expected: FlightItinerary)
    case documents([TripDocument], expected: [TripDocument])
    case setPacked(UUID, Bool)
    case togglePacked(UUID)
    case addPacking([String])
    case renamePacking(UUID, String, expected: String)
    case removePacking(UUID)
}
extension TravelNotebook {
    public func changingEssentials(_ change: EssentialsChange, tripID: UUID) throws -> TravelNotebook {
        var next = self
        guard let index = trips.firstIndex(where: { $0.id == tripID }) else { throw NotebookEditError.changed }
        var value = trips[index].essentials ?? TripEssentials()
        switch change {
        case .flights(let flights, let expected):
            guard value.flights == expected else { throw NotebookEditError.changed }
            value.flights = flights
        case .documents(let documents, let expected):
            guard value.documents == expected else { throw NotebookEditError.changed }
            value.documents = documents
        case .togglePacked(let id):
            guard let i = value.packing.firstIndex(where: { $0.id == id }) else { throw NotebookEditError.changed }
            value.packing[i].packed.toggle()
        case .setPacked(let id, let packed):
            guard let i = value.packing.firstIndex(where: { $0.id == id }) else { throw NotebookEditError.changed }
            value.packing[i].packed = packed
        case .addPacking(let titles):
            for text in titles {
                let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { continue }
                if !value.packing.contains(where: { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }) { value.packing.append(PackingItem(title: title)) }
            }
        case .renamePacking(let id, let text, let expected):
            guard let i = value.packing.firstIndex(where: { $0.id == id }), value.packing[i].title == expected else { throw NotebookEditError.changed }
            value.packing[i].title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .removePacking(let id): value.packing.removeAll { $0.id == id }
        }
        guard value.isValid else { throw NotebookError.invalidContent }
        next.trips[index].essentials = value
        return next
    }
}
