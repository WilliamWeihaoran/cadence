#if os(macOS)
import Foundation
import SwiftUI
import Testing
@testable import Cadence

@MainActor
struct TaskSurfaceFreezeSupportTests {

    // MARK: - applyFrozenTaskOrder

    @Test func applyFrozenTaskOrderReturnsLiveOrderWhenNothingIsFrozen() {
        let a = task(title: "a", order: 0)
        let b = task(title: "b", order: 1)

        let result = applyFrozenTaskOrder([a, b], frozen: nil)

        #expect(result.map(\.title) == ["a", "b"])
    }

    @Test func applyFrozenTaskOrderKeepsCapturedRowOrderAheadOfNewArrivals() {
        let a = task(title: "a", order: 0)
        let b = task(title: "b", order: 1)
        let c = task(title: "c", order: 2)

        // Captured while hovering, back when only b/a were visible (in that order).
        let frozen = [b, a]
        // The live/natural order now also includes a brand-new task c.
        let live = [a, b, c]

        let result = applyFrozenTaskOrder(live, frozen: frozen)

        // Previously-visible rows keep their captured relative order; new rows are appended.
        #expect(result.map(\.title) == ["b", "a", "c"])
    }

    @Test func applyFrozenTaskOrderDropsTasksThatBecameDoneWhileFrozen() {
        let a = task(title: "a", order: 0)
        let b = task(title: "b", order: 1)
        b.status = .done

        let result = applyFrozenTaskOrder([a], frozen: [a, b])

        #expect(result.map(\.title) == ["a"])
    }

    /// T-342. The done case above has been pinned since the freeze was written; this is its other
    /// half. `applyFrozenTaskOrder` filtered on `!$0.isDone`, and a cancelled task is not `isDone`,
    /// so cancelling a row while a surface was frozen left it pinned at the head of an *active*
    /// list until the freeze released — while completing the row beside it removed it at once.
    @Test func applyFrozenTaskOrderDropsTasksThatBecameCancelledWhileFrozen() {
        let a = task(title: "a", order: 0)
        let b = task(title: "b", order: 1)
        b.status = .cancelled

        let result = applyFrozenTaskOrder([a], frozen: [a, b])

        #expect(result.map(\.title) == ["a"])
    }

    /// Says the rule rather than two of its cases: whatever `CadenceTaskQuerySupport.isFinishedTask`
    /// calls finished leaves the frozen order, and whatever it calls open stays. Adding a fifth
    /// `TaskStatus` cannot leave this test pinning only the statuses that existed when it was
    /// written.
    @Test func theFrozenOrderKeepsExactlyTheStatusesTheSharedPredicateCallsOpen() {
        for status in TaskStatus.allCases {
            let held = task(title: "held", order: 0)
            held.status = status

            let result = applyFrozenTaskOrder([], frozen: [held])
            let isFinished = CadenceTaskQuerySupport.isFinishedTask(held)

            #expect(
                result.isEmpty == isFinished,
                "\(status) is \(isFinished ? "finished" : "open") but the freeze \(result.isEmpty ? "dropped" : "kept") it"
            )
        }
        // Non-vacuity: the loop must have seen both answers, not four of one.
        #expect(TaskStatus.allCases.contains(.done))
        #expect(TaskStatus.allCases.contains(.cancelled))
        #expect(TaskStatus.allCases.contains(.todo))
    }

    @Test func applyFrozenTaskOrderDoesNotDuplicateATaskPresentInBothLists() {
        let a = task(title: "a", order: 0)
        let b = task(title: "b", order: 1)

        let result = applyFrozenTaskOrder([a, b], frozen: [a])

        #expect(result.map(\.title) == ["a", "b"])
        #expect(result.count == 2)
    }

    // MARK: - resolveFrozenTaskGroups (list-group snapshot path)

    @Test func resolveFrozenTaskGroupsReturnsNilWhenNoSnapshotIsFrozen() {
        let a = task(title: "a", order: 0)
        #expect(resolveFrozenTaskGroups(nil, from: [a]) == nil)
    }

    @Test func resolveFrozenTaskGroupsRehydratesTaskIDsAgainstCurrentTasks() {
        let a = task(title: "a", order: 0)
        let b = task(title: "b", order: 1)
        let snapshot = [
            FrozenTaskGroupSnapshot(id: "g1", title: "Group 1", accent: .blue, taskIDs: [a.id, b.id])
        ]

        let resolved = resolveFrozenTaskGroups(snapshot, from: [a, b])

        #expect(resolved?.count == 1)
        #expect(resolved?.first?.tasks.map(\.title) == ["a", "b"])
    }

    @Test func resolveFrozenTaskGroupsDropsGroupsThatBecomeEmptyAfterFilteringDoneTasks() {
        let a = task(title: "a", order: 0)
        a.status = .done
        let snapshot = [
            FrozenTaskGroupSnapshot(id: "g1", title: "Group 1", accent: .blue, taskIDs: [a.id])
        ]

        let resolved = resolveFrozenTaskGroups(snapshot, from: [a])

        #expect(resolved?.isEmpty == true)
    }

    /// The group resolver's half of T-342. A frozen group whose only task was cancelled used to
    /// survive its own `isEmpty` check and keep rendering an empty-in-spirit section.
    @Test func resolveFrozenTaskGroupsDropsGroupsHoldingOnlyCancelledTasks() {
        let a = task(title: "a", order: 0)
        a.status = .cancelled
        let snapshot = [
            FrozenTaskGroupSnapshot(id: "g1", title: "Group 1", accent: Theme.blue, taskIDs: [a.id])
        ]

        let resolved = resolveFrozenTaskGroups(snapshot, from: [a])

        #expect(resolved?.isEmpty == true)
    }

    /// Done and cancelled, side by side in one group, must both go — the asymmetry T-342 reported
    /// is only visible when the two are compared in the same call.
    @Test func resolveFrozenTaskGroupsTreatsDoneAndCancelledAlike() {
        let finishedDone = task(title: "done", order: 0)
        finishedDone.status = .done
        let finishedCancelled = task(title: "cancelled", order: 1)
        finishedCancelled.status = .cancelled
        let open = task(title: "open", order: 2)
        let all = [finishedDone, finishedCancelled, open]
        let snapshot = [
            FrozenTaskGroupSnapshot(id: "g1", title: "Group 1", accent: Theme.blue, taskIDs: all.map(\.id))
        ]

        let resolved = resolveFrozenTaskGroups(snapshot, from: all)

        #expect(resolved?.first?.tasks.map(\.title) == ["open"])
    }

    @Test func resolveFrozenTaskGroupsSkipsTaskIDsThatNoLongerExist() {
        let a = task(title: "a", order: 0)
        let missingID = UUID()
        let snapshot = [
            FrozenTaskGroupSnapshot(id: "g1", title: "Group 1", accent: .blue, taskIDs: [a.id, missingID])
        ]

        let resolved = resolveFrozenTaskGroups(snapshot, from: [a])

        #expect(resolved?.first?.tasks.map(\.id) == [a.id])
    }

    // MARK: - TaskSurfaceFreezeCoordinator capture/release contract

    @Test func captureIsANoOpOnceOrderIsAlreadyFrozen() {
        let a = task(title: "a", order: 0)
        let b = task(title: "b", order: 1)
        var frozenOrder: [AppTask]? = [a]
        var primary: [FrozenTaskGroupSnapshot]? = nil
        var secondary: [Never]? = nil

        let didCapture = TaskSurfaceFreezeCoordinator.capture(
            frozenOrder: &frozenOrder,
            primarySnapshot: &primary,
            secondarySnapshot: &secondary,
            naturalTasks: [b],
            sourcePrimarySnapshot: [],
            sourceSecondarySnapshot: []
        )

        // Capture must not clobber an order snapshot that was already taken this hover.
        #expect(frozenOrder?.map(\.title) == ["a"])
        // The return value is what the observers guard on: reporting `true` here would write the
        // bindings back on every row boundary the pointer crosses, which is the rebuild storm the
        // signal exists to prevent.
        #expect(didCapture == false)
    }

    @Test func captureSkipsAnEmptyPrimarySnapshotSoGroupBoundariesStayLive() {
        // This is the exact contract flat/date/priority grouped surfaces rely on:
        // passing an empty snapshot must leave primarySnapshot nil (never frozen),
        // so the section tree keeps recomputing live instead of jittering between
        // a stale frozen tree and the real one.
        let a = task(title: "a", order: 0)
        var frozenOrder: [AppTask]? = nil
        var primary: [FrozenTaskGroupSnapshot]? = nil
        var secondary: [Never]? = nil

        let didCapture = TaskSurfaceFreezeCoordinator.capture(
            frozenOrder: &frozenOrder,
            primarySnapshot: &primary,
            secondarySnapshot: &secondary,
            naturalTasks: [a],
            sourcePrimarySnapshot: [],
            sourceSecondarySnapshot: []
        )

        #expect(frozenOrder != nil)
        #expect(primary == nil)
        // Order was captured even though the snapshot was skipped, so the write-back must happen —
        // reporting `false` here would leave the surface unfrozen and rows re-sorting under the
        // pointer.
        #expect(didCapture == true)
    }

    @Test func captureStoresANonEmptyPrimarySnapshotOnlyOnce() {
        let a = task(title: "a", order: 0)
        let snapshotAtHoverStart = [FrozenTaskGroupSnapshot(id: "g1", title: "G1", accent: .blue, taskIDs: [a.id])]
        var frozenOrder: [AppTask]? = nil
        var primary: [FrozenTaskGroupSnapshot]? = nil
        var secondary: [Never]? = nil

        let firstCapture = TaskSurfaceFreezeCoordinator.capture(
            frozenOrder: &frozenOrder,
            primarySnapshot: &primary,
            secondarySnapshot: &secondary,
            naturalTasks: [a],
            sourcePrimarySnapshot: snapshotAtHoverStart,
            sourceSecondarySnapshot: []
        )
        #expect(primary?.first?.id == "g1")
        #expect(firstCapture == true)

        // A later capture call (e.g. re-hovering the same row) with a different
        // "current" snapshot must not replace the one taken at hover start.
        let laterSnapshot = [FrozenTaskGroupSnapshot(id: "g2", title: "G2", accent: .red, taskIDs: [a.id])]
        let secondCapture = TaskSurfaceFreezeCoordinator.capture(
            frozenOrder: &frozenOrder,
            primarySnapshot: &primary,
            secondarySnapshot: &secondary,
            naturalTasks: [a],
            sourcePrimarySnapshot: laterSnapshot,
            sourceSecondarySnapshot: []
        )
        #expect(primary?.first?.id == "g1")
        #expect(secondCapture == false)
    }

    @Test func releaseClearsAllCapturedSnapshots() {
        let a = task(title: "a", order: 0)
        var frozenOrder: [AppTask]? = [a]
        var primary: [FrozenTaskGroupSnapshot]? = [FrozenTaskGroupSnapshot(id: "g1", title: "G1", accent: .blue, taskIDs: [a.id])]
        var secondary: [Never]? = nil

        TaskSurfaceFreezeCoordinator.release(
            frozenOrder: &frozenOrder,
            primarySnapshot: &primary,
            secondarySnapshot: &secondary
        )

        #expect(frozenOrder == nil)
        #expect(primary == nil)
    }

    // MARK: - TaskSurfaceFreezeState convenience wrapper

    @Test func freezeStateCaptureThenReleaseRoundTrips() {
        let a = task(title: "a", order: 0)
        var state = TaskSurfaceFreezeState<FrozenTaskGroupSnapshot, Never>(
            frozenOrder: nil,
            primarySnapshot: nil,
            secondarySnapshot: nil
        )

        state.captureIfNeeded(naturalTasks: [a], sourcePrimarySnapshot: [], sourceSecondarySnapshot: [])
        #expect(state.frozenOrder != nil)
        #expect(state.primarySnapshot == nil)

        state.release()
        #expect(state.frozenOrder == nil)
        #expect(state.primarySnapshot == nil)
    }

    // MARK: - The freeze source must be the rendered list (Today's rollover flicker)

    /// **The reported flicker, as a value.** *"while i hover over different sections of tasks, some
    /// sections just glitch in and out … i think it's the tasks that are being rolled over that are
    /// appearing and disappearing."*
    ///
    /// macOS Today draws `todayGroupedTaskItems`, which **withholds** the tasks the rollover banner
    /// is offering to roll; the hover-freeze observer was handed `todayEligibleTasks`, which
    /// **includes** them. This is what that pairing does, and it is not a fault in the freeze:
    /// `applyFrozenTaskOrder` holds a frozen row that has left the live list on purpose (T-342), so
    /// a snapshot of the wider array is an instruction to put every withheld row back.
    ///
    /// Asserted over the two named derivations rather than over the panel, because it is a claim
    /// about *them*: `todayEligibleTasks` is not a safe freeze source for this page and cannot
    /// become one. `todaysHoverFreezeIsHandedTheRowsThePageDraws` below pins which one the panel
    /// actually passes.
    @Test func freezingTodaysWiderArrayPutsTheWithheldRolloverRowsBackOnThePage() {
        let todayKey = "2026-09-05"
        let pastDo = task(title: "yesterday's plan", order: 0)
        pastDo.scheduledDate = "2026-09-04"
        let dueToday = task(title: "due today", order: 1)
        dueToday.dueDate = todayKey

        let derived = TasksPanelDerivedState(allTasks: [pastDo, dueToday], todayKey: todayKey)

        // The banner is up, so the page is deliberately one row short.
        #expect(derived.overdoTasks.map(\.id) == [pastDo.id])
        let drawn = derived.todayGroupedTaskItems(showRolloverNotice: true)
        #expect(drawn.map(\.id) == [dueToday.id])
        // ...and the wider array the observer used to be handed is not.
        #expect(Set(derived.todayEligibleTasks.map(\.id)) == Set([pastDo.id, dueToday.id]))

        let whileHovering = applyFrozenTaskOrder(drawn, frozen: derived.todayEligibleTasks)
        #expect(
            whileHovering.map(\.id) == [pastDo.id, dueToday.id],
            "a freeze taken from `todayEligibleTasks` reinstates the withheld row — this is the flicker"
        )

        // Freezing what the page draws is inert, which is what a freeze is supposed to be.
        let frozenOnTheDrawnRows = applyFrozenTaskOrder(drawn, frozen: drawn)
        #expect(frozenOnTheDrawnRows.map(\.id) == drawn.map(\.id))
    }

    /// The call site, pinned: `hoverFreezeObserver` must be handed the same expression
    /// `todayGroupSections` draws, and both now read it from `naturalTodayRows`.
    ///
    /// A source scan because the panel is a SwiftUI view and the wiring is a private method — the
    /// bug was never in a function a test could call, it was in *which* function was called. Scoped
    /// to the two declaration bodies rather than the file, so an unrelated `todayEligibleTasks`
    /// elsewhere in `TasksPanel` cannot answer it.
    @Test func todaysHoverFreezeIsHandedTheRowsThePageDraws() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TasksPanel.swift")
        let code = CadenceSourceScan.strippingComments(source)
        #expect(code != source, "self-check: the comment stripper ran")

        let observer = try #require(
            CadenceSourceScan.declarationBody("private func hoverFreezeObserver(", in: code)
        )
        let sections = try #require(
            CadenceSourceScan.declarationBody("private func todayGroupSections(", in: code)
        )
        let rows = try #require(
            CadenceSourceScan.declarationBody("private func naturalTodayRows(", in: code)
        )

        #expect(observer.contains("naturalTodayRows("), "the freeze must snapshot the rendered rows")
        #expect(sections.contains("naturalTodayRows("), "and the rows must come from the same call")
        #expect(
            !observer.contains("todayEligibleTasks"),
            "`todayEligibleTasks` includes the rows the rollover banner withholds"
        )
        // Non-vacuity, and the other half of the pairing: the one derivation both halves share is
        // the withholding one.
        #expect(rows.contains("todayGroupedTaskItems(showRolloverNotice:"))
    }

    // MARK: - Helpers

    private func task(title: String, order: Int) -> AppTask {
        let task = AppTask(title: title)
        task.order = order
        return task
    }
}
#endif
