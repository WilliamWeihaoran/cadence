import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-497, tier 3: the last four condemned `try? save()` sites.**
///
/// Three of them are one sentence written three times — "flush an in-place edit, then close" — on
/// the search sheet's note editor, the task detail sheet and the `[[link]]` note editor. The fourth,
/// `KanbanCardMetaSupportViews.select`, was never blocked on anything: a popover picking a task's
/// list, closing over a swallowed `moveToContainer`.
///
/// **The decision the three encode, because it is the reason they sat open.** The blocking question
/// was what an *undo* means for a field the user is still looking at and still has focus in. The
/// answer is that these sites need none: the edit is in-place on an object the store already holds,
/// so there is nothing to un-insert, and restoring the model under a live caret would delete what
/// the user typed in order to tell them it was not saved. The rule is broken here only because
/// closing **claims** the write landed. Stop claiming it — keep the surface open, keep the text,
/// name the refusal — and the undo question does not arise.
///
/// So the assertions below come in two flavours on purpose. `CadenceInPlaceEditFlush` is asserted
/// to leave the edit **exactly where it was**, which is the opposite of what every other commit
/// unit in this app promises and is the whole decision. `moveToContainer` is asserted to restore,
/// because the picker holds no draft and a half-moved task is nobody's intent.
///
/// The four surfaces themselves are `private` members of SwiftUI views, three of them inside
/// `#if os(iOS)`, so those are source scans.
@MainActor
struct CadenceInPlaceEditFlushCommitTests {

    private struct CommitRefused: Error {}

    private func container() throws -> ModelContainer {
        try CadenceModelContainerFactory.makeInMemoryContainer()
    }

    // MARK: - Behavioural: the flush unit

    /// **Behavioural.** The success path, read through a *second* context so the assertion cannot
    /// be satisfied by the writing context's own memory.
    @Test func aflushedInPlaceEditIsInTheStoreBeforeTheSurfaceCloses() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let note = Note(kind: .permanent, title: "Draft", content: "one")
        modelContext.insert(note)
        try modelContext.save()

        note.content = "one two"

        #expect(CadenceInPlaceEditFlush.flush(in: modelContext))
        #expect(!modelContext.hasChanges, "the edit is still pending after the flush answered yes")
        #expect(
            try ModelContext(modelContainer).fetch(FetchDescriptor<Note>()).map(\.content) == ["one two"],
            "the store does not hold the text the sheet is about to close over"
        )
    }

    /// **Behavioural, and this is the decision itself.** A refused flush answers `false` and
    /// changes **nothing**: the field still holds what the user typed, and the context still holds
    /// it pending, so pressing Done again can still land it.
    ///
    /// A `commitEdit`-style undo here would pass an "it was not saved" assertion and fail the user,
    /// because the text it restored is the text they were still looking at. That is why this test
    /// asserts the edit *survives* rather than that it is gone.
    @Test func arefusedFlushKeepsWhatTheUserTypedAndLeavesItRetryable() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let note = Note(kind: .permanent, title: "Draft", content: "one")
        modelContext.insert(note)
        try modelContext.save()

        note.content = "one two"

        #expect(!CadenceInPlaceEditFlush.flush(in: modelContext, commit: { _ in throw CommitRefused() }))
        #expect(note.content == "one two", "the refused flush took the user's text with it")
        #expect(modelContext.hasChanges, "the refused edit is no longer pending, so Done cannot retry it")

        #expect(CadenceInPlaceEditFlush.flush(in: modelContext))
        #expect(
            try ModelContext(modelContainer).fetch(FetchDescriptor<Note>()).map(\.content) == ["one two"],
            "a second Done could not land the edit the first one failed to"
        )
    }

    /// **Behavioural.** The refusal does not reach past the surface that raised it. This is the
    /// app's single `ModelContext`, so a flush that rolled back would discard whatever else is
    /// pending — the reason `CadencePendingChangePersistence.commitEdit`'s doc gives for not
    /// offering a `rollback()` undo, and doubly true for a unit that is not undoing at all.
    @Test func arefusedFlushLeavesUnrelatedPendingWorkAlone() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let note = Note(kind: .permanent, title: "Draft", content: "one")
        let project = Project(name: "Launch")
        modelContext.insert(note)
        modelContext.insert(project)
        try modelContext.save()

        note.content = "one two"
        project.name = "Launch & Learn"

        #expect(!CadenceInPlaceEditFlush.flush(in: modelContext, commit: { _ in throw CommitRefused() }))
        #expect(project.name == "Launch & Learn")

        try modelContext.save()
        #expect(
            try ModelContext(modelContainer).fetch(FetchDescriptor<Project>()).map(\.name) == ["Launch & Learn"]
        )
    }

    // MARK: - Behavioural: the kanban list move

    /// **Behavioural.** A committed move is in the store, and the popover's `false` branch is not
    /// taken.
    @Test func acommittedListMoveIsInTheStoreBeforeThePopoverCloses() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let area = Area(name: "Work")
        let task = AppTask(title: "Ship")
        modelContext.insert(area)
        modelContext.insert(task)
        try modelContext.save()

        #expect(
            CadenceTaskMutationSupport.moveToContainer(
                task,
                area: area,
                project: nil,
                allTasks: [task],
                modelContext: modelContext
            )
        )
        #expect(!modelContext.hasChanges)
        #expect(
            try ModelContext(modelContainer)
                .fetch(FetchDescriptor<AppTask>())
                .map { $0.area?.name } == ["Work"],
            "the store does not hold the move the popover closed over"
        )
    }

    /// **Behavioural, and the defect.** A refused move answers `false` **and puts the task back in
    /// the list it started in** — including its `order`, which `CadenceTaskFieldSnapshot` does not
    /// carry. `assignContainer` sends a genuine move to the end of its new list, so a restore that
    /// reset the relationships and left the order would move the task inside the list it never left.
    @Test func arefusedListMoveLeavesTheTaskInTheListItStartedIn() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let origin = Area(name: "Work")
        let destination = Area(name: "Home")
        let task = AppTask(title: "Ship")
        task.area = origin
        task.order = 3
        task.sectionName = TaskSectionDefaults.defaultName
        let neighbour = AppTask(title: "Sweep")
        neighbour.area = destination
        neighbour.order = 41
        for model in [origin, destination] { modelContext.insert(model) }
        for model in [task, neighbour] { modelContext.insert(model) }
        try modelContext.save()

        #expect(
            !CadenceTaskMutationSupport.moveToContainer(
                task,
                area: destination,
                project: nil,
                allTasks: [task, neighbour],
                modelContext: modelContext,
                commit: { _ in throw CommitRefused() }
            )
        )

        #expect(task.area?.name == "Work", "the refused move left the task in the destination list")
        #expect(task.project == nil)
        #expect(task.order == 3, "the refused move left the task at the tail of a list it never joined")

        try modelContext.save()
        let stored = try ModelContext(modelContainer)
            .fetch(FetchDescriptor<AppTask>())
            .first { $0.title == "Ship" }
        #expect(stored?.area?.name == "Work")
        #expect(stored?.order == 3)
    }

    // MARK: - Behavioural: the task sheet's date write

    /// **Behavioural.** The wrapper the task sheet writes its dates through answers, and it answers
    /// the *flush* way rather than the undo way: a refused write leaves both fields exactly as the
    /// user set them, because the pickers above them are still on screen holding those values.
    ///
    /// This is the frame under `finishEditingAndDismiss`. Before T-497 it ended
    /// `try? modelContext.save()`, so the sheet could commit honestly and still be closing over a
    /// swallow one frame down — which is the chain half 2 of the `try? save()` rule follows.
    @Test func therefusedPlanningDateWriteAnswersFalseAndKeepsTheDatesTheUserPicked() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let task = AppTask(title: "Ship")
        modelContext.insert(task)
        try modelContext.save()

        #expect(
            !CadenceTaskDateEditing.setPlanningDates(
                scheduledDate: "2026-09-02",
                dueDate: "2026-09-03",
                for: task,
                in: modelContext,
                commit: { _ in throw CommitRefused() }
            )
        )
        #expect(task.scheduledDate == "2026-09-02", "the refused write took the day the user picked")
        #expect(task.dueDate == "2026-09-03")

        #expect(
            CadenceTaskDateEditing.setPlanningDates(
                scheduledDate: "2026-09-02",
                dueDate: "2026-09-03",
                for: task,
                in: modelContext
            )
        )
        let stored = try ModelContext(modelContainer).fetch(FetchDescriptor<AppTask>())
        #expect(stored.map(\.scheduledDate) == ["2026-09-02"])
        #expect(stored.map(\.dueDate) == ["2026-09-03"])
    }

    // MARK: - Source shape: the four surfaces

    /// **Source shape.** The three "flush, then close" surfaces reach the shared flush, name the
    /// refusal with the shared sentence, and put the close **below** the refusal branch.
    ///
    /// The ordering is the assertion that matters: a notice set beside a `dismiss()` that still
    /// runs is the same lie with a sentence on top of it.
    @Test func everyInPlaceEditFlushSurfaceClosesOnlyBelowItsRefusal() throws {
        // Each site's *report* is named individually, because each site claims success in its own
        // spelling: the two note editors answer `true` to a `body` that then dismisses, and the
        // task sheet dismisses itself.
        let surfaces = [
            ("Cadence/iOS/iOSSearchSupportViews.swift", "flushBeforeDismissing", "return true"),
            ("Cadence/iOS/iOSMarkdownReferenceSupport.swift", "flushBeforeDismissing", "return true"),
            ("Cadence/iOS/iOSTaskDetailSheet.swift", "finishEditingAndDismiss", "dismiss()")
        ]

        for (path, name, report) in surfaces {
            let view = try CadenceCommitSurfaceScan.scanned(path)
            let body = try CadenceCommitSurfaceScan.declarationBody(named: name, in: view)

            // Not anchored on `guard ` — the task sheet's condition has a first clause
            // (`applyDates()`), asserted on its own below. What every site must share is that the
            // flush *is* the condition rather than a statement above one.
            #expect(
                body.contains("CadenceInPlaceEditFlush.flush(in: modelContext) else {"),
                "\(path).\(name) does not guard on the shared flush"
            )
            #expect(
                body.contains("saveFailureNotice = CadenceInPlaceEditFlush.failureNotice"),
                "\(path).\(name) does not name the refusal with the shared sentence"
            )
            #expect(
                CadenceSourceScan.matchCount(#"try\?"#, in: body) == 0,
                "\(path).\(name) still swallows a commit"
            )
            #expect(
                CadenceSourceScan.matchCount(#"modelContext\.rollback\(\)"#, in: body) == 0,
                """
                \(path).\(name) rolls the context back, which discards the text the user is still \
                looking at — the undo this ticket decided against.
                """
            )
            #expect(
                refusalPrecedes(
                    marker: "saveFailureNotice = CadenceInPlaceEditFlush.failureNotice",
                    report: report,
                    in: body
                ),
                "\(path).\(name) reports success above its refusal branch"
            )
            // Exactly one, not "at least one". An ordering check anchored on the *first*
            // occurrence is satisfied by a second copy of the report inside the refusal branch —
            // which is the defect itself, reintroduced below the assertion that was meant to catch
            // it. Counting is what closes that.
            #expect(
                CadenceSourceScan.matchCount(NSRegularExpression.escapedPattern(for: report), in: body) == 1,
                "\(path).\(name) reports success in more than one place"
            )
        }

        // The task sheet writes its two date fields on the way out, through a wrapper that used to
        // end `try? modelContext.save()` — so the sheet's own commit was honest while the frame
        // under it swallowed, which is the chain half 2 of the rule follows. Both frames answer
        // now, and the dismissal is one condition over both.
        let sheet = try CadenceCommitSurfaceScan.scanned("Cadence/iOS/iOSTaskDetailSheet.swift")
        let finish = try CadenceCommitSurfaceScan.declarationBody(named: "finishEditingAndDismiss", in: sheet)
        #expect(
            finish.contains("guard applyDates(), CadenceInPlaceEditFlush.flush(in: modelContext) else {"),
            "iOSTaskDetailSheet dismisses without asking whether its date write landed"
        )
        for (path, name) in [
            ("Cadence/Shared/CadenceTaskDateEditing.swift", "setPlanningDates"),
            ("Cadence/Shared/CadenceTaskMutationSupport.swift", "setPlanningDates")
        ] {
            let source = try CadenceCommitSurfaceScan.scanned(path)
            let body = try CadenceCommitSurfaceScan.declarationBody(named: name, in: source)
            #expect(
                CadenceSourceScan.matchCount(#"try\?"#, in: body) == 0,
                "\(path).\(name) still swallows the commit the sheet closes over"
            )
        }

        // The two note editors flush from a helper, so the `dismiss()` that used to be the claim
        // lives one frame up in `body` and has to guard on the answer. `iOSTaskDetailSheet` flushes
        // and closes in the one declaration already asserted above.
        for path in [
            "Cadence/iOS/iOSSearchSupportViews.swift",
            "Cadence/iOS/iOSMarkdownReferenceSupport.swift"
        ] {
            let view = try CadenceCommitSurfaceScan.scanned(path)
            #expect(
                view.contains("guard flushBeforeDismissing() else { return }"),
                "\(path) dismisses without asking whether the flush landed"
            )
        }
    }

    /// **Source shape.** Every notice these surfaces set is actually drawn. A notice that is set and
    /// never rendered is the same silence one layer further in — the mistake
    /// `iOSCalendarEventEditSheet` made at regular width, found by this same ticket's tier 1.
    @Test func everyInPlaceEditFlushNoticeIsDrawnOnTheSurfaceThatStaysOpen() throws {
        for path in [
            "Cadence/iOS/iOSSearchSupportViews.swift",
            "Cadence/iOS/iOSMarkdownReferenceSupport.swift",
            "Cadence/iOS/iOSTaskDetailSheet.swift"
        ] {
            let view = try CadenceCommitSurfaceScan.scanned(path)
            #expect(
                view.contains("@State private var saveFailureNotice: String?"),
                "\(path) does not hold a notice slot"
            )
            #expect(
                view.contains("CadenceInlineFailureNotice(text: saveFailureNotice)"),
                "\(path) sets a notice it never draws"
            )
        }
    }

    /// **Source shape.** The kanban list picker guards on the move, names the refusal, and closes
    /// only below it — and the notice it sets is drawn inside the popover that stayed open.
    @Test func thekanbanListPickerStaysOpenOverARefusedMove() throws {
        let path = "Cadence/macOS/Views/KanbanCardMetaSupportViews.swift"
        let view = try CadenceCommitSurfaceScan.scanned(path)
        let body = try CadenceCommitSurfaceScan.declarationBody(named: "select", in: view)

        #expect(
            body.contains("guard CadenceTaskMutationSupport.moveToContainer("),
            "\(path).select does not guard on the move"
        )
        #expect(
            body.contains("moveFailureNotice = CadenceTaskFieldEditCommit.saveFailureNotice"),
            "\(path).select does not name the refusal"
        )
        #expect(
            CadenceSourceScan.matchCount(#"try\?"#, in: body) == 0,
            "\(path).select still swallows a commit"
        )
        #expect(
            refusalPrecedes(
                marker: "moveFailureNotice = CadenceTaskFieldEditCommit.saveFailureNotice",
                report: "isPresented = false",
                in: body
            ),
            "\(path).select closes the popover above its refusal branch"
        )
        #expect(
            CadenceSourceScan.matchCount(#"isPresented = false"#, in: body) == 1,
            "\(path).select closes the popover in more than one place"
        )
        #expect(
            view.contains("CadenceInlineFailureNotice(text: moveFailureNotice)"),
            "\(path) sets a notice it never draws"
        )
    }

    /// **Source shape, and the non-vacuity check for the two scans above.** The reader really does
    /// strip comments and really did read these files: each of the four names a literal only its
    /// own source carries, and none of them reads back a sentence that lives in a comment.
    @Test func theflushSurfaceScanReadsTheFilesItClaimsTo() throws {
        let markers = [
            ("Cadence/iOS/iOSSearchSupportViews.swift", "struct iOSNoteDetailSheet: View {"),
            ("Cadence/iOS/iOSMarkdownReferenceSupport.swift", "struct iOSLinkedNoteEditorSheet: View {"),
            ("Cadence/iOS/iOSTaskDetailSheet.swift", "struct iOSTaskDetailSheet: View {"),
            ("Cadence/macOS/Views/KanbanCardMetaSupportViews.swift", "struct KanbanContainerPickerPopover: View {")
        ]

        for (path, marker) in markers {
            let view = try CadenceCommitSurfaceScan.scanned(path)
            #expect(view.contains(marker), "\(path) did not read as itself")
            #expect(
                !view.contains("T-497"),
                "\(path) reads its own ticket references, so the comment stripper is not running"
            )
        }
    }

    /// Whether every occurrence of `report` sits below the first occurrence of `marker`.
    ///
    /// The refusal branch here is a `guard … else`, not a `catch`, so
    /// `CadenceCommitSurfaceScan.reportFollowsTheCatch` is the wrong reader. Same crude offset
    /// comparison, anchored forwards for the T-659 reason: anchoring on the last occurrence answers
    /// "is *some* occurrence below the branch", which the defect itself satisfies.
    private func refusalPrecedes(marker: String, report: String, in body: String) -> Bool {
        guard let refusal = body.range(of: marker),
              let reported = body.range(of: report) else { return false }
        return reported.lowerBound > refusal.lowerBound
    }
}
