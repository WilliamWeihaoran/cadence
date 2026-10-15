#if os(macOS)
import Foundation
import SwiftData

/// What has to happen to app-wide state when `macOSRootView.refreshAppData()` swaps the model
/// context out from under the UI (T-3098).
///
/// `refreshAppData()` bumps `dataRefreshID`, and that `.id()` is applied to `macOSRootMainShell`
/// and `macOSRootOverlayStack` only — so every view rebuilds against the replacement context while
/// the root's own `.onAppear`, which seeds the singletons, does not re-run. Anything app-wide that
/// holds a *model object* therefore keeps pointing into the retired context, and SwiftData says
/// nothing about it: the object still answers, its rows are simply the ones the other process's
/// write never reached, and a write through it lands on a context the UI has stopped reading.
///
/// The three holders are not treated the same way, because what they hold is not worth the same:
///
/// - **`FocusManager.activeSession` is re-resolved by id.** A focus session is long-running and is
///   most often stopped just after returning to the app — which is exactly when the swap has just
///   happened — so clearing it would throw away a running session for an invisible bookkeeping
///   reason. Re-resolution is safe precisely because the stopwatch is *not* in `activeSession`:
///   `FocusManager` keeps elapsed time in its own `CadenceFocusTimerState`, derived from a start
///   instant, so exchanging the task object changes which row the session points at and nothing
///   about the clock. When the row is gone from the store (the other process deleted it) the old
///   object is **kept**, not cleared: a stale pointer is recoverable and a discarded session is not.
/// - **`HoveredTaskManager` is cleared.** Hover is per-pointer-position state the `.id()` rebuild
///   has already invalidated from the other end — each row's `@State isHovered` is reset by the
///   rebuild, so no `endHovering` ever fires and the manager is left asserting a hover that no row
///   believes in. Clearing restores the agreement; the next mouse move re-seeds it in a frame.
/// - **`TaskCompletionAnimationManager` is not touched here at all**, and that is deliberate. It
///   resolves its context from the task it is settling (`settleContext(for:)`), so it is correct
///   across a swap without being told one happened — including a swap that lands midway through
///   the 2.5s fill, which is the case re-seeding it from here would get wrong.
enum macOSRootDataRefreshSupport {
    /// Re-points the app-wide holders at `context` after a swap.
    static func adoptReplacementContext(
        _ context: ModelContext,
        focusManager: FocusManager,
        hoveredTaskManager: HoveredTaskManager
    ) {
        if let session = reresolvedSession(focusManager.activeSession, in: context) {
            focusManager.activeSession = session
        }
        hoveredTaskManager.clear()
    }

    /// The same session, pointing at `context`'s copy of its row — or `nil` when there is nothing
    /// to change, so the caller leaves `activeSession` alone rather than writing an equal value
    /// into an `@Observable` property and inviting a redraw.
    ///
    /// `nil` covers all three of "no session", "already resolved against this context" and "the row
    /// is no longer in the store". The last of those is the one worth naming: it is **not** a
    /// reason to end the session.
    static func reresolvedSession(
        _ session: FocusManager.ActiveSession?,
        in context: ModelContext
    ) -> FocusManager.ActiveSession? {
        switch session {
        case .none:
            return nil
        case .task(let task):
            guard let live = fetchTask(id: task.id, in: context), live !== task else { return nil }
            return .task(live)
        }
    }

    private static func fetchTask(id: UUID, in context: ModelContext) -> AppTask? {
        var descriptor = FetchDescriptor<AppTask>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }
}
#endif
