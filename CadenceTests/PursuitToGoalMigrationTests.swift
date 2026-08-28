import Foundation
import SwiftData
import Testing
@testable import Cadence

@MainActor
struct PursuitToGoalMigrationTests {
    @Test func pursuitBecomesTopLevelGoalCarryingItsIdentity() throws {
        let modelContext = try makeContext()

        let context = Context(name: "Personal")
        let pursuit = Pursuit(title: "Become more knowledgeable", context: context, kind: .ongoing)
        pursuit.desc = "Read widely and take notes"
        pursuit.icon = "book.fill"
        pursuit.colorHex = "#a78bfa"
        pursuit.status = .paused
        pursuit.order = 3
        pursuit.createdAt = Date(timeIntervalSince1970: 1_700_000_000)

        modelContext.insert(context)
        modelContext.insert(pursuit)
        try modelContext.save()

        #expect(PursuitToGoalMigration.migrate(modelContext: modelContext))

        let migrated = try #require(try modelContext.fetch(FetchDescriptor<Goal>()).first)
        #expect(migrated.title == "Become more knowledgeable")
        #expect(migrated.desc == "Read widely and take notes")
        #expect(migrated.icon == "book.fill")
        #expect(migrated.colorHex == "#a78bfa")
        #expect(migrated.kind == .ongoing)
        #expect(migrated.status == .paused)
        #expect(migrated.order == 3)
        #expect(migrated.createdAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(migrated.context?.id == context.id)
        #expect(migrated.isTopLevel)
        // A pursuit had no dates, so the migrated goal stays undated on the timeline.
        #expect(migrated.startDate.isEmpty)
        #expect(migrated.endDate.isEmpty)
    }

    @Test func childGoalsBecomeMilestonesOfTheMigratedGoal() throws {
        let modelContext = try makeContext()

        let context = Context(name: "Personal")
        let pursuit = Pursuit(title: "Become more knowledgeable", context: context)
        let milestone = Goal(title: "Read 12 books", context: context)
        milestone.pursuit = pursuit

        modelContext.insert(context)
        modelContext.insert(pursuit)
        modelContext.insert(milestone)
        try modelContext.save()

        #expect(PursuitToGoalMigration.migrate(modelContext: modelContext))

        let goals = try modelContext.fetch(FetchDescriptor<Goal>())
        let migrated = try #require(goals.first { $0.title == "Become more knowledgeable" })
        #expect(milestone.parentGoal?.id == migrated.id)
        #expect(milestone.pursuit == nil)
        #expect((migrated.subGoals ?? []).map(\.id) == [milestone.id])
    }

    @Test func childHabitsRepointAtTheMigratedGoal() throws {
        let modelContext = try makeContext()

        let context = Context(name: "Personal")
        let pursuit = Pursuit(title: "Become more knowledgeable", context: context)
        let habit = Habit(title: "Read 30 minutes", context: context)
        habit.pursuit = pursuit

        modelContext.insert(context)
        modelContext.insert(pursuit)
        modelContext.insert(habit)
        try modelContext.save()

        #expect(PursuitToGoalMigration.migrate(modelContext: modelContext))

        let migrated = try #require(try modelContext.fetch(FetchDescriptor<Goal>()).first)
        #expect(habit.goal?.id == migrated.id)
        #expect(habit.pursuit == nil)
        #expect((migrated.habits ?? []).map(\.id) == [habit.id])
    }

    @Test func explicitGoalNestingSurvivesMigration() throws {
        let modelContext = try makeContext()

        let pursuit = Pursuit(title: "Get stronger")
        let existingParent = Goal(title: "Powerlifting total")
        let child = Goal(title: "Deadlift 300")
        child.parentGoal = existingParent
        child.pursuit = pursuit

        modelContext.insert(pursuit)
        modelContext.insert(existingParent)
        modelContext.insert(child)
        try modelContext.save()

        #expect(PursuitToGoalMigration.migrate(modelContext: modelContext))

        // The explicit nesting is more specific than the pursuit grouping, so it wins.
        #expect(child.parentGoal?.id == existingParent.id)
        #expect(child.pursuit == nil)

        let migrated = try #require(try modelContext.fetch(FetchDescriptor<Goal>()).first { $0.title == "Get stronger" })
        #expect((migrated.subGoals ?? []).isEmpty)
    }

    @Test func habitAlreadyLinkedToGoalIsNotRepointed() throws {
        let modelContext = try makeContext()

        let pursuit = Pursuit(title: "Get stronger")
        let goal = Goal(title: "Deadlift 300")
        let habit = Habit(title: "Lift three times", goal: goal)
        habit.pursuit = pursuit

        modelContext.insert(pursuit)
        modelContext.insert(goal)
        modelContext.insert(habit)
        try modelContext.save()

        #expect(PursuitToGoalMigration.migrate(modelContext: modelContext))

        #expect(habit.goal?.id == goal.id)
        #expect(habit.pursuit == nil)

        let migrated = try #require(try modelContext.fetch(FetchDescriptor<Goal>()).first { $0.title == "Get stronger" })
        #expect((migrated.habits ?? []).isEmpty)
    }

    @Test func pursuitsAreDeletedOnceTheirContentsAreRehung() throws {
        let modelContext = try makeContext()

        let context = Context(name: "Personal")
        let pursuit = Pursuit(title: "Become more knowledgeable", context: context)
        let milestone = Goal(title: "Read 12 books", context: context)
        let habit = Habit(title: "Read 30 minutes", context: context)
        milestone.pursuit = pursuit
        habit.pursuit = pursuit

        modelContext.insert(context)
        modelContext.insert(pursuit)
        modelContext.insert(milestone)
        modelContext.insert(habit)
        try modelContext.save()

        #expect(PursuitToGoalMigration.migrate(modelContext: modelContext))

        #expect(try modelContext.fetch(FetchDescriptor<Pursuit>()).isEmpty)
        #expect((context.pursuits ?? []).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<Goal>()).count == 2)
        #expect(try modelContext.fetch(FetchDescriptor<Habit>()).count == 1)
    }

    @Test func runningTheMigrationTwiceIsHarmless() throws {
        let modelContext = try makeContext()

        let context = Context(name: "Personal")
        let pursuit = Pursuit(title: "Become more knowledgeable", context: context)
        let milestone = Goal(title: "Read 12 books", context: context)
        let habit = Habit(title: "Read 30 minutes", context: context)
        milestone.pursuit = pursuit
        habit.pursuit = pursuit

        modelContext.insert(context)
        modelContext.insert(pursuit)
        modelContext.insert(milestone)
        modelContext.insert(habit)
        try modelContext.save()

        #expect(PursuitToGoalMigration.migrate(modelContext: modelContext))
        let goalIDsAfterFirstPass = Set(try modelContext.fetch(FetchDescriptor<Goal>()).map(\.id))

        #expect(PursuitToGoalMigration.migrate(modelContext: modelContext))

        #expect(Set(try modelContext.fetch(FetchDescriptor<Goal>()).map(\.id)) == goalIDsAfterFirstPass)
        #expect(try modelContext.fetch(FetchDescriptor<Pursuit>()).isEmpty)
        #expect(milestone.parentGoal?.title == "Become more knowledgeable")
        #expect(habit.goal?.title == "Become more knowledgeable")
    }

    @Test func emptyStoreMigratesCleanly() throws {
        let modelContext = try makeContext()

        #expect(PursuitToGoalMigration.migrate(modelContext: modelContext))
        #expect(try modelContext.fetch(FetchDescriptor<Goal>()).isEmpty)
    }

    /// `PursuitToGoalMigration.completionKey` is private, so it is spelled here — which also pins
    /// it: changing the key without bumping `v1` would silently re-run the migration everywhere.
    private static let completionKey = "pursuitToGoalMigration.v1.completed"

    /// A device that already migrated, then restores a backup that still has `Pursuit` rows in it.
    ///
    /// `PersistenceController.init` applies a pending restore before it opens the container and
    /// calls `performStartupMaintenance`, so the store startup maintenance reads can be a backup
    /// that predates the migration — while the flag, which lives in `UserDefaults` rather than in
    /// the store, is still set. A flag-only guard skips the pass forever and the restored pursuits
    /// are stranded with nothing showing them. T-393.
    @Test func aRestoredBackupIsMigratedEvenThoughTheFlagIsAlreadySet() throws {
        try withTemporaryDefaults("PursuitToGoalMigrationTests") { defaults in
            let modelContext = try makeContext()
            defaults.set(true, forKey: Self.completionKey)

            let context = Context(name: "Personal")
            let pursuit = Pursuit(title: "Restored from a backup", context: context)
            let milestone = Goal(title: "Read 12 books", context: context)
            milestone.pursuit = pursuit
            modelContext.insert(context)
            modelContext.insert(pursuit)
            modelContext.insert(milestone)
            try modelContext.save()

            PursuitToGoalMigration.runIfNeeded(modelContext: modelContext, defaults: defaults)

            #expect(try modelContext.fetch(FetchDescriptor<Pursuit>()).isEmpty)
            let migrated = try #require(
                try modelContext.fetch(FetchDescriptor<Goal>()).first { $0.title == "Restored from a backup" }
            )
            #expect(migrated.isTopLevel)
            #expect(milestone.parentGoal?.id == migrated.id)
        }
    }

    /// The flag still does its job on the ordinary launch: it latches after a clean pass, and a
    /// store with nothing left to fold is not rewritten by the content probe that replaced it.
    @Test func theFlagLatchesAndAStoreWithNoPursuitsIsLeftAlone() throws {
        try withTemporaryDefaults("PursuitToGoalMigrationTests") { defaults in
            let modelContext = try makeContext()

            let context = Context(name: "Personal")
            let pursuit = Pursuit(title: "Become more knowledgeable", context: context)
            modelContext.insert(context)
            modelContext.insert(pursuit)
            try modelContext.save()

            #expect(!defaults.bool(forKey: Self.completionKey))
            PursuitToGoalMigration.runIfNeeded(modelContext: modelContext, defaults: defaults)
            #expect(defaults.bool(forKey: Self.completionKey))
            let afterFirstLaunch = Set(try modelContext.fetch(FetchDescriptor<Goal>()).map(\.id))
            #expect(afterFirstLaunch.count == 1)

            PursuitToGoalMigration.runIfNeeded(modelContext: modelContext, defaults: defaults)

            #expect(Set(try modelContext.fetch(FetchDescriptor<Goal>()).map(\.id)) == afterFirstLaunch)
            #expect(try modelContext.fetch(FetchDescriptor<Pursuit>()).isEmpty)
        }
    }

    private func makeContext() throws -> ModelContext {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        return ModelContext(container)
    }
}
