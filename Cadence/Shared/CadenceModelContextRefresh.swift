import SwiftData

/// Swapping a `ModelContext` wholesale — the shape both `macOSRootView` and `NotePanel` use to
/// pick up writes another process made to the same store.
///
/// The order here is the correctness contract, and it is the reason this is one function rather
/// than a dance each caller re-implements: a `ModelContext` that is dropped takes its unsaved
/// inserts, updates and deletes with it, silently. So the outgoing context is saved *before* the
/// replacement is made, never after and never not at all.
nonisolated enum CadenceModelContextRefresh {
    /// Saves anything pending on `context`, then returns a fresh context on the same container.
    ///
    /// The caller is responsible for storing the result and for flushing any of its own in-flight
    /// edits (an editor buffer, say) into `context` first — this function can only save what the
    /// context already knows about.
    static func replacement(for context: ModelContext) -> ModelContext {
        if context.hasChanges {
            try? context.save()
        }
        context.processPendingChanges()
        return ModelContext(context.container)
    }
}
