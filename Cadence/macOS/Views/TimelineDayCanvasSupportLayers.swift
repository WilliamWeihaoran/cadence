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

struct TimelineWorkHoursHighlightLayer: View {
    let width: CGFloat
    let metrics: TimelineMetrics
    let startMinute: Int
    let endMinute: Int

    private var highlightFrame: CalendarWorkHoursPreferences.HighlightFrame? {
        CalendarWorkHoursPreferences.highlightFrame(
            startMinute: startMinute,
            endMinute: endMinute,
            timelineStartHour: metrics.startHour,
            timelineEndHour: metrics.endHour,
            hourHeight: metrics.hourHeight
        )
    }

    var body: some View {
        if let highlightFrame {
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(Theme.amber.opacity(0.075))
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Theme.amber.opacity(0.28))
                        .frame(width: 3)
                }
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Theme.amber.opacity(0.12))
                        .frame(height: 1)
                }
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Theme.amber.opacity(0.1))
                        .frame(height: 1)
                }
                .frame(width: width, height: highlightFrame.height)
                .offset(y: highlightFrame.y)
                .allowsHitTesting(false)
        }
    }
}

struct TimelineScheduledBlocksLayer: View {
    let eventLayouts: [TimelineEventLayout]
    let bundleLayouts: [TimelineBundleLayout]
    let taskLayouts: [TimelineBlockLayout]
    let allTasks: [AppTask]
    let areas: [Area]
    let projects: [Project]
    let width: CGFloat
    let metrics: TimelineMetrics
    let style: TimelineBlockStyle
    @Binding var selectedTaskID: UUID?
    @Binding var selectedBundleID: UUID?
    @Binding var selectedEventID: String?
    @Binding var activeDragTaskID: UUID?
    @Binding var activeDragBundleID: UUID?
    let onTaskDroppedOnBundle: (AppTask, TaskBundle) -> Void
    let onTaskBundleDropAccepted: (UUID) -> Void
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
                areas: areas,
                projects: projects,
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
                onBundleDropAccepted: onTaskBundleDropAccepted,
                onCreateBundleWithTask: onCreateBundleFromTasks,
                onSelect: onTaskSelected
            )
            .zIndex(2)
        }
    }
}
#endif
