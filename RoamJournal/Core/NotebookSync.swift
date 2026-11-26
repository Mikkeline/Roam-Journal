import Foundation
import CryptoKit

public enum SyncContent: Codable, Equatable, Sendable {
    case trip(TravelTrip)
    case entry(tripID: UUID, entry: TravelEntry)
    case deletedTrip(UUID)
    case deletedEntry(tripID: UUID, entryID: UUID)
    public var tripID: UUID {
        switch self {
        case .trip(let trip): trip.id
        case .entry(let id, _), .deletedTrip(let id), .deletedEntry(let id, _): id
        }
    }
    public var recordName: String {
        switch self {
        case .trip(let trip): "trip-" + trip.id.uuidString
        case .deletedTrip(let id): "trip-" + id.uuidString
        case .entry(_, let entry): "entry-" + entry.id.uuidString
        case .deletedEntry(_, let id): "entry-" + id.uuidString
        }
    }
    public var isDeleted: Bool {
        switch self { case .deletedTrip, .deletedEntry: true; default: false }
    }
    public func validated() throws {
        switch self {
        case .trip(let trip):
            guard trip.entries.isEmpty else { throw SyncError.invalidRecord }
            _ = try TravelNotebook(trips: [trip]).validated()
        case .entry(_, let entry):
            guard !entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  entry.place?.isValid ?? true, entry.place == nil || entry.kind == .place else { throw SyncError.invalidRecord }
        case .deletedTrip, .deletedEntry: break
        }
    }
}
public struct SyncRevision: Codable, Equatable, Comparable, Sendable {
    public var counter: Int64
    public var author: UUID
    public init(counter: Int64, author: UUID) { self.counter = counter; self.author = author }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.counter == rhs.counter ? lhs.author.uuidString < rhs.author.uuidString : lhs.counter < rhs.counter
    }
}
public struct SyncItem: Codable, Equatable, Sendable {
    public var revision: SyncRevision
    public var content: SyncContent
    public var observed: [UUID: Int64]
    public var recordName: String { content.recordName }
    public init(revision: SyncRevision, content: SyncContent) {
        self.revision = revision; self.content = content; self.observed = [revision.author: revision.counter]
    }
    public func knows(_ other: Self) -> Bool { observed[other.revision.author, default: 0] >= other.revision.counter }
    public func validated() throws {
        try content.validated()
        guard revision.counter > 0, revision.counter < Int64.max,
              observed[revision.author, default: 0] >= revision.counter,
              observed.values.allSatisfy({ $0 > 0 && $0 < Int64.max }) else { throw SyncError.invalidRecord }
    }
    public func merging(_ other: Self) throws -> Self {
        guard recordName == other.recordName, content.tripID == other.content.tripID,
              revision.counter > 0, other.revision.counter > 0 else { throw SyncError.invalidRecord }
        if content.isDeleted != other.content.isDeleted { return content.isDeleted ? self : other }
        if revision == other.revision, content != other.content { throw SyncError.invalidRecord }
        var winner = revision < other.revision ? other : self
        winner.observed.merge(observed, uniquingKeysWith: max)
        winner.observed.merge(other.observed, uniquingKeysWith: max)
        return winner
    }
}
public enum SyncError: LocalizedError {
    case invalidRecord, accountChanged, deletedItem, setupRequired, cloudReset
    public var errorDescription: String? {
        switch self {
        case .invalidRecord: "An iCloud record could not be verified. Your local journal has been kept."
        case .accountChanged: "This journal is linked to another iCloud account. Sign in to the original account to resume sync. Your local trips have been kept."
        case .deletedItem: "This item was deleted on another device. Copy your draft into a new entry to keep it."
        case .setupRequired: "iCloud sync isn’t available in this build. Your trips are saved on this device."
        case .cloudReset: "The iCloud journal was removed or reset. Local trips are safe. Turn sync off and enable it again only if you want to upload them again."
        }
    }
}
public struct NotebookSyncState: Codable, Equatable, Sendable {
    public var deviceID: UUID
    public var accountID: String
    public private(set) var counter: Int64 = 0
    public private(set) var records: [String: SyncItem] = [:]
    public init(deviceID: UUID = UUID(), accountID: String) { self.deviceID = deviceID; self.accountID = accountID }
    mutating func mapAttachments(_ transform: (Data?, AttachmentReference?) throws -> (Data?, AttachmentReference?)) rethrows {
        records = try records.mapValues { item in
            var item = item
            switch item.content {
            case .trip(let trip): item.content = .trip(try trip.mappingAttachments(transform))
            case .entry(let id, let entry): item.content = .entry(tripID: id, entry: try entry.mappingAttachments(transform))
            default: break
            }
            return item
        }
    }
    public mutating func seed(_ notebook: TravelNotebook) throws {
        _ = try notebook.validated()
        guard records.isEmpty else { throw SyncError.invalidRecord }
        for trip in notebook.trips {
            var metadata = trip; metadata.entries = []
            try write(.trip(metadata))
            for entry in trip.entries { try write(.entry(tripID: trip.id, entry: entry)) }
        }
    }
    public mutating func write(_ content: SyncContent) throws {
        try content.validated()
        if let old = records[content.recordName], old.content.tripID != content.tripID { throw SyncError.invalidRecord }
        guard counter < Int64.max - 1 else { throw SyncError.invalidRecord }
        if records[content.recordName]?.content.isDeleted == true, !content.isDeleted { throw SyncError.deletedItem }
        counter += 1
        var item = SyncItem(revision: SyncRevision(counter: counter, author: deviceID), content: content)
        if let old = records[content.recordName] { item.observed.merge(old.observed, uniquingKeysWith: max) }
        records[content.recordName] = item
    }
    public mutating func merge(_ incoming: [SyncItem]) throws {
        for item in incoming {
            try item.validated()
            if let old = records[item.recordName] {
                let merged = try old.merging(item)
                if !old.knows(item), !item.knows(old), old.content != item.content,
                   case .entry = old.content, case .entry = item.content {
                    let loser = old.revision < item.revision ? old : item
                    if case .entry(let parent, var entry) = loser.content {
                        entry.id = Self.conflictID(loser)
                        entry.title += " · Other version"
                        let copy = SyncItem(revision: loser.revision, content: .entry(tripID: parent, entry: entry))
                        if let existing = records[copy.recordName] { records[copy.recordName] = try existing.merging(copy) }
                        else { records[copy.recordName] = copy }
                    }
                }
                records[item.recordName] = merged
            } else { records[item.recordName] = item }
            counter = max(counter, item.revision.counter)
        }
    }
    public func validated() throws {
        guard !accountID.isEmpty, counter >= 0, counter < Int64.max else { throw SyncError.invalidRecord }
        for (name, item) in records {
            guard name == item.recordName, counter >= item.revision.counter else { throw SyncError.invalidRecord }
            try item.validated()
        }
    }
    private static func conflictID(_ item: SyncItem) -> UUID {
        let value = item.recordName + "|" + String(item.revision.counter) + "|" + item.revision.author.uuidString
        let b = Array(SHA256.hash(data: Data(value.utf8)))
        return UUID(uuid: (b[0],b[1],b[2],b[3],b[4],b[5],b[6],b[7],b[8],b[9],b[10],b[11],b[12],b[13],b[14],b[15]))
    }
    public func materialized() throws -> [TravelTrip] {
        var trips: [UUID: TravelTrip] = [:]
        for item in records.values {
            if case .trip(var trip) = item.content { trip.entries = []; trips[trip.id] = trip }
        }
        for item in records.values {
            if case .entry(let parent, let entry) = item.content, trips[parent] != nil { trips[parent]?.entries.append(entry) }
        }
        let result = trips.values.map { value in
            var trip = value
            trip.entries.sort { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
            return trip
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        _ = try TravelNotebook(trips: result).validated()
        return result
    }
}
