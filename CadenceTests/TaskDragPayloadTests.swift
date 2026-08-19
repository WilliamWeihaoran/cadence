import Foundation
import Testing
@testable import Cadence

/// The `listTask:` / `taskBundle:` drag wire format.
///
/// `TaskDragPayload` was unified from two byte-identical per-platform copies precisely because a
/// divergence in these strings would make a platform's drags silently stop matching, with nothing
/// to catch it — and then it shipped with no tests at all, while two macOS surfaces hand-spelled
/// both halves of it (including `dropFirst(9)`, the prefix's length as a literal). These pin the
/// three documented branches of `taskID(from:)`, the strict `listTaskID(from:)` the reorder
/// surfaces need, and the round trips.
struct TaskDragPayloadTests {

    // MARK: - Round trips

    @Test func aTaskPayloadRoundTripsThroughItsOwnPrefix() {
        let id = UUID()
        let payload = TaskDragPayload.string(for: id)

        #expect(payload == "listTask:\(id.uuidString)")
        #expect(TaskDragPayload.taskID(from: payload) == id)
        #expect(TaskDragPayload.listTaskID(from: payload) == id)
    }

    @Test func aBundlePayloadRoundTripsThroughItsOwnPrefix() {
        let id = UUID()
        let payload = TaskDragPayload.bundleString(for: id)

        #expect(payload == "taskBundle:\(id.uuidString)")
        #expect(TaskDragPayload.bundleID(from: payload) == id)
    }

    // MARK: - The three branches of `taskID(from:)`

    /// Branch one: a `listTask:`-prefixed payload yields its task id.
    @Test func taskIDReadsAPrefixedPayload() {
        let id = UUID()

        #expect(TaskDragPayload.taskID(from: "listTask:\(id.uuidString)") == id)
    }

    /// Branch two: a bundle payload yields `nil` rather than the bundle's own id. Asking for a
    /// task id and being handed a bundle id would be worse than being handed nothing.
    @Test func taskIDRefusesToReadABundlePayloadAsATask() {
        let bundleID = UUID()

        #expect(TaskDragPayload.taskID(from: TaskDragPayload.bundleString(for: bundleID)) == nil)
        #expect(TaskDragPayload.bundleID(from: TaskDragPayload.bundleString(for: bundleID)) == bundleID)
    }

    /// Branch three: a bare UUID is accepted, because the kanban card
    /// (`KanbanColumnSupportViews`) and the month-grid task chip (`CalendarPageMonthSupportViews`)
    /// both drag `.draggable(task.id.uuidString)` — no prefix at all.
    ///
    /// Not `TasksPanel`, which an earlier draft of this comment named: its rows are prefixed, via
    /// `TasksPanelSupport.taskDragPayload(for:)` → `string(for:)`.
    @Test func taskIDAcceptsABareUUID() {
        let id = UUID()

        #expect(TaskDragPayload.taskID(from: id.uuidString) == id)
    }

    @Test func aMalformedPayloadIsRejectedOnEveryBranch() {
        #expect(TaskDragPayload.taskID(from: "listTask:not-a-uuid") == nil)
        #expect(TaskDragPayload.taskID(from: "not-a-uuid") == nil)
        #expect(TaskDragPayload.listTaskID(from: "listTask:not-a-uuid") == nil)
        #expect(TaskDragPayload.bundleID(from: "taskBundle:not-a-uuid") == nil)
    }

    // MARK: - The strict decode

    /// `listTaskID(from:)` exists because the two task-list reorder surfaces must *not* accept a
    /// bare-UUID payload: a kanban card or month-grid chip dragged onto a task row is not a reorder.
    /// This is the one behaviour that separates it from `taskID(from:)`.
    @Test func listTaskIDRequiresThePrefixThatTaskIDWouldForgive() {
        let id = UUID()

        #expect(TaskDragPayload.taskID(from: id.uuidString) == id)
        #expect(TaskDragPayload.listTaskID(from: id.uuidString) == nil)
    }

    /// Every other drag context's payload, refused. These are the prefixes listed in `CLAUDE.md`.
    @Test func listTaskIDRejectsEveryForeignContext() {
        let id = UUID().uuidString
        let foreign = [
            "taskBundle:\(id)",
            "area:\(id)",
            "project:\(id)",
            "newTask:\(id)",
            "allDayEvent:\(id)",
            ""
        ]

        for payload in foreign {
            #expect(TaskDragPayload.listTaskID(from: payload) == nil)
        }
    }
}
