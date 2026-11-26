import Foundation
public enum JournalRecovery {
    /// The damaged journal is never moved or removed. Publish a pointer only after the new archive verifies.
    public static func install(_ book: TravelNotebook, into archive: NotebookArchive, pointer: URL, directory: String) throws -> TravelNotebook {
        guard UUID(uuidString: directory) != nil else { throw NotebookError.invalidContent }
        try archive.save(book)
        let verified = try archive.loadMetadata()
        try Task.checkCancellation()
        try Data(directory.utf8).write(to: pointer, options: .atomic)
        return verified
    }
}
