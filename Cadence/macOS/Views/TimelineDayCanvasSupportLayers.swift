#if os(macOS)
import SwiftUI

struct TimelineCreateGridLayer: View {
    let metrics: TimelineMetrics
    let blockedFrames: [TimelineBlockFrame]
    let showHalfHourMarks: Bool
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
                    blockedFrames: blockedFrames,
                    showHalfHourMark: showHalfHourMarks,
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
    let bundleLayouts: [TimelineBundleLayout]
    let taskLayouts: [TimelineBlockLayout]
    let allTasks: [AppTask]
    let width: CGFloat
    let metrics: TimelineMetrics
    let style: TimelineBlockStyle
    @Binding var selectedTaskID: UUID?
    @Binding var selectedBundleID: UUID?
    @Binding var selectedEventID: String?
    @Binding var activeDragTaskID: UUID?
    @Binding var activeDragBundleID: UUID?
    let onTaskDroppedOnBundle: (AppTask, TaskBundle) -> Void
    let onCreateBundleFromTasks: (AppTask, AppTask) -> Void
    let onTaskSelected: () -> Void
    let onBundleSelected: () -> Void

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

        ForEach(bundleLayouts, id: \.bundle.id) { layout in
            TimelineBundleBlock(
                bundle: layout.bundle,
                allTasks: allTasks,
                column: layout.column,
                totalColumns: layout.totalColumns,
                totalWidth: width,
                metrics: metrics,
                style: style,
                selectedBundleID: $selectedBundleID,
                activeDragBundleID: $activeDragBundleID,
                onTaskDropped: onTaskDroppedOnBundle,
                onSelect: onBundleSelected
            )
            .zIndex(3)
        }

        ForEach(taskLayouts, id: \.task.id) { layout in
            TimelineTaskBlock(
                task: layout.task,
                allTasks: allTasks,
                column: layout.column,
                totalColumns: layout.totalColumns,
                totalWidth: width,
                metrics: metrics,
                style: style,
                selectedTaskID: $selectedTaskID,
                activeDragTaskID: $activeDragTaskID,
                onCreateBundleWithTask: onCreateBundleFromTasks,
                onSelect: onTaskSelected
            )
            .zIndex(2)
        }
    }
}
#endif
