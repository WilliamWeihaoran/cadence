import Foundation
import SwiftData
import Testing
@testable import Cadence

/// Discarding a `ModelContext` is a silent operation, which is what makes the order in
/// `CadenceModelContextRefresh` a contract rather than a style choice.
///
/// `macOSRootView.refreshAppData()` and `NotePanel.refreshFromStore()` both throw away their
/// context and build a new one so the UI picks up writes made to the store by another process.
/// Anything the outgoing context is still holding goes with it — no throw, no log, no failed
/// fetch, just an edit that is not there the next time the note is opened. So the save happens
/// first, every time, and these tests fail if it stops happening.
@MainActor
struct CadenceModelContextRefreshTests {

    private func makeContainer() throws -> ModelContainer {
        try CadenceTestStore.container()
    }

    /// The whole point: an unsaved insert survives the swap.
    @Test func unsavedWorkIsSavedBeforeTheContextIsDiscarded() throws {
        let container = try makeContainer()
        let outgoing = ModelContext(container)
        outgoing.insert(Note(kind: .daily, title: "Standup", content: "written but not saved", dateKey: "2026-08-19"))
        #expect(outgoing.hasChanges)

        let replacement = CadenceModelContextRefresh.replacement(for: outgoing)

        let notes = try replacement.fetch(FetchDescriptor<Note>())
        #expect(notes.count == 1)
        #expect(notes.first?.content == "written but not saved")
    }

    /// An unsaved *edit* to an existing row is as easy to lose as an insert, and is the case the
    /// notes panel actually hits — it flushes the editor buffer into the context and then refreshes.
    @Test func unsavedEditsToExistingRowsSurviveTheSwap() throws {
        let container = try makeContainer()
        let seeding = ModelContext(container)
        let note = Note(kind: .daily, title: "Standup", content: "first", dateKey: "2026-08-19")
        seeding.insert(note)
        try seeding.save()

        let outgoing = ModelContext(container)
        let loaded = try #require(try outgoing.fetch(FetchDescriptor<Note>()).first)
        loaded.content = "edited after load"

        let replacement = CadenceModelContextRefresh.replacement(for: outgoing)

        let reloaded = try #require(try replacement.fetch(FetchDescriptor<Note>()).first)
        #expect(reloaded.content == "edited after load")
    }

    /// The replacement is a genuinely new context on the *same* store — a refresh that returned
    /// the same context would show the same stale rows, and one on a different container would
    /// quietly detach the whole window from the user's data.
    @Test func theReplacementIsANewContextOnTheSameContainer() throws {
        let container = try makeContainer()
        let outgoing = ModelContext(container)

        let replacement = CadenceModelContextRefresh.replacement(for: outgoing)

        #expect(replacement !== outgoing)
        #expect(replacement.container === container)
    }

    /// A refresh with nothing pending is the common case (the scenePhase checkpoint fires on every
    /// activation) and must be a no-op, not an error path.
    @Test func refreshingACleanContextIsHarmless() throws {
        let container = try makeContainer()
        let seeding = ModelContext(container)
        seeding.insert(Note(kind: .daily, title: "Standup", content: "saved", dateKey: "2026-08-19"))
        try seeding.save()

        let outgoing = ModelContext(container)
        #expect(!outgoing.hasChanges)

        let replacement = CadenceModelContextRefresh.replacement(for: outgoing)

        #expect(try replacement.fetch(FetchDescriptor<Note>()).count == 1)
    }
}
