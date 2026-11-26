import SwiftUI
import UIKit

struct TripsScreen: View {
    @EnvironmentObject private var store: NotebookStore
    @State private var query = ""
    @State private var editor: TravelTrip?
    @State private var path: [NotebookDestination] = []
    @State private var showSettings = false
    @State private var stageFilter = "All"
    @State private var openAfterCreate: UUID?
    @AppStorage("roam.tripSort") private var sort = "journey"
    private var trips: [TravelTrip] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.notebook.trips.filter {
            (term.isEmpty || $0.destination.localizedStandardContains(term)) && (stageFilter == "All" || $0.stage.rawValue == stageFilter)
        }.sorted { left, right in
            if sort == "name" { return left.destination.localizedStandardCompare(right.destination) == .orderedAscending }
            if sort == "recent" { return left.startDate > right.startDate }
            let rank: [TripStage: Int] = [.travelling: 0, .upcoming: 1, .past: 2]
            if rank[left.stage] != rank[right.stage] { return rank[left.stage, default: 0] < rank[right.stage, default: 0] }
            return left.stage == .past ? left.startDate > right.startDate : left.startDate < right.startDate
        }
    }
    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Find a destination").font(.subheadline).foregroundStyle(.primary)
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundStyle(.primary)
                            TextField("", text: $query).accessibilityLabel("Find a destination").autocorrectionDisabled()
                            if !query.isEmpty { Button("Clear search", systemImage: "xmark.circle.fill") { query = "" }.labelStyle(.iconOnly) }
                        }.frame(minHeight: 44)
                    }
                }
                if query.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Your private travel journal").font(.caption.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                            Text("Your travels, kept close.").font(.title.bold()).fixedSize(horizontal: false, vertical: true)
                            Text("Plans, favourite places, and the moments in between.").font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        }.foregroundStyle(.white).padding(.vertical, 12)
                            .listRowBackground(LinearGradient(colors: [Color(red: 0.15, green: 0.46, blue: 0.44), Color(red: 0.08, green: 0.26, blue: 0.29)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
                if !store.notebook.trips.isEmpty {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(["All"] + TripStage.allCases.map(\.rawValue), id: \.self) { stage in
                                    Button { stageFilter = stage } label: {
                                        Text(stage).font(.subheadline.weight(.medium)).padding(.horizontal, 14).frame(minHeight: 44)
                                            .background(stageFilter == stage ? JournalPalette.accent.opacity(0.16) : Color.secondary.opacity(0.06), in: Capsule())
                                            .foregroundStyle(stageFilter == stage ? JournalPalette.accent : .primary)
                                    }.buttonStyle(.plain).accessibilityValue(stageFilter == stage ? "Selected" : "")
                                }
                            }
                        }
                    }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
                if trips.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label(store.notebook.trips.isEmpty ? "Start a new chapter" : "No matching trips", systemImage: store.notebook.trips.isEmpty ? "book.closed" : "magnifyingglass")
                        } description: { Text(store.notebook.trips.isEmpty ? "Create a trip to collect notes, places, and photos. Saved trips open with Face ID." : "Try another destination or change the trip filter.") }
                        actions: {
                            if store.notebook.trips.isEmpty { Button("Create your first trip", systemImage: "plus") { newTrip() }.buttonStyle(.borderedProminent).tint(JournalPalette.filledAccent) }
                            else { Button("Show all trips") { query = ""; stageFilter = "All" } }
                        }
                    }
                } else {
                    Section(query.isEmpty ? "Your trips" : "Search results") {
                        ForEach(trips) { trip in NavigationLink(value: NotebookDestination.trip(trip.id)) { TripCard(trip: trip) } }
                    }
                }
                Section {
                    Button { showSettings = true } label: { HStack { CloudStatusLabel(); Spacer(); Image(systemName: "chevron.right").font(.caption) } }.buttonStyle(.plain)
                } footer: { Text("Notes and photos stay hidden until you unlock a trip with Face ID.") }
            }
            .scrollDismissesKeyboard(.interactively).navigationTitle("Roam Journal")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Settings", systemImage: "gearshape") { showSettings = true } }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort trips", selection: $sort) {
                            Text("Next journeys first").tag("journey"); Text("Most recent first").tag("recent"); Text("Destination A–Z").tag("name")
                        }
                    } label: { Label("Sort trips", systemImage: "arrow.up.arrow.down") }
                    Button("New trip", systemImage: "plus") { newTrip() }
                }
            }
            .navigationDestination(for: NotebookDestination.self) { route in
                TripAccessGate(tripID: route.tripID) {
                    switch route {
                    case .trip(let id): TripScreen(tripID: id)
                    case .entry(let trip, let entry): EntryScreen(tripID: trip, entryID: entry)
                    }
                }
            }
            .onChange(of: path) { old, new in if let id = old.last?.tripID, id != new.last?.tripID { store.leaveTrip() } }
            .sheet(item: $editor, onDismiss: { if let id = openAfterCreate { openAfterCreate = nil; path.append(.trip(id)) } }) { trip in
                TripEditor(trip: trip, isNew: true, onSaved: { openAfterCreate = $0 })
            }
            .sheet(isPresented: $showSettings) { JournalSettings() }
        }
    }
    private func newTrip() {
        let date = Calendar.current.startOfDay(for: .now)
        editor = TravelTrip(destination: "", startDate: date, endDate: date)
    }
}
struct TripScreen: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var store: NotebookStore
    @Environment(\.dismiss) private var dismiss
    let tripID: UUID
    @State private var query = ""
    @State private var filter = "All"
    @State private var entryEditor: TravelEntry?
    @State private var editTrip = false
    @State private var editEssentials = false
    @State private var deleteTrip = false
    @State private var deleting: TravelEntry?
    @State private var showDelete = false
    @State private var error: String?
    private var trip: TravelTrip? { store.notebook.trips.first { $0.id == tripID } }
    private var entries: [TravelEntry] {
        guard let trip else { return [] }
        return trip.entries.filter { $0.matches(query) && (filter == "All" || $0.kind.title == filter) }.sorted { $0.date > $1.date }
    }
    private var days: [Date] { Array(Set(entries.map { Calendar.current.startOfDay(for: $0.date) })).sorted(by: >) }
    var body: some View {
        Group {
            if let trip {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(trip.dateLabel, systemImage: "calendar")
                            HStack(spacing: 16) {
                                Label("\(trip.entries.filter { $0.kind == .note }.count) notes", systemImage: "text.alignleft")
                                Label("\(trip.entries.filter { $0.kind == .place }.count) places", systemImage: "mappin.and.ellipse")
                            }.font(.subheadline).foregroundStyle(.secondary)
                        }.padding(.vertical, 6)
                    }
                    Section("Travel essentials") {
                        Button { editEssentials = true } label: {
                            Label("Flights, documents & packing", systemImage: "suitcase.rolling")
                        }
                        if let essentials = trip.essentials {
                            if !essentials.outbound.number.isEmpty { Label("Outbound · " + essentials.outbound.number, systemImage: "airplane.departure") }
                            if !essentials.returning.number.isEmpty { Label("Return · " + essentials.returning.number, systemImage: "airplane.arrival") }
                            Text("\(essentials.documents.count) documents · \(essentials.packing.filter(\.packed).count)/\(essentials.packing.count) packed").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    if store.hasDeferredCloudChanges {
                        Section {
                            Label("iCloud updates are waiting", systemImage: "icloud.and.arrow.down").foregroundStyle(JournalPalette.accent)
                            Text(store.remoteDeletionMessage(tripID: tripID) ?? "Finish your edits, then return to the trip list to refresh.").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Section {
                        Picker("Entry type", selection: $filter) { Text("All").tag("All"); Text("Notes").tag("Note"); Text("Places").tag("Place") }.pickerStyle(.segmented)
                    }
                    if entries.isEmpty {
                        Section {
                            ContentUnavailableView {
                                Label(trip.entries.isEmpty ? "Keep the little things" : "No matching entries", systemImage: "square.and.pencil")
                            } description: { Text(trip.entries.isEmpty ? "Write a plan, remember a moment, or save somewhere you’d like to go." : "Try another search or entry type.") }
                            actions: {
                                if trip.entries.isEmpty { Button("Write a note") { add(.note) }.buttonStyle(.borderedProminent).tint(JournalPalette.filledAccent) }
                                else { Button("Show all entries") { query = ""; filter = "All" } }
                            }
                        }
                    } else {
                        ForEach(days, id: \.self) { day in
                            Section {
                                ForEach(entries.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }) { row($0) }
                            } header: { Text(day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))) }
                        }
                    }
                    Section { ShareLink(item: trip.exportText) { Label("Share trip text…", systemImage: "square.and.arrow.up") } }
                    footer: { Text("Shares unencrypted entry text, saved addresses and map links, without photos.") }
                }
                .scrollDismissesKeyboard(.interactively).navigationTitle(trip.destination)
                .searchable(text: $query, prompt: "Search this trip")
                .safeAreaInset(edge: .bottom) {
                    let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
                    layout {
                        Button { add(.note) } label: { Label("Write a note", systemImage: "square.and.pencil").frame(maxWidth: .infinity) }
                        Button { add(.place) } label: { Label("Save a place", systemImage: "mappin.and.ellipse").frame(maxWidth: .infinity) }
                    }.buttonStyle(.borderedProminent).tint(JournalPalette.filledAccent).controlSize(.large).padding().background(.bar)
                }
                .toolbar {
                    Menu {
                        Button("Edit trip", systemImage: "pencil") { editTrip = true }
                        Button("Lock trip", systemImage: "lock") { store.lockTrip() }
                        Button("Delete trip", systemImage: "trash", role: .destructive) { deleteTrip = true }
                    } label: { Label("Trip actions", systemImage: "ellipsis.circle") }
                }
                .sheet(isPresented: $editTrip) { TripEditor(trip: trip, isNew: false) }
                .sheet(isPresented: $editEssentials) { TripEssentialsEditor(trip: trip) }
                .confirmationDialog("Delete this trip?", isPresented: $deleteTrip, titleVisibility: .visible) {
                    Button("Delete trip and all entries", role: .destructive) { Task { do { try await store.deleteTrip(tripID); dismiss() } catch { self.error = error.localizedDescription } } }
                } message: { Text("This removes all notes, places, photos, flights, documents, and packing items. This cannot be undone.") }
            } else { ContentUnavailableView("Trip unavailable", systemImage: "book.closed") }
        }
        .sheet(item: $entryEditor) { entry in EntryEditor(entry: entry, tripID: tripID, isNew: !(trip?.entries.contains { $0.id == entry.id } ?? false)) }
        .confirmationDialog("Delete this entry?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Delete entry", role: .destructive) {
                guard let entry = deleting else { return }
                Task { do { try await store.deleteEntry(entry.id, tripID: tripID) } catch { self.error = error.localizedDescription } }
                deleting = nil
            }
        } message: { Text("The entry and its attached photo will be removed. This cannot be undone.") }
        .alert("Couldn’t save changes", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
    private func add(_ kind: EntryKind) { entryEditor = TravelEntry(kind: kind, title: "") }
    private func row(_ entry: TravelEntry) -> some View {
        NavigationLink(value: NotebookDestination.entry(tripID, entry.id)) {
            HStack(alignment: .top, spacing: 14) {
                if entry.hasPhoto {
                    NotebookImage(data: entry.photo, reference: entry.photoReference, tripID: tripID, pixels: 160).frame(width: 64, height: 72).clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
                } else {
                    Image(systemName: entry.kind.symbol).font(.title3).foregroundStyle(JournalPalette.accent).frame(width: 48, height: 48).background(JournalPalette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.title).font(.headline).foregroundStyle(.primary)
                    if !entry.text.isEmpty { Text(entry.text).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                    if let place = entry.place, !place.address.isEmpty { Text(place.address).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    Text(entry.kind.title).font(.caption).foregroundStyle(JournalPalette.accent)
                }
            }.padding(.vertical, 6).accessibilityElement(children: .combine)
        }.swipeActions {
            Button("Delete", role: .destructive) { deleting = entry; showDelete = true }
            Button("Edit") { entryEditor = entry }.tint(JournalPalette.accent)
        }
    }
}
struct EntryScreen: View {
    @EnvironmentObject private var store: NotebookStore
    let tripID: UUID
    let entryID: UUID
    @State private var editing = false
    private var entry: TravelEntry? { store.notebook.trips.first { $0.id == tripID }?.entries.first { $0.id == entryID } }
    var body: some View {
        Group {
            if let entry {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Label(entry.kind.title, systemImage: entry.kind.symbol).font(.subheadline.weight(.medium)).foregroundStyle(JournalPalette.accent)
                        Text(entry.title).font(.largeTitle.bold()).textSelection(.enabled)
                        Text(entry.date.formatted(date: .complete, time: .omitted)).font(.subheadline).foregroundStyle(.secondary)
                        if entry.hasPhoto {
                            NotebookImage(data: entry.photo, reference: entry.photoReference, tripID: tripID).clipShape(RoundedRectangle(cornerRadius: 18)).accessibilityLabel("Photo attached to \(entry.title)")
                        }
                        if let place = entry.place { SavedPlaceCard(place: place) }
                        if !entry.text.isEmpty { Text(entry.text).textSelection(.enabled) } else { Text("No additional details.").foregroundStyle(.secondary) }
                    }.frame(maxWidth: 720, alignment: .leading).padding(24).frame(maxWidth: .infinity)
                }.navigationTitle(entry.kind.title).navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("Edit") { editing = true } }
                    .sheet(isPresented: $editing) { EntryEditor(entry: entry, tripID: tripID, isNew: false) }
            } else { ContentUnavailableView("Entry unavailable", systemImage: "doc") }
        }
    }
}
