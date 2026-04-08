#if os(macOS)
import SwiftUI

struct TimelineDayCanvasOverlaySupport {
    static func previewTask(
        activeDragTaskID: UUID?,
        dropPreviewTaskID: UUID?,
        allTasks: [AppTask]
    ) -> AppTask? {
        let previewTaskID = activeDragTaskID ?? dropPreviewTaskID
        return allTasks.first(where: { $0.id == previewTaskID })
    }

    static func ghostRange(
        dragStartMin: Int?,
        dragEndMin: Int?,
        pendingStartMin: Int?,
        pendingEndMin: Int?
    ) -> (start: Int, end: Int)? {
        guard let start = dragStartMin ?? pendingStartMin,
              let end = dragEndMin ?? pendingEndMin,
              end > start else { return nil }
        return (start, end)
    }
}

struct TimelineDropPreviewOverlay: View {
    let isDropTargeted: Bool
    let previewTask: AppTask?
    let dropPreviewStartMin: Int?
    let layouts: [TimelineBlockLayout]
    let width: CGFloat
    let metrics: TimelineMetrics
    let style: TimelineBlockStyle

    var body: some View {
        if isDropTargeted,
           let previewTask,
           let previewStartMin = dropPreviewStartMin {
            let previewLayout = layouts.first(where: { $0.task.id == previewTask.id })
            TimelineDraggedTaskPreview(
                task: previewTask,
                startMinute: previewStartMin,
                durationMinutes: previewTask.estimatedMinutes > 0 ? previewTask.estimatedMinutes : 30,
                column: previewLayout?.column ?? 0,
                totalColumns: previewLayout?.totalColumns ?? 1,
                totalWidth: width,
                metrics: metrics,
                style: style
            )
            .zIndex(3)
        }
    }
}

struct TimelineDraftCreationOverlay: View {
    let ghostRange: (start: Int, end: Int)?
    let width: CGFloat
    let metrics: TimelineMetrics
    let style: TimelineBlockStyle
    @Binding var showNewTaskPopover: Bool
    let onDismissed: () -> Void
    @ViewBuilder let popoverContent: (Int, Int) -> AnyView

    var body: some View {
        if let ghostRange {
            TimelineDraftGhostLayer(
                startMinute: ghostRange.start,
                endMinute: ghostRange.end,
                width: width,
                metrics: metrics,
                style: style
            )

            TimelineDraftPopoverAnchor(
                startMinute: ghostRange.start,
                endMinute: ghostRange.end,
                width: width,
                metrics: metrics,
                style: style,
                isPresented: $showNewTaskPopover,
                onDismissed: onDismissed
            ) {
                popoverContent(ghostRange.start, ghostRange.end)
            }
        }
    }
}
#endif
