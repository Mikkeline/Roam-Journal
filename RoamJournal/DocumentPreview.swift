import SwiftUI
import PDFKit
import UIKit

struct DocumentPreview: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: NotebookStore
    let document: TripDocument
    let tripID: UUID
    @State private var bytes: Data?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Group {
                if let error { ContentUnavailableView("Document unavailable", systemImage: "doc.badge.ellipsis", description: Text(error)) }
                else if bytes == nil { ProgressView("Opening document…") }
                else if document.type == "pdf" { PrivatePDFView(data: bytes ?? Data()) }
                else if document.type == "image" {
                    ScrollView { NotebookImage(data: bytes, reference: nil, tripID: tripID, pixels: 3200).frame(maxWidth: .infinity).accessibilityLabel(document.name) }
                } else if let text = String(data: bytes ?? Data(), encoding: .utf8) {
                    ScrollView { Text(text).frame(maxWidth: .infinity, alignment: .leading).padding() }
                } else { ContentUnavailableView("Preview unavailable", systemImage: "doc") }
            }.navigationTitle(document.name).navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { dismiss() } }
        }.task(id: document.id) { do { bytes = try await store.attachmentData(document.data.isEmpty ? nil : document.data, reference: document.attachment, tripID: tripID) } catch { self.error = error.localizedDescription } }
    }
}
private struct PrivatePDFView: UIViewRepresentable {
    let data: Data
    func makeUIView(context: Context) -> PDFView { let view = PDFView(); view.autoScales = true; view.document = PDFDocument(data: data); return view }
    func updateUIView(_ uiView: PDFView, context: Context) {}
}
