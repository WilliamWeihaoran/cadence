#if os(macOS)
import SwiftUI

struct TimelineCreateGridLayer: View {
    let metrics: TimelineMetrics
    let blockedFrames: [TimelineBlockFrame]
    let showHalfHourMarks: Bool
    /// True while a block drag that began on this canvas is live ([[T-5350]]: the page's shared
    /// session, scoped to this canvas's own blocks).
    let refusesDraftCreation: Bool
    let onTapBackground: () -> Void
    let onDragChanged: (Int, Int) -> Void
    let onDragEnded: (Int, Int) -> Void

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: metrics.totalHeight)
            .overlay { TimelineHourGridLines(metrics: metrics, showHalfHourMarks: showHalfHourMarks) }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTapBackground)
            // One gesture over the whole canvas, reading the canvas's own coordinate space. It
            // used to be one gesture per hour row, with the canvas Y rebuilt from the row's index
            // — the only interactive layer here not placed from a `TimelineBlockFrame`, and the
            // only one whose accuracy depended on the *layout* of a `VStack` staying exactly zero-
            // spaced, zero-padded and flush with canvas Y = 0.
            .gesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .named(TimelineDayCanvas.coordinateSpaceName))
                    .onChanged { value in
                        guard shouldHandle(startLocation: value.startLocation) else { return }
                        onDragChanged(
                            metrics.snappedMinute(fromY: value.startLocation.y),
                            metrics.snappedMinute(fromY: value.location.y)
                        )
                    }
                    .onEnded { value in
                        guard shouldHandle(startLocation: value.startLocation) else { return }
                        onDragEnded(
                            metrics.snappedMinute(fromY: value.startLocation.y),
                            metrics.snappedMinute(fromY: value.location.y)
                        )
                    }
            )
            .suppressWindowBackgroundDrag()
    }

    private func shouldHandle(startLocation: CGPoint) -> Bool {
        guard !refusesDraftCreation else { return false }
        return !TimelineMetricsSupport.isInsideBlockedBlock(point: startLocation, blockedFrames: blockedFrames)
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
            metrics: metrics
        )
    }

    var body: some View {
        if let highlightFrame {
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(Theme.amber.opacity(0.026))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Theme.amber.opacity(0.055))
                        .frame(height: 1)
                }
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Theme.amber.opacity(0.045))
                        .frame(height: 1)
                }
                .frame(width: width, height: highlightFrame.height)
                .offset(y: highlightFrame.y)
                .allowsHitTesting(false)
        }
    }
}

struct TimelineScheduledBlocksLayer: View {
    let todayKey: String
    let eventLayouts: [TimelineEventLayout]
    let taskLayouts: [TimelineBlockLayout]
    let allTasks: [AppTask]
    let areas: [Area]
    let projects: [Project]
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

        // [[T-3170]]: the Block layer was drawn here at `zIndex(3)`, between the events and the
        // task blocks. `TimelineBundleBlock` is deleted, so events and tasks are the whole of what
        // this layer draws. The remaining z-order is deliberate and unchanged: events below, task
        // blocks above.

        ForEach(taskLayouts, id: \.task.id) { layout in
            TimelineTaskBlock(
                task: layout.task,
                todayKey: todayKey,
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
