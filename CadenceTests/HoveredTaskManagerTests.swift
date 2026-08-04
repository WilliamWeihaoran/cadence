#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// Regression coverage for `HoveredTaskManager`'s rapid hover in/out handling
/// (delayed-clear debounce) and its guards against acting on a task that is no
/// longer the currently-hovered one — the scenarios most likely to leave two
/// rows simultaneously "hovered" or cause repeated regroup thrash.
@Suite(.serialized)
@MainActor
struct HoveredTaskManagerTests {

    @Test func beginHoveringSetsTaskAndSource() {
        let manager = HoveredTaskManager.shared
        manager.clear()
        let a = task(title: "a")

        manager.beginHovering(a, source: .list)

        #expect(manager.hoveredTask?.id == a.id)
        #expect(manager.hoveredSource == .list)
        manager.clear()
    }

    @Test func beginHoveringOnANewRowImmediatelyReplacesThePreviousHoverWithNoOverlap() {
        // Simulates fast mouse movement across adjacent rows: row A's onHover(false)
        // fires just before row B's onHover(true). At no point should both be
        // considered hovered, and B must win even though A's clear is still pending.
        let manager = HoveredTaskManager.shared
        manager.clear()
        let a = task(title: "a")
        let b = task(title: "b")

        manager.beginHovering(a, source: .list)
        manager.endHovering(a) // schedules a delayed clear for a
        manager.beginHovering(b, source: .list) // must cancel a's pending clear

        #expect(manager.hoveredTask?.id == b.id)
        manager.clear()
    }

    @Test func delayedClearOnlyFiresIfNoOtherRowWasHoveredMeanwhile() async {
        let manager = HoveredTaskManager.shared
        manager.clear()
        let a = task(title: "a")

        manager.beginHovering(a, source: .list)
        manager.endHovering(a)

        try? await Task.sleep(nanoseconds: 160_000_000) // > 0.08s debounce window

        #expect(manager.hoveredTask == nil)
    }

    @Test func delayedClearIsCancelledWhenTheSameRowIsReHoveredBeforeItFires() async {
        let manager = HoveredTaskManager.shared
        manager.clear()
        let a = task(title: "a")

        manager.beginHovering(a, source: .list)
        manager.endHovering(a)
        manager.beginHovering(a, source: .list) // pointer briefly re-entered the same row

        try? await Task.sleep(nanoseconds: 160_000_000)

        // The stale clear scheduled before the re-hover must not have fired.
        #expect(manager.hoveredTask?.id == a.id)
        manager.clear()
    }

    @Test func endHoveringIgnoresATaskThatIsNoLongerTheHoveredOne() {
        // Guards against a kanban card whose row was reused/moved calling endHovering
        // for a task that has since been superseded by a different hover.
        let manager = HoveredTaskManager.shared
        manager.clear()
        let a = task(title: "a")
        let b = task(title: "b")

        manager.beginHovering(b, source: .kanban)
        manager.endHovering(a) // stale reference to a task that isn't hovered anymore

        #expect(manager.hoveredTask?.id == b.id)
        manager.clear()
    }

    @Test func beginHoveringDateRequiresTheDateTaskToMatchTheHoveredTask() {
        let manager = HoveredTaskManager.shared
        manager.clear()
        let a = task(title: "a")
        let b = task(title: "b")

        manager.beginHovering(a, source: .list)
        manager.beginHoveringDate(.doDate, for: b) // b isn't the hovered task

        #expect(manager.hoveredDateKind == nil)
        manager.clear()
    }

    @Test func endHoveringDateIgnoresATaskThatIsNoLongerHovered() {
        let manager = HoveredTaskManager.shared
        manager.clear()
        let a = task(title: "a")

        manager.beginHovering(a, source: .list)
        manager.beginHoveringDate(.dueDate, for: a)
        manager.endHoveringDate(for: task(title: "unrelated"))

        #expect(manager.hoveredDateKind == .dueDate)
        manager.clear()
    }

    @Test func beginHoveringWhileTaskCreationSheetIsPresentedClearsInsteadOfHovering() {
        let manager = HoveredTaskManager.shared
        manager.clear()
        let a = task(title: "a")
        manager.beginHovering(a, source: .list)

        TaskCreationManager.shared.isPresented = true
        defer { TaskCreationManager.shared.isPresented = false }

        manager.beginHovering(task(title: "b"), source: .list)

        #expect(manager.hoveredTask == nil)
    }

    @Test func clearCancelsAnyPendingDelayedClear() async {
        let manager = HoveredTaskManager.shared
        manager.clear()
        let a = task(title: "a")

        manager.beginHovering(a, source: .list)
        manager.endHovering(a)
        manager.clear()
        manager.beginHovering(a, source: .list)

        try? await Task.sleep(nanoseconds: 160_000_000)

        // If the old work item wasn't cancelled it would incorrectly clear
        // the fresh hover started right after `clear()`.
        #expect(manager.hoveredTask?.id == a.id)
        manager.clear()
    }

    // MARK: - Helpers

    private func task(title: String) -> AppTask {
        AppTask(title: title)
    }
}
#endif
