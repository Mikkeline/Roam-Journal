import Foundation
import CryptoKit

public struct NotebookArchive: Sendable {
    public let fileURL: URL
    private let key: SymmetricKey
    private static let v2 = Data("RJAR2\n".utf8)
    private static let header = Data("RJAR3\n".utf8)
    private static let prefix = "roam-blob-v1:"
    public var attachmentsURL: URL { fileURL.appendingPathExtension("attachments") }
    public var previousURL: URL { fileURL.appendingPathExtension("previous") }
    public init(fileURL: URL, key: SymmetricKey) { self.fileURL = fileURL; self.key = key }
    private func plaintext(_ data: Data) throws -> Data {
        let sealed = data.starts(with: Self.header) || data.starts(with: Self.v2) ? Data(data.dropFirst(Self.header.count)) : data
        return try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key)
    }
    private func decode(_ data: Data) throws -> TravelNotebook {
        let decoder = JSONDecoder()
        if data.starts(with: Self.v2) {
            // Upgrade the old JSON reference strings without decrypting binary sidecars.
            func upgrade(_ value: Any) throws -> Any {
                if let array = value as? [Any] { return try array.map(upgrade) }
                guard var object = value as? [String: Any] else { return value }
                for (field, replacement) in [("photo", "photoReference"), ("data", "attachment")] {
                    if let encoded = object[field] as? String, encoded.hasPrefix(Self.prefix) {
                        let id = String(encoded.dropFirst(Self.prefix.count)); guard Self.validID(id) else { throw NotebookError.invalidContent }
                        let size = try FileManager.default.attributesOfItem(atPath: attachmentsURL.appendingPathComponent(id).path)[.size] as? NSNumber
                        guard let size, size.intValue > 28 else { throw NotebookError.invalidContent }
                        object[replacement] = ["blobID": id, "byteCount": size.intValue - 28]
                        if field == "photo" { object.removeValue(forKey: field) } else { object[field] = "" }
                    }
                }
                return try object.mapValues(upgrade)
            }
            let upgraded = try upgrade(JSONSerialization.jsonObject(with: plaintext(data)))
            return try decoder.decode(TravelNotebook.self, from: JSONSerialization.data(withJSONObject: upgraded)).validated()
        }
        return try decoder.decode(TravelNotebook.self, from: plaintext(data)).validated()
    }
    public func loadMetadata() throws -> TravelNotebook {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            if FileManager.default.fileExists(atPath: previousURL.path) { throw NotebookError.invalidContent }
            return TravelNotebook()
        }
        return try decode(Data(contentsOf: fileURL))
    }
    public func load() throws -> TravelNotebook { try materialize(loadMetadata()) }
    public func materialize(_ book: TravelNotebook) throws -> TravelNotebook {
        try book.mappingAttachments { data, ref in
            if let data { return (data, nil) }
            return (try ref.map(read), nil)
        }
    }
    public func read(_ reference: AttachmentReference) throws -> Data {
        guard reference.isValid else { throw NotebookError.invalidContent }
        let bytes = try Data(contentsOf: attachmentsURL.appendingPathComponent(reference.blobID))
        let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: bytes), using: key, authenticating: Data(reference.blobID.utf8))
        guard plain.count == reference.byteCount else { throw NotebookError.invalidContent }
        return plain
    }
    public func store(_ data: Data) throws -> AttachmentReference {
        guard !data.isEmpty, data.count <= 30_000_000 else { throw NotebookError.invalidContent }
        try FileManager.default.createDirectory(at: attachmentsURL, withIntermediateDirectories: true)
        let id = HMAC<SHA256>.authenticationCode(for: data, using: key).map { String(format: "%02x", $0) }.joined()
        let ref = AttachmentReference(blobID: id, byteCount: data.count)
        let path = attachmentsURL.appendingPathComponent(id)
        if FileManager.default.fileExists(atPath: path.path) {
            // Only new/imported payloads verify existing ciphertext; routine reference saves avoid reading blobs.
            guard try read(ref) == data else { throw NotebookError.invalidContent }
        } else { try Self.writeProtected(AES.GCM.seal(data, using: key, authenticating: Data(id.utf8)).combined!, to: path) }
        return ref
    }
    public func externalize(_ book: TravelNotebook) throws -> TravelNotebook {
        try book.mappingAttachments { data, ref in
            if let data { return (nil, try store(data)) }
            if let ref { guard ref.isValid, FileManager.default.fileExists(atPath: attachmentsURL.appendingPathComponent(ref.blobID).path) else { throw NotebookError.invalidContent } }
            return (nil, ref)
        }
    }
    public func save(_ notebook: TravelNotebook) throws {
        _ = try notebook.validated()
        let metadata = try externalize(notebook)
        let fm = FileManager.default
        try fm.createDirectory(at: attachmentsURL, withIntermediateDirectories: true)
        let plain = try JSONEncoder().encode(metadata)
        let sealed = try AES.GCM.seal(plain, using: key).combined!
        if fm.fileExists(atPath: fileURL.path) {
            let old = try Data(contentsOf: fileURL)
            if !old.starts(with: Self.header) {
                let legacy = fileURL.appendingPathExtension("legacy-backup")
                if !fm.fileExists(atPath: legacy.path) { try Self.writeProtected(old, to: legacy) }
            }
            try Self.writeProtected(old, to: previousURL)
        }
        try Self.writeProtected(Self.header + sealed, to: fileURL)
        var keep = metadata.attachmentReferences.map(\.blobID).reduce(into: Set<String>()) { $0.insert($1) }
        if let old = try? Data(contentsOf: previousURL), let plain = try? plaintext(old) { keep.formUnion(Self.references(in: plain)) }
        for url in (try? fm.contentsOfDirectory(at: attachmentsURL, includingPropertiesForKeys: nil)) ?? [] where !keep.contains(url.lastPathComponent) { try? fm.removeItem(at: url) }
    }
    public func previousSnapshot() throws -> TravelNotebook { try materialize(decode(Data(contentsOf: previousURL))) }
    private static func validID(_ id: String) -> Bool { id.count == 64 && id.allSatisfy { $0.isASCII && $0.isHexDigit && !$0.isUppercase } }
    private static func references(in data: Data) -> Set<String> {
        var result = Set<String>()
        func walk(_ value: Any) {
            if let text = value as? String, text.hasPrefix(prefix) { result.insert(String(text.dropFirst(prefix.count))) }
            else if let array = value as? [Any] { array.forEach(walk) }
            else if let dict = value as? [String: Any] {
                if let id = dict["blobID"] as? String, validID(id) { result.insert(id) }
                dict.values.forEach(walk)
            }
        }
        if let value = try? JSONSerialization.jsonObject(with: data) { walk(value) }; return result
    }
    private static func writeProtected(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}
