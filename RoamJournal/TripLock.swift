import SwiftUI
import UIKit

enum NotebookDestination: Hashable {
    case trip(UUID), entry(UUID, UUID)
    var tripID: UUID { switch self { case .trip(let id), .entry(let id, _): id } }
}
struct TripAccessGate<Content: View>: View {
    @EnvironmentObject private var store: NotebookStore
    let tripID: UUID
    @ViewBuilder let content: () -> Content
    @State private var hasOpened = false
    private var unlocked: Bool { store.tripAccess.allows(tripID) }
    var body: some View {
        ZStack {
            if unlocked || hasOpened { content().opacity(unlocked ? 1 : 0).disabled(!unlocked).accessibilityHidden(!unlocked) }
            if !unlocked { TripUnlockScreen(tripID: tripID).navigationTitle("Locked trip") }
        }
        .onChange(of: store.tripAccess.unlockedTripID, initial: true) { _, _ in if unlocked { hasOpened = true } }
        .task { if !unlocked && !store.requiresReauthentication { store.authenticateTrip(tripID) } }
    }
}
struct TripUnlockScreen: View {
    @EnvironmentObject private var store: NotebookStore
    let tripID: UUID
    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "faceid").font(.system(size: 56)).foregroundStyle(JournalPalette.accent).accessibilityHidden(true)
            Text("Your trip is locked").font(.title.bold())
            Text("Use Face ID to open its journal, flights, documents, and packing list.").foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let message = store.authenticationMessage { Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center) }
            if store.isAuthenticating { ProgressView("Checking Face ID…") }
            Button("Unlock with Face ID", systemImage: "faceid") { store.authenticateTrip(tripID) }
                .buttonStyle(.borderedProminent).tint(JournalPalette.filledAccent).disabled(store.isAuthenticating)
            Text("Face ID is required. There is no in-app passcode fallback.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(32).frame(maxWidth: 500).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(uiColor: .systemBackground))
    }
}
struct TripPrivacyWindow: UIViewRepresentable {
    @ObservedObject var store: NotebookStore
    var locallyInactive = false
    func makeUIView(context: Context) -> PrivacyAnchor { let view = PrivacyAnchor(); view.store = store; view.locallyInactive = locallyInactive; return view }
    func updateUIView(_ view: PrivacyAnchor, context: Context) { view.store = store; view.locallyInactive = locallyInactive; view.refresh() }
    static func dismantleUIView(_ view: PrivacyAnchor, coordinator: ()) { view.removeCover() }
    @MainActor final class PrivacyAnchor: UIView {
        var store: NotebookStore?
        var locallyInactive = false
        private var cover: UIWindow?
        override init(frame: CGRect) {
            super.init(frame: frame)
            NotificationCenter.default.addObserver(self, selector: #selector(coverBeforeInactive), name: UIApplication.willResignActiveNotification, object: nil)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        @objc private func coverBeforeInactive() { showCover() }
        override func didMoveToWindow() { super.didMoveToWindow(); refresh() }
        func refresh() {
            guard let store, let scene = window?.windowScene else { return }
            if cover?.windowScene !== scene {
                removeCover()
                let cover = UIWindow(windowScene: scene)
                cover.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
                cover.backgroundColor = .systemBackground
                let controller = UIHostingController(rootView: PrivacyWindowContent(onClose: { [weak self] in self?.closeTrip() }).environmentObject(store).tint(JournalPalette.accent))
                controller.view.accessibilityViewIsModal = true; cover.rootViewController = controller; self.cover = cover
            }
            if locallyInactive || store.sceneInactive || store.requiresReauthentication { showCover() } else { cover?.isHidden = true }
        }
        private func showCover() { window?.endEditing(true); cover?.isHidden = false }
        private func closeTrip() {
            guard let store else { return }
            if let root = window?.rootViewController, root.presentedViewController != nil { root.dismiss(animated: false) { store.closeProtectedTrip() } }
            else { store.closeProtectedTrip() }
        }
        func removeCover() { cover?.isHidden = true; cover?.rootViewController = nil; cover = nil }
    }
}
private struct PrivacyWindowContent: View {
    @EnvironmentObject private var store: NotebookStore
    let onClose: () -> Void
    @State private var confirmClose = false
    var body: some View {
        Group {
            if !store.sceneInactive, store.requiresReauthentication, let id = store.protectedTripID {
                VStack(spacing: 0) { TripUnlockScreen(tripID: id); Button("Close trip") { confirmClose = true }.padding(.bottom, 28) }
                    .confirmationDialog("Close this trip?", isPresented: $confirmClose, titleVisibility: .visible) {
                        Button("Close and discard unsaved changes", role: .destructive, action: onClose)
                    } message: { Text("Returns to the trip list. Saved entries remain; unsaved edits will be discarded.") }
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "lock.shield.fill").font(.system(size: 52)).foregroundStyle(JournalPalette.accent)
                    Text("Roam Journal").font(.title.bold())
                    Text("Private travel notes").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(uiColor: .systemBackground))
            }
        }.privacySensitive()
    }
}
