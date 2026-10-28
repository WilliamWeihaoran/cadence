import Foundation
import SwiftData
import SwiftUI

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
///
/// **[[T-7871]] — iOS drains it too, on leaving `.active`.** iOS sends no termination notice to a
/// suspended app that is swiped away or jettisoned, so a quit hook is not enough there. The shared
/// `iOSMarkdownEditingSurface` holds typing in `draftText` behind a 2.5 s pure debounce
/// (`iOSMarkdownEditorFlush`), re-armed on every keystroke, and a scene entering the background
/// moves no first responder, so nothing wrote the held text to its host before suspension. The
/// surface now registers its held write here whenever it schedules one, and `iOSRootView` calls
/// `flushPendingEditorContentOnLeavingActive(_:committing:)` from its `scenePhase` observer.
@MainActor
final class MarkdownEditorTerminationFlush {
    static let shared = MarkdownEditorTerminationFlush()

    private var flushes: [UUID: @MainActor () -> Void] = [:]

    var registeredCount: Int { flushes.count }

    func register(_ id: UUID, flush: @escaping @MainActor () -> Void) {
        flushes[id] = flush
    }

    /// **T-7832.** Registers a flush that only commits what `modelContext` already holds.
    ///
    /// For a field typed straight into the model — `NoteEditorPane`'s title — rather than into a
    /// `@State` buffer: there is nothing to write back, only an uncommitted change that Return or
    /// blur would have committed ([[T-4971]]) and a Cmd-Q reaches neither. It writes no buffer, so
    /// unlike the body's flush it needs no gate against a note switch: committing the context is
    /// right whichever note is on screen, and a no-op when nothing is pending.
    func registerCommit(_ id: UUID, in modelContext: ModelContext) {
        register(id) {
            _ = CadencePendingChangePersistence.commitTypedContent(in: modelContext)
        }
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

    /// **[[T-7871]].** The iOS scene hook: on any phase other than `.active`, writes every held
    /// editor buffer to its host and commits what that left pending in `modelContext`.
    ///
    /// `.inactive` counts, not only `.background`: a card swiped away in the app switcher was
    /// inactive when it was killed and may never reach `.background`. A host binding that saves
    /// itself has already committed by the time the commit runs, which then has nothing to do; one
    /// that writes the model straight through (`$note.content`) is committed here. Returns whether
    /// it ran.
    @discardableResult
    func flushPendingEditorContentOnLeavingActive(
        _ phase: ScenePhase,
        committing modelContext: ModelContext
    ) -> Bool {
        guard phase != .active else { return false }
        flushAllBeforeTermination()
        CadencePendingChangePersistence.commitTypedContent(in: modelContext)
        return true
    }
}
