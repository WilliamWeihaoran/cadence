#if os(macOS)
import SwiftUI
import SwiftData

enum TimelineTaskBlockInteractionSupport {
    static func timeRangeLabel(for task: AppTask) -> String {
        TimeFormatters.timeRange(
            startMin: task.scheduledStartMin,
            endMin: task.scheduledStartMin + task.timelineDurationMinutes
        )
    }

    static func frame(
        task: AppTask,
        column: Int,
        totalColumns: Int,
        totalWidth: CGFloat,
        metrics: TimelineMetrics,
        style: TimelineBlockStyle
    ) -> TimelineBlockFrame {
        computeTimelineBlockFrame(
            startMinute: task.scheduledStartMin,
            durationMinutes: task.timelineDurationMinutes,
            column: column,
            totalColumns: totalColumns,
            totalWidth: totalWidth,
            metrics: metrics,
            style: style
        )
    }

    static func beginHover(
        task: AppTask,
        selectedTaskID: Binding<UUID?>,
        activeDragTaskID: Binding<UUID?>,
        hoveredTaskManager: HoveredTaskManager,
        hoveredEditableManager: HoveredEditableManager,
        deleteConfirmationManager: DeleteConfirmationManager,
        modelContext: ModelContext,
        onSelect: @escaping () -> Void
    ) {
        hoveredTaskManager.beginHovering(task, source: .timeline)
        hoveredEditableManager.beginHovering(id: "timeline-task-\(task.id.uuidString)") {
            onSelect()
            activeDragTaskID.wrappedValue = nil
            selectedTaskID.wrappedValue = task.id
        } onDelete: {
            deleteConfirmationManager.presentTaskDelete(task, in: modelContext) {
                if hoveredTaskManager.hoveredTask?.id == task.id {
                    hoveredTaskManager.hoveredTask = nil
                }
                if selectedTaskID.wrappedValue == task.id {
                    selectedTaskID.wrappedValue = nil
                }
                if activeDragTaskID.wrappedValue == task.id {
                    activeDragTaskID.wrappedValue = nil
                }
                hoveredEditableManager.endHovering(id: "timeline-task-\(task.id.uuidString)")
            }
        }
    }

    static func endHover(task: AppTask, hoveredTaskManager: HoveredTaskManager, hoveredEditableManager: HoveredEditableManager) {
        hoveredTaskManager.endHovering(task)
        hoveredEditableManager.endHovering(id: "timeline-task-\(task.id.uuidString)")
    }

    /// [[T-18718]]: the `.onDisappear` half of the block's hover. A block leaves the canvas under
    /// a parked pointer -- Cmd+T unschedules it, or Cmd+\ closes the timeline overlay -- and
    /// `.onHover(false)` never fires then, so without this the managers keep the gone block: the
    /// next Cmd+Return / Cmd+P / Cmd+Delete acts on a task that is no longer on screen.
    ///
    /// Guarded on the block's own hover, as the task row's teardown is: the same task can be a row
    /// in the list beside the timeline, and an unguarded `endHovering(task)` from a block that was
    /// never hovered would end that row's hover. Both managers' `endHovering` are identity-guarded,
    /// so a block the pointer has already left for another no-ops.
    static func endHoverOnDisappear(
        isHovered: inout Bool,
        task: AppTask,
        hoveredTaskManager: HoveredTaskManager,
        hoveredEditableManager: HoveredEditableManager
    ) {
        guard isHovered else { return }
        isHovered = false
        endHover(task: task, hoveredTaskManager: hoveredTaskManager, hoveredEditableManager: hoveredEditableManager)
    }

    static func beginResize(
        task: AppTask,
        selectedTaskID: Binding<UUID?>,
        activeDragTaskID: Binding<UUID?>,
        resizeSession: inout TimelineResizeSession?,
        edge: TimelineResizeEdge,
        localY: CGFloat,
        frame: TimelineBlockFrame,
        metrics: TimelineMetrics,
        onSelect: () -> Void
    ) {
        guard resizeSession == nil else { return }
        onSelect()
        // Dismissing the inspector is right for a resize — the popover is anchored to a block that
        // is about to change length underneath it — and wrong for a press that never moved. The
        // caller is what decides which this is: the strip's drag gesture has `minimumDistance: 0`
        // and so fires on mouse-down, and it now waits for `isResizeDrag` before calling in here.
        // While it did not, clicking a strip closed the inspector instead of opening it.
        selectedTaskID.wrappedValue = nil
        activeDragTaskID.wrappedValue = nil
        resizeSession = TimelineResizeSession.begin(
            edge: edge,
            localY: localY,
            blockTopY: frame.y,
            blockDrawnHeight: frame.height,
            originStartMin: task.scheduledStartMin,
            originEndMin: task.scheduledEndMin,
            metrics: metrics
        )
    }

    static func updateResize(
        task: AppTask,
        session: TimelineResizeSession?,
        localY: CGFloat,
        frame: TimelineBlockFrame,
        metrics: TimelineMetrics
    ) {
        guard let session else { return }
        let range = metrics.resizedRange(
            session: session,
            localY: localY,
            blockTopY: frame.y,
            blockDrawnHeight: frame.height
        )
        task.scheduledStartMin = range.start
        task.estimatedMinutes = max(5, range.end - range.start)
    }

    /// The end of a resize drag, **committed** ([[T-4970]]).
    ///
    /// `updateResize` writes `scheduledStartMin` and `estimatedMinutes` on every frame of the drag,
    /// which is what makes the block follow the pointer, and the drag used to end by clearing its
    /// session and nothing else — so the new length sat pending in the app's single `ModelContext`
    /// until an unrelated save committed it or an unrelated `rollback()` discarded it: the
    /// [[T-4911]] / [[T-503]] shape. `origin` is the task as the drag found it, so a refusal puts
    /// the block back where it started rather than rolling back anyone else's pending work, and
    /// reminders are reconciled once after either answer, since the slot is what they describe.
    @discardableResult
    static func commitResize(
        _ task: AppTask,
        restoring origin: CadenceTaskFieldSnapshot,
        in modelContext: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Bool {
        let landed: Bool
        do {
            try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit) {
                origin.restore(to: task)
            }
            landed = true
        } catch {
            landed = false
        }
        (reconciler ?? .default).run(in: modelContext)
        return landed
    }
}
#endif
