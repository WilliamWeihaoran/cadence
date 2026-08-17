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
            deleteConfirmationManager.present(
                title: "Delete Task?",
                message: "This will permanently delete \"\(task.title.isEmpty ? "Untitled" : task.title)\"."
            ) {
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
                modelContext.deleteTask(task)
            }
        }
    }

    static func endHover(task: AppTask, hoveredTaskManager: HoveredTaskManager, hoveredEditableManager: HoveredEditableManager) {
        hoveredTaskManager.endHovering(task)
        hoveredEditableManager.endHovering(id: "timeline-task-\(task.id.uuidString)")
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
}
#endif
