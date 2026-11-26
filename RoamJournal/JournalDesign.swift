import SwiftUI
import UIKit

enum JournalPalette {
    static let filledAccent = Color(red: 0.10, green: 0.36, blue: 0.35)
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.46, green: 0.82, blue: 0.76, alpha: 1) : UIColor(red: 0.10, green: 0.36, blue: 0.35, alpha: 1)
    })
}
enum TripStage: String, CaseIterable { case upcoming = "Upcoming", travelling = "Travelling", past = "Past"
    var symbol: String { switch self { case .upcoming: "airplane"; case .travelling: "location.fill"; case .past: "book.closed" } }
}
extension TravelTrip {
    var stage: TripStage {
        let today = Calendar.current.startOfDay(for: .now)
        if today < Calendar.current.startOfDay(for: startDate) { return .upcoming }
        if today > Calendar.current.startOfDay(for: endDate) { return .past }
        return .travelling
    }
    var dayCount: Int { max(1, (Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: startDate), to: Calendar.current.startOfDay(for: endDate)).day ?? 0) + 1) }
    var dateLabel: String { "\(startDate.formatted(date: .abbreviated, time: .omitted)) – \(endDate.formatted(date: .abbreviated, time: .omitted))" }
}
struct TripCard: View {
    let trip: TravelTrip
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(trip.stage.rawValue, systemImage: trip.stage.symbol).font(.caption.weight(.semibold)).foregroundStyle(JournalPalette.accent)
                    .padding(.horizontal, 10).padding(.vertical, 6).background(JournalPalette.accent.opacity(0.09), in: Capsule())
                Spacer(); Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary).accessibilityLabel("Locked")
            }
            Text(trip.destination).font(.title2.weight(.semibold)).foregroundStyle(.primary)
            Text(trip.dateLabel).font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Text("\(trip.dayCount) \(trip.dayCount == 1 ? "day" : "days") · \(trip.entries.count) entries")
                Spacer(); Label("Face ID", systemImage: "faceid")
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 8).accessibilityElement(children: .combine)
    }
}
struct CloudStatusLabel: View {
    @EnvironmentObject private var store: NotebookStore
    var body: some View {
        HStack(spacing: 7) {
            if store.isSyncing { ProgressView().controlSize(.small) }
            else { Image(systemName: store.cloudEnabled ? (store.cloudMessage == nil ? "icloud" : "icloud.slash") : "iphone") }
            Text(store.cloudEnabled ? (store.isSyncing ? "Syncing with iCloud" : store.hasDeferredCloudChanges ? "iCloud updates waiting" : store.cloudMessage != nil ? "Sync needs attention" : store.cloudHasPendingChanges ? "Waiting to sync" : "Synced with iCloud") : "Saved on this device")
        }.font(.caption).foregroundStyle(.secondary)
    }
}
struct JournalSettings: View {
    @EnvironmentObject private var store: NotebookStore
    @Environment(\.dismiss) private var dismiss
    @State private var enableSync = false
    @State private var disableSync = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "book.closed.fill").font(.largeTitle).foregroundStyle(JournalPalette.accent).padding(16).background(JournalPalette.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
                        VStack(alignment: .leading, spacing: 4) { Text("Roam Journal").font(.title2.bold()); Text("Your travels, kept close.").foregroundStyle(.secondary) }
                    }.padding(.vertical, 8)
                }
                Section {
                    Toggle("iCloud sync", isOn: Binding(get: { store.cloudEnabled }, set: { value in if value { enableSync = true } else { disableSync = true } }))
                        .disabled(!store.cloudAvailable || (store.isSyncing && !store.cloudEnabled))
                    CloudStatusLabel()
                    if !store.cloudAvailable { Text("This build saves on this device. iCloud is available in an iCloud-enabled build.").font(.footnote).foregroundStyle(.secondary) }
                    if let message = store.cloudMessage { Text(message).font(.callout).foregroundStyle(.secondary) }
                    if store.cloudEnabled {
                        Button("Sync now", systemImage: "arrow.triangle.2.circlepath") { store.requestCloudSync() }.disabled(store.isSyncing)
                        if let date = store.lastCloudSync { LabeledContent("Last completed sync", value: date.formatted(date: .abbreviated, time: .shortened)).font(.footnote).foregroundStyle(.secondary) }
                    }
                } header: { Text("iCloud") } footer: { Text("Optional in a supported build. Syncs trips, notes, places, and photo copies with devices using the same iCloud account. Offline edits stay here until they can sync. Face ID is still required to open trips.") }
                Section("Recovery") {
                    NavigationLink("Recently Deleted") { RecentlyDeletedScreen() }
                    NavigationLink { JournalBackupScreen() } label: { Label("Backup & restore", systemImage: "externaldrive.badge.checkmark") }
                }
                Section("Reference data") { NavigationLink("Airport & airline data") { ReferenceDataScreen() } }
                Section("Privacy") {
                    NavigationLink("Privacy policy") { PrivacyPolicyScreen() }
                    LabeledContent("Trip access") { Label("Face ID only", systemImage: "faceid").foregroundStyle(JournalPalette.accent) }
                    NavigationLink("Privacy & storage", destination: JournalPrivacyDetails())
                }
                Section("Sync behaviour") {
                    Text("Changes sync after saving, on activation, periodically while active, and with Sync now. Keep the app open to finish.")
                    Text("Independent entry edits merge. Competing offline entry edits keep an extra copy marked Other version. Concurrent trip name/date edits retain one version. Deleted items stay deleted.")
                }.font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Enable iCloud sync?", isPresented: $enableSync, titleVisibility: .visible) {
                Button("Enable iCloud sync") { Task { await store.enableCloudSync() } }
            } message: { Text("Uploads existing local trips and photo copies to your private iCloud database and downloads trips from the same account. If you removed the cloud journal, enabling again uploads local copies again. Face ID is required.") }
            .confirmationDialog("Turn off iCloud sync?", isPresented: $disableSync, titleVisibility: .visible) {
                Button("Keep data and turn off sync") { store.disableCloudSync() }
            } message: { Text("Local and cloud copies remain. Future changes stop syncing; a request already in progress may finish.") }
        }
    }
}
struct JournalPrivacyDetails: View {
    var body: some View {
        List {
            Section("Private on your device") {
                Text("The local journal and separate attachment files use AES-GCM and a random key in this device’s Keychain. The key is not uploaded to iCloud. The app can decrypt data while the device is unlocked.")
                Text("Saved trips require Face ID. Leaving a trip or backgrounding locks access. Trip names, dates, and entry counts remain visible on the home screen.")
                Text("Face ID controls access in the app; it does not add biometric access control to the archive key or prevent screenshots and runtime inspection.")
            }
            Section("Optional iCloud") {
                Text("A supported iCloud build uses your private CloudKit database. Each cloud payload has a fresh AES-GCM key in a CloudKit encrypted field. The local archive key is never shared. Apple’s account recovery and data-protection settings apply.")
                Text("Sync uploads resized attached photo copies. Turning sync off does not delete cloud copies. Deleting synced items propagates the deletion. This is not a claim of forensic secure erasure.")
            }
            Section("Maps & search") {
                Text("Place search uses Apple Maps and sends your search query to Apple. Saved maps load by default and can be hidden. Showing a map or opening Apple Maps loads the selected location through Apple’s services. Use my location requests a one-time location fix with your permission to focus searches nearby. Your journal text is not included in search requests. There is no background location tracking.")
                Text("Saved names, addresses, and coordinates are part of the encrypted entry. They remain readable offline; live search and map tiles need a connection.")
            }
            Section("Photos & sharing") {
                Text("You select individual photos. A resized JPEG copy is saved without original metadata; photo-library originals remain unchanged.")
                Text("Share trip text creates an unencrypted copy including saved addresses and map links, without photos, only after unlocking the trip and choosing to share.")
            }
            Section("Keep important memories") {
                Text("The local archive is excluded from device backups because its key is device-only. With sync off, deleting the app or losing the device can lose everything. Only completed cloud uploads can be restored in a supported iCloud build.")
                Text("Sync is not historical backup. Use Backup & restore to save an encrypted file with a separate recovery code. Keep both safe; Face ID is required to manage backups.")
            }
        }.navigationTitle("Privacy & storage").navigationBarTitleDisplayMode(.inline)
    }
}
#Preview("Trip card") {
    NavigationStack { List { TripCard(trip: TravelTrip(destination: "Kyoto & Osaka")) }.navigationTitle("Roam Journal") }.tint(JournalPalette.accent)
}
#Preview("Trip card accessibility") {
    NavigationStack { List { TripCard(trip: TravelTrip(destination: "A weekend in the mountains")) }.navigationTitle("Roam Journal") }.dynamicTypeSize(.accessibility2).preferredColorScheme(.dark).tint(JournalPalette.accent)
}
