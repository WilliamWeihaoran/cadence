#if os(macOS)
import SwiftUI
import SwiftData

enum TimelineTaskBlockInteractionSupport {
    static let resizeHandleHeight: CGFloat = 8

    static func timeRangeLabel(for task: AppTask) -> String {
        let duration = max(task.estimatedMinutes, 5)
        return TimeFormatters.timeRange(
            startMin: task.scheduledStartMin,
            endMin: task.scheduledStartMin + duration
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
            durationMinutes: task.estimatedMinutes,
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
        activeResizeEdge: inout TimelineTaskBlock.ResizeEdge?,
        resizeOriginStartMin: inout Int?,
        resizeOriginEndMin: inout Int?,
        edge: TimelineTaskBlock.ResizeEdge,
        onSelect: () -> Void
    ) {
        guard activeResizeEdge == nil else { return }
        onSelect()
        selectedTaskID.wrappedValue = nil
        activeDragTaskID.wrappedValue = nil
        activeResizeEdge = edge
        resizeOriginStartMin = task.scheduledStartMin
        resizeOriginEndMin = task.scheduledStartMin + max(task.estimatedMinutes, 5)
    }

    static func updateResize(
        task: AppTask,
        edge: TimelineTaskBlock.ResizeEdge,
        localY: CGFloat,
        frame: TimelineBlockFrame,
        metrics: TimelineMetrics,
        resizeHandleHeight: CGFloat,
        resizeOriginStartMin: Int?,
        resizeOriginEndMin: Int?
    ) {
        guard let originStart = resizeOriginStartMin,
              let originEnd = resizeOriginEndMin else { return }

        let localYOffset: CGFloat
        switch edge {
        case .start:
            localYOffset = localY
        case .end:
            localYOffset = max(0, frame.height - resizeHandleHeight) + localY
        }

        let snappedMinute = metrics.snappedMinute(fromY: frame.y + localYOffset)

        switch edge {
        case .start:
            let nextStart = min(snappedMinute, originEnd - 5)
            task.scheduledStartMin = nextStart
            task.estimatedMinutes = max(5, originEnd - nextStart)
        case .end:
            let nextEnd = max(snappedMinute, originStart + 5)
            task.scheduledStartMin = originStart
            task.estimatedMinutes = max(5, nextEnd - originStart)
        }
    }
}
#endif
