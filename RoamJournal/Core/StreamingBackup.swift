import Foundation
import CryptoKit

/// A sequence of individually authenticated records. Peak payload memory is bounded by one attachment.
public enum StreamingBackup {
    private static let magic = Data("ROAM-STREAM-2\n".utf8)
    public static let maximumBytes: UInt64 = 2_000_000_000
    private static func integer(_ value: UInt64) -> Data { withUnsafeBytes(of: value.bigEndian) { Data($0) } }
    private static func number(_ data: Data) -> UInt64 { data.reduce(0) { ($0 << 8) | UInt64($1) } }
    private static func read(_ count: Int, from file: FileHandle) throws -> Data {
        var data = Data()
        while data.count < count {
            guard let part = try file.read(upToCount: count - data.count), !part.isEmpty else { throw BackupError.unreadable }
            data.append(part)
        }; return data
    }
    public static func isStreaming(_ url: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        return try handle.read(upToCount: magic.count) == magic
    }
    public static func write(_ book: TravelNotebook, code: String, to url: URL, readAttachment: (AttachmentReference) throws -> Data) throws {
        var book = try book.validated(); book.syncState = nil; book.purgeExpiredDeletions()
        var inline = false; _ = book.mappingAttachments { data, ref in if data != nil { inline = true }; return (data, ref) }
        guard !inline, !FileManager.default.fileExists(atPath: url.path) else { throw BackupError.unreadable }
        let key = try NotebookBackup.key(code)
        #if os(iOS)
        _ = FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.protectionKey: FileProtectionType.complete])
        #else
        _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        #endif
        let file = try FileHandle(forWritingTo: url); defer { try? file.close() }
        var success = false; defer { if !success { try? FileManager.default.removeItem(at: url) } }
        try file.write(contentsOf: magic); var index: UInt64 = 0; var written: UInt64 = UInt64(magic.count)
        func frame(_ kind: UInt8, _ bytes: Data) throws {
            try Task.checkCancellation()
            let aad = magic + integer(index) + Data([kind])
            let sealed = try AES.GCM.seal(bytes, using: key, authenticating: aad).combined!
            written += UInt64(sealed.count + 9); guard written <= maximumBytes else { throw BackupError.tooLarge }
            try file.write(contentsOf: Data([kind]) + integer(UInt64(sealed.count))); try file.write(contentsOf: sealed); index += 1
        }
        let metadata = try JSONEncoder().encode(book)
        guard metadata.count <= 16_000_000 else { throw BackupError.tooLarge }
        try frame(0, metadata)
        for reference in book.attachmentReferences.sorted(by: { $0.blobID < $1.blobID }) {
            let bytes = try readAttachment(reference)
            guard bytes.count == reference.byteCount else { throw BackupError.unreadable }
            try frame(1, Data(reference.blobID.utf8) + bytes)
        }
        try frame(2, Data()); try file.synchronize(); success = true
    }
    /// The sink can transcode one payload at a time into a destination encrypted archive.
    public static func read(_ url: URL, code: String, storeAttachment: ((Data) throws -> AttachmentReference)? = nil) throws -> TravelNotebook {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard UInt64(size) <= maximumBytes else { throw BackupError.tooLarge }
        let key = try NotebookBackup.key(code)
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        guard try read(magic.count, from: file) == magic else { throw BackupError.unreadable }
        var index: UInt64 = 0
        func frame() throws -> (UInt8, Data) {
            try Task.checkCancellation()
            let kind = try read(1, from: file)[0]
            let length = number(try read(8, from: file))
            guard length >= 28, length <= 30_000_100 else { throw BackupError.unreadable }
            let aad = magic + integer(index) + Data([kind]); index += 1
            do { return (kind, try AES.GCM.open(AES.GCM.SealedBox(combined: read(Int(length), from: file)), using: key, authenticating: aad)) }
            catch { throw BackupError.unreadable }
        }
        let first = try frame(); guard first.0 == 0, first.1.count <= 16_000_000 else { throw BackupError.unreadable }
        var book = try JSONDecoder().decode(TravelNotebook.self, from: first.1).validated(); book.syncState = nil
        var inline = false; _ = book.mappingAttachments { data, ref in if data != nil { inline = true }; return (data, ref) }; guard !inline else { throw BackupError.unreadable }
        let expected = Dictionary(grouping: book.attachmentReferences, by: \.blobID)
        guard expected.values.allSatisfy({ $0.count == 1 }) else { throw BackupError.unreadable }
        var found = Set<String>(); var replacements: [String: AttachmentReference] = [:]
        while true {
            let record = try frame()
            if record.0 == 2 { guard record.1.isEmpty, found == Set(expected.keys), (try file.read(upToCount: 1) ?? Data()).isEmpty else { throw BackupError.unreadable }; break }
            guard record.0 == 1, record.1.count >= 64, let id = String(data: record.1.prefix(64), encoding: .utf8), let reference = expected[id]?.first, found.insert(id).inserted else { throw BackupError.unreadable }
            let payload = Data(record.1.dropFirst(64)); guard payload.count == reference.byteCount else { throw BackupError.unreadable }
            if let storeAttachment { replacements[id] = try storeAttachment(payload) }
        }
        if storeAttachment != nil {
            book = try book.mappingAttachments { data, ref in
                if let ref { guard let replaced = replacements[ref.blobID] else { throw BackupError.unreadable }; return (nil, replaced) }
                guard data == nil else { throw BackupError.unreadable }; return (nil, nil)
            }
        }
        return book
    }
}
