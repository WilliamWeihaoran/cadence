#if os(macOS)
import SwiftUI

struct TimelineCreateGridLayer: View {
    let metrics: TimelineMetrics
    let taskFrames: [TimelineBlockFrame]
    @Binding var activeDragTaskID: UUID?
    let onTapBackground: () -> Void
    let onDragChanged: (Int, Int) -> Void
    let onDragEnded: (Int, Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(metrics.startHour..<metrics.endHour, id: \.self) { hour in
                TimelineCreateRow(
                    hour: hour,
                    metrics: metrics,
                    taskFrames: taskFrames,
                    activeDragTaskID: $activeDragTaskID,
                    onTapBackground: onTapBackground,
                    onDragChanged: onDragChanged,
                    onDragEnded: onDragEnded
                )
            }
        }
    }
}

struct TimelineScheduledBlocksLayer: View {
    let eventLayouts: [TimelineEventLayout]
    let taskLayouts: [TimelineBlockLayout]
    let width: CGFloat
    let metrics: TimelineMetrics
    let style: TimelineBlockStyle
    @Binding var selectedTaskID: UUID?
    @Binding var selectedEventID: String?
    @Binding var activeDragTaskID: UUID?
    let onTaskSelected: () -> Void

    var body: some View {
        ForEach(eventLayouts, id: \.item.id) { layout in
            TimelineEventBlock(
                item: layout.item,
                layout: layout,
                totalWidth: width,
                metrics: metrics,
                style: style,
                selectedEventID: $selectedEventID,
                selectedTaskID: $selectedTaskID
            )
            .zIndex(2)
        }

        ForEach(taskLayouts, id: \.task.id) { layout in
            TimelineTaskBlock(
                task: layout.task,
                column: layout.column,
                totalColumns: layout.totalColumns,
                totalWidth: width,
                metrics: metrics,
                style: style,
                selectedTaskID: $selectedTaskID,
                activeDragTaskID: $activeDragTaskID,
                onSelect: onTaskSelected
            )
            .zIndex(2)
        }
    }
}
#endif
