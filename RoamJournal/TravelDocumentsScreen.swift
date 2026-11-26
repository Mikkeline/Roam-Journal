import SwiftUI
import UniformTypeIdentifiers

struct TravelDocumentsScreen: View {
    @EnvironmentObject private var store: NotebookStore
    let tripID: UUID
    @State private var editing = false
    @State private var preview: TripDocument?
    @State private var query = ""
    @State private var category = "All"
    private var documents: [TripDocument] { store.notebook.trips.first { $0.id == tripID }?.essentials?.documents ?? [] }
    var body: some View {
        List {
            if documents.isEmpty {
                ContentUnavailableView { Label("Keep your travel papers close", systemImage: "doc.text") } description: { Text("Add tickets, hotel confirmations, insurance, and other documents for offline access.") } actions: { Button("Add documents") { editing = true } }
            }
            Section { Picker("Category", selection: $category) { Text("All").tag("All"); ForEach(DocumentCategory.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) } } }
            ForEach(documents.filter { (query.isEmpty || $0.name.localizedStandardContains(query)) && (category == "All" || ($0.category ?? .other).rawValue == category) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { document in Button { preview = document } label: { DocumentRow(document: document) }.buttonStyle(.plain) }
            Section { Text("Tap to preview offline. Use Edit to add or remove encrypted copies. Originals in Files are kept.").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("Travel documents").searchable(text: $query, prompt: "Find a document")
            .toolbar { Button("Edit") { editing = true } }
            .sheet(isPresented: $editing) { DocumentsEditor(tripID: tripID, documents: documents) }
            .sheet(item: $preview) { DocumentPreview(document: $0, tripID: tripID) }
    }
}
private struct DocumentRow: View {
    let document: TripDocument
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(document.name, systemImage: "doc.text").foregroundStyle(.primary)
            Text(ByteCountFormatter.string(fromByteCount: Int64(document.byteCount), countStyle: .file)).font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }
}
private struct DocumentsEditor: View {
    @EnvironmentObject private var store: NotebookStore
    @Environment(\.dismiss) private var dismiss
    let tripID: UUID
    let importer: any TravelDocumentImporting
    private let original: [TripDocument]
    @State private var draft: [TripDocument]
    @State private var importing = false
    @State private var loading = false
    @State private var discard = false
    @State private var deleting: TripDocument?
    @State private var error: String?
    @State private var work: Task<Void, Never>?
    init(tripID: UUID, documents: [TripDocument], importer: any TravelDocumentImporting = TravelDocumentImporter()) {
        self.tripID = tripID; self.importer = importer; original = documents; _draft = State(initialValue: documents)
    }
    private var dirty: Bool { draft != original }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach($draft) { $document in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Document name", text: $document.name)
                            Picker("Category", selection: Binding(get: { document.category ?? .other }, set: { document.category = $0 })) { ForEach(DocumentCategory.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                            Button("Remove copy", role: .destructive) { deleting = document }
                        }
                    }
                    Button("Add document from Files", systemImage: "doc.badge.plus") { importing = true }.disabled(loading || draft.count >= 20)
                    if loading { ProgressView("Importing document…") }
                } footer: { Text("PDF, images, and UTF-8 text. Up to 10 MB per file, 30 MB and 20 files per trip. Tap Save to keep changes.") }
            }.disabled(store.isSaving)
                .navigationTitle("Edit documents").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if dirty || loading { discard = true } else { dismiss() } }.disabled(store.isSaving) }
                    ToolbarItem(placement: .confirmationAction) { Button(store.isSaving ? "Saving…" : "Save") {
                        Task { do { try await store.updateEssentials(.documents(draft, expected: original), tripID: tripID); dismiss() } catch { self.error = error.localizedDescription } }
                    }.disabled(store.isSaving || loading || draft.contains { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) }
                }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image, .plainText]) { result in
                    switch result { case .success(let url): read(url); case .failure(let error): self.error = error.localizedDescription }
                }
                .interactiveDismissDisabled(dirty || loading || store.isSaving)
                .confirmationDialog("Remove this document copy?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                    Button("Remove copy", role: .destructive) { if let id = deleting?.id { draft.removeAll { $0.id == id } }; deleting = nil }
                } message: { Text("The original in Files is kept. Save to confirm removal.") }
                .confirmationDialog("Discard document changes?", isPresented: $discard, titleVisibility: .visible) { Button("Discard changes", role: .destructive) { work?.cancel(); dismiss() } }
                .alert("Documents need attention", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
                .onDisappear { work?.cancel() }
        }
    }
    private func read(_ url: URL) {
        loading = true
        work = Task { @MainActor in
            defer { loading = false }
            do {
                let document = try await importer.read(url); try Task.checkCancellation()
                var check = TripEssentials(); check.documents = draft + [document]
                guard check.isValid else { throw DocumentImportError.limit }
                draft.append(document)
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
}
