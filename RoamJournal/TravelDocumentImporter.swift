import Foundation
import UniformTypeIdentifiers
import PDFKit
import UIKit

protocol TravelDocumentImporting: Sendable {
    func read(_ url: URL) async throws -> TripDocument
}
struct TravelDocumentImporter: TravelDocumentImporting {
    func read(_ url: URL) async throws -> TripDocument {
        try await Task.detached(priority: .userInitiated) { try readTripDocument(url) }.value
    }
}
enum DocumentImportError: LocalizedError {
    case limit, invalid
    var errorDescription: String? {
        switch self {
        case .limit: "Choose a file up to 10 MB. Each trip supports 20 documents and 30 MB total."
        case .invalid: "This file couldn’t be opened. Choose a readable PDF, image, or UTF-8 text file. Download cloud-only files in Files first."
        }
    }
}
private func readTripDocument(_ url: URL) throws -> TripDocument {
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey, .isRegularFileKey])
    guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= 10_000_000 else { throw DocumentImportError.limit }
    let data = try Data(contentsOf: url)
    guard !data.isEmpty, data.count <= 10_000_000 else { throw DocumentImportError.limit }
    let type: String
    if values.contentType?.conforms(to: .pdf) == true, PDFDocument(data: data) != nil { type = "pdf" }
    else if values.contentType?.conforms(to: .image) == true, UIImage(data: data) != nil { type = "image" }
    else if values.contentType?.conforms(to: .plainText) == true, String(data: data, encoding: .utf8) != nil { type = "text" }
    else { throw DocumentImportError.invalid }
    return TripDocument(name: url.lastPathComponent, type: type, data: data)
}
