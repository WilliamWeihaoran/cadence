import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **No launch writes a `Goal`, a `Habit`, a `HabitCompletion` or a `GoalListLink`** ([[T-2077]]).
///
/// The owner retired goals and habits at the depth *"remove the UI and stop writing, keep the
/// schema"*: the models stay in `CadenceSchema`, the CloudKit record types stay, and the rows
/// already in the store — 2 habits, 7 habit completions and 5 goals in Production at the time the
/// ticket was filed — stay exactly as they are, so the decision stays reversible. The one thing
/// that must never happen again is a write.
///
/// **Why this suite is a store test and not a source scan.** A scan for `Goal(` or
/// `modelContext.insert` proves something about the text and nothing about the behaviour: three of
/// the writers this ticket removed were *field* writes (`habit.reminderMinuteOfDay = nil`) and one
/// was a *delete*, and no constructor scan would have caught any of them. So this drives the whole
/// launch — `PersistenceController.performStartupMaintenance`, the real one, not a replay of it —
/// over a store deliberately arranged to contain every row shape a retired pass used to react to,
/// and asserts the four tables come out byte-identical.
///
/// **The fixture is the evidence.** Every assertion here is satisfied by an empty store, so the
/// fixture is built to be the exact opposite: a `Pursuit` with a child goal and a child habit (the
/// `PursuitToGoalMigration` fold), a habit-day duplicated across two rows (the
/// `repairDuplicateHabitCompletions` collapse), and a habit whose `reminderMinuteOfDay` is outside
/// `0...1439` (the `repairOutOfRangeHabitReminders` clear). `theFixtureHoldsEveryRowARetiredPassUsedToReactTo`
/// is the control: if the fixture ever stops holding one of those, the counts stop being evidence
/// and that test goes red first.
///
/// **Mutation-tested.** Restoring any one of the three retired passes turns at least one
/// `#expect` below red — see the ledger entry for which line each one lands on.
///
/// **`.preservesTheStoredLaunchReports` is load-bearing, not copied decoration.** This suite calls
/// `PersistenceController.performStartupMaintenance`, which reaches
/// `DataIntegrityRepairService.repairAndRecordFailure` and `NoteMigrationService`'s writer, and
/// neither takes an injectable store: `record(_:)` is a private static writing
/// `UserDefaults.standard`. Without the trait, running this suite overwrites the launch report the
/// *app* reads back on its next launch with `{"source":"test"}` ([[T-480]]).
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

            // Read off a **second context on the same container**, so this is the store rather
            // than the live objects: a pass that wrote and saved would show here even if the
            // in-memory graph happened to look unchanged.
            #expect(try snapshot(of: ModelContext(container)) == before)

            // The three field-level writes the retired passes made, each asserted on the row
            // itself. Counts alone cannot see any of them.
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

        // the retired reminder pass cleared a minute outside `0...1439`. 1440 is outside it,
        // asked of the one function that owns the range rather than restated.
        #expect(!HabitReminderTime.namesATimeOfDay(1440))
        #expect(fixture.corruptReminder.reminderMinuteOfDay == 1440)

        // the retired duplicate collapse took a habit-day carrying more than one row.
        let day = (fixture.duplicatedHabit.completions ?? []).filter { $0.date == Self.duplicatedDay }
        #expect(day.count == 2)
    }

    /// The MCP write surface cannot mint either model any more, and the tools are **absent** from
    /// the advertised schema rather than present and refusing.
    ///
    /// Read from source because `CadenceMCPToolDefinitions` lives in `CadenceMCPServer`, a
    /// command-line target this test bundle does not link. That is the same reason
    /// `CadenceMCPToolContractTests` scans rather than calls.
    @Test func theMCPWriteSurfaceAdvertisesNoGoalOrHabitConstructor() throws {
        let definitions = try CadenceSourceScan.sourceFile("CadenceMCPServer/CadenceMCPToolDefinitions.swift")
        let router = try CadenceSourceScan.sourceFile("CadenceMCPServer/CadenceMCPToolRouter.swift")
        let service = try CadenceSourceScan.sourceFile("Cadence/Services/MCPReadOnly/CadenceWriteService.swift")

        // Non-vacuity: the files were found and still hold the surface this is about.
        #expect(definitions.contains("\"create_task\""), "non-vacuity: wrong definitions file")
        #expect(router.contains("case \"create_task\":"), "non-vacuity: wrong router file")
        #expect(service.contains("func createTask("), "non-vacuity: wrong write service")

        #expect(!definitions.contains("Tool(name: \"create_goal\""))
        #expect(!definitions.contains("Tool(name: \"create_habit\""))
        #expect(!router.contains("case \"create_goal\":"))
        #expect(!router.contains("case \"create_habit\":"))
        #expect(!service.contains("func createGoal("))
        #expect(!service.contains("func createHabit("))

        // The reads are deliberately untouched: this removes the ability to mint, not to see.
        #expect(definitions.contains("Tool(name: \"list_goals\""))
        #expect(definitions.contains("Tool(name: \"list_habits\""))
        #expect(definitions.contains("Tool(name: \"get_goal\""))
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

    /// The four tracking tables, as sorted row identities rather than counts.
    ///
    /// Identities and not counts, deliberately: a pass that minted one row and deleted another —
    /// which is precisely the shape the retired fold in `PursuitToGoalMigration` had on the `Goal`
    /// table, paired with the retired duplicate collapse on the completion table — leaves every
    /// count intact.
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
