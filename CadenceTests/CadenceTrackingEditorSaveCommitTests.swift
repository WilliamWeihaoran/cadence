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

    /// The success path, asserted from a **second context on the same container**: the first
    /// context answers with the new goal whether or not the save landed, so a single-context
    /// assertion passes against the bug.
    @Test func acommittedGoalCreationIsInTheStoreBeforeTheEditorCouldClose() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)

        let goal = try CadenceTrackingMutationSupport.saveGoal(
            nil,
            title: "Ship the thing",
            desc: "",
            startDate: "2026-08-30",
            endDate: "2026-09-30",
            progressType: .subtasks,
            targetHours: 0,
            icon: "flag.fill",
            colorHex: Theme.blueHex,
            kind: .completable,
            status: .active,
            context: nil,
            parentGoal: nil,
            allGoals: [],
            modelContext: modelContext
        )

        #expect(goal != nil)
        #expect(!modelContext.hasChanges)
        #expect(try ModelContext(modelContainer).fetch(FetchDescriptor<Goal>()).map(\.title) == ["Ship the thing"])
    }

    /// A refused creation throws **and leaves nothing behind** — not in the store, and not pending
    /// in the context, where the next unrelated `save()` from any other screen would commit it.
    @Test func arefusedGoalCreationLeavesNothingPendingForSomeoneElseToCommit() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)

        #expect(throws: CommitRefused.self) {
            _ = try CadenceTrackingMutationSupport.saveGoal(
                nil,
                title: "Ship the thing",
                desc: "",
                startDate: "2026-08-30",
                endDate: "2026-09-30",
                progressType: .subtasks,
                targetHours: 0,
                icon: "flag.fill",
                colorHex: Theme.blueHex,
                kind: .completable,
                status: .active,
                context: nil,
                parentGoal: nil,
                allGoals: [],
                modelContext: modelContext,
                commit: { _ in throw CommitRefused() }
            )
        }

        #expect(try modelContext.fetch(FetchDescriptor<Goal>()).isEmpty)
        #expect(try ModelContext(modelContainer).fetch(FetchDescriptor<Goal>()).isEmpty)
    }

    /// A refused **edit** puts every field back. Without the undo, the live `Goal` keeps answering
    /// with the new title while the store holds the old one, and every `@Query` list on screen
    /// shows a rename that did not happen.
    @Test func arefusedGoalEditPutsEveryFieldBackTheWayItWasFound() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let goal = Goal(title: "Old")
        goal.desc = "Old definition"
        goal.startDate = "2026-01-01"
        goal.endDate = "2026-02-01"
        goal.icon = "flag.fill"
        goal.colorHex = Theme.blueHex
        goal.kind = .completable
        goal.status = .active
        goal.targetHours = 3
        modelContext.insert(goal)
        try modelContext.save()

        #expect(throws: CommitRefused.self) {
            _ = try CadenceTrackingMutationSupport.saveGoal(
                goal,
                title: "New",
                desc: "New definition",
                startDate: "2026-03-01",
                endDate: "2026-04-01",
                progressType: .hours,
                targetHours: 40,
                icon: "sparkles",
                colorHex: Theme.redHex,
                kind: .ongoing,
                status: .paused,
                context: nil,
                parentGoal: nil,
                allGoals: [goal],
                modelContext: modelContext,
                commit: { _ in throw CommitRefused() }
            )
        }

        #expect(goal.title == "Old")
        #expect(goal.desc == "Old definition")
        #expect(goal.startDate == "2026-01-01")
        #expect(goal.endDate == "2026-02-01")
        #expect(goal.progressType == .subtasks)
        #expect(goal.targetHours == 3)
        #expect(goal.icon == "flag.fill")
        #expect(goal.colorHex == Theme.blueHex)
        #expect(goal.kind == .completable)
        #expect(goal.status == .active)
    }

    /// `nil` still means only what it always meant — the title was empty — and it is **not** a
    /// throw. That separation is the whole of T-470: a caller that conflated the two would show a
    /// store failure for a blank field, or swallow a refused store, depending which way it guessed.
    @Test func anemptyGoalTitleAnswersNilRatherThanThrowingEvenWhenTheCommitWouldRefuse() throws {
        let modelContext = ModelContext(try container())
        let goal = try CadenceTrackingMutationSupport.saveGoal(
            nil,
            title: "   ",
            desc: "",
            startDate: "2026-08-30",
            endDate: "2026-09-30",
            progressType: .subtasks,
            targetHours: 0,
            icon: "flag.fill",
            colorHex: Theme.blueHex,
            kind: .completable,
            status: .active,
            context: nil,
            parentGoal: nil,
            allGoals: [],
            modelContext: modelContext,
            commit: { _ in throw CommitRefused() }
        )
        #expect(goal == nil)
    }

    // MARK: - Habits

    @Test func arefusedHabitCreationLeavesNothingPendingForSomeoneElseToCommit() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)

        #expect(throws: CommitRefused.self) {
            _ = try CadenceTrackingMutationSupport.saveHabit(
                nil,
                title: "Read",
                icon: "book.fill",
                colorHex: Theme.blueHex,
                frequencyType: .daily,
                frequencyDays: [],
                targetCount: 1,
                context: nil,
                goal: nil,
                allHabits: [],
                modelContext: modelContext,
                commit: { _ in throw CommitRefused() }
            )
        }

        #expect(try modelContext.fetch(FetchDescriptor<Habit>()).isEmpty)
        #expect(try ModelContext(modelContainer).fetch(FetchDescriptor<Habit>()).isEmpty)
    }

    @Test func arefusedHabitEditPutsEveryFieldBackTheWayItWasFound() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let habit = Habit(title: "Old")
        habit.icon = "book.fill"
        habit.colorHex = Theme.blueHex
        habit.frequencyType = .daily
        habit.frequencyDays = []
        habit.targetCount = 1
        modelContext.insert(habit)
        try modelContext.save()

        #expect(throws: CommitRefused.self) {
            _ = try CadenceTrackingMutationSupport.saveHabit(
                habit,
                title: "New",
                icon: "figure.run",
                colorHex: Theme.redHex,
                frequencyType: .daysOfWeek,
                frequencyDays: [1, 3, 5],
                targetCount: 3,
                context: nil,
                goal: nil,
                allHabits: [habit],
                modelContext: modelContext,
                commit: { _ in throw CommitRefused() }
            )
        }

        #expect(habit.title == "Old")
        #expect(habit.icon == "book.fill")
        #expect(habit.colorHex == Theme.blueHex)
        #expect(habit.frequencyType == .daily)
        #expect(habit.frequencyDays == [])
        #expect(habit.targetCount == 1)
    }

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
    @Test func eachRefusalNamesItsOwnObjectAndOnlyTheDeleteClaimsNothingWasRemoved() {
        #expect(CadenceTrackingMutationSupport.goalSaveFailureNotice == "Couldn't save this goal.")
        #expect(CadenceTrackingMutationSupport.habitSaveFailureNotice == "Couldn't save this habit.")
        #expect(CadenceTaskMutationSupport.bundleDeleteFailureNotice.contains("Nothing was removed."))
        // The create family carries no such clause: a refused creation has nothing to fear losing.
        #expect(!CadenceTrackingMutationSupport.goalSaveFailureNotice.contains("Nothing"))
        #expect(!CadenceTaskMutationSupport.bundleSaveFailureNotice.contains("Nothing"))
    }

    /// macOS's goal editor. A private method on a SwiftUI view, so this is a scan.
    @Test func themacGoalSheetDismissesOnlyThroughASuccessfulTry() throws {
        let body = try functionBody("save", in: "Cadence/macOS/Sheets/CreateGoalSheet.swift")
        #expect(CadenceSourceScan.matchCount("try CadenceTrackingMutationSupport\\.saveGoal", in: body) == 1)
        #expect(CadenceSourceScan.matchCount("saveError = CadenceTrackingMutationSupport\\.goalSaveFailureNotice", in: body) == 1)
        #expect(
            failureBranchReturnsBeforeReportingSuccess(body, report: "dismiss()"),
            "CreateGoalSheet.save() can still reach dismiss() from the catch"
        )
    }

    /// The three iOS call sites, which this target does not compile.
    @Test func theIOSTrackingEditorsAndBlockDeleteDismissOnlyThroughASuccessfulTry() throws {
        for (name, path, notice) in [
            ("save", "Cadence/iOS/iOSTrackingEditorSheets.swift", "goalSaveFailureNotice"),
            ("save", "Cadence/iOS/iOSTrackingEditorSheets.swift", "habitSaveFailureNotice"),
        ] {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            #expect(CadenceSourceScan.matchCount("actionError = CadenceTrackingMutationSupport\\.\(notice)", in: source) >= 1, "\(path) \(name)")
        }

        let editors = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTrackingEditorSheets.swift")
        )
        #expect(CadenceSourceScan.matchCount("try\\? modelContext\\.save\\(\\)", in: editors) == 0)
        #expect(CadenceSourceScan.matchCount("try CadenceTrackingMutationSupport\\.save(Goal|Habit)", in: editors) == 2)

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

    /// Non-vacuity for the three scans above: the reader really returned Swift.
    @Test func thetrackingSaveCommitScansReadRealSource() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTrackingEditorSheets.swift")
        #expect(raw.contains("struct iOSGoalEditorSheet: View"))
        #expect(CadenceSourceScan.strippingComments(raw) != raw)
        #expect(try functionBody("save", in: "Cadence/macOS/Sheets/CreateGoalSheet.swift").contains("do {"))
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
