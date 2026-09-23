import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-191: `GoalContributionResolver` folds `goal.listLinks`' tasks into a goal's percentage on
/// every platform, and `GoalListLink` had **zero** references under `Cadence/iOS` — so an iOS user
/// watched a number move for a reason the device could not show or change.
///
/// **Two kinds of test here, and the second kind is the point.** The first half pins the pure
/// decisions: which links a goal shows, what the attribution sentence says, and that attaching a
/// list really does move `summary.progress`. The second half reads the real source files and fails
/// the moment iOS grows its own `insert(GoalListLink(...))` beside macOS's — a helper can be right
/// while nothing calls it, which is exactly how this gap opened.
///
/// Source-text assertions are the only tool available for the iOS half: `Cadence/iOS/` is entirely
/// inside `#if os(iOS)` and this target builds for macOS, so there is no iOS symbol to reference.
/// The helpers follow `CadenceSharedTaskRowJobsTests` — exact per-file counts rather than
/// "contains", comment-stripping rather than allowlisting, and a non-vacuity test so a broken scan
/// cannot make the absence assertions pass silently.
@MainActor
struct CadenceGoalListLinkSurfaceTests {

    // MARK: - Fixtures

    private struct Store {
        let container: ModelContainer
        let modelContext: ModelContext
        let context: Context
        let area: Area
        let project: Project
        let goal: Goal
    }

    private func makeStore() throws -> Store {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let context = Context(name: "Work")
        let area = Area(name: "Documents", context: context)
        let project = Project(name: "Launch", context: context)
        let goal = Goal(title: "Ship it", context: context)

        modelContext.insert(context)
        modelContext.insert(area)
        modelContext.insert(project)
        modelContext.insert(goal)

        return Store(
            container: container,
            modelContext: modelContext,
            context: context,
            area: area,
            project: project,
            goal: goal
        )
    }

    private func summary(
        progressType: GoalProgressType = .subtasks,
        totalTasks: Int,
        directTaskCount: Int,
        linkedListCount: Int
    ) -> GoalContributionSummary {
        GoalContributionSummary(
            progressType: progressType,
            targetHours: 10,
            totalTasks: totalTasks,
            completedTasks: 0,
            directTaskCount: directTaskCount,
            linkedListCount: linkedListCount,
            focusMinutes: 0,
            overdueTaskIDs: [],
            recentCompletedCount: 0,
            nextActionTitle: nil,
            nextActionDueDate: nil
        )
    }

    // MARK: - The premise

    /// The ticket's claim, asserted rather than assumed: a link is what moves the bar, and nothing
    /// about the goal itself changed between these two reads.
    @Test func attachingAListMovesTheGoalsProgress() throws {
        let store = try makeStore()

        let open = AppTask(title: "Open")
        open.area = store.area
        let done = AppTask(title: "Done")
        done.area = store.area
        done.status = .done
        store.modelContext.insert(open)
        store.modelContext.insert(done)

        let before = GoalContributionResolver.summary(for: store.goal)
        #expect(before.totalTasks == 0)
        #expect(before.progress == 0)

        try store.modelContext.attachList(.area(store.area), to: store.goal)

        let after = GoalContributionResolver.summary(for: store.goal)
        #expect(after.totalTasks == 2)
        #expect(after.completedTasks == 1)
        #expect(after.progress == 0.5)
        #expect(after.linkedListCount == 1)
        #expect(after.directTaskCount == 0)
    }

    // MARK: - Attach / detach

    @Test func attachingInsertsOneLinkAndIsIdempotent() throws {
        let store = try makeStore()

        try store.modelContext.attachList(.area(store.area), to: store.goal)
        try store.modelContext.attachList(.area(store.area), to: store.goal)

        let links = try store.modelContext.fetch(FetchDescriptor<GoalListLink>())
        #expect(links.count == 1)
        #expect(GoalLinkPresentation.links(of: store.goal).count == 1)
        #expect(GoalLinkPresentation.isAttached(.area(store.area), to: store.goal))
        #expect(!GoalLinkPresentation.isAttached(.project(store.project), to: store.goal))
    }

    /// A duplicate link cannot move the percentage — `contributingTasks` dedupes by task `id` — so
    /// this asserts what a duplicate *would* actually break: anything counting links rather than
    /// tasks. `linkedListCount` feeds the "N lists" chip, the attribution line and two MCP DTOs, and
    /// a second row would appear in both inspectors.
    ///
    /// The previous name and comment here claimed the percentage was the symptom. It was not, and a
    /// mutation removing `attachList`'s early return left this test **passing** — protected upstream,
    /// exactly like the `isDone` guard on the goal Momentum count that was reverted for the same
    /// reason.
    @Test func aDuplicateAttachIsCollapsedSoLinkCountsStayTruthful() throws {
        let store = try makeStore()

        let task = AppTask(title: "Counted once")
        task.area = store.area
        store.modelContext.insert(task)

        try store.modelContext.attachList(.area(store.area), to: store.goal)
        try store.modelContext.attachList(.area(store.area), to: store.goal)

        let summary = GoalContributionResolver.summary(for: store.goal)

        // The assertions that actually fail when idempotency is removed. `totalTasks` is **not** one
        // of them — `contributingTasks` dedupes by task `id`, so it stays 1 either way, which is why
        // this test passed under a mutation removing the guard.
        #expect(summary.linkedListCount == 1)
        #expect(GoalLinkPresentation.links(of: store.goal).count == 1)

        // Kept as documentation of what a duplicate does *not* break, so nobody restores the old
        // rationale: the percentage is protected upstream regardless of this guard.
        #expect(summary.totalTasks == 1)
    }

    @Test func togglingAttachesThenDetaches() throws {
        let store = try makeStore()

        #expect(try store.modelContext.toggleGoalListLink(.project(store.project), on: store.goal))
        #expect(GoalLinkPresentation.links(of: store.goal).count == 1)

        #expect(try store.modelContext.toggleGoalListLink(.project(store.project), on: store.goal) == false)
        #expect(GoalLinkPresentation.links(of: store.goal).isEmpty)
        #expect(try store.modelContext.fetch(FetchDescriptor<GoalListLink>()).isEmpty)
    }

    // MARK: - A refused attach, and what the two sheets say about it ([[T-1306]])

    /// A commit that refuses. `ModelContext.save()` cannot be made to throw out of an in-memory
    /// container, which is why both mutations take their commit as a parameter at all.
    private struct CommitRefused: Error {}

    private static func refuse(_ modelContext: ModelContext) throws { throw CommitRefused() }

    /// [[T-1306]]: the checkmark has to agree with the alert.
    ///
    /// Both attach sheets draw from `GoalLinkPresentation.isAttached` and both goal inspectors from
    /// `links(of:)`, and until this ticket both kept the list ticked after a refusal while
    /// `changeFailureNotice` said "Nothing was changed." Measured on this Mac (Xcode 27,
    /// 2026-09-20) before the fix: `(goal.listLinks ?? []).count == 1` with that link's `isDeleted`
    /// set, `links(of:).count == 1`, `isAttached == true`.
    ///
    /// **Nothing here pins a toolchain answer ([[T-1296]]).** The array's count between the refusal
    /// and the next processed pending change is exactly the framework timing this repository's two
    /// Xcode majors disagree about, so it is not asserted. What is asserted is the pair of readings
    /// the user is looking at — which `existingLink`'s `isDeleted` skip makes right whether or not
    /// the array has caught up — and then the store, read forwards through the next unrelated
    /// `save()` from a second context, in [[T-1295]]'s shape.
    @Test func arefusedAttachLeavesBothSheetsAgreeingWithTheAlert() throws {
        let store = try makeStore()
        let task = AppTask(title: "Area task")
        task.area = store.area
        store.modelContext.insert(task)
        try store.modelContext.save()

        #expect(throws: CommitRefused.self) {
            try store.modelContext.attachList(.area(store.area), to: store.goal, commit: Self.refuse)
        }

        #expect(
            GoalLinkPresentation.isAttached(.area(store.area), to: store.goal) == false,
            "both attach sheets still tick a list the alert says was not attached"
        )
        #expect(
            GoalLinkPresentation.links(of: store.goal).isEmpty,
            "both goal inspectors still draw a row for a link the store does not hold"
        )

        // **And the progress bar, which does not go through `GoalLinkPresentation` at all.**
        // `GoalContributionSummary` reads `goal.listLinks` raw — twice, for the counted tasks and
        // for the "N lists" chip — so this is the half that the restore has to actually *process*
        // rather than merely assign. Measured before the fix: 1 list and 1 counted task, from a
        // refusal.
        let summary = GoalContributionResolver.summary(for: store.goal)
        #expect(summary.linkedListCount == 0, "the goal's \"N lists\" chip counts a refused attach")
        #expect(summary.totalTasks == 0, "the goal's progress bar counts a refused attach's work")

        try store.modelContext.save()
        let reader = ModelContext(store.container)
        #expect(try reader.fetch(FetchDescriptor<GoalListLink>()).isEmpty)
        #expect(try reader.fetch(FetchDescriptor<Goal>()).count == 1)
    }

    /// The `isDeleted` skip on its own, against the state it exists for — and **toolchain-free by
    /// construction** ([[T-1306]], [[T-1296]]).
    ///
    /// The two readings above are made right twice over: `attachList` processes its restore, and
    /// `links(of:)` / `existingLink(for:on:)` skip a deleted link besides. That is deliberate
    /// belt-and-braces — the Xcode 26 reading of whether `processPendingChanges()` materialises the
    /// restored array could not be taken, because this Mac has Xcode 27.0 and no second toolchain —
    /// and it would otherwise be a guard no mutation can kill, which this repository has been
    /// bitten by twice on this very file. So it is exercised here directly rather than through the
    /// refusal: a link deleted and **not** processed is the state the skip answers for, and if a
    /// toolchain clears the array at the delete instead, every assertion below still holds.
    @Test func aDeletedLinkIsNotAnAttachedListInEitherReading() throws {
        let store = try makeStore()
        let link = try #require(try store.modelContext.attachList(.area(store.area), to: store.goal))
        try store.modelContext.save()
        #expect(GoalLinkPresentation.isAttached(.area(store.area), to: store.goal))

        store.modelContext.delete(link)

        #expect(
            GoalLinkPresentation.links(of: store.goal).isEmpty,
            "a row the store is about to drop is still drawn as a linked list"
        )
        #expect(
            GoalLinkPresentation.isAttached(.area(store.area), to: store.goal) == false,
            "a row the store is about to drop still ticks the list on both attach sheets"
        )
        #expect(
            GoalLinkPresentation.existingLink(for: .area(store.area), on: store.goal) == nil,
            "attachList's idempotence guard would hand this link back and attach nothing"
        )
    }

    /// **The third reading, and the one no filter in `GoalLinkPresentation` could reach**
    /// ([[T-1306]]'s open half, closed by [[T-1321]]).
    ///
    /// `GoalContributionResolver` walks `goal.listLinks` **raw** — once for the tasks the goal
    /// counts and once for the "N lists" chip — so a link the store is about to drop moved the
    /// goal's *progress bar*, which is the part of this no inspector-side filter can protect. It
    /// is also what makes it safe for `detachGoalListLink` to stop severing the link's references
    /// before deleting it: the reading that matters no longer depends on the inverse array having
    /// caught up, only on the object's own `isDeleted`.
    ///
    /// Deleted and **not** processed, deliberately — that is the state a refusal leaves behind
    /// between the throw and the next processed change, and the state a detach is in before its
    /// flush.
    @Test func aDeletedLinkIsNotCountedByTheProgressBarEither() throws {
        let store = try makeStore()
        let task = AppTask(title: "Area task")
        task.area = store.area
        store.modelContext.insert(task)
        let link = try #require(try store.modelContext.attachList(.area(store.area), to: store.goal))
        try store.modelContext.save()

        // The link is what the goal's progress is made of, so the assertions below are not
        // measuring a goal that never counted anything.
        #expect(GoalContributionResolver.summary(for: store.goal).totalTasks == 1)
        #expect(GoalContributionResolver.summary(for: store.goal).linkedListCount == 1)

        store.modelContext.delete(link)

        let summary = GoalContributionResolver.summary(for: store.goal)
        #expect(
            summary.totalTasks == 0,
            "a row the store is about to drop is still counted in the goal's progress bar"
        )
        #expect(
            summary.linkedListCount == 0,
            "a row the store is about to drop is still counted by the \"N lists\" chip"
        )
    }

    /// The second reading of the same state, and the one that is not cosmetic ([[T-1306]]).
    ///
    /// `attachList`'s idempotence guard returns any link already pointing at the target. Measured
    /// on Xcode 27 before the fix, straight after a refusal it returned the *refused* link — the
    /// deleted one — so the retry committed nothing, `toggleGoalListLink` answered `true`, and the
    /// store ended with no row at all. `CreateGoalSheet`'s own retry never saw this, because
    /// `saveGoal` runs a real `save()` before the attach is tried again; every other retry path on
    /// both platforms went straight back into the guard.
    @Test func theAttachAfterARefusedOneAttachesRatherThanReturningTheRefusedLink() throws {
        let store = try makeStore()
        try store.modelContext.save()

        #expect(throws: CommitRefused.self) {
            try store.modelContext.attachList(.area(store.area), to: store.goal, commit: Self.refuse)
        }

        let retried = try #require(try store.modelContext.attachList(.area(store.area), to: store.goal))
        #expect(!retried.isDeleted, "the retry handed back the link the refusal deleted")
        #expect(!store.modelContext.hasChanges, "the retry left its attach pending")

        let reader = ModelContext(store.container)
        #expect(
            try reader.fetch(FetchDescriptor<GoalListLink>()).count == 1,
            "the retry reported an attach the store does not hold"
        )
        #expect(GoalLinkPresentation.isAttached(.area(store.area), to: store.goal))
    }

    /// The mirror, `commitDelete` + `rollback()` rather than `commitInsert` + `delete`.
    ///
    /// A refused detach must leave the link in the store and leave nothing pending, and both of
    /// those hold on every toolchain. **The three references are asserted now, and they are the
    /// only reading added — because after [[T-1321]] nothing writes them.**
    ///
    /// Before that, `detachGoalListLink` nulled `goal` / `area` / `project` before deleting, so
    /// what `rollback()` had to undo was an *edit* — the one thing [[T-1296]] measured the two
    /// Xcode majors disagreeing about. On 27 the live reference came back at once (measured
    /// 2026-09-20: `link.goal` and `link.area` both non-`nil`, `isAttached == true`); through 26 an
    /// edit's undo waits for a refetch, and `links(of:)` drops a link with neither an area nor a
    /// project, so the row would have vanished from both goal inspectors under "Nothing was
    /// changed." **That reading could not be taken** — this Mac has one toolchain — so the fix was
    /// chosen to be right by construction rather than by measurement: the detach makes no edit, so
    /// these three hold the values the store holds on any toolchain, for the same reason a variable
    /// nobody assigns keeps its value.
    ///
    /// **`isDeleted` and `isAttached` are still not asserted, and that is still deliberate.**
    /// Whether `rollback()`'s un-delete has reached this materialised object, and whether
    /// `goal.listLinks` has taken the row back after the `processPendingChanges()` that emptied it,
    /// are both framework timing. What *is* asserted is that the two cannot disagree: a row the
    /// array still holds may not be a row the inspector drops. That is the vanishing row itself,
    /// and it is a bound rather than a pin —
    /// `CadenceStartupRecoveryReasonTests` is the shape this follows.
    ///
    /// **[[T-1349]]: the live bound is not the whole of what the user sees, and the construction
    /// argument above is not a proof.** R65 corrects two things [[T-1321]] leaned on. `rollback()`'s
    /// restoration is *documented* — Apple says it cancels unsaved insertions and deletions and
    /// returns modified models to their last committed values — so this is a contract question, not
    /// an undocumented one. And the 26-vs-27 difference is **not** an established Apple change:
    /// zero rollback mentions across the inspected iOS/macOS 26 and 27 release notes, so T-1296's
    /// readings stand as observations of a compatibility difference to contain, not as evidence
    /// either toolchain restores every graph. What that costs T-1321 is the word *proof*: removing
    /// the explicit `nil` writes removes the **application's** edits, but `delete` followed by
    /// `processPendingChanges()` still asks SwiftData to alter relationship state, and a
    /// SwiftData-backed property is not an ordinary variable that changes only where this method
    /// assigns it. "Nothing writes them, so they hold" is a good reason and not a demonstration.
    ///
    /// So the reading below is added, and it is the one that answers *what the user sees* on both
    /// toolchains: the app's own presentation reader, run over a goal fetched afresh. Every render
    /// after any refetch — reopening the inspector, a `@Query` invalidation, the next launch — is
    /// this reading, and it converges under either answer to the live-array question. It is also
    /// strictly more than the row count it sits beside: a count of 1 is satisfied by a link
    /// restored with a `nil` area, which `links(of:)` drops and the inspector therefore does not
    /// draw. **A partial restoration fails here.** The derived "N lists" chip is asserted for the
    /// same reason — it is the second thing the refusal must not have silently changed.
    ///
    /// What is still *not* asserted is `drawn == true` on the live reference. That is exactly the
    /// measurement this Mac cannot take, and pinning one toolchain's answer to it is what turned CI
    /// red in [[T-1279]] and again in [[T-1319]]. It stays in [[T-1336]] with the question narrowed
    /// rather than guessed.
    @Test func arefusedDetachKeepsTheLinkInTheStoreAndLeavesNothingPending() throws {
        let store = try makeStore()
        let link = try #require(try store.modelContext.attachList(.area(store.area), to: store.goal))
        try store.modelContext.save()

        #expect(throws: CommitRefused.self) {
            try store.modelContext.detachGoalListLink(link, commit: Self.refuse)
        }

        #expect(!store.modelContext.hasChanges, "the refused detach left a change for the next save")

        // Construction, not timing: the detach writes none of these three.
        #expect(link.goal != nil, "the refused detach left the link severed from its goal")
        #expect(link.area != nil, "the refused detach left the link pointing at no list")
        #expect(link.project == nil, "an area link acquired a project")

        // The bound. Either reading of the array is allowed; a row present and invisible is not.
        let held = (store.goal.listLinks ?? []).contains { $0.id == link.id }
        let drawn = GoalLinkPresentation.links(of: store.goal).contains { $0.id == link.id }
        #expect(
            held == drawn,
            "the row is in goal.listLinks and dropped by links(of:) — the vanishing row T-1321 is about"
        )

        let reader = ModelContext(store.container)
        #expect(
            try reader.fetch(FetchDescriptor<GoalListLink>()).count == 1,
            "the refusal said nothing was changed and the row is gone"
        )

        // What the user sees, on either toolchain: the app's own reader over a goal read afresh.
        // A row count cannot distinguish a whole link from one restored without its area, and the
        // second is drawn by nothing.
        let refetchedGoal = try #require(
            try reader.fetch(FetchDescriptor<Goal>()).first { $0.id == store.goal.id },
            "the goal itself is gone from a store the refusal did not touch"
        )
        #expect(
            GoalLinkPresentation.links(of: refetchedGoal).map(\.id) == [link.id],
            "the inspector draws no link for a goal the refusal left attached to one"
        )
        #expect(
            GoalLinkPresentation.isAttached(.area(store.area), to: refetchedGoal),
            "the attach sheet's checkmark reads unattached after a refusal that changed nothing"
        )
        #expect(
            GoalContributionResolver.summary(for: refetchedGoal).linkedListCount == 1,
            "the goal's \"N lists\" chip dropped a list the refusal put back"
        )
    }

    /// **The detach makes no edit for `rollback()` to undo, read from the source ([[T-1321]]).**
    ///
    /// This is the assertion the behavioural test above cannot make. The property that makes the
    /// refusal correct on a toolchain nobody here can run is a property of the *construction* — the
    /// three references are never written, so there is nothing for `rollback()` to be late about —
    /// and the only way to pin a construction is to read it. Re-growing `link.goal = nil` fails
    /// here, on 27, where the behavioural difference is invisible.
    ///
    /// Re-assigning them in a `catch` after the throw is the repair [[T-1321]] rejected by name:
    /// it is a fresh pending edit in the app's one `ModelContext`, which is what the `hasChanges`
    /// assertion above exists to forbid. So `nil` may not appear in the body at all.
    @Test func theDetachWritesNothingForARollbackToPutBack() throws {
        let helpers = try CadenceCommitSurfaceScan.scanned("Cadence/Shared/GoalListLinkHelpers.swift")
        let body = try #require(
            CadenceSourceScan.functionBody(named: "detachGoalListLink", in: helpers),
            "detachGoalListLink is no longer a function"
        )

        #expect(!body.contains("= nil"), "the detach assigns again: \(body)")
        #expect(!body.contains("catch"), "the detach grew a catch, which can only hold a pending edit")
        // Non-vacuity: this really is the detach's body, and it still deletes and still commits.
        #expect(body.contains("delete(link)"))
        #expect(body.contains("CadencePendingChangePersistence.commitDelete(in: self, commit: commit)"))
    }

    /// The reverse of `ListDeleteHelpers` cascading `goalLinks` when a list is deleted: detaching
    /// removes the join row and **nothing else**. The list, its tasks and the goal are the user's
    /// real work and outlive the link, exactly as they outlive a deleted goal.
    @Test func detachingOrphansNothingButRemovesTheRow() throws {
        let store = try makeStore()

        let task = AppTask(title: "Area task")
        task.area = store.area
        store.modelContext.insert(task)

        try store.modelContext.attachList(.area(store.area), to: store.goal)
        let link = try #require(GoalLinkPresentation.links(of: store.goal).first)

        try store.modelContext.detachGoalListLink(link)

        #expect(try store.modelContext.fetch(FetchDescriptor<GoalListLink>()).isEmpty)
        #expect(GoalLinkPresentation.links(of: store.goal).isEmpty)
        #expect((store.goal.listLinks ?? []).isEmpty)
        #expect((store.area.goalLinks ?? []).isEmpty)
        // The far side survives.
        #expect(try store.modelContext.fetch(FetchDescriptor<Area>()).count == 1)
        #expect(try store.modelContext.fetch(FetchDescriptor<Goal>()).count == 1)
        #expect(try store.modelContext.fetch(FetchDescriptor<AppTask>()).count == 1)
        #expect(store.area.tasks?.count == 1)
        // And the goal stops counting the list's work.
        #expect(GoalContributionResolver.summary(for: store.goal).totalTasks == 0)
    }

    /// `deleteGoal` already removes a goal's links; this is the same guarantee read from the other
    /// end, because a surviving link is a row whose `goal` is gone and whose `tasks` still resolve.
    @Test func deletingAGoalTakesItsLinksWithIt() throws {
        let store = try makeStore()
        try store.modelContext.attachList(.area(store.area), to: store.goal)

        try store.modelContext.deleteGoal(store.goal)

        #expect(try store.modelContext.fetch(FetchDescriptor<GoalListLink>()).isEmpty)
        #expect(try store.modelContext.fetch(FetchDescriptor<Area>()).count == 1)
    }

    // MARK: - Which links a goal shows

    /// A link pointing at nothing is dropped, because `GoalContributionResolver.linkedListCount`
    /// drops it too — a surviving "Missing List" row would be a contributor the percentage has
    /// never heard of.
    @Test func targetlessLinksAreNotShown() throws {
        let store = try makeStore()

        let broken = GoalListLink(goal: store.goal)
        store.modelContext.insert(broken)
        try store.modelContext.attachList(.area(store.area), to: store.goal)

        #expect(GoalLinkPresentation.links(of: store.goal).count == 1)
        #expect(GoalContributionResolver.summary(for: store.goal).linkedListCount == 1)
    }

    /// `listLinks` is a SwiftData to-many with no defined order, so the sort has to be total:
    /// title alone leaves two lists of the same name swapping places between renders.
    @Test func linksAreOrderedTotally() throws {
        let store = try makeStore()

        let second = Area(name: "documents", context: store.context)
        let third = Area(name: "Admin", context: store.context)
        store.modelContext.insert(second)
        store.modelContext.insert(third)

        try store.modelContext.attachList(.area(store.area), to: store.goal)
        try store.modelContext.attachList(.area(second), to: store.goal)
        try store.modelContext.attachList(.area(third), to: store.goal)

        let titles = GoalLinkPresentation.links(of: store.goal).map(\.title)
        #expect(titles.first == "Admin")
        #expect(titles.count == 3)
        // Case-insensitive equals means the id tie-break decides, so the result must not depend on
        // the order the relationship hands them over — and a stored to-many has no promised order.
        // The previous assertion compared one call to another call, which is a value against itself
        // and could never fail.
        let forward = GoalLinkPresentation.links(of: store.goal).map(\.id)
        store.goal.listLinks = (store.goal.listLinks ?? []).reversed()
        #expect(GoalLinkPresentation.links(of: store.goal).map(\.id) == forward)
    }

    @Test func theContributionLabelCountsOnlyWorkTheGoalCounts() throws {
        let store = try makeStore()

        let open = AppTask(title: "Open")
        open.area = store.area
        let cancelled = AppTask(title: "Cancelled")
        cancelled.area = store.area
        cancelled.status = .cancelled
        store.modelContext.insert(open)
        store.modelContext.insert(cancelled)

        try store.modelContext.attachList(.area(store.area), to: store.goal)
        let link = try #require(GoalLinkPresentation.links(of: store.goal).first)

        #expect(GoalLinkPresentation.contributingTaskCount(for: link) == 1)
        #expect(GoalLinkPresentation.contributionLabel(for: link) == "1 contributing task")
        #expect(GoalLinkPresentation.contributionLabel(taskCount: 0) == "0 contributing tasks")
        #expect(GoalLinkPresentation.contributionLabel(taskCount: 12) == "12 contributing tasks")
        // The row-metric spelling of the same figure, for the trailing slot of a 44pt row.
        #expect(GoalLinkPresentation.contributionMetric(for: link) == "1 task")
        #expect(GoalLinkPresentation.contributionMetric(taskCount: 0) == "0 tasks")
        #expect(GoalLinkPresentation.contributionMetric(taskCount: 12) == "12 tasks")
    }

    // MARK: - Explaining the number

    @Test func theAttributionLineNamesTheLinkedShareOfTheCount() {
        #expect(
            GoalLinkPresentation.attributionLine(
                for: summary(totalTasks: 9, directTaskCount: 2, linkedListCount: 2)
            ) == "7 of 9 counted tasks come from 2 linked lists."
        )
        #expect(
            GoalLinkPresentation.attributionLine(
                for: summary(totalTasks: 4, directTaskCount: 3, linkedListCount: 1)
            ) == "1 of 4 counted tasks come from 1 linked list."
        )
    }

    /// Nothing to explain gets no line — a goal whose counted work is all directly assigned should
    /// not carry a sentence saying zero, and neither should a goal with a link whose list is empty.
    @Test func theAttributionLineIsSilentWhenThereIsNothingToExplain() {
        #expect(GoalLinkPresentation.attributionLine(for: summary(totalTasks: 5, directTaskCount: 5, linkedListCount: 0)) == nil)
        #expect(GoalLinkPresentation.attributionLine(for: summary(totalTasks: 5, directTaskCount: 5, linkedListCount: 2)) == nil)
        #expect(GoalLinkPresentation.attributionLine(for: summary(totalTasks: 0, directTaskCount: 0, linkedListCount: 1)) == nil)
        // A direct count above the total cannot make the sentence claim negative work.
        #expect(GoalLinkPresentation.attributionLine(for: summary(totalTasks: 2, directTaskCount: 5, linkedListCount: 1)) == nil)
    }

    /// An hours goal's bar is logged time, so the linked tasks move the task count and not the
    /// percentage. Saying so is the difference between explaining the number and naming the wrong
    /// cause for it.
    @Test func anHoursGoalSaysWhatItsBarActuallyTracks() {
        let line = GoalLinkPresentation.attributionLine(
            for: summary(progressType: .hours, totalTasks: 6, directTaskCount: 1, linkedListCount: 1)
        )
        #expect(line == "5 of 6 counted tasks come from 1 linked list. Progress tracks logged hours.")
    }

    /// `linkedListCount` recurses sub-goals, so a direction's chip can outnumber the rows in its
    /// own section — and the lists you cannot see are the ones moving a number you cannot explain.
    @Test func inheritedLinksAreNamedRatherThanSilentlyMissing() {
        #expect(GoalLinkPresentation.inheritedListNote(ownLinkCount: 1, totalLinkCount: 1) == nil)
        #expect(GoalLinkPresentation.inheritedListNote(ownLinkCount: 2, totalLinkCount: 1) == nil)
        #expect(GoalLinkPresentation.inheritedListNote(ownLinkCount: 1, totalLinkCount: 2) == "1 more list is attached to a milestone.")
        #expect(GoalLinkPresentation.inheritedListNote(ownLinkCount: 0, totalLinkCount: 3) == "3 more lists are attached to milestones.")
    }

    /// The section's own count and the recursive chip must be able to disagree — which is the whole
    /// reason the note above exists.
    @Test func aMilestonesLinkCountsForItsDirectionWithoutBecomingItsRow() throws {
        let store = try makeStore()
        let milestone = Goal(title: "Milestone", context: store.context)
        milestone.parentGoal = store.goal
        store.modelContext.insert(milestone)

        try store.modelContext.attachList(.area(store.area), to: milestone)

        let summary = GoalContributionResolver.summary(for: store.goal)
        #expect(summary.linkedListCount == 1)
        #expect(GoalLinkPresentation.links(of: store.goal).isEmpty)
        #expect(
            GoalLinkPresentation.inheritedListNote(
                ownLinkCount: GoalLinkPresentation.links(of: store.goal).count,
                totalLinkCount: summary.linkedListCount
            ) == "1 more list is attached to a milestone."
        )
    }

    // MARK: - Candidates

    @Test func candidatesAreGroupedByContextWithAreasBeforeProjects() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let work = Context(name: "Work")
        let home = Context(name: "Home")
        let workArea = Area(name: "Docs", context: work)
        let workProject = Project(name: "Launch", context: work)
        let homeArea = Area(name: "House", context: home)
        let unfiled = Project(name: "Loose Ends")
        for model in [work, home] { modelContext.insert(model) }
        modelContext.insert(workArea)
        modelContext.insert(workProject)
        modelContext.insert(homeArea)
        modelContext.insert(unfiled)

        let groups = GoalLinkPresentation.candidateGroups(
            contexts: [work, home],
            areas: [workArea, homeArea],
            projects: [workProject, unfiled],
            query: ""
        )

        #expect(groups.map(\.title) == ["Work", "Home", CadenceSidebarLists.ungroupedTitle])
        #expect(groups[0].targets.map(\.displayName) == ["Docs", "Launch"])
        #expect(groups[1].targets.map(\.displayName) == ["House"])
        #expect(groups[2].targets.map(\.displayName) == ["Loose Ends"])
        #expect(GoalLinkPresentation.candidateCount(in: groups) == 4)
    }

    @Test func searchFiltersCandidatesAndDropsEmptiedGroups() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let work = Context(name: "Work")
        let home = Context(name: "Home")
        let docs = Area(name: "Documents", context: work)
        let house = Area(name: "House", context: home)
        for model in [work, home] { modelContext.insert(model) }
        modelContext.insert(docs)
        modelContext.insert(house)

        let groups = GoalLinkPresentation.candidateGroups(
            contexts: [work, home],
            areas: [docs, house],
            projects: [],
            query: "  DOC "
        )

        #expect(groups.count == 1)
        #expect(groups[0].targets.map(\.displayName) == ["Documents"])
    }

    /// No status filter, deliberately: progress keeps counting an archived list's tasks, so hiding
    /// it here would leave a contributor that cannot be detached from the picker that manages
    /// contributors.
    @Test func anArchivedListStaysAttachableBecauseItStillContributes() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let work = Context(name: "Work")
        let archived = Project(name: "Old Launch", context: work)
        archived.status = .archived
        modelContext.insert(work)
        modelContext.insert(archived)

        let groups = GoalLinkPresentation.candidateGroups(
            contexts: [work],
            areas: [],
            projects: [archived],
            query: ""
        )

        #expect(GoalLinkPresentation.candidateCount(in: groups) == 1)
    }

    @Test func anUntitledListStillGetsANameInGoalListLinkSurface() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let area = Area(name: "   ")
        let project = Project(name: "")
        modelContext.insert(area)
        modelContext.insert(project)

        #expect(GoalLinkTarget.area(area).displayName == "Untitled Area")
        #expect(GoalLinkTarget.project(project).displayName == "Untitled Project")
    }

    @Test func theCandidateSubtitleUsesTheAppsOwnActiveTaskSpelling() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let area = Area(name: "Docs")
        let task = AppTask(title: "Open")
        task.area = area
        modelContext.insert(area)
        modelContext.insert(task)

        // "1 active task", not the "\(count) active tasks" the attach sheet used to interpolate.
        #expect(GoalLinkTarget.area(area).openTaskLabel == "1 active task")
    }

    // MARK: - Both platforms reach the one path

    /// **The call-site half.** `GoalListLink` is constructed in exactly one place in the app now,
    /// so neither platform can grow its own spelling of "attach a list" — which is what the macOS
    /// sheet's four private `insert(GoalListLink(...))` lines were, and what iOS would otherwise
    /// have had to copy.
    @Test func onlyTheSharedHelperConstructsALink() throws {
        // A plain substring count is wrong here, and finding that out was worth the run: every
        // `modelContext.toggleGoalListLink(` and `detachGoalListLink(` call *contains*
        // `GoalListLink(`, so a `components(separatedBy:)` count made the shared helper's own file
        // report 5 and named all four call sites as offenders. The initializer needs a left word
        // boundary.
        let pattern = "(?<![A-Za-z0-9_])GoalListLink\\("
        var offenders: [String] = []
        for path in try swiftFiles(under: "Cadence") {
            let code = try strippingComments(sourceFile(path))
            let count = code.matchCount(ofPattern: pattern)
            guard count > 0 else { continue }
            offenders.append("\(path):\(count)")
        }
        // **The archive importer constructs one too, and it is an exception rather than a
        // seventh hand-spelling of "attach a list".** What `GoalLinkTarget.makeLink(for:)` exists
        // to make unspellable-wrong is the *choice* between `area` and `project`; the importer
        // makes no choice. It restores rows, in two passes, because a link's goal and list may
        // arrive later in the same archive than the link does: pass one builds every row bare and
        // copies scalars, pass two resolves ids into relationships. `makeLink(for:)` needs a live
        // `Goal` and an already-resolved target, so it is not available at construction time and
        // would not be the right call if it were — a restore that re-derived which list a link
        // pointed at would be authoring, not restoring.
        //
        // So the exemption is the *empty* construction, asserted as such. The importer may write
        // `GoalListLink()` and nothing else; the day it writes `GoalListLink(goal:area:)` it has
        // started spelling the invariant by hand and this goes red.
        #expect(
            offenders.contains("Cadence/Services/CadenceArchiveImportService.swift:1"),
            "the importer no longer constructs a link — delete this exemption: \(offenders)"
        )
        offenders.removeAll { $0 == "Cadence/Services/CadenceArchiveImportService.swift:1" }
        let importer = try strippingComments(sourceFile("Cadence/Services/CadenceArchiveImportService.swift"))
        #expect(
            importer.matchCount(ofPattern: "(?<![A-Za-z0-9_])GoalListLink\\(\\)") == 1,
            "the importer's link construction is no longer the argument-less one"
        )
        // And the relationships really are set in pass two, which is the reason the construction
        // can be empty: without this the assertion above would also pass on an importer that
        // simply lost the goal and the list.
        #expect(importer.contains("model.goal = record.goalID.flatMap { destination.goals[$0] }"))
        #expect(importer.contains("model.area = record.areaID.flatMap { destination.areas[$0] }"))
        #expect(importer.contains("model.project = record.projectID.flatMap { destination.projects[$0] }"))

        #expect(offenders == ["Cadence/Shared/GoalListLinkHelpers.swift:2"])
    }

    /// iOS's detach and macOS's are the same function, and iOS's attach sheet and macOS's are the
    /// same toggle. Exact counts, not "contains": reverting *one* of these call sites has to fail.
    @Test func bothPlatformsCallTheSharedAttachAndDetachPath() throws {
        try expectCallSites(of: "toggleGoalListLink", at: [
            // Declaration.
            "Cadence/Shared/GoalListLinkHelpers.swift": 1,
            "Cadence/iOS/iOSGoalAttachListsSheet.swift": 1,
            "Cadence/macOS/Views/GoalAttachWorkSheet.swift": 1
        ])

        try expectCallSites(of: "detachGoalListLink", at: [
            // Declaration, plus the call inside `toggleGoalListLink`.
            "Cadence/Shared/GoalListLinkHelpers.swift": 2,
            "Cadence/iOS/iOSFeatureDetailViews.swift": 1,
            "Cadence/macOS/Views/GoalsView.swift": 1
        ])

        try expectCallSites(of: "attachList", at: [
            // Declaration, plus the call inside `toggleGoalListLink`.
            "Cadence/Shared/GoalListLinkHelpers.swift": 2,
            // One, not two, since T-536 folded the `.area` / `.project` branches into a single
            // call on the resolved `CadenceTaskComposerSupport.selection(fromToken:)` target.
            // The property this test pins is that both platforms reach the shared path at all;
            // the count fell because two branches became one, not because a caller was lost.
            "Cadence/macOS/Sheets/CreateGoalSheet.swift": 1
        ])

        try expectCallSites(of: "candidateGroups", at: [
            "Cadence/Shared/GoalListLinkHelpers.swift": 1,
            "Cadence/iOS/iOSGoalAttachListsSheet.swift": 1,
            "Cadence/macOS/Views/GoalAttachWorkSheet.swift": 1
        ])
    }

    /// The presentation decisions are read from one place on both platforms — the ordering rule,
    /// the row's task-count label, and the empty section's copy.
    @Test func bothPlatformsReadTheSharedLinkPresentation() throws {
        try expectOccurrences(of: "GoalLinkPresentation.links(", at: [
            "Cadence/iOS/iOSFeatureDetailViews.swift": 1,
            "Cadence/macOS/Views/GoalInspectorView.swift": 1
        ])

        // macOS's row has the width for the sentence; iOS's 44pt row takes the metric. Both come
        // from `contributingTaskCount`, and neither file spells the count itself.
        try expectOccurrences(of: "GoalLinkPresentation.contributionLabel(", at: [
            "Cadence/iOS/iOSFeatureDetailViews.swift": 0,
            "Cadence/macOS/Views/GoalsSupportViews.swift": 1
        ])
        try expectOccurrences(of: "GoalLinkPresentation.contributionMetric(", at: [
            "Cadence/iOS/iOSFeatureDetailViews.swift": 1,
            "Cadence/macOS/Views/GoalsSupportViews.swift": 0
        ])

        try expectOccurrences(of: "GoalLinkPresentation.emptyExplanation", at: [
            "Cadence/iOS/iOSFeatureDetailViews.swift": 1,
            "Cadence/macOS/Views/GoalInspectorView.swift": 1
        ])
    }

    /// The explanation is on the screen, not only in the value type: the iOS goal detail draws the
    /// attribution line under its progress bar and the inherited-links note in its section.
    @Test func theIOSGoalDetailShowsTheLinkedListsSectionAndTheAttribution() throws {
        try expectOccurrences(of: "GoalLinkPresentation.attributionLine(", at: [
            "Cadence/iOS/iOSFeatureDetailViews.swift": 1
        ])
        try expectOccurrences(of: "GoalLinkPresentation.inheritedListNote(", at: [
            "Cadence/iOS/iOSFeatureDetailViews.swift": 1
        ])
        try expectOccurrences(of: "iOSGoalAttachListsSheet(", at: [
            "Cadence/iOS/iOSFeatureDetailViews.swift": 1
        ])
        try expectOccurrences(of: "linkedListsSection", at: [
            // The declaration and the one place the body reads it.
            "Cadence/iOS/iOSFeatureDetailViews.swift": 2
        ])
    }

    // MARK: - The scan itself

    /// The counts above are only worth anything if the scan actually reads files, and a scan that
    /// silently returns nothing passes every zero-count assertion. This is the test that stops them
    /// going vacuous — the exact failure mode that let a `/tmp` against `/private/tmp` path
    /// mismatch look like real regressions while the scan was reading nothing at all.
    @Test func theSourceScanActuallyReachesBothPlatformsSourceInGoalListLinkSurface() throws {
        let files = try swiftFiles(under: "Cadence")

        #expect(files.count > 300, "the source scan found \(files.count) files and cannot be doing its job")
        #expect(files.contains("Cadence/Shared/GoalListLinkHelpers.swift"))
        #expect(files.contains("Cadence/iOS/iOSGoalAttachListsSheet.swift"))
        #expect(files.contains("Cadence/iOS/iOSFeatureDetailViews.swift"))
        #expect(files.contains("Cadence/macOS/Views/GoalAttachWorkSheet.swift"))
        #expect(files.contains("Cadence/macOS/Views/GoalInspectorView.swift"))
        #expect(files.contains("Cadence/macOS/Views/GoalsSupportViews.swift"))
        #expect(files.contains("Cadence/macOS/Views/GoalsView.swift"))
        #expect(files.contains("Cadence/macOS/Sheets/CreateGoalSheet.swift"))

        // And it must be reading *code*, not an empty string: a positive assertion over the same
        // reader the counts above use.
        let sheet = try strippingComments(sourceFile("Cadence/iOS/iOSGoalAttachListsSheet.swift"))
        #expect(sheet.contains("struct iOSGoalAttachListsSheet: View"))
        #expect(!sheet.contains("Attach or detach the areas and projects"))
    }
}

// MARK: - Source-reading helpers

private extension String {
    /// Regex match count, for scans where a bare substring would over-count — `GoalListLink(`
    /// sits inside `toggleGoalListLink(`.
    func matchCount(ofPattern pattern: String) -> Int {
        var count = 0
        var searchRange = startIndex..<endIndex
        while let found = range(of: pattern, options: .regularExpression, range: searchRange) {
            count += 1
            searchRange = found.upperBound..<endIndex
        }
        return count
    }
}


/// Fails unless `name` is called exactly `count` times in each listed file.
///
/// **Exact counts, not "contains".** `CadenceSharedBoardChromeTests` documents why: a mutation run
/// caught a version of that file asserting only that each file mentioned the shared component
/// somewhere, and reverting *one* of four call sites left it green.
private func expectCallSites(
    of name: String,
    at callSites: [String: Int],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    for (path, expected) in callSites {
        let code = try strippingComments(sourceFile(path))
        let actual = code.components(separatedBy: "\(name)(").count - 1
        #expect(
            actual == expected,
            "\(path) calls \(name) \(actual) times, expected \(expected)",
            sourceLocation: sourceLocation
        )
    }
}

/// Fails unless `text` occurs exactly `count` times as live code in each listed file. Unlike
/// `expectCallSites` this does not append `(`, so it can pin a property read too.
private func expectOccurrences(
    of text: String,
    at files: [String: Int],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    for (path, expected) in files {
        let code = try strippingComments(sourceFile(path))
        let actual = code.components(separatedBy: text).count - 1
        #expect(
            actual == expected,
            "\(path) contains \(text) \(actual) times, expected \(expected)",
            sourceLocation: sourceLocation
        )
    }
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// Enumerated by `enumerator(atPath:)` rather than `enumerator(at:)` on purpose: the URL variant
/// yields *absolute* paths, and `#filePath` can name the repo through a symlinked prefix
/// (`/tmp` against `/private/tmp` on an isolated build tree) that `FileManager` resolves and the
/// literal does not.
private func swiftFiles(under relativeDirectory: String) throws -> [String] {
    let directory = repositoryRoot().appendingPathComponent(relativeDirectory)
    guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else {
        return []
    }
    return enumerator.compactMap { element in
        guard let relativePath = element as? String, relativePath.hasSuffix(".swift") else { return nil }
        return "\(relativeDirectory)/\(relativePath)"
    }
}

private func sourceFile(_ relativePath: String) throws -> String {
    try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

/// Blanks out `//` line comments and `/* */` block comments so the assertions above read code
/// rather than prose. Crude on purpose: a `//` inside a string literal is blanked too, which can
/// only ever make these checks *stricter* about what counts as a comment, never looser about live
/// code.
private func strippingComments(_ source: String) throws -> String {
    // T-1269/T-1270: one pass per pattern, in CadenceSourceScan, on the guarded
    // `(?<!:)//` that the slashes in a URL cannot trigger.
    return CadenceSourceScan.strippingComments(source)
}
