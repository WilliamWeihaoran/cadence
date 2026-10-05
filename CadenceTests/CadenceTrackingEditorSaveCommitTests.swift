import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-322's first three fixes: the two tracking mutations and the block delete that reported success
/// over a store that had refused.
///
/// All three are the shape T-470 and T-471 closed on the calendar quick-create sheet, found by
/// applying that ticket's rule to the rest of the app rather than by another audit tripping over
/// them:
///
/// - `saveGoal` and `saveHabit` ended `try? modelContext.save(); return resolved`, and **all three**
///   of their callers read a non-`nil` answer as success and dismissed. A refused write therefore
///   closed the editor over a goal or habit the store had never taken, and the user's only clue was
///   its absence from the list behind.
/// - `deleteBundle` ended `try? modelContext.save()` and its one production caller dismissed
///   straight after, so a refused delete closed the sheet exactly as a successful one does.
///
/// **The behavioural half runs against a real container with a refused `commit`**, which is the
/// only way to reach these paths: a `save()` that throws cannot be provoked out of an in-memory
/// container, so the commit is a parameter — the same reasoning `CadencePendingChangePersistence`
/// gives for its own.
///
/// **The source half covers `Cadence/iOS/`**, which is behind `#if os(iOS)` and is not compiled by
/// this target. Three of the five call sites live there.
@MainActor
struct CadenceTrackingEditorSaveCommitTests {

    private struct CommitRefused: Error {}

    private func container() throws -> ModelContainer {
        try CadenceModelContainerFactory.makeInMemoryContainer()
    }

    // MARK: - Goals

    // **The seven goal and habit editor tests left with [[T-2079]].**
    //
    // They covered `saveGoal` and `saveHabit`: that a committed create was in the store before
    // the editor could close, that a refused one left nothing pending for someone else's
    // `save()` to take, that a refused *edit* put every field back ([[T-322]]), that an empty
    // title answered `nil` rather than throwing, and that macOS's goal sheet reached
    // `dismiss()` only past a successful `try`. Both helpers and all three editors are gone.
    // The block family below is untouched and is what still gives this suite its subject.

    // MARK: - Habits

    // MARK: - Blocks

    /// The delete family's promise, earned: `bundleDeleteFailureNotice` says nothing was removed,
    /// and `commitDelete`'s rollback is what makes that true — the block is back **and so is the
    /// membership it had unpicked before the commit**, which is the half a `save()`-only fix would
    /// have left undone.
    @Test func arefusedBlockDeleteMakesTheBlockAndItsMembersVisibleAgain() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let bundle = TaskBundle(title: "Deep work", dateKey: "2026-08-30", startMin: 540, durationMinutes: 90)
        let task = AppTask(title: "Write")
        modelContext.insert(bundle)
        modelContext.insert(task)
        task.bundle = bundle
        task.scheduledDate = "2026-08-30"
        task.scheduledStartMin = -1
        bundle.tasks = [task]
        try modelContext.save()

        #expect(throws: CommitRefused.self) {
            try CadenceTaskMutationSupport.deleteBundle(
                bundle,
                modelContext: modelContext,
                commit: { _ in throw CommitRefused() }
            )
        }

        // Asserted through a fetch, not off the live objects: `rollback()` un-deletes immediately,
        // but an *edit* it reverses is only visible once something reads the store again — the
        // measurement `CadencePendingChangePersistence.commitEdit` documents.
        let survivors = try modelContext.fetch(FetchDescriptor<TaskBundle>())
        #expect(survivors.count == 1)
        #expect(survivors.first?.tasks?.count == 1)
        #expect(try ModelContext(modelContainer).fetch(FetchDescriptor<TaskBundle>()).count == 1)

        #expect(
            !modelContext.hasChanges,
            "a refused delete left a pending change in the app's one shared ModelContext"
        )
        // The next unrelated save, from any other screen, stands in for the coin flip a swallowed
        // failure resolves on. With the commit unit doing its job there is nothing left for it to
        // find.
        try modelContext.save()
        #expect(try ModelContext(modelContainer).fetch(FetchDescriptor<TaskBundle>()).count == 1)
    }

    // Two mutations separate this test, both measured at exit 65 against it and nothing else:
    // `deleteBundle` rethrowing **without** the rollback (`try commit(modelContext)`), and
    // `deleteBundle` swallowing (`try? commit(modelContext)`) — the original defect with the new
    // signature. The first is what the last three assertions above are for; the second is what
    // `#expect(throws:)` is for.
    //
    // A note on how that was measured, because it cost a run to notice: `deleteTasks`, 460 lines
    // earlier in the same file, ends with a **character-identical** call to
    // `CadencePendingChangePersistence.commitDelete(in: modelContext, commit: commit)`. A mutation
    // written as a plain substitution lands there instead, and neither suite here covers
    // `deleteTasks` — so it reads as a surviving mutant and would have been reported as this test
    // failing to pin its own subject. Anchor the substitution on the `modelContext.delete(bundle)`
    // line above it.

    @Test func acommittedBlockDeleteRemovesTheBlockAndKeepsItsTasks() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let bundle = TaskBundle(title: "Deep work", dateKey: "2026-08-30", startMin: 540, durationMinutes: 90)
        let task = AppTask(title: "Write")
        modelContext.insert(bundle)
        modelContext.insert(task)
        task.bundle = bundle
        bundle.tasks = [task]
        try modelContext.save()

        try CadenceTaskMutationSupport.deleteBundle(bundle, modelContext: modelContext)

        let reader = ModelContext(modelContainer)
        #expect(try reader.fetch(FetchDescriptor<TaskBundle>()).isEmpty)
        #expect(try reader.fetch(FetchDescriptor<AppTask>()).map(\.title) == ["Write"])
    }

    // MARK: - The five call sites

    /// The notices are held beside the mutations that throw them, so a surface reaching for one
    /// cannot invent a sixth spelling of "that didn't work".
    ///
    /// **Two of the five went with [[T-2079]]**: `goalSaveFailureNotice` and
    /// `habitSaveFailureNotice` named refusals of `saveGoal` and `saveHabit`, and neither helper
    /// nor either notice exists. What the pair proved — that a *create* carries no "Nothing was
    /// removed." clause and a *delete* does, because a refused creation has nothing to fear losing
    /// — is still proved, by the block family that remains.
    @Test func eachRefusalNamesItsOwnObjectAndOnlyTheDeleteClaimsNothingWasRemoved() {
        #expect(CadenceTaskMutationSupport.bundleDeleteFailureNotice.contains("Nothing was removed."))
        #expect(!CadenceTaskMutationSupport.bundleSaveFailureNotice.contains("Nothing"))
        // Non-vacuity: the two notices really are different sentences about the same object, so the
        // contrast above is a property of the pair rather than of one string.
        #expect(CadenceTaskMutationSupport.bundleSaveFailureNotice != CadenceTaskMutationSupport.bundleDeleteFailureNotice)
    }

    /// The three iOS call sites, which this target does not compile.
    @Test func theIOSTrackingEditorsAndBlockDeleteDismissOnlyThroughASuccessfulTry() throws {
        // **The two iOS tracking editors left with [[T-2079]].** `iOSTrackingEditorSheets.swift`
        // held `iOSGoalEditorSheet` and `iOSHabitEditorSheet`, both of which saved through
        // `CadenceTrackingMutationSupport`; the file is deleted, so the assertions that each one
        // reached `actionError` before `dismiss()` have no subject. The block half below is
        // untouched and is what still gives this test its name.
        let sheet = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarBundleDetailSheet.swift")
        )
        #expect(CadenceSourceScan.matchCount("try CadenceTaskMutationSupport\\.deleteBundle", in: sheet) == 1)
        #expect(CadenceSourceScan.matchCount("deleteFailed = true", in: sheet) == 1)
        #expect(
            CadenceSourceScan.matchCount("bundleDeleteFailureAlertTitle", in: sheet) == 1,
            "the block delete failure has no alert to land in"
        )
    }

    // MARK: - Blocks

    /// **T-566.** A refused block edit puts the block *and its members* back.
    ///
    /// The member half is the one a header-only undo would have missed: moving a block moves every
    /// task in it, so an undo that restored the four fields on `TaskBundle` would leave the tasks
    /// sitting on the day the store had just refused to put them on — and the sheet would be
    /// telling the user "Nothing was changed" over a context where something was.
    @Test func arefusedBlockEditPutsTheBlockAndItsMembersBack() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let bundle = TaskBundle(title: "Admin", dateKey: "2026-08-21", startMin: 600, durationMinutes: 30)
        let member = AppTask(title: "Email")
        // Whatever the member held before the edit is what the undo owes it back; 615 rather than
        // the usual -1 so that a restore-to-a-constant would fail here.
        member.scheduledDate = "2026-08-21"
        member.scheduledStartMin = 615
        modelContext.insert(bundle)
        modelContext.insert(member)
        member.bundle = bundle
        bundle.tasks = [member]
        try modelContext.save()

        #expect(throws: CommitRefused.self) {
            try CadenceTaskMutationSupport.updateBundle(
                bundle,
                title: "Deep work",
                dateKey: "2026-08-24",
                startMin: 900,
                durationMinutes: 60,
                modelContext: modelContext,
                commit: { _ in throw CommitRefused() }
            )
        }

        #expect(bundle.title == "Admin")
        #expect(bundle.dateKey == "2026-08-21")
        #expect(bundle.startMin == 600)
        #expect(bundle.durationMinutes == 30)
        #expect(member.scheduledDate == "2026-08-21")
        #expect(member.scheduledStartMin == 615)
        #expect(try ModelContext(modelContainer).fetch(FetchDescriptor<TaskBundle>()).map(\.dateKey) == ["2026-08-21"])

        // And the same call still edits when the commit is accepted, so what was pinned above is
        // the undo rather than a function that stopped writing.
        try CadenceTaskMutationSupport.updateBundle(
            bundle,
            title: "Deep work",
            dateKey: "2026-08-24",
            startMin: 900,
            durationMinutes: 60,
            modelContext: modelContext
        )
        #expect(bundle.dateKey == "2026-08-24")
        #expect(member.scheduledDate == "2026-08-24")
        #expect(member.scheduledStartMin == -1)
    }

    /// The Save button that reports it, which this target does not compile.
    ///
    /// Its sibling ten lines above — "Delete Block" — has caught since T-322, and the sibling
    /// *create* sheet since T-471; this was the third exit from the same sheet and the one still
    /// dismissing over a refusal.
    @Test func theIOSBlockSheetSaveDismissesOnlyThroughASuccessfulTry() throws {
        let sheet = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarBundleDetailSheet.swift")
        )
        #expect(CadenceSourceScan.matchCount("try CadenceTaskMutationSupport\\.updateBundle", in: sheet) == 1)
        #expect(CadenceSourceScan.matchCount("private func save\\(\\) throws", in: sheet) == 1)
        #expect(
            CadenceSourceScan.matchCount("bundleEditFailureAlertTitle", in: sheet) == 1,
            "the block edit failure has no alert to land in"
        )
        #expect(
            CadenceSourceScan.matchCount("CadencePendingChangePersistence\\.editFailureNotice", in: sheet) == 1,
            "the alert promises nothing changed, which only the undo can earn"
        )

        let saveButton = try #require(sheet.range(of: "Button(\"Save\")"))
        let button = try #require(
            CadenceSourceScan.matchedBody(
                after: saveButton.upperBound,
                in: sheet,
                open: "{",
                close: "}"
            )
        )
        #expect(
            failureBranchReturnsBeforeReportingSuccess(button, report: "dismiss()"),
            "the Save button can still reach dismiss() from the catch"
        )
    }

    /// Non-vacuity for the scans above: the reader really returned Swift.
    ///
    /// It read `iOSTrackingEditorSheets.swift` and `CreateGoalSheet.swift` until [[T-2079]] deleted
    /// both — they were pure goal/habit write surfaces. It reads the block sheet instead, which is
    /// the one this suite still scans, and **asserts the two deleted paths are gone**: a
    /// non-vacuity check that silently started reading a file that no longer exists would throw
    /// rather than report, and a re-added editor should fail here rather than slip past.
    @Test func thetrackingSaveCommitScansReadRealSource() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarBundleDetailSheet.swift")
        #expect(raw.contains("struct iOSCalendarBundleDetailSheet: View"))
        #expect(CadenceSourceScan.strippingComments(raw) != raw)

        let files = try CadenceSourceScan.swiftFiles(under: "Cadence")
        #expect(files.count > 300, "the sweep read \(files.count) files and cannot be doing its job")
        #expect(!files.contains("Cadence/iOS/iOSTrackingEditorSheets.swift"))
        #expect(!files.contains("Cadence/macOS/Sheets/CreateGoalSheet.swift"))
    }

    private func functionBody(_ name: String, in path: String) throws -> String {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
        return try #require(CadenceSourceScan.functionBody(named: name, in: source))
    }

    /// True when every `catch` in the body returns before the success report is reached.
    private func failureBranchReturnsBeforeReportingSuccess(_ body: String, report: String) -> Bool {
        guard let catchRange = body.range(of: "catch {") else { return false }
        guard let reportRange = body.range(of: report) else { return false }
        guard let returnRange = body.range(of: "return", range: catchRange.upperBound..<body.endIndex) else {
            return false
        }
        return returnRange.upperBound < reportRange.lowerBound
    }
}
