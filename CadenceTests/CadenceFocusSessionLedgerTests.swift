import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-621: focus minutes were read-modify-write counters, so two devices lost sessions.**
///
/// `AppTask.actualMinutes`, `Area.loggedMinutes` and `Project.loggedMinutes` are CloudKit-synced
/// scalars that three sites wrote with `+=`. Two devices each bank a session, each reads the same
/// starting value, each writes its own sum, and the record that arrives second wins — one session
/// gone, and with it the goal progress `GoalContributionSummary` folds `actualMinutes` into.
///
/// The fix is a ledger: `FocusSessionLog`, one row per increment, and
/// `CadenceFocusLedger.reconcile(in:)` to raise a counter back to what its rows say. The counters
/// stay because ~20 surfaces read them and they are what moves before any sync happens.
///
/// **What this suite has to pin, in order of how much it matters:**
/// 1. Two replicas each logging a session end up with **both** — the defect, behaviourally.
/// 2. Reconciling is idempotent, because there is no `SchemaMigrationPlan` in this project and so
///    no run-once hook to hang a backfill on. It runs on every launch, for ever.
/// 3. Reconciling only ever **raises**, because startup runs it against a store that may have
///    received a fraction of CloudKit's rows.
/// 4. A row written *after* a reconcile is counted once, not twice — the invariant that lets the
///    baseline be `min(previousMinutes)` rather than a stored field nobody can migrate in.
@MainActor
struct CadenceFocusSessionLedgerTests {

    private struct CommitRefused: Error {}

    // MARK: - 1. The defect, behaviourally

    /// **The failing-first test.** Two replicas of one task, each of which really ran
    /// `CadenceFocusLedger.bank` against its own store, merged the way CloudKit merges: the scalar
    /// is whichever device's record landed last, and both devices' ledger rows are present.
    ///
    /// The banked *values* come from real `bank` runs; only the transport is simulated, because
    /// two `ModelContainer`s cannot hand each other a `PersistentModel`. Before the reconcile the
    /// merged store holds 110 — the second writer's sum, with the first writer's 25 minutes gone.
    /// That number is the ticket.
    @Test func twoReplicasEachLoggingASessionEndUpWithBothRatherThanOne() throws {
        let replicaA = try replicaBanking(minutes: 25, ontoACounterHolding: 100)
        let replicaB = try replicaBanking(minutes: 10, ontoACounterHolding: 100)

        // Each device, alone, is right about itself and wrong about the other.
        #expect(replicaA.counterAfter == 125)
        #expect(replicaB.counterAfter == 110)

        let context = ModelContext(try CadenceTestStore.container())
        let task = AppTask(title: "Draft the proposal")
        task.actualMinutes = 100
        context.insert(task)
        // CloudKit's merge of a synced scalar: last writer wins. B's record landed second.
        task.actualMinutes = replicaB.counterAfter
        attach(replicaA.row, to: task, in: context)
        attach(replicaB.row, to: task, in: context)
        try context.save()

        #expect(task.actualMinutes == 110, "the merge really did drop a session")

        let changed = CadenceFocusLedger.reconcile(in: context)

        #expect(changed)
        #expect(
            task.actualMinutes == 135,
            "both sessions must survive the merge: 100 before the ledger, plus 25 and plus 10"
        )
    }

    /// The same merge on a list counter. `Project.loggedMinutes` is what an hours-mode `Goal`
    /// reads, so this is the half that shows up as wrong goal progress rather than a wrong label.
    @Test func twoReplicasEachLoggingASessionKeepBothOnTheListCounterToo() throws {
        let context = ModelContext(try CadenceTestStore.container())
        let project = Project(name: "Launch")
        project.loggedMinutes = 40
        context.insert(project)
        try context.save()

        // Device A banks 30 here.
        CadenceFocusLedger.bank(30, to: project, in: context)
        #expect(project.loggedMinutes == 70)
        // Device B banked 15 concurrently from 40, and its record arrived second.
        project.loggedMinutes = 55
        let deviceBRow = FocusSessionLog(minutes: 15, previousMinutes: 40, loggedAt: Date(), dayKey: "2026-09-03")
        context.insert(deviceBRow)
        deviceBRow.project = project
        try context.save()

        CadenceFocusLedger.reconcile(in: context)

        #expect(project.loggedMinutes == 85)
    }

    /// The same merge, healed by the **next session** instead of by a store-wide pass. `bank`
    /// corrects the subject it is about to write to, so a task you focus again fixes its own
    /// counter with no launch hook and no fetch over the store.
    @Test func thenextSessionOnATaskHealsACounterAMergeClobbered() throws {
        let context = ModelContext(try CadenceTestStore.container())
        let task = AppTask(title: "Draft the proposal")
        task.actualMinutes = 100
        context.insert(task)
        try context.save()

        CadenceFocusLedger.bank(25, to: task, in: context)
        task.actualMinutes = 110 // a concurrent 10-minute session won the merge
        let other = FocusSessionLog(minutes: 10, previousMinutes: 100, loggedAt: Date(), dayKey: "2026-09-03")
        context.insert(other)
        other.task = task
        try context.save()

        CadenceFocusLedger.bank(5, to: task, in: context)

        #expect(task.actualMinutes == 140, "100 before the ledger, plus 25, plus 10, plus the 5 just banked")
        #expect(CadenceFocusLedger.reconcile(in: context) == false, "bank left nothing for the sweep to do")
    }

    /// After a bank, the counter and the ledger agree **exactly**. That equality is the invariant
    /// the whole design rests on: it is what makes the store-wide pass idempotent rather than
    /// merely convergent, because the pass recomputes a number the counter already holds.
    @Test func aCounterEqualsItsLedgerTotalAfterEveryBank() throws {
        let context = ModelContext(try CadenceTestStore.container())
        let task = AppTask(title: "Repeatedly focused")
        task.actualMinutes = 7
        context.insert(task)
        try context.save()

        for minutes in [3, 11, 1, 40] {
            CadenceFocusLedger.bank(minutes, to: task, in: context)
            #expect(CadenceFocusLedger.reconciledTotal(of: task.focusSessions ?? []) == task.actualMinutes)
        }
        #expect(task.actualMinutes == 62)
    }

    // MARK: - 2. Idempotence — the property that replaces a backfill

    /// Reconciling twice lands on the same number. There is no migration hook in this project to
    /// run a backfill once, so this pass runs at every launch on every device: a version that
    /// added rather than recomputed would double a user's logged time on the second launch.
    @Test func reconcilingRepeatedlyLandsOnTheSameTotal() throws {
        let context = ModelContext(try CadenceTestStore.container())
        let area = Area(name: "Home")
        area.loggedMinutes = 60
        context.insert(area)
        try context.save()

        CadenceFocusLedger.bank(20, to: area, in: context)
        area.loggedMinutes = 65 // a merge dropped 15 of the 20
        try context.save()

        var totals: [Int] = []
        for _ in 0..<4 {
            CadenceFocusLedger.reconcile(in: context)
            totals.append(area.loggedMinutes)
        }

        #expect(totals == [80, 80, 80, 80])
    }

    /// The second and later runs report **no change**, which is what keeps startup maintenance from
    /// saving — and re-syncing — a store nothing happened to.
    @Test func aSecondReconcileReportsNothingChanged() throws {
        let context = ModelContext(try CadenceTestStore.container())
        let task = AppTask(title: "Review")
        task.actualMinutes = 10
        context.insert(task)
        try context.save()

        CadenceFocusLedger.bank(5, to: task, in: context)
        task.actualMinutes = 10 // the increment was clobbered
        try context.save()

        #expect(CadenceFocusLedger.reconcile(in: context))
        #expect(task.actualMinutes == 15)
        #expect(CadenceFocusLedger.reconcile(in: context) == false)
        #expect(task.actualMinutes == 15)
    }

    /// An empty ledger reconciles nothing and says so. This is the store a fresh device has on the
    /// launch that races its first CloudKit import, and the pass has to be inert there.
    @Test func aStoreWithNoLedgerRowsIsLeftAlone() throws {
        let context = ModelContext(try CadenceTestStore.container())
        let task = AppTask(title: "Untouched")
        task.actualMinutes = 90
        context.insert(task)
        try context.save()

        #expect(CadenceFocusLedger.reconcile(in: context) == false)
        #expect(task.actualMinutes == 90, "a counter with no rows behind it is not a counter to lower")
    }

    // MARK: - 3. It only ever raises

    /// A partially-synced store holds a subset of the rows, so its computed total is too low.
    /// Writing that back would destroy minutes the counter already had — the exact failure mode
    /// `DataIntegrityRepairService`'s doc comment forbids for an unattended startup pass. `max`
    /// makes it a no-op instead, and the total climbs as the missing rows arrive.
    @Test func aPartiallySyncedStoreIsANoOpRatherThanALoss() throws {
        let context = ModelContext(try CadenceTestStore.container())
        let task = AppTask(title: "Half synced")
        task.actualMinutes = 100
        context.insert(task)
        // Only one of the two devices' rows has arrived; the counter already reflects both.
        task.actualMinutes = 135
        let arrived = FocusSessionLog(minutes: 25, previousMinutes: 100, loggedAt: Date(), dayKey: "2026-09-03")
        context.insert(arrived)
        arrived.task = task
        try context.save()

        #expect(CadenceFocusLedger.reconcile(in: context) == false)
        #expect(task.actualMinutes == 135, "125 is what the visible rows say; 135 is what the store knows")

        // The straggler lands.
        let late = FocusSessionLog(minutes: 10, previousMinutes: 100, loggedAt: Date(), dayKey: "2026-09-03")
        context.insert(late)
        late.task = task
        try context.save()

        #expect(CadenceFocusLedger.reconcile(in: context) == false)
        #expect(task.actualMinutes == 135)
    }

    // MARK: - 4. The baseline stays the baseline

    /// A session banked *after* a reconcile carries the reconciled counter as its `previousMinutes`,
    /// which is above the existing minimum — so it adds its own minutes and does not move the
    /// baseline. This is the invariant that lets the legacy total be `min(previousMinutes)` rather
    /// than a stored field this project has no `SchemaMigrationPlan` to add.
    @Test func aSessionBankedAfterAReconcileCountsOnceAndDoesNotMoveTheBaseline() throws {
        let context = ModelContext(try CadenceTestStore.container())
        let task = AppTask(title: "Ongoing")
        task.actualMinutes = 100
        context.insert(task)
        try context.save()

        CadenceFocusLedger.bank(25, to: task, in: context)
        task.actualMinutes = 110 // a concurrent 10-minute session won the merge
        let other = FocusSessionLog(minutes: 10, previousMinutes: 100, loggedAt: Date(), dayKey: "2026-09-03")
        context.insert(other)
        other.task = task
        try context.save()

        CadenceFocusLedger.reconcile(in: context)
        #expect(task.actualMinutes == 135)

        CadenceFocusLedger.bank(5, to: task, in: context)
        #expect(task.actualMinutes == 140)
        #expect((task.focusSessions ?? []).map(\.previousMinutes).min() == 100)

        CadenceFocusLedger.reconcile(in: context)
        #expect(task.actualMinutes == 140, "the reconcile must not re-add the session it just watched")
    }

    // MARK: - The write sites record rows

    /// Banking against a task moves the task's counter **and** its list's, and records a row for
    /// each — two counters, two rows, because they reconcile independently.
    @Test func bankingASessionRecordsOneRowPerCounterItMoves() throws {
        let context = ModelContext(try CadenceTestStore.container())
        let project = Project(name: "Launch")
        let task = AppTask(title: "Write the brief")
        task.project = project
        context.insert(project)
        context.insert(task)
        try context.save()

        CadenceFocusLedger.bank(25, forTaskAndItsList: task, in: context)
        try context.save()

        #expect(task.actualMinutes == 25)
        #expect(project.loggedMinutes == 25)
        #expect((task.focusSessions ?? []).count == 1)
        #expect((project.focusSessions ?? []).count == 1)
        #expect((task.focusSessions ?? []).first?.previousMinutes == 0)
        #expect(try context.fetchCount(FetchDescriptor<FocusSessionLog>()) == 2)
    }

    /// The stopwatch door. `CadenceFocusSupport.bankElapsedSeconds(_:to:)` is what the single-task
    /// timer banks through on both platforms, and it must now leave a row behind.
    @Test func theStopwatchLogsThroughTheLedger() throws {
        let context = ModelContext(try CadenceTestStore.container())
        let area = Area(name: "Home")
        let task = AppTask(title: "Tidy")
        task.area = area
        context.insert(area)
        context.insert(task)
        try context.save()

        CadenceFocusSupport.bankElapsedSeconds(25 * 60, to: task, in: context)
        try context.save()

        #expect(task.actualMinutes == 25)
        #expect(area.loggedMinutes == 25)
        #expect(try context.fetchCount(FetchDescriptor<FocusSessionLog>()) == 2)
    }

    /// The block door. `distributeMinutes` spreads a block's minutes across its ticked members, and
    /// each member's share is its own row — otherwise a block session is invisible to the reconcile
    /// that a single-task session is not.
    @Test func aBlockSessionRecordsARowPerMember() throws {
        let context = ModelContext(try CadenceTestStore.container())
        let project = Project(name: "Launch")
        let first = AppTask(title: "One")
        first.estimatedMinutes = 30
        first.project = project
        let second = AppTask(title: "Two")
        second.estimatedMinutes = 30
        second.project = project
        context.insert(project)
        context.insert(first)
        context.insert(second)
        try context.save()

        try CadenceFocusSupport.distributeMinutes(60, across: [first, second], in: context)
        try context.save()

        #expect(first.actualMinutes == 30)
        #expect(second.actualMinutes == 30)
        #expect(project.loggedMinutes == 60)
        // Two member rows plus two project rows: the project counter really took two increments.
        #expect(try context.fetchCount(FetchDescriptor<FocusSessionLog>()) == 4)
        #expect(CadenceFocusLedger.reconciledTotal(of: project.focusSessions ?? []) == 60)
    }

    /// A session under a whole minute writes nothing, and now that includes writing no row. A
    /// ledger row for zero minutes would be a record of work that did not happen.
    @Test func aSessionUnderAMinuteRecordsNoRow() throws {
        let context = ModelContext(try CadenceTestStore.container())
        let task = AppTask(title: "Blinked at it")
        context.insert(task)
        try context.save()

        CadenceFocusSupport.bankElapsedSeconds(20, to: task, in: context)

        #expect(task.actualMinutes == 0)
        #expect(try context.fetchCount(FetchDescriptor<FocusSessionLog>()) == 0)
    }

    // MARK: - A refused commit undoes the row too

    /// **The half a ledger makes newly dangerous.** `CadenceFocusSupport.complete` restores the
    /// three counters when the settle is refused (T-636(c)). If it restored the counters and left
    /// the rows, the rows would sit in the app's one `ModelContext` as pending inserts for the next
    /// unrelated `save()` to take — and the next reconcile would raise the counter back to include
    /// a session the user was told was not recorded.
    @Test func arefusedCompletionLeavesNoLedgerRowBehind() throws {
        let context = ModelContext(try CadenceTestStore.container())
        let project = Project(name: "Launch")
        let task = AppTask(title: "Finish it")
        task.project = project
        task.actualMinutes = 10
        project.loggedMinutes = 10
        context.insert(project)
        context.insert(task)
        try context.save()

        #expect(throws: CommitRefused.self) {
            try CadenceFocusSupport.complete(
                task,
                elapsedSeconds: 25 * 60,
                modelContext: context,
                commit: { _ in throw CommitRefused() }
            )
        }

        #expect(task.actualMinutes == 10)
        #expect(project.loggedMinutes == 10)
        #expect((task.focusSessions ?? []).isEmpty)
        #expect((project.focusSessions ?? []).isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<FocusSessionLog>()) == 0)
        // And the reconcile has nothing to resurrect.
        #expect(CadenceFocusLedger.reconcile(in: context) == false)
        #expect(task.actualMinutes == 10)
    }

    /// **The block door's own version of the test above (T-654).** `distributeMinutes` is what
    /// `CadenceFocusBundleSupport.endSession` and `iOSFocusView.logBundleSession` share, and it
    /// snapshots every credited member before writing — a refusal has to put every one of them
    /// back, not just the first. Proved across a **second** `ModelContext` over the same container,
    /// not just the one that ran the refused commit: reading the same context back only shows
    /// whatever is still pending in memory, which is true whether the write rolled back or is
    /// merely uncommitted. A fresh context can only see what the store actually holds, which is
    /// what distinguishes "restored" from "never left this process".
    @Test func arefusedBlockSessionLeavesNoLedgerRowBehindForAnyMember() throws {
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)
        let project = Project(name: "Launch")
        let first = AppTask(title: "One")
        first.estimatedMinutes = 30
        first.actualMinutes = 5
        first.project = project
        let second = AppTask(title: "Two")
        second.estimatedMinutes = 30
        second.actualMinutes = 7
        second.project = project
        project.loggedMinutes = 12
        context.insert(project)
        context.insert(first)
        context.insert(second)
        try context.save()

        #expect(throws: CommitRefused.self) {
            try CadenceFocusSupport.distributeMinutes(
                60,
                across: [first, second],
                in: context,
                commit: { _ in throw CommitRefused() }
            )
        }

        // The context itself is back to what it was before the write.
        #expect(first.actualMinutes == 5)
        #expect(second.actualMinutes == 7)
        #expect(project.loggedMinutes == 12)
        #expect((first.focusSessions ?? []).isEmpty)
        #expect((second.focusSessions ?? []).isEmpty)
        #expect((project.focusSessions ?? []).isEmpty)

        // Saving the same context again proves nothing was left pending for an unrelated save to
        // take, and a fresh context over the same container proves the store itself never moved.
        try context.save()
        let reader = ModelContext(container)
        let storedProject = try #require(try reader.fetch(FetchDescriptor<Project>()).first)
        #expect(storedProject.loggedMinutes == 12)
        #expect(try reader.fetchCount(FetchDescriptor<FocusSessionLog>()) == 0)
        let storedTasks = try reader.fetch(FetchDescriptor<AppTask>()).sorted { $0.title < $1.title }
        #expect(storedTasks.map(\.actualMinutes) == [5, 7])
    }

    // MARK: - The model reaches every surface a `@Model` has to

    /// `CadenceSchema` is the authoritative list, and a model outside it is not persisted at all.
    /// The reset, export and markdown-classification surfaces are each held by their own
    /// schema-driven suite; this is the one that fails first if the entry is missing.
    @Test func theLedgerIsInTheSchema() {
        #expect(CadenceSchema.schema.entities.map(\.name).contains("FocusSessionLog"))
    }

    // MARK: - Helpers

    /// One device, with its own store, really running `bank` against a counter that already held
    /// `existing` minutes. Returns what that device wrote and the row it recorded, as values —
    /// a `PersistentModel` cannot cross containers, so the merge above rebuilds the row.
    private func replicaBanking(
        minutes: Int,
        ontoACounterHolding existing: Int
    ) throws -> (counterAfter: Int, row: (minutes: Int, previousMinutes: Int)) {
        let context = ModelContext(try CadenceTestStore.container())
        let task = AppTask(title: "Draft the proposal")
        task.actualMinutes = existing
        context.insert(task)
        try context.save()

        CadenceFocusLedger.bank(minutes, to: task, in: context)
        try context.save()

        let row = try #require((task.focusSessions ?? []).first)
        return (task.actualMinutes, (row.minutes, row.previousMinutes))
    }

    private func attach(
        _ row: (minutes: Int, previousMinutes: Int),
        to task: AppTask,
        in context: ModelContext
    ) {
        let log = FocusSessionLog(
            minutes: row.minutes,
            previousMinutes: row.previousMinutes,
            loggedAt: Date(),
            dayKey: "2026-09-03"
        )
        context.insert(log)
        log.task = task
    }
}
