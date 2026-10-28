#if os(macOS)
import Foundation

/// **T-7811.** The markdown editors' uncommitted `@State` buffers, drained on quit.
///
/// Each of the five macOS markdown editors holds what the user typed in view state and writes it
/// to the store only at a flush point — focus loss, `.onDisappear`, a note or tab switch, or the
/// fallback commit ([[T-7810]]). A Cmd-Q reaches none of them: AppKit termination is not known to
/// run SwiftUI's `.onDisappear`, so `CadenceAppDelegate.applicationWillTerminate` drains this
/// registry, the same shape [[T-5305]] (focus stopwatch) and [[T-5360]] (pending ticks) use.
///
/// An editor registers its `flushPendingEditorContent` each time it arms a fallback commit — the
/// moment it has something pending — so the closure is always the one captured by the editor's
/// latest render, holding its current note or task. It unregisters in `.onDisappear`. The closure
/// runs the flush only while the editor's fallback task is still armed: once a load, a note switch
/// or a flush clears it, the captured note or task may not be the one the buffer now belongs to,
/// so a registration left behind writes nothing.
/// Does not help an abrupt kill; that is what the fallback commit's ceiling bounds.
@MainActor
final class MarkdownEditorTerminationFlush {
    static let shared = MarkdownEditorTerminationFlush()

    private var flushes: [UUID: @MainActor () -> Void] = [:]

    var registeredCount: Int { flushes.count }

    func register(_ id: UUID, flush: @escaping @MainActor () -> Void) {
        flushes[id] = flush
    }

    func unregister(_ id: UUID) {
        flushes[id] = nil
    }

    /// Runs every registered flush, synchronously, and clears the registry.
    func flushAllBeforeTermination() {
        let pending = flushes
        flushes = [:]
        for flush in pending.values {
            flush()
        }
    }
}
#endif
