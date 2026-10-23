#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

/// One task-block drag, held where **every** day column of a page can see it ([[T-5350]]).
///
/// Each `TimelineDayCanvas` used to own its own `activeDragTaskID` and `dragYOffset`. `.onDrag`
/// set the id on the *source* column and only the column that performed the drop cleared its own
/// copy, so a Week-view drag onto another day left the source holding the id: drag-to-create there
/// did nothing, its next drop previewed the old task and landed at a minute measured from the old
/// task's start, and the receiving column — which had no id — placed the block's top at the
/// pointer instead of where the block had been grabbed. One session per page, ended by whichever
/// column performs the drop, is the fix; a canvas outside a page that supplies one keeps a session
/// of its own, which is the old single-column behaviour.
@Observable
final class TimelineTaskDragSession {
    /// The block being dragged, from `.onDrag` until a canvas performs the drop.
    private(set) var taskID: UUID?
    /// Pointer Y less the block's top Y, fixed the first time the drag enters a canvas — which is
    /// the source column, at the grab — and reused by every column it enters after that.
    private(set) var grabOffsetY: CGFloat?

    func begin(taskID: UUID) {
        self.taskID = taskID
        grabOffsetY = nil
    }

    func end() {
        taskID = nil
        grabOffsetY = nil
    }

    /// The offset a canvas the drag has just entered subtracts from the pointer. `taskStartMin`
    /// is the dragged task's current start, or `nil` when the canvas cannot find the task.
    func enteredOffset(pointerY: CGFloat, taskStartMin: Int?, metrics: TimelineMetrics) -> CGFloat {
        guard taskID != nil else { return 0 }
        if let grabOffsetY { return grabOffsetY }
        guard let taskStartMin else { return 0 }
        let offset = pointerY - metrics.yOffset(for: taskStartMin)
        grabOffsetY = offset
        return offset
    }

    /// The offset in force for the drag now over a canvas: zero for anything that is not this
    /// session's block (a row dragged in from a task list, an all-day chip).
    var currentOffset: CGFloat {
        taskID == nil ? 0 : (grabOffsetY ?? 0)
    }

    /// The payload a canvas resolved names a different task: this session is the leftover of a
    /// block drag released outside every canvas, and must not shape this drop.
    func reconcile(payloadTaskID: UUID) {
        if let taskID, taskID != payloadTaskID {
            end()
        }
    }

    /// Whether a block drag that began on one of `taskIDs` is still live — the one case in which
    /// a canvas refuses drag-to-create. Scoped to the canvas's own blocks so a drag between other
    /// columns never disables this one.
    func isDragging(anyOf taskIDs: [UUID]) -> Bool {
        guard let taskID else { return false }
        return taskIDs.contains(taskID)
    }

    /// The `activeDragTaskID` binding the block and gesture layers already speak.
    var taskIDBinding: Binding<UUID?> {
        Binding(
            get: { self.taskID },
            set: { newValue in
                if let newValue {
                    if newValue != self.taskID { self.begin(taskID: newValue) }
                } else {
                    self.end()
                }
            }
        )
    }
}

extension EnvironmentValues {
    /// The page-wide drag session the Calendar timeline's day columns share ([[T-5350]]).
    @Entry var timelineTaskDragSession: TimelineTaskDragSession? = nil
}

struct TimelineDropDelegate: DropDelegate {
    let metrics: TimelineMetrics
    let allTasks: [AppTask]
    let onDropTaskAtMinute: (AppTask, Int) -> Void
    let onDropAllDayEventAtMinute: ((CalendarAllDayEventDropPayload, Int) -> Void)?

    @Binding var isTargeted: Bool
    @Binding var previewTaskID: UUID?
    @Binding var previewStartMin: Int?
    let dragSession: TimelineTaskDragSession
    @Binding var selectedTaskID: UUID?

    func validateDrop(info: DropInfo) -> Bool {
        !info.itemProviders(for: [UTType.text]).isEmpty
    }

    func dropEntered(info: DropInfo) {
        isTargeted = true
        let task = dragSession.taskID.flatMap { taskID in allTasks.first(where: { $0.id == taskID }) }
        _ = dragSession.enteredOffset(
            pointerY: info.location.y,
            taskStartMin: task?.scheduledStartMin,
            metrics: metrics
        )
        updatePreview(with: info)
        resolveTaskID(from: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard isTargeted else { return DropProposal(operation: .cancel) }
        updatePreview(with: info)
        resolveTaskID(from: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
        previewTaskID = nil
        previewStartMin = nil
        // The session is deliberately kept: leaving one day column for the next is the middle of
        // a cross-day drag, not its end ([[T-5350]]).
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        let startMin = previewStartMin ?? metrics.snappedMinute(fromY: info.location.y - dragSession.currentOffset)

        previewTaskID = nil
        previewStartMin = nil
        // Ends the drag for every column sharing the session, the source included ([[T-5350]]).
        dragSession.end()
        selectedTaskID = nil

        guard let provider = info.itemProviders(for: [UTType.text]).first else {
            return false
        }

        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let payload = object as? NSString else { return }
            let payloadString = payload as String
            if let eventPayload = CalendarEventDragPayload.allDayEventPayload(from: payloadString) {
                Task { @MainActor in
                    onDropAllDayEventAtMinute?(eventPayload, startMin)
                }
            } else if let uuid = taskID(from: payloadString) {
                Task { @MainActor in
                    guard let task = allTasks.first(where: { $0.id == uuid }) else { return }
                    onDropTaskAtMinute(task, startMin)
                }
            }
        }
        return true
    }

    private func updatePreview(with info: DropInfo) {
        previewStartMin = metrics.snappedMinute(fromY: info.location.y - dragSession.currentOffset)
    }

    private func resolveTaskID(from info: DropInfo) {
        guard previewTaskID == nil,
              let provider = info.itemProviders(for: [UTType.text]).first else { return }

        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let payload = object as? NSString,
                  let uuid = taskID(from: payload as String) else { return }

            Task { @MainActor in
                guard isTargeted else { return }
                dragSession.reconcile(payloadTaskID: uuid)
                previewTaskID = uuid
            }
        }
    }

    nonisolated private func taskID(from payload: String) -> UUID? {
        TaskDragPayload.taskID(from: payload)
    }
}
#endif
