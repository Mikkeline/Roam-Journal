import Foundation

/// Acquiring happens before a command reads the current notebook, preventing stale queued snapshots.
@MainActor public final class MutationGate {
    private var held = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    public init() {}
    public func acquire() async {
        if !held { held = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    public func release() {
        if waiters.isEmpty { held = false } else { waiters.removeFirst().resume() }
    }
}
