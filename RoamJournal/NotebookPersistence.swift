import Foundation

actor NotebookPersistence {
    private var archive: NotebookArchive?
    private var cache: [AttachmentReference: Data] = [:]
    private var cacheBytes = 0
    func load(_ value: NotebookArchive) throws -> TravelNotebook {
        var notebook = try value.loadMetadata()
        var inline = false; _ = notebook.mappingAttachments { data, ref in if data != nil { inline = true }; return (data, ref) }
        if inline { try value.save(notebook); notebook = try value.loadMetadata() }
        archive = value; return notebook
    }
    func save(_ notebook: TravelNotebook) throws -> TravelNotebook {
        guard let archive else { throw NotebookError.invalidContent }
        try archive.save(notebook); return try archive.loadMetadata()
    }
    func read(_ reference: AttachmentReference) throws -> Data {
        if let hit = cache[reference] { return hit }
        guard let archive else { throw NotebookError.invalidContent }
        let data = try archive.read(reference)
        if data.count <= 8_000_000 {
            if cacheBytes + data.count > 24_000_000 { clearCache() }
            cache[reference] = data; cacheBytes += data.count
        }; return data
    }
    func clearCache() { cache.removeAll(); cacheBytes = 0 }
    func materialize(_ notebook: TravelNotebook) throws -> TravelNotebook {
        guard let archive else { throw NotebookError.invalidContent }; return try archive.materialize(notebook)
    }
    func export(_ notebook: TravelNotebook, code: String, to url: URL) throws {
        guard let archive else { throw NotebookError.invalidContent }
        let metadata = try archive.externalize(notebook)
        try StreamingBackup.write(metadata, code: code, to: url, readAttachment: archive.read)
    }
    func importFile(_ url: URL, code: String) throws -> TravelNotebook {
        guard let archive else { throw NotebookError.invalidContent }
        if try StreamingBackup.isStreaming(url) { return try StreamingBackup.read(url, code: code, storeAttachment: archive.store) }
        return try readLegacy(url, code: code)
    }
    func installFile(_ url: URL, code: String, archive: NotebookArchive, pointer: URL, directory: String) throws -> TravelNotebook {
        let book = try StreamingBackup.isStreaming(url) ? StreamingBackup.read(url, code: code, storeAttachment: archive.store) : readLegacy(url, code: code)
        return try install(book, archive: archive, pointer: pointer, directory: directory)
    }
    private func readLegacy(_ url: URL, code: String) throws -> TravelNotebook {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= NotebookBackup.maximumBytes else { throw BackupError.tooLarge }
        return try NotebookBackup.open(Data(contentsOf: url), code: code)
    }
    func previous(_ archive: NotebookArchive) throws -> TravelNotebook { try archive.previousSnapshot() }
    func install(_ notebook: TravelNotebook, archive: NotebookArchive, pointer: URL, directory: String) throws -> TravelNotebook {
        let verified = try JournalRecovery.install(notebook, into: archive, pointer: pointer, directory: directory)
        self.archive = archive; clearCache(); return verified
    }
}
