import SwiftUI
struct RecentlyDeletedScreen: View {
    @EnvironmentObject private var store: NotebookStore
    @Environment(\.scenePhase) private var phase
    @State private var unlocked = false
    @State private var error: String?
    @State private var empty = false
    @State private var task: Task<Void, Never>?
    var body: some View {
        List {
            if unlocked {
                Section("Trips") { ForEach(store.notebook.deletedTrips ?? []) { record in
                    VStack(alignment: .leading) { Text(record.trip.destination).font(.headline); Text(record.deletedAt, style: .date).font(.caption); Button("Restore trip") { Task { do { try await store.restoreDeletedTrip(record.id) } catch { self.error = error.localizedDescription } } } }
                } }
                Section("Entries") { ForEach(store.notebook.deletedEntries ?? []) { record in
                    VStack(alignment: .leading) { Text(record.entry.title).font(.headline); Text(record.deletedAt, style: .date).font(.caption); Button("Restore entry") { Task { do { try await store.restoreDeletedEntry(record.id) } catch { self.error = error.localizedDescription } } } }
                } }
                Section { Button("Empty Recently Deleted", role: .destructive) { empty = true } } footer: { Text("Kept for up to 30 days on this device. Restored items get new identities. Restore the parent trip before restoring a deleted entry. Recovery copies are not synced; encrypted backups include them. Emptying is not forensic erasure.") }
            } else { Button("Unlock Recently Deleted", systemImage: "faceid") { unlock() } }
        }.navigationTitle("Recently Deleted").disabled(store.isSaving)
            .onChange(of: phase) { _, phase in if phase == .background { task?.cancel(); unlocked = false } }
            .onDisappear { task?.cancel(); unlocked = false }
            .confirmationDialog("Permanently remove recovery copies?", isPresented: $empty, titleVisibility: .visible) { Button("Remove recovery copies", role: .destructive) { Task { do { try await store.eraseDeleted() } catch { self.error = error.localizedDescription } } } }
            .alert("Recovery needs attention", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
    private func unlock() { task = Task { do { try await store.authorizeBackup(); unlocked = true } catch { self.error = error.localizedDescription } } }
}
