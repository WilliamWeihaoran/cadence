import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-648: a note's embedded task card repainted over a swallowed save, in four editors.**
///
/// `NotePanel`, `ListNotesSupportViews` and `NoteEditorPane` each held their own
/// `toggleEmbeddedSubtask` and `renameEmbeddedTask`, and `iOSMarkdownEditingSurface` held the first
/// of the two. All seven declarations were the same three lines: mutate the task, `try?
/// modelContext.save()`, hand back a fresh `MarkdownTaskEmbedRenderInfo` — which is what repaints
/// the card drawn inside the note. So a refused commit left the card showing a tick or a title the
/// store does not hold, and nothing else on screen disagreed. This is [[T-366]], the defect
/// `TaskEmbedFieldEditorPopover` was fixed for, in four more places.
///
/// **Only one of the seven was visible to the rule**, and that is worth recording. The iOS one
/// *returns* the render info, so [[T-636]](b)'s Optional half read the answer as the report. The
/// three macOS pairs answer `Void` and hand the identical value **sideways**, through
/// `refreshEmbeddedTask` one frame down — a spelling the detector still cannot see ([[T-657]]).
/// Six of the seven were therefore fixed off the ticket's prose rather than off a red test, which
/// is why the source-shape scan below names every one of them explicitly rather than counting.
///
/// `CadenceNoteTaskEmbedEditing` is a static enum in `Shared/`, so both undo paths are asserted
/// behaviourally against a real container with a `commit` that throws. The seven surfaces are
/// `private func`s on SwiftUI views, three of them behind `#if os(macOS)` and one behind
/// `#if os(iOS)`, so those are source scans.
@MainActor
struct CadenceNoteTaskEmbedCommitTests {

    private struct CommitRefused: Error {}

    private func container() throws -> ModelContainer {
        try CadenceModelContainerFactory.makeInMemoryContainer()
    }

    private func taskWithSubtask(in modelContext: ModelContext) throws -> (AppTask, Subtask) {
        let task = AppTask(title: "Ship the beta")
        let subtask = Subtask(title: "Write the notes")
        subtask.parentTask = task
        task.subtasks = [subtask]
        modelContext.insert(task)
        modelContext.insert(subtask)
        try modelContext.save()
        return (task, subtask)
    }

    // MARK: - Behavioural: ticking a subtask on the card

    /// **Behavioural.** The committed tick is in the store — read through a *second* context —
    /// before the card is repainted from it.
    @Test func acommittedEmbeddedSubtaskTickIsInTheStoreBeforeTheCardRepaints() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let (_, subtask) = try taskWithSubtask(in: modelContext)

        #expect(CadenceNoteTaskEmbedEditing.toggleSubtask(subtask, in: modelContext))
        #expect(subtask.isDone)
        #expect(!modelContext.hasChanges, "the tick is still pending after the toggle answered yes")
        #expect(
            try ModelContext(modelContainer).fetch(FetchDescriptor<Subtask>()).map(\.isDone) == [true],
            "the store does not hold the tick the card is about to draw"
        )
    }

    /// **Behavioural, and the defect.** A refused tick answers `false` with the subtask back
    /// untouched, so a caller that repaints on `false` would be drawing a state that exists
    /// nowhere.
    ///
    /// Asserted from a second context as well as the first: a single-context read passes against
    /// the bug, because the writing context answers with the value it is holding whether or not the
    /// save threw.
    @Test func arefusedEmbeddedSubtaskTickLeavesTheSubtaskAsItWas() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let (_, subtask) = try taskWithSubtask(in: modelContext)

        #expect(
            !CadenceNoteTaskEmbedEditing.toggleSubtask(
                subtask,
                in: modelContext,
                commit: { _ in throw CommitRefused() }
            )
        )
        #expect(!subtask.isDone, "the refused tick is still on the subtask the card draws from")

        // The symptom this ticket is really about: one `ModelContext` app-wide, so a swallowed
        // failure leaves the change *pending* for whatever screen saves next. The assertion that
        // matters is what the next unrelated save commits — and it is nothing.
        try modelContext.save()
        #expect(
            try ModelContext(modelContainer).fetch(FetchDescriptor<Subtask>()).map(\.isDone) == [false],
            "the next unrelated save committed a tick the store had already refused"
        )
    }

    // MARK: - Behavioural: renaming the card

    /// **Behavioural.** A committed rename applies the inline priority shortcut and lands both
    /// fields.
    @Test func acommittedEmbeddedRenameLandsTheTitleAndTheShortcutPriority() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let (task, _) = try taskWithSubtask(in: modelContext)

        #expect(CadenceNoteTaskEmbedEditing.rename(task, to: "Shipped the beta !!!", in: modelContext))
        #expect(task.title == "Shipped the beta")
        #expect(task.priority == .high)
        #expect(!modelContext.hasChanges)

        let stored = try ModelContext(modelContainer).fetch(FetchDescriptor<AppTask>())
        #expect(stored.map(\.title) == ["Shipped the beta"])
        #expect(stored.map(\.priority) == [.high])
    }

    /// **Behavioural.** The shortcut moves the priority as a side effect of the title, so a
    /// refused rename has to put **both** back. `CadenceTaskFieldSnapshot` used to carry
    /// `priorityRaw` and not `title`, so restoring through it would have undone the priority and
    /// kept the title, leaving the card holding half of an edit nobody made — which is why this
    /// undo was written out by hand. [[T-701]] put `title` in the snapshot; this assertion is
    /// unchanged by that, because it is about the outcome and not about which unit produces it.
    @Test func arefusedEmbeddedRenameRestoresTheTitleAndThePriorityTogether() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let (task, _) = try taskWithSubtask(in: modelContext)
        task.priority = .low
        try modelContext.save()

        #expect(
            !CadenceNoteTaskEmbedEditing.rename(
                task,
                to: "Shipped the beta !!!",
                in: modelContext,
                commit: { _ in throw CommitRefused() }
            )
        )
        #expect(task.title == "Ship the beta", "the refused rename left its title on the card")
        #expect(task.priority == .low, "the refused rename left its shortcut priority on the card")

        try modelContext.save()
        let stored = try ModelContext(modelContainer).fetch(FetchDescriptor<AppTask>())
        #expect(stored.map(\.title) == ["Ship the beta"])
        #expect(stored.map(\.priority) == [.low])
    }

    /// **Behavioural, T-765.** `task.priority` coerces an unrecognised `priorityRaw` to `.none` on
    /// read, which is exactly why `CadenceTaskFieldSnapshot` snapshots the raw string rather than
    /// the computed enum (see its doc comment). A hand-rolled undo that reads and writes back
    /// through `task.priority` does not get that protection: it round-trips an unrecognised raw
    /// value through `.none` and writes `"none"` back, silently discarding whatever the store
    /// actually held. This is the divergence T-765 asked to be enumerated rather than assumed away.
    @Test func arefusedEmbeddedRenameRestoresAnUnrecognisedPriorityRawExactly() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let (task, _) = try taskWithSubtask(in: modelContext)
        task.priorityRaw = "urgent-legacy"
        try modelContext.save()

        #expect(
            !CadenceNoteTaskEmbedEditing.rename(
                task,
                to: "Shipped the beta !!!",
                in: modelContext,
                commit: { _ in throw CommitRefused() }
            )
        )
        #expect(
            task.priorityRaw == "urgent-legacy",
            "the refused rename replaced an unrecognised priorityRaw with \"none\""
        )
    }

    /// **Behavioural.** Neither undo reaches past the edit it is undoing. This is the app's single
    /// `ModelContext`: a refused tick on a card inside a note must not take the note the user is
    /// typing with it, which is exactly what a `rollback()` undo would do.
    @Test func arefusedEmbeddedCardEditLeavesUnrelatedPendingWorkAlone() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let (task, subtask) = try taskWithSubtask(in: modelContext)
        let note = Note(kind: .permanent, title: "Notepad", content: "one")
        modelContext.insert(note)
        try modelContext.save()

        note.content = "one two"
        #expect(
            !CadenceNoteTaskEmbedEditing.toggleSubtask(
                subtask,
                in: modelContext,
                commit: { _ in throw CommitRefused() }
            )
        )
        #expect(note.content == "one two", "the refused tick discarded the text in the note around it")

        note.content = "one two three"
        #expect(
            !CadenceNoteTaskEmbedEditing.rename(
                task,
                to: "Renamed",
                in: modelContext,
                commit: { _ in throw CommitRefused() }
            )
        )
        #expect(note.content == "one two three", "the refused rename discarded the text around it")

        try modelContext.save()
        #expect(
            try ModelContext(modelContainer).fetch(FetchDescriptor<Note>()).map(\.content) == ["one two three"]
        )
    }

    // MARK: - Source shape: the seven declarations in four editors

    /// **Source shape.** Every one of the seven reaches the shared unit, names the refusal, and
    /// repaints the card only **below** the refusal branch.
    ///
    /// Named one by one rather than counted, deliberately: six of the seven are invisible to
    /// `CadenceSaveCommitDisciplineTests` (T-657), so a count is the one thing that could not tell
    /// anybody which site drifted back.
    @Test func everyEmbeddedTaskCardEditorRepaintsOnlyBelowItsRefusal() throws {
        let editors = [
            ("Cadence/macOS/Views/NotePanel.swift", "toggleEmbeddedSubtask", "refreshEmbeddedTask(task)"),
            ("Cadence/macOS/Views/NotePanel.swift", "renameEmbeddedTask", "refreshEmbeddedTask(task)"),
            (
                "Cadence/macOS/Views/ListNotesSupportViews.swift",
                "toggleEmbeddedSubtask",
                "refreshEmbeddedTask(embeddedTask)"
            ),
            (
                "Cadence/macOS/Views/ListNotesSupportViews.swift",
                "renameEmbeddedTask",
                "refreshEmbeddedTask(embeddedTask)"
            ),
            ("Cadence/macOS/Views/NoteEditorPane.swift", "toggleEmbeddedSubtask", "refreshEmbeddedTask(task)"),
            ("Cadence/macOS/Views/NoteEditorPane.swift", "renameEmbeddedTask", "refreshEmbeddedTask(task)"),
            (
                "Cadence/iOS/iOSMarkdownEditingSurface.swift",
                "toggleEmbeddedSubtask",
                "return MarkdownTaskEmbedRenderInfo.task(task)"
            )
        ]

        for (path, name, repaint) in editors {
            let view = try CadenceCommitSurfaceScan.scanned(path)
            let body = try CadenceCommitSurfaceScan.declarationBody(named: name, in: view)

            #expect(
                body.contains("guard CadenceNoteTaskEmbedEditing."),
                "\(path).\(name) does not guard on the shared commit"
            )
            #expect(
                body.contains("embeddedTaskFailureNotice = CadenceTaskFieldEditCommit.saveFailureNotice"),
                "\(path).\(name) does not name the refusal with the shared sentence"
            )
            #expect(
                CadenceSourceScan.matchCount(#"try\?"#, in: body) == 0,
                "\(path).\(name) still swallows a commit"
            )
            #expect(
                body.contains(repaint),
                "\(path).\(name) no longer repaints the card at all"
            )
            #expect(
                refusalPrecedes(
                    marker: "embeddedTaskFailureNotice = CadenceTaskFieldEditCommit.saveFailureNotice",
                    report: repaint,
                    in: body
                ),
                "\(path).\(name) repaints the card above its refusal branch"
            )
            // Exactly one, not "at least one". An ordering check anchored on the *first*
            // occurrence is satisfied by a second repaint placed inside the refusal branch — which
            // is the defect itself, reintroduced under the assertion meant to catch it. The iOS
            // site is the sharpest case: its refusal branch answers `nil`, and answering the render
            // info there instead would restore T-648 exactly.
            #expect(
                CadenceSourceScan.matchCount(NSRegularExpression.escapedPattern(for: repaint), in: body) == 1,
                "\(path).\(name) repaints the card in more than one place"
            )
        }
    }

    /// **Source shape.** Each of the four editors holds a notice slot and draws it. A notice set and
    /// never rendered is the same silence one layer further in.
    @Test func everyEmbeddedTaskCardEditorDrawsTheNoticeItSets() throws {
        for path in [
            "Cadence/macOS/Views/NotePanel.swift",
            "Cadence/macOS/Views/ListNotesSupportViews.swift",
            "Cadence/macOS/Views/NoteEditorPane.swift",
            "Cadence/iOS/iOSMarkdownEditingSurface.swift"
        ] {
            let view = try CadenceCommitSurfaceScan.scanned(path)
            #expect(
                view.contains("@State private var embeddedTaskFailureNotice: String?"),
                "\(path) does not hold a notice slot"
            )
            #expect(
                view.contains("CadenceInlineFailureNotice(text: embeddedTaskFailureNotice)"),
                "\(path) sets a notice it never draws"
            )
        }
    }

    /// **Source shape, and the non-vacuity check for the scans above.** Each file read as itself,
    /// and the comment stripper really ran — a scan that read raw source would find this ticket's
    /// number in the doc comments the fix left behind.
    @Test func theembeddedTaskCardScanReadsTheFilesItClaimsTo() throws {
        let markers = [
            ("Cadence/macOS/Views/NotePanel.swift", "struct NotePanel: View {"),
            ("Cadence/macOS/Views/ListNotesSupportViews.swift", "struct TaskNoteEditorPane: View {"),
            ("Cadence/macOS/Views/NoteEditorPane.swift", "struct NoteEditorPane: View {"),
            ("Cadence/iOS/iOSMarkdownEditingSurface.swift", "struct iOSMarkdownEditingSurface: View {")
        ]

        for (path, marker) in markers {
            let view = try CadenceCommitSurfaceScan.scanned(path)
            #expect(view.contains(marker), "\(path) did not read as itself")
            #expect(
                !view.contains("T-648"),
                "\(path) reads its own ticket references, so the comment stripper is not running"
            )
        }
    }

    /// Whether `report` sits below the first occurrence of `marker`. See
    /// `CadenceInPlaceEditFlushCommitTests.refusalPrecedes` — the refusal branch is a `guard … else`
    /// rather than a `catch`, and the anchor is forwards for the T-659 reason.
    private func refusalPrecedes(marker: String, report: String, in body: String) -> Bool {
        guard let refusal = body.range(of: marker),
              let reported = body.range(of: report) else { return false }
        return reported.lowerBound > refusal.lowerBound
    }
}
