import Foundation
import SwiftData
import Testing
@testable import Cadence

/// What the retired pursuit migration does now: **nothing at all** ([[T-2077]]).
///
/// This suite used to hold fifteen assertions that the pass folded a `Pursuit` into a `Goal` —
/// that it carried the pursuit's identity across, re-parented its child goals, re-pointed its
/// habits, deleted the pursuit afterwards and latched a `UserDefaults` flag. Every one of those
/// was an assertion that a **launch** creates `Goal` records, which is the single thing T-2077
/// stops. They are not weakened here; they are inverted, because the behaviour they described is
/// the behaviour the owner asked to be removed.
///
/// **The replacement asserts the store is unmoved across the pass**: the same `Goal`, `Pursuit`
/// and `Habit` row counts before and after, **and** the two relationships the fold rewrote read
/// off the rows themselves — a count pair alone cannot tell a quiet pass from one that minted a
/// goal and deleted a pursuit, which is why the pointer checks sit beside it. It is driven from a
/// store deliberately arranged in the shape
/// the old migration reacted hardest to — a pursuit owning a child goal and a child habit, with
/// the completion flag *unset* so no fast path can be what makes it quiet.
///
/// **Non-vacuity, which the old suite's own `runIfNeededSeparatesAFoldFromAStoreWithNothingLeftToFold`
/// warns about in as many words.** A store with no `Pursuit` row would pass this suite against the
/// *old* implementation too, so every test below seeds at least one pursuit and the first one
/// asserts the seed is still there afterwards — if the fixture ever stops holding a pursuit, the
/// counts stop being evidence and `theFixtureItselfHoldsAPursuitToFold` goes red.
@MainActor
struct PursuitToGoalMigrationTests {

    /// The guard with teeth: a launch-shaped call over a store full of foldable rows writes
    /// nothing.
    ///
    /// Restoring the old `migrate` body turns this red on the first `#expect` — the pre-pass goal
    /// set is `[milestone]` and the post-pass set gains the goal minted from the pursuit.
    @Test func theRetiredMigrationCreatesNoGoalAndDeletesNoPursuit() throws {
        try withTemporaryDefaults("PursuitToGoalMigrationTests") { defaults in
            let modelContext = try makeContext()
            let fixture = try seedAFoldablePursuit(in: modelContext)

            let goalsBefore = try count(of: Goal.self, in: modelContext)
            let pursuitsBefore = try count(of: Pursuit.self, in: modelContext)
            let habitsBefore = try count(of: Habit.self, in: modelContext)

            #expect(PursuitToGoalMigration.runIfNeeded(modelContext: modelContext, defaults: defaults) == .nothingToDo)

            #expect(try count(of: Goal.self, in: modelContext) == goalsBefore)
            #expect(try count(of: Pursuit.self, in: modelContext) == pursuitsBefore)
            #expect(try count(of: Habit.self, in: modelContext) == habitsBefore)

            // The two relationships the fold used to rewrite, read off the rows themselves rather
            // than off a count: counts net out under a pass that both mints and deletes, and these
            // do not.
            #expect(fixture.milestone.parentGoal == nil)
            #expect(fixture.milestone.pursuit?.id == fixture.pursuit.id)
            #expect(fixture.habit.goal == nil)
            #expect(fixture.habit.pursuit?.id == fixture.pursuit.id)
        }
    }

    /// The same call, run twice, from a store whose completion flag is already set — the [[T-393]]
    /// restored-backup shape, which is the one path that could still re-arm the old pass on a
    /// device that migrated years ago. It is quiet now for a reason that does not depend on the
    /// flag at all.
    @Test func aRestoredPreMergeBackupIsLeftExactlyAsItArrived() throws {
        try withTemporaryDefaults("PursuitToGoalMigrationTests") { defaults in
            let modelContext = try makeContext()
            defaults.set(true, forKey: Self.completionKey)
            _ = try seedAFoldablePursuit(in: modelContext)

            let goalsBefore = try count(of: Goal.self, in: modelContext)
            let pursuitsBefore = try count(of: Pursuit.self, in: modelContext)

            PursuitToGoalMigration.runIfNeeded(modelContext: modelContext, defaults: defaults)
            PursuitToGoalMigration.runIfNeeded(modelContext: modelContext, defaults: defaults)

            #expect(try count(of: Goal.self, in: modelContext) == goalsBefore)
            #expect(try count(of: Pursuit.self, in: modelContext) == pursuitsBefore)
        }
    }

    /// The pass does not latch the completion flag any more, and that is deliberate rather than an
    /// oversight: a set flag records a migration that happened, and none did.
    @Test func theCompletionFlagIsNeitherReadNorWritten() throws {
        try withTemporaryDefaults("PursuitToGoalMigrationTests") { defaults in
            let modelContext = try makeContext()
            _ = try seedAFoldablePursuit(in: modelContext)

            #expect(!defaults.bool(forKey: Self.completionKey))
            PursuitToGoalMigration.runIfNeeded(modelContext: modelContext, defaults: defaults)
            #expect(!defaults.bool(forKey: Self.completionKey))
        }
    }

    /// The control. Every count above is only evidence while the fixture really does hold the row
    /// the old pass reacted to; an empty store satisfies all of them against either implementation.
    @Test func theFixtureItselfHoldsAPursuitToFold() throws {
        let modelContext = try makeContext()
        let fixture = try seedAFoldablePursuit(in: modelContext)

        #expect(try modelContext.fetch(FetchDescriptor<Pursuit>()).count == 1)
        #expect((fixture.pursuit.goals ?? []).count == 1)
        #expect((fixture.pursuit.habits ?? []).count == 1)
        // The old `migrate` folded a pursuit only when the child had no parent goal of its own and
        // the habit named no goal, so the fixture is in the state it reacted to, not beside it.
        #expect(fixture.milestone.parentGoal == nil)
        #expect(fixture.habit.goal == nil)
    }

    // MARK: - Fixture

    private struct FoldableFixture {
        let pursuit: Pursuit
        let milestone: Goal
        let habit: Habit
    }

    /// A pursuit owning one child goal and one child habit, both in the state the retired `migrate`
    /// reacted to. Saved, so the pass sees committed rows rather than pending ones.
    private func seedAFoldablePursuit(in modelContext: ModelContext) throws -> FoldableFixture {
        let context = Context(name: "Personal")
        let pursuit = Pursuit(title: "Become more knowledgeable", context: context, kind: .ongoing)
        let milestone = Goal(title: "Read 12 books", context: context)
        milestone.pursuit = pursuit
        let habit = Habit(title: "Read 20 pages")
        habit.context = context
        habit.pursuit = pursuit

        modelContext.insert(context)
        modelContext.insert(pursuit)
        modelContext.insert(milestone)
        modelContext.insert(habit)
        try modelContext.save()

        return FoldableFixture(pursuit: pursuit, milestone: milestone, habit: habit)
    }

    /// The `UserDefaults` key the retired pass latched. It was private to the migration and was
    /// spelled here before T-2077 for the same reason it is spelled here now: it is what
    /// `theCompletionFlagIsNeitherReadNorWritten` watches, so the day someone re-arms the pass,
    /// the key this suite checks is the key that pass would use.
    private static let completionKey = "pursuitToGoalMigration.v1.completed"

    private func count<T: PersistentModel>(of _: T.Type, in modelContext: ModelContext) throws -> Int {
        try modelContext.fetch(FetchDescriptor<T>()).count
    }

    private func makeContext() throws -> ModelContext {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        return ModelContext(container)
    }
}
