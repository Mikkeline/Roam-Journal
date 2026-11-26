import SwiftUI

struct PackingScreen: View {
    @EnvironmentObject private var store: NotebookStore
    let tripID: UUID
    @State private var newItem = ""
    @State private var rename: PackingItem?
    @State private var renamedTitle = ""
    @State private var templateName = ""
    @State private var namingTemplate = false
    @State private var error: String?
    private var items: [PackingItem] { store.notebook.trips.first { $0.id == tripID }?.essentials?.packing ?? [] }
    var body: some View {
        List {
            Section {
                let packed = items.filter(\.packed).count
                ProgressView(value: Double(packed), total: Double(max(items.count, 1))) { Text("\(packed) of \(items.count) packed") }
                if store.isSaving { ProgressView("Saving…") }
            }
            Section("Still to pack") {
                ForEach(items.filter { !$0.packed }) { packingRow($0) }
                if !items.isEmpty, items.allSatisfy(\.packed) { Label("Everything is packed", systemImage: "checkmark.circle.fill").foregroundStyle(JournalPalette.accent) }
                HStack {
                    TextField("Add something to bring", text: $newItem).onSubmit { add() }
                    Button("Add") { add() }.disabled(newItem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if items.contains(where: \.packed) {
                Section("Packed") { ForEach(items.filter(\.packed)) { packingRow($0) } }
            }
            Section {
                Button("Add suggested essentials", systemImage: "checklist") { perform(.addPacking(TripEssentials.suggestedPacking)) }
                NavigationLink("Use a packing template") { PackingTemplatesScreen(tripID: tripID) }
                Button("Save this list as a template", systemImage: "square.on.square") { templateName = ""; namingTemplate = true }.disabled(items.isEmpty)
            } footer: { Text("Each change saves immediately. Use the circle to mark packed/unpacked. Swipe to rename or remove. Templates reuse item names with every item unpacked; they are included in encrypted backups and stored on this device.") }
        }
        .navigationTitle("Packing checklist").scrollDismissesKeyboard(.interactively)
        .alert("Rename packing item", isPresented: Binding(get: { rename != nil }, set: { if !$0 { rename = nil } })) {
            TextField("Item", text: $renamedTitle)
            Button("Save") { if let item = rename { perform(.renamePacking(item.id, renamedTitle, expected: item.title)) }; rename = nil }.disabled(renamedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) { rename = nil }
        }
        .alert("Save packing template", isPresented: $namingTemplate) {
            TextField("Template name", text: $templateName)
            Button("Save") { Task { do { try await store.savePackingTemplate(name: templateName, tripID: tripID) } catch { self.error = error.localizedDescription } } }.disabled(templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: { Text("For example: City break, Hiking, or Winter travel. Only item names are kept, without packed status.") }
        .alert("Packing wasn’t updated", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
    private func packingRow(_ item: PackingItem) -> some View {
        Button { perform(.togglePacked(item.id)) } label: {
            HStack(spacing: 12) {
                Image(systemName: item.packed ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(JournalPalette.accent)
                Text(item.title).strikethrough(item.packed).foregroundStyle(.primary)
                Spacer()
            }.padding(.vertical, 4).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("\(item.title), \(item.packed ? "packed" : "not packed")").accessibilityHint("Double tap to change packed status")
            .swipeActions {
                Button("Remove", role: .destructive) { perform(.removePacking(item.id)) }
                Button("Rename") { renamedTitle = item.title; rename = item }.tint(JournalPalette.accent)
            }
    }
    private func perform(_ change: EssentialsChange) { Task { do { try await store.updateEssentials(change, tripID: tripID) } catch { self.error = error.localizedDescription } } }
    private func add() {
        let title = newItem.trimmingCharacters(in: .whitespacesAndNewlines); guard !title.isEmpty else { return }
        Task { do { try await store.updateEssentials(.addPacking([title]), tripID: tripID); newItem = "" } catch { self.error = error.localizedDescription } }
    }
}
private struct PackingTemplatesScreen: View {
    @EnvironmentObject private var store: NotebookStore
    let tripID: UUID
    @State private var error: String?
    @State private var deleting: PackingTemplate?
    @State private var applied: String?
    var body: some View {
        List {
            ForEach(store.notebook.packingTemplates ?? []) { template in
                Button {
                    Task { do { try await store.updateEssentials(.addPacking(template.items), tripID: tripID); applied = template.name } catch { self.error = error.localizedDescription } }
                } label: {
                    VStack(alignment: .leading, spacing: 5) { Text(template.name).font(.headline); Text("\(template.items.count) items · Tap to add missing items").font(.caption).foregroundStyle(.secondary) }
                }.swipeActions { Button("Delete template", role: .destructive) { deleting = template } }
            }
            if (store.notebook.packingTemplates ?? []).isEmpty { ContentUnavailableView("No saved templates", systemImage: "checklist", description: Text("Create a packing list, then choose Save this list as a template.")) }
            if let applied { Text("Added missing items from \(applied). Existing items and ticks were kept.").font(.footnote).foregroundStyle(.secondary) }
        }.disabled(store.isSaving).navigationTitle("Packing templates")
            .confirmationDialog("Delete this template?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete template", role: .destructive) { if let id = deleting?.id { Task { do { try await store.deletePackingTemplate(id, tripID: tripID) } catch { self.error = error.localizedDescription } } }; deleting = nil }
            } message: { Text("Trip packing lists are kept.") }
            .alert("Template needs attention", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
}
