import Foundation

public enum NotebookEditError: LocalizedError {
    case changed
    public var errorDescription: String? { "This item changed or was deleted in another window. Keep a copy of your draft, then reopen the item before saving." }
}
extension TravelNotebook {
    public func editingTrip(_ trip: TravelTrip, expected: TravelTrip?) throws -> TravelNotebook {
        var next = self
        if let index = trips.firstIndex(where: { $0.id == trip.id }) {
            if var expected {
                var current = trips[index]; current.entries = []; expected.entries = []
                guard current == expected else { throw NotebookEditError.changed }
            }
            var edited = trip; edited.entries = trips[index].entries; next.trips[index] = edited
        } else {
            guard expected == nil else { throw NotebookEditError.changed }
            next.trips.append(trip)
        }
        return next
    }
    public func editingEntry(_ entry: TravelEntry, tripID: UUID, expected: TravelEntry?) throws -> TravelNotebook {
        var next = self
        guard let i = trips.firstIndex(where: { $0.id == tripID }) else { throw NotebookEditError.changed }
        if let j = trips[i].entries.firstIndex(where: { $0.id == entry.id }) {
            if let expected, expected != trips[i].entries[j] { throw NotebookEditError.changed }
            next.trips[i].entries[j] = entry
        } else {
            guard expected == nil else { throw NotebookEditError.changed }
            next.trips[i].entries.append(entry)
        }
        return next
    }
}
