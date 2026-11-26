import Foundation
import Vision
import PDFKit
import UIKit
import ImageIO

protocol TicketRecognizing: Sendable { func text(in document: TripDocument) async throws -> String }
struct OnDeviceTicketRecognizer: TicketRecognizing {
    func text(in document: TripDocument) async throws -> String {
        let worker = Task.detached(priority: .userInitiated) {
            func recognise(_ image: CGImage) throws -> String {
                try Task.checkCancellation()
                let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.usesLanguageCorrection = true
                try VNImageRequestHandler(cgImage: image).perform([request])
                return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            }
            if document.type == "pdf", let pdf = PDFDocument(data: document.data) {
                var result = ""
                for index in 0..<min(pdf.pageCount, 10) {
                    guard let page = pdf.page(at: index) else { continue }
                    let text = page.string ?? ""
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 { result += text + "\n" }
                    else if let cg = page.thumbnail(of: CGSize(width: 1600, height: 2200), for: .mediaBox).cgImage { result += try recognise(cg) + "\n" }
                    if result.count > 200_000 { break }
                }; return String(result.prefix(200_000))
            }
            if let source = CGImageSourceCreateWithData(document.data as CFData, nil),
               let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2400, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) { return try recognise(cg) }
            throw DocumentImportError.invalid
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }
}
