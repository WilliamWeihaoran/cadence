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

        TaskSurfaceFreezeCoordinator.capture(
            frozenOrder: &frozenOrder,
            primarySnapshot: &primary,
            secondarySnapshot: &secondary,
            naturalTasks: [b],
            sourcePrimarySnapshot: [],
            sourceSecondarySnapshot: []
        )

        // Capture must not clobber an order snapshot that was already taken this hover.
        #expect(frozenOrder?.map(\.title) == ["a"])
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

        TaskSurfaceFreezeCoordinator.capture(
            frozenOrder: &frozenOrder,
            primarySnapshot: &primary,
            secondarySnapshot: &secondary,
            naturalTasks: [a],
            sourcePrimarySnapshot: [],
            sourceSecondarySnapshot: []
        )

        #expect(frozenOrder != nil)
        #expect(primary == nil)
    }

    @Test func captureStoresANonEmptyPrimarySnapshotOnlyOnce() {
        let a = task(title: "a", order: 0)
        let snapshotAtHoverStart = [FrozenTaskGroupSnapshot(id: "g1", title: "G1", accent: .blue, taskIDs: [a.id])]
        var frozenOrder: [AppTask]? = nil
        var primary: [FrozenTaskGroupSnapshot]? = nil
        var secondary: [Never]? = nil

        TaskSurfaceFreezeCoordinator.capture(
            frozenOrder: &frozenOrder,
            primarySnapshot: &primary,
            secondarySnapshot: &secondary,
            naturalTasks: [a],
            sourcePrimarySnapshot: snapshotAtHoverStart,
            sourceSecondarySnapshot: []
        )
        #expect(primary?.first?.id == "g1")

        // A later capture call (e.g. re-hovering the same row) with a different
        // "current" snapshot must not replace the one taken at hover start.
        let laterSnapshot = [FrozenTaskGroupSnapshot(id: "g2", title: "G2", accent: .red, taskIDs: [a.id])]
        TaskSurfaceFreezeCoordinator.capture(
            frozenOrder: &frozenOrder,
            primarySnapshot: &primary,
            secondarySnapshot: &secondary,
            naturalTasks: [a],
            sourcePrimarySnapshot: laterSnapshot,
            sourceSecondarySnapshot: []
        )
        #expect(primary?.first?.id == "g1")
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

    // MARK: - Helpers

    private func task(title: String, order: Int) -> AppTask {
        let task = AppTask(title: title)
        task.order = order
        return task
    }
}
#endif
