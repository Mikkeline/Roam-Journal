import SwiftUI
import Combine
import CloudKit
import UIKit

@main struct RoamJournalApp: App {
    @StateObject private var store = NotebookStore()
    var body: some Scene { WindowGroup { NotebookRoot(store: store) } }
}
struct NotebookRoot: View {
    @Environment(\.scenePhase) private var phase
    @ObservedObject var store: NotebookStore
    @State private var sceneID = UUID()
    private var testColorScheme: ColorScheme? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-roam-ui-test-dark") { return .dark }
        if ProcessInfo.processInfo.arguments.contains("-roam-ui-test-light") { return .light }
        #endif
        return nil
    }
    var body: some View {
        Group {
            if store.isReady { TripsScreen().id(store.navigationResetID) }
            else {
                NavigationStack { ContentUnavailableView {
                    Label("Notebook unavailable", systemImage: "lock.trianglebadge.exclamationmark")
                } description: { Text(store.loadError ?? "Opening your journal…") }
                actions: {
                    Button("Try again") { Task { await store.open() } }.buttonStyle(.borderedProminent).tint(JournalPalette.filledAccent).disabled(store.isOpening)
                    NavigationLink("Recover from encrypted backup") { JournalBackupScreen() }.disabled(store.isOpening)
                } }
            }
        }
        .preferredColorScheme(testColorScheme)
        .environmentObject(store).tint(JournalPalette.accent).privacySensitive()
        .background(TripPrivacyWindow(store: store, locallyInactive: phase != .active).frame(width: 0, height: 0))
        .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged).receive(on: RunLoop.main)) { _ in store.cloudAccountChanged() }
        .onChange(of: phase, initial: true) { _, phase in
            store.updateScene(sceneID, active: phase == .active, background: phase == .background)
            if phase == .background { Task { await ThumbnailCache.shared.clear() } }
        }
        .onDisappear { store.removeScene(sceneID) }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(45)) } catch { return }
                if !store.sceneInactive { store.requestCloudSync() }
            }
        }
    }
}
