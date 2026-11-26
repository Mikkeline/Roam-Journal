import Foundation

public struct AttachmentReference: Codable, Equatable, Hashable, Sendable {
    public var blobID: String
    public var byteCount: Int
    public init(blobID: String, byteCount: Int) { self.blobID = blobID; self.byteCount = byteCount }
    public var isValid: Bool { blobID.count == 64 && blobID.allSatisfy { $0.isASCII && $0.isHexDigit && !$0.isUppercase } && byteCount > 0 && byteCount <= 30_000_000 }
}
extension TravelNotebook {
    public func mappingAttachments(_ transform: (Data?, AttachmentReference?) throws -> (Data?, AttachmentReference?)) rethrows -> TravelNotebook {
        var copy = self
        copy.trips = try trips.map { try $0.mappingAttachments(transform) }
        if var state = copy.syncState { try state.mapAttachments(transform); copy.syncState = state }
        copy.deletedTrips = try deletedTrips?.map { record in var record = record; record.trip = try record.trip.mappingAttachments(transform); return record }
        copy.deletedEntries = try deletedEntries?.map { record in var record = record; record.entry = try record.entry.mappingAttachments(transform); return record }
        return copy
    }
    public var attachmentReferences: Set<AttachmentReference> {
        var refs = Set<AttachmentReference>()
        _ = mappingAttachments { data, ref in if let ref { refs.insert(ref) }; return (data, ref) }
        return refs
    }
}
extension TravelTrip {
    func mappingAttachments(_ transform: (Data?, AttachmentReference?) throws -> (Data?, AttachmentReference?)) rethrows -> TravelTrip {
        var trip = self; trip.entries = try entries.map { try $0.mappingAttachments(transform) }
        if var details = essentials {
            details.documents = try details.documents.map { document in
                var document = document
                let mapped = try transform(document.data.isEmpty ? nil : document.data, document.attachment)
                document.data = mapped.0 ?? Data(); document.attachment = mapped.1
                return document
            }; trip.essentials = details
        }
        return trip
    }
}
extension TravelEntry {
    func mappingAttachments(_ transform: (Data?, AttachmentReference?) throws -> (Data?, AttachmentReference?)) rethrows -> TravelEntry {
        var entry = self; (entry.photo, entry.photoReference) = try transform(photo, photoReference); return entry
    }
    public var hasPhoto: Bool { photo != nil || photoReference != nil }
}
