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

    /// The delete family's promise, earned: a refused block delete leaves nothing removed,
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

    // `eachRefusalNamesItsOwnObjectAndOnlyTheDeleteClaimsNothingWasRemoved` was declared here.
    // It contrasted `bundleSaveFailureNotice` with `bundleDeleteFailureNotice`, the last two of
    // five notices this suite once held. [[T-3170]]'s trio pass deleted both with
    // `TimelineBundleBlock`, the last surface that could refuse a block operation, so the pair it
    // compared no longer exists. The delete family's "Nothing was removed." clause is still held
    // by `CadenceTaskMutationSupport.deleteFailureNotice` and its siblings.

    // `theIOSTrackingEditorsAndBlockDeleteDismissOnlyThroughASuccessfulTry` was declared here.
    //
    // It began as three iOS call sites. [[T-2079]] deleted two of them with
    // `iOSTrackingEditorSheets.swift` — `iOSGoalEditorSheet` and `iOSHabitEditorSheet`, both saving
    // through `CadenceTrackingMutationSupport` — and left the block half, which gave the test its
    // name. [[T-3170]] has now deleted `iOSCalendarBundleDetailSheet.swift` with the Block feature,
    // so the last of the three is gone and the test has no call site left to read.
    //
    // **The rule itself is not retired**, only this surface's instance of it:
    // `CadenceSaveCommitDisciplineTests` holds the repo-wide `try? save()` census, and
    // `arefusedBlockDeleteMakesTheBlockAndItsMembersVisibleAgain` above still pins the mutation the deleted button
    // called.

    // MARK: - Blocks

    // `arefusedBlockEditPutsTheBlockAndItsMembersBack` (T-566) was declared here. It pinned
    // CadenceTaskMutationSupport.updateBundle's undo, which reached the members as well as the
    // block's own four fields. [[T-3170]]'s trio pass deleted `updateBundle` and `moveBundle`
    // with the last surfaces that called them, so there is no edit left to refuse.

    // `theIOSBlockSheetSaveDismissesOnlyThroughASuccessfulTry` was declared here, and read the
    // "Save" button of `iOSCalendarBundleDetailSheet` to prove its `catch` returned before
    // `dismiss()`. Its sibling "Delete Block" had caught since T-322 and the sibling *create*
    // sheet since T-471; this was the third exit from the same sheet. [[T-3170]] deleted the sheet,
    // so there is no button to read. The half that was never about the button, `updateBundle`'s
    // undo, went with `updateBundle` itself in [[T-3170]]'s trio pass.

    /// Non-vacuity for the scans in this suite: the reader really returned Swift.
    ///
    /// It read `iOSTrackingEditorSheets.swift` and `CreateGoalSheet.swift` until [[T-2079]] deleted
    /// both, then the block sheet until [[T-3170]] deleted that. It reads the shared mutation the
    /// surviving tests are about, and **asserts the three deleted paths are gone**: a non-vacuity
    /// check that silently started reading a file that no longer exists would throw rather than
    /// report, and a re-added editor or Block sheet should fail here rather than slip past.
    @Test func thetrackingSaveCommitScansReadRealSource() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceTaskMutationSupport.swift")
        #expect(raw.contains("static func deleteBundle("))
        #expect(CadenceSourceScan.strippingComments(raw) != raw)

        let files = try CadenceSourceScan.swiftFiles(under: "Cadence")
        #expect(files.count > 300, "the sweep read \(files.count) files and cannot be doing its job")
        #expect(!files.contains("Cadence/iOS/iOSTrackingEditorSheets.swift"))
        #expect(!files.contains("Cadence/macOS/Sheets/CreateGoalSheet.swift"))
        #expect(!files.contains("Cadence/iOS/iOSCalendarBundleDetailSheet.swift"))
    }

    // The local functionBody(_:in:) and failureBranchReturnsBeforeReportingSuccess(_:report:) were
    // declared here. Both read a *button body* out of a view file to prove its `catch` returned
    // before the success report, and every caller they had was one of the three iOS write surfaces
    // this suite has now outlived — two to [[T-2079]], the Block sheet to [[T-3170]]. The scan is
    // not lost: `CadenceSourceScan.functionBody(named:in:)` is the shared reader and the
    // dismiss-over-a-refusal shape is held repo-wide by `CadenceSaveCommitDisciplineTests`.
}
