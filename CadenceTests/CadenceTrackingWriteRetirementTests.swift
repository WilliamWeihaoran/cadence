import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **No code path in the app writes a `Goal`, a `Habit`, a `HabitCompletion` or a `GoalListLink`**
/// ([[T-2077]] + [[T-2079]]).
///
/// The owner retired goals and habits at the depth *"remove the UI and stop writing, keep the
/// schema"*: the models stay in `CadenceSchema`, the CloudKit record types stay, and the rows
/// already in the store — 2 habits, 7 habit completions and 5 goals in Production when the work was
/// filed — stay exactly as they are, so the decision stays reversible. The one thing that must
/// never happen again is a write.
///
/// **Why this is a store test and not a source scan.** A scan for `Goal(` or `modelContext.insert`
/// proves something about the text and nothing about the behaviour: three of the writers T-2077
/// removed were *field* writes (`habit.reminderMinuteOfDay = nil`) and one was a *delete*, and no
/// constructor needle would have caught any of them. So this drives the whole launch —
/// `PersistenceController.performStartupMaintenance`, the real one, not a replay — and a task
/// lifecycle over a goal, and asserts the four tracking tables come out unmoved.
///
/// **The fixture is the evidence.** Every assertion here is satisfied by an empty store, so the
/// fixture is built to be the opposite: a `Pursuit` with a child goal and a child habit (the
/// retired `PursuitToGoalMigration` fold), a habit-day duplicated across two rows (the retired
/// duplicate collapse), a habit whose `reminderMinuteOfDay` is outside `0...1439` (the retired
/// reminder clear), and a goal list link. `theFixtureHoldsEveryRowARetiredPassUsedToReactTo` is the
/// control: if the fixture ever stops holding one of those, the counts stop being evidence and that
/// test goes red first.
///
/// **The two construction scans are the other half**, and they live with the models they are about:
/// `CadenceHabitCompletionDuplicateTests.nothingUnderCadenceConstructsAHabitCompletion` and
/// `CadenceGoalListLinkSurfaceTests.nothingUnderCadenceConstructsAGoalListLink`. `Goal` and `Habit`
/// have no such scan because the archive importer legitimately constructs both, which is why this
/// suite reads row identities instead.
@Suite(.preservesTheStoredLaunchReports)
@MainActor
struct CadenceTrackingWriteRetirementTests {

    /// The whole launch maintenance sequence, over a store full of rows the retired passes used to
    /// rewrite. Nothing moves.
    @Test func afullStartupMaintenancePassWritesNoTrackingRow() throws {
        try withTemporaryDefaults("CadenceTrackingWriteRetirementTests") { defaults in
            let container = try CadenceModelContainerFactory.makeInMemoryContainer()
            let modelContext = ModelContext(container)
            let fixture = try seedEveryRetiredPassTrigger(in: modelContext)

            let before = try snapshot(of: modelContext)

            PersistenceController.performStartupMaintenance(in: modelContext, defaults: defaults)

            #expect(try snapshot(of: modelContext) == before)

            // Read off a **second context on the same container**, so this is the store rather than
            // the live objects: a pass that wrote and saved would show here even if the in-memory
            // graph happened to look unchanged.
            #expect(try snapshot(of: ModelContext(container)) == before)

            // The three field-level writes the retired passes made, each asserted on the row
            // itself. Row identities cannot see any of them.
            #expect(fixture.corruptReminder.reminderMinuteOfDay == 1440, "a startup pass cleared a habit reminder")
            #expect(fixture.milestone.parentGoal == nil, "a startup pass re-parented a goal")
            #expect(fixture.pursuitHabit.goal == nil, "a startup pass re-pointed a habit at a goal")
            #expect(fixture.milestone.pursuit?.id == fixture.pursuit.id, "a startup pass unhooked a pursuit's goal")
        }
    }

    /// The same launch, run twice. A pass that is quiet the first time and writes the second — the
    /// shape a latched `UserDefaults` flag produces — is not quiet.
    @Test func asecondLaunchOverTheSameStoreWritesNothingEither() throws {
        try withTemporaryDefaults("CadenceTrackingWriteRetirementTests") { defaults in
            let container = try CadenceModelContainerFactory.makeInMemoryContainer()
            let modelContext = ModelContext(container)
            _ = try seedEveryRetiredPassTrigger(in: modelContext)

            let before = try snapshot(of: modelContext)
            PersistenceController.performStartupMaintenance(in: modelContext, defaults: defaults)
            PersistenceController.performStartupMaintenance(in: modelContext, defaults: defaults)

            #expect(try snapshot(of: ModelContext(container)) == before)
        }
    }

    /// **A task lifecycle over a goal writes no goal** ([[T-2079]]).
    ///
    /// This is the subtle one, and it was suspected rather than known: completing a task could
    /// plausibly update the goal's progress. It does not, and the reason is structural — goal
    /// progress is **computed**. `GoalContributionSummary` is a plain `struct` built by
    /// `GoalContributionResolver` on read, not a `@Model`, so there is no stored percentage for a
    /// task operation to move. `Goal.loggedHours` is the one stored field that could have carried
    /// one, and `nothingButTheArchiveImporterAssignsAGoalsLoggedHours` below is its guard.
    @Test func ataskLifecycleOverAGoalAndAHabitWritesNoTrackingRow() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let fixture = try seedEveryRetiredPassTrigger(in: modelContext)

        let task = AppTask(title: "Draft chapter 1")
        task.goal = fixture.milestone
        task.context = fixture.milestone.context
        modelContext.insert(task)
        try modelContext.save()

        let before = try snapshot(of: modelContext)
        let goalFieldsBefore = Self.fields(of: fixture.milestone)

        try CadenceTaskMutationSupport.toggleCompletion(task, modelContext: modelContext)
        #expect(CadenceTaskQuerySupport.isFinishedTask(task), "premise: the task really completed")
        try CadenceTaskMutationSupport.toggleCompletion(task, modelContext: modelContext)
        #expect(!CadenceTaskQuerySupport.isFinishedTask(task), "premise: the task really reopened")

        #expect(try snapshot(of: modelContext) == before)
        #expect(try snapshot(of: ModelContext(container)) == before)
        #expect(Self.fields(of: fixture.milestone) == goalFieldsBefore, "a task operation edited a goal")
        #expect(fixture.corruptReminder.reminderMinuteOfDay == 1440, "a task operation edited a habit")

        // Non-vacuity: the resolver really is reading this goal, so "the goal did not change" is a
        // statement about a goal something looked at rather than about an inert row.
        #expect(GoalContributionResolver.summary(for: fixture.milestone).totalTasks == 1)
    }

    /// `Goal.loggedHours` has **no live writer**, which is the one stored field that could have let
    /// a focus session move a goal row.
    ///
    /// Its own declaration says "manual + future timer data"; the timer was never wired, and the
    /// only code that assigns it is `CadenceArchiveImportService`, restoring a value the owner
    /// already had. Asserted as a source fact rather than a behavioural one because the claim *is*
    /// about the set of writers, and a behavioural test can only show that the paths it happened to
    /// drive left it alone.
    ///
    /// **The needle matches compound assignment, and mutation is what taught it to.** It was
    /// `\.loggedHours\s*=`, and a mutation that made `toggleCompletion` run
    /// `task.goal?.loggedHours += 1` sailed straight past it — `+` sits between the name and the
    /// `=` — while `ataskLifecycleOverAGoalAndAHabitWritesNoTrackingRow` above caught it against
    /// the store. Both instruments stay, and that is why: the scan knows the *set* of writers and
    /// the store test knows what a write *does*, and each one's blind spot is the other's subject.
    ///
    /// **`(?!=)` is load-bearing and the fourth witness below is what found it.** Widening to
    /// `[-+*/]?=` made `if goal.loggedHours == 0` a match, because the optional operator slot
    /// happily takes nothing and the `=` it then finds is the first half of `==`. A comparison is
    /// not a write, and a needle that calls one a write would have reported this file's own
    /// readers as offenders.
    @Test func nothingButTheArchiveImporterAssignsAGoalsLoggedHours() throws {
        var offenders: [String] = []
        for path in try CadenceSourceScan.swiftFiles(under: "Cadence") {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            let count = CadenceSourceScan.matchCount(#"\.loggedHours\s*[-+*/]?=(?!=)"#, in: code)
            guard count > 0 else { continue }
            offenders.append("\(path):\(count)")
        }
        #expect(
            offenders == ["Cadence/Services/CadenceArchiveImportService.swift:1"],
            "a shipped file assigns Goal.loggedHours: \(offenders)"
        )
        // Non-vacuity on both halves: the needle matches a real assignment and misses a read, and
        // the sweep walked a tree rather than nothing.
        #expect(CadenceSourceScan.matchCount(#"\.loggedHours\s*[-+*/]?=(?!=)"#, in: "model.loggedHours = record.loggedHours") == 1)
        #expect(CadenceSourceScan.matchCount(#"\.loggedHours\s*[-+*/]?=(?!=)"#, in: "goal.loggedHours += 1") == 1)
        #expect(CadenceSourceScan.matchCount(#"\.loggedHours\s*[-+*/]?=(?!=)"#, in: "let x = goal.loggedHours") == 0)
        #expect(CadenceSourceScan.matchCount(#"\.loggedHours\s*[-+*/]?=(?!=)"#, in: "if goal.loggedHours == 0 {") == 0)
        #expect(try CadenceSourceScan.swiftFiles(under: "Cadence").count > 300)
    }

    /// The control. Every count above is only evidence while the fixture really holds the rows the
    /// retired passes reacted to; an empty store satisfies all of them against the old code too.
    @Test func theFixtureHoldsEveryRowARetiredPassUsedToReactTo() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let fixture = try seedEveryRetiredPassTrigger(in: modelContext)

        // The retired fold inside `PursuitToGoalMigration` took a pursuit whose child goal had no
        // parent and whose child habit named no goal. That is this row, in that state.
        #expect(try modelContext.fetch(FetchDescriptor<Pursuit>()).count == 1)
        #expect((fixture.pursuit.goals ?? []).count == 1)
        #expect((fixture.pursuit.habits ?? []).count == 1)
        #expect(fixture.milestone.parentGoal == nil)
        #expect(fixture.pursuitHabit.goal == nil)

        // The retired reminder pass cleared a minute outside `0...1439`. 1440 is outside it, asked
        // of the one function that owns the range rather than restated.
        #expect(!HabitReminderTime.namesATimeOfDay(1440))
        #expect(fixture.corruptReminder.reminderMinuteOfDay == 1440)

        // The retired duplicate collapse took a habit-day carrying more than one row.
        let day = (fixture.duplicatedHabit.completions ?? []).filter { $0.date == Self.duplicatedDay }
        #expect(day.count == 2)
    }

    // MARK: - Fixture

    private struct RetiredPassTriggers {
        let pursuit: Pursuit
        let milestone: Goal
        let pursuitHabit: Habit
        let corruptReminder: Habit
        let duplicatedHabit: Habit
    }

    private static let duplicatedDay = "2026-03-09"

    /// One row for each retired pass, in the state that pass reacted to. Saved, so the launch sees
    /// committed rows rather than pending ones.
    private func seedEveryRetiredPassTrigger(in modelContext: ModelContext) throws -> RetiredPassTriggers {
        let context = Context(name: "Personal")
        modelContext.insert(context)

        let pursuit = Pursuit(title: "Become more knowledgeable", context: context, kind: .ongoing)
        let milestone = Goal(title: "Read 12 books", context: context)
        milestone.pursuit = pursuit
        let pursuitHabit = Habit(title: "Read 20 pages")
        pursuitHabit.context = context
        pursuitHabit.pursuit = pursuit
        modelContext.insert(pursuit)
        modelContext.insert(milestone)
        modelContext.insert(pursuitHabit)

        let corruptReminder = Habit(title: "Wraps to midnight on iOS")
        corruptReminder.reminderMinuteOfDay = 1440
        modelContext.insert(corruptReminder)

        let duplicatedHabit = Habit(title: "Meditate")
        modelContext.insert(duplicatedHabit)
        for _ in 0..<2 {
            modelContext.insert(HabitCompletion(date: Self.duplicatedDay, habit: duplicatedHabit))
        }

        // A link row too, so the fourth table is not asserted empty-against-empty.
        let area = Area(name: "Reading")
        area.context = context
        modelContext.insert(area)
        modelContext.insert(GoalListLink(goal: milestone, area: area))

        try modelContext.save()

        return RetiredPassTriggers(
            pursuit: pursuit,
            milestone: milestone,
            pursuitHabit: pursuitHabit,
            corruptReminder: corruptReminder,
            duplicatedHabit: duplicatedHabit
        )
    }

    /// Every stored field on a `Goal` that a write could move, as one comparable string.
    ///
    /// Row identities catch a mint and a delete; they cannot see an **edit**, and `saveGoal` was an
    /// edit path as much as a create one. This is what makes "the goal did not change" mean the
    /// goal's own values rather than its continued existence.
    private static func fields(of goal: Goal) -> String {
        [
            goal.title, goal.desc, goal.startDate, goal.endDate,
            goal.progressType.rawValue, String(goal.targetHours), String(goal.loggedHours),
            goal.icon, goal.colorHex, goal.kind.rawValue, goal.status.rawValue,
            String(goal.order),
            goal.context?.id.uuidString ?? "-", goal.parentGoal?.id.uuidString ?? "-",
        ].joined(separator: "|")
    }

    /// The four tracking tables, as sorted row identities rather than counts.
    ///
    /// Identities and not counts, deliberately: a pass that minted one row and deleted another —
    /// which is precisely the shape the retired fold had on the `Goal` table paired with the
    /// retired duplicate collapse on the completion table — leaves every count intact.
    private func snapshot(of modelContext: ModelContext) throws -> TrackingSnapshot {
        TrackingSnapshot(
            goals: try modelContext.fetch(FetchDescriptor<Goal>()).map(\.id.uuidString).sorted(),
            habits: try modelContext.fetch(FetchDescriptor<Habit>()).map(\.id.uuidString).sorted(),
            completions: try modelContext.fetch(FetchDescriptor<HabitCompletion>()).map(\.id.uuidString).sorted(),
            links: try modelContext.fetch(FetchDescriptor<GoalListLink>()).map(\.id.uuidString).sorted()
        )
    }

    private struct TrackingSnapshot: Equatable {
        let goals: [String]
        let habits: [String]
        let completions: [String]
        let links: [String]
    }
}
