import SwiftUI
import PhotosUI
import ImageIO
import UIKit

struct TripEditor: View {
    @EnvironmentObject private var store: NotebookStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TravelTrip
    private let original: TravelTrip
    let isNew: Bool
    let onSaved: ((UUID) -> Void)?
    @FocusState private var destinationFocused: Bool
    @State private var error: String?
    @State private var discard = false
    private var dirty: Bool { draft != original }
    init(trip: TravelTrip, isNew: Bool, onSaved: ((UUID) -> Void)? = nil) {
        original = trip; _draft = State(initialValue: trip); self.isNew = isNew; self.onSaved = onSaved
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Where are you heading?") {
                    TextField("Destination or trip name", text: $draft.destination).textInputAutocapitalization(.words).accessibilityLabel("Trip destination")
                        .focused($destinationFocused).submitLabel(.done).onSubmit { destinationFocused = false }
                }
                Section("Travel dates") {
                    DatePicker("Starts", selection: $draft.startDate, displayedComponents: .date)
                    DatePicker("Ends", selection: $draft.endDate, in: draft.startDate..., displayedComponents: .date)
                }
                Section { Label(store.cloudEnabled ? "Saved here · iCloud sync enabled" : "Saved on this device", systemImage: "lock.fill").foregroundStyle(.secondary) }
                footer: { Text("Add notes, places, and photos once the trip is created.") }
            }.disabled(store.isSaving).navigationTitle(isNew ? "New trip" : "Edit trip").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if dirty { discard = true } else { dismiss() } }.disabled(store.isSaving) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(store.isSaving ? "Saving…" : "Save") {
                            var trip = draft; trip.destination = trip.destination.trimmingCharacters(in: .whitespacesAndNewlines)
                            Task { do { try await store.saveTrip(trip, replacing: isNew ? nil : original); onSaved?(trip.id); dismiss() } catch { self.error = error.localizedDescription } }
                        }.disabled(store.isSaving || draft.destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.endDate < draft.startDate)
                    }
                }
                .task { if isNew { destinationFocused = true } }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: draft.startDate) { _, date in if draft.endDate < date { draft.endDate = date } }
                .interactiveDismissDisabled(dirty || store.isSaving)
                .confirmationDialog("Discard unsaved changes?", isPresented: $discard, titleVisibility: .visible) { Button("Discard changes", role: .destructive) { dismiss() } }
                .alert("Trip wasn’t saved", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        }
    }
}
struct EntryEditor: View {
    @EnvironmentObject private var store: NotebookStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TravelEntry
    private let original: TravelEntry
    let tripID: UUID
    let isNew: Bool
    private enum Field: Hashable { case title, details }
    @FocusState private var focusedField: Field?
    @State private var showPlaceSearch = false
    @State private var photoSelection: PhotosPickerItem?
    @State private var loadingPhoto = false
    @State private var error: String?
    @State private var discard = false
    private var dirty: Bool { draft != original }
    init(entry: TravelEntry, tripID: UUID, isNew: Bool) {
        original = entry; _draft = State(initialValue: entry); self.tripID = tripID; self.isNew = isNew
    }
    var body: some View {
        let photoLabel = draft.hasPhoto ? "Replace photo" : "Add a photo"
        return NavigationStack {
            Form {
                Section {
                    Picker("Entry type", selection: $draft.kind) { ForEach(EntryKind.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) } }
                    TextField(draft.kind == .place ? "Place name" : "Note title", text: $draft.title).textInputAutocapitalization(.sentences).accessibilityLabel("Entry title").focused($focusedField, equals: .title)
                    DatePicker("Date", selection: $draft.date, displayedComponents: .date)
                }
                if draft.kind == .place {
                    Section {
                        if let place = draft.place {
                            SavedPlaceCard(place: place, allowsExternalMaps: false)
                            Button("Change location", systemImage: "magnifyingglass") { focusedField = nil; showPlaceSearch = true }
                            Button("Remove location", role: .destructive) { draft.place = nil }
                        } else {
                            Button("Search Apple Maps", systemImage: "map") { focusedField = nil; showPlaceSearch = true }
                        }
                    } header: { Text("Location") } footer: { Text("Search to attach a name, address, and map pin, or enter a place manually above. Searches require internet.") }
                }
                Section(draft.kind == .place ? "Things to remember" : "Your note") {
                    TextField(draft.kind == .place ? "Address, opening hours, or why you want to go…" : "Plans, moments, little details…", text: $draft.text, axis: .vertical)
                        .lineLimit(8...24).accessibilityLabel("Entry details").focused($focusedField, equals: .details)
                }
                Section {
                    if draft.hasPhoto {
                        NotebookImage(data: draft.photo, reference: draft.photoReference, tripID: tripID).frame(maxHeight: 240).accessibilityLabel("Attached photo preview")
                        Button("Remove photo", role: .destructive) { draft.photo = nil; draft.photoReference = nil; photoSelection = nil }.disabled(loadingPhoto)
                    }
                    PhotosPicker(selection: $photoSelection, matching: .images) { Label(photoLabel, systemImage: "photo.badge.plus") }.disabled(loadingPhoto)
                    if loadingPhoto { ProgressView("Preparing photo…") }
                } header: { Text("Photo") } footer: { Text("One resized photo per entry. The original in your library stays unchanged.") }
                Section {
                    Label("Tap Save to keep this entry", systemImage: "lock.fill").font(.footnote).foregroundStyle(.secondary)
                    if store.hasDeferredCloudChanges { Text(store.remoteDeletionMessage(tripID: tripID, entryID: draft.id) ?? "iCloud updates are waiting. Finish the draft, then close the trip to refresh.").font(.footnote).foregroundStyle(.secondary) }
                }
            }.disabled(store.isSaving).navigationTitle(isNew ? "New entry" : "Edit entry").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if dirty { discard = true } else { dismiss() } }.disabled(store.isSaving) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(store.isSaving ? "Saving…" : "Save") {
                            var entry = draft; entry.title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
                            Task { do { try await store.saveEntry(entry, tripID: tripID, replacing: isNew ? nil : original); dismiss() } catch { self.error = error.localizedDescription } }
                        }.disabled(store.isSaving || loadingPhoto || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focusedField = nil } }
                }
                .sheet(isPresented: $showPlaceSearch) {
                    PlaceSearchScreen { place in
                        let oldName = draft.place?.name
                        if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.title == oldName { draft.title = place.name }
                        draft.place = place
                    }
                }
                .onChange(of: draft.kind) { _, kind in if kind == .note { draft.place = nil } }
                .scrollDismissesKeyboard(.interactively).interactiveDismissDisabled(dirty || loadingPhoto || store.isSaving)
                .confirmationDialog("Discard unsaved changes?", isPresented: $discard, titleVisibility: .visible) { Button("Discard changes", role: .destructive) { dismiss() } }
                .alert("Entry needs attention", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
                .task(id: photoSelection) {
                    guard let selected = photoSelection else { return }
                    loadingPhoto = true; defer { loadingPhoto = false }
                    do {
                        guard let data = try await selected.loadTransferable(type: Data.self), data.count <= 30_000_000 else { throw PhotoError.unavailable }
                        try Task.checkCancellation()
                        let photo = try await Task.detached(priority: .userInitiated) { try preparePhoto(data) }.value
                        try Task.checkCancellation(); draft.photo = photo; draft.photoReference = nil
                    } catch is CancellationError {} catch { self.error = error.localizedDescription }
                }
        }
    }
}
private enum PhotoError: LocalizedError {
    case unavailable
    var errorDescription: String? { "This photo could not be added. Choose an image smaller than 30 MB. If it is stored in iCloud, download it in Photos first." }
}
private func preparePhoto(_ data: Data) throws -> Data {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1600] as CFDictionary),
          let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.8) else { throw PhotoError.unavailable }
    return jpeg
}
