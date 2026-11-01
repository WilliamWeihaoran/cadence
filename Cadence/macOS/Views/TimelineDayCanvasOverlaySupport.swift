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
                durationMinutes: previewTask.timelineDurationMinutes,
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
    let draft: TimelineDraftSelection?
    /// Where the draft block belongs ([[T-8851]]). `.allDayStrip` draws **no ghost here** — the
    /// day's all-day strip draws a chip for it instead — while the popover's anchor stays on the
    /// pressed range either way, so flipping All day never moves the panel out from under the
    /// pointer. iOS's column asks the same rule.
    var placement: CadenceCalendarDraftPlacement = .hourLadder
    let width: CGFloat
    let metrics: TimelineMetrics
    let style: TimelineBlockStyle
    @Binding var showNewTaskPopover: Bool
    let onDismissed: () -> Void
    @ViewBuilder let popoverContent: (Int, Int) -> AnyView

    var body: some View {
        if let draft {
            if placement.drawsBlockInHourLadder {
                TimelineDraftGhostLayer(
                    startMinute: draft.start,
                    endMinute: draft.end,
                    width: width,
                    metrics: metrics,
                    style: style
                )
            }

            TimelineDraftPopoverAnchor(
                startMinute: draft.start,
                endMinute: draft.end,
                width: width,
                metrics: metrics,
                style: style,
                isPresented: $showNewTaskPopover,
                onDismissed: onDismissed
            ) {
                // One range: the ghost above, the popover's own header, and everything the
                // popover creates all read `draft`. The creation closures used to shadow these
                // parameters and re-read the canvas's `pendingStartMin`/`pendingEndMin` instead,
                // so what the popover showed and what it made were two separate lookups.
                popoverContent(draft.start, draft.end)
            }
        }
    }
}
#endif
