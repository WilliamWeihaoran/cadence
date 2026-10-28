import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Cadence

/// **[[T-7871]] — iOS editor text held back from the store when the app leaves the foreground.**
///
/// `iOSMarkdownEditingSurface` holds typing in view state behind a 2.5 s pure debounce, and iOS
/// kills a suspended app (swiped away, jettisoned) without any termination notice, so whatever was
/// still held when the scene left `.active` was lost. The surface now registers its held write in
/// `MarkdownEditorTerminationFlush`, and `iOSRootView`'s `scenePhase` observer drains it and
/// commits. The hook is driven for real here against an in-memory store and read back from a
/// second context; the two call sites, which only the iOS leg compiles, are pinned from source.
///
/// Not verified: a real background-and-kill on a device or simulator ([[T-7872]]).
@MainActor
@Suite
struct MarkdownEditorBackgroundFlushTests {

    /// A note saved with `"saved"`, and a registered held write that puts `typed` into it the way
    /// a `$note.content` host binding does: into the model, with no save of its own.
    private func noteWithHeldTyping(
        _ typed: String
    ) throws -> (container: ModelContainer, editing: ModelContext, noteID: UUID, flushID: UUID) {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let editing = ModelContext(container)
        let note = Note(kind: .list, title: "Note", content: "saved")
        editing.insert(note)
        try editing.save()
        let flushID = UUID()
        MarkdownEditorTerminationFlush.shared.register(flushID) { note.content = typed }
        return (container, editing, note.id, flushID)
    }

    private func storedContent(of noteID: UUID, in container: ModelContainer) throws -> String {
        let reader = ModelContext(container)
        let stored = try #require(
            try reader.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.id == noteID })).first
        )
        return stored.content
    }

    @Test func enteringTheBackgroundWritesHeldEditorTextToTheStore() throws {
        let fixture = try noteWithHeldTyping("typed, then home")

        let ran = MarkdownEditorTerminationFlush.shared.flushPendingEditorContentOnLeavingActive(
            .background,
            committing: fixture.editing
        )

        #expect(ran)
        #expect(
            try storedContent(of: fixture.noteID, in: fixture.container) == "typed, then home",
            "text typed before backgrounding is not in the store, so a kill loses it"
        )
        #expect(!fixture.editing.hasChanges)
    }

    /// A card swiped away in the app switcher was `.inactive`, and may never reach `.background`.
    @Test func goingInactiveWritesHeldEditorTextToTheStore() throws {
        let fixture = try noteWithHeldTyping("typed, then app switcher")

        MarkdownEditorTerminationFlush.shared.flushPendingEditorContentOnLeavingActive(
            .inactive,
            committing: fixture.editing
        )

        #expect(
            try storedContent(of: fixture.noteID, in: fixture.container) == "typed, then app switcher",
            "text typed before the app switcher is not in the store"
        )
    }

    @Test func returningToActiveFlushesNothing() throws {
        let fixture = try noteWithHeldTyping("still being typed")
        defer { MarkdownEditorTerminationFlush.shared.unregister(fixture.flushID) }

        let ran = MarkdownEditorTerminationFlush.shared.flushPendingEditorContentOnLeavingActive(
            .active,
            committing: fixture.editing
        )

        #expect(!ran)
        #expect(try storedContent(of: fixture.noteID, in: fixture.container) == "saved")
    }

    // MARK: - The iOS call sites

    /// The root view's `scenePhase` observer calls the hook with the app's context, unconditionally
    /// (the hook itself decides on the phase), before anything else in the observer.
    @Test func theIOSRootSceneObserverDrainsTheEditorsFirst() throws {
        let source = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSRootView.swift"))
        let observer = try #require(source.range(of: ".onChange(of: scenePhase) { _, phase in"))
        // Comments are blanked to spaces, not removed; collapse whitespace before reading order.
        let head = String(source[observer.upperBound...].prefix(800))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let hook = try #require(
            head.range(of: "MarkdownEditorTerminationFlush.shared.flushPendingEditorContentOnLeavingActive("),
            "iOSRootView's scenePhase observer does not flush the editors"
        )
        #expect(head.hasPrefix("MarkdownEditorTerminationFlush."), "the flush is not the observer's first act")
        #expect(head[hook.upperBound...].hasPrefix(" phase, committing: modelContext )"))
        let widgets = try #require(head.range(of: "CadenceWidgetRefreshCenter.reloadAllWidgets()"))
        #expect(hook.lowerBound < widgets.lowerBound)
    }

    /// The surface registers its held write every time it holds one, under its own key, and drops
    /// the registration when it goes.
    @Test func theIOSEditingSurfaceRegistersItsHeldWrite() throws {
        let source = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSMarkdownEditingSurface.swift")
        )
        let schedule = try #require(CadenceSourceScan.functionBody(named: "scheduleCommit", in: source))
        #expect(schedule.contains("let held = pendingCommit"))
        #expect(schedule.contains(
            "MarkdownEditorTerminationFlush.shared.register(backgroundFlushID) { held.flush() }"
        ))
        #expect(source.contains("@State private var backgroundFlushID = UUID()"))
        let disappear = try #require(source.range(of: ".onDisappear {"))
        #expect(
            String(source[disappear.upperBound...].prefix(200))
                .contains("MarkdownEditorTerminationFlush.shared.unregister(backgroundFlushID)"),
            "the surface's background flush is never unregistered"
        )
    }
}
