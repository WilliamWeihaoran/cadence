#if os(macOS)
import SwiftUI

struct TimelineTaskBlock: View {
    let task: AppTask
    let column: Int
    let totalColumns: Int
    let totalWidth: CGFloat
    let metrics: TimelineMetrics
    let style: TimelineBlockStyle
    @Binding var selectedTaskID: UUID?
    @Binding var activeDragTaskID: UUID?
    let onSelect: () -> Void

    private var timeRangeLabel: String {
        let duration = max(task.estimatedMinutes, 5)
        return TimeFormatters.timeRange(startMin: task.scheduledStartMin, endMin: task.scheduledStartMin + duration)
    }

    private var frame: TimelineBlockFrame {
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

    var body: some View {
        timelineBlockBody(
            task: task,
            durationMinutes: task.estimatedMinutes,
            timeRangeLabel: timeRangeLabel,
            frame: frame,
            style: style,
            showSelection: selectedTaskID == task.id
        )
        .frame(width: frame.width, height: frame.height)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
            activeDragTaskID = nil
            selectedTaskID = task.id
        }
        .onDrag {
            activeDragTaskID = task.id
            return NSItemProvider(object: task.id.uuidString as NSString)
        } preview: {
            timelineDragPreview(task: task, style: style)
        }
        .popover(

            isPresented: Binding(
                get: { selectedTaskID == task.id },
                set: { isPresented in
                    if isPresented {
                        selectedTaskID = task.id
                    } else if selectedTaskID == task.id {
                        selectedTaskID = nil
                    }
                }
            )
        ) {
            TaskDetailPopover(task: task)
        }
        .position(x: frame.centerX, y: frame.centerY)
    }

}

struct TimelineDraggedTaskPreview: View {
    let task: AppTask
    let startMinute: Int
    let durationMinutes: Int
    let column: Int
    let totalColumns: Int
    let totalWidth: CGFloat
    let metrics: TimelineMetrics
    let style: TimelineBlockStyle

    private var frame: TimelineBlockFrame {
        computeTimelineBlockFrame(
            startMinute: startMinute,
            durationMinutes: durationMinutes,
            column: column,
            totalColumns: totalColumns,
            totalWidth: totalWidth,
            metrics: metrics,
            style: style
        )
    }

    private var timeRangeLabel: String {
        TimeFormatters.timeRange(startMin: startMinute, endMin: startMinute + max(durationMinutes, 5))
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .fill(Theme.blue.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: style.cornerRadius)
                        .stroke(Theme.blue.opacity(0.55), lineWidth: 1)
                )
                .frame(width: frame.width, height: frame.height)

            timelineBlockBody(
                task: task,
                durationMinutes: durationMinutes,
                timeRangeLabel: timeRangeLabel,
                frame: frame,
                style: style,
                showSelection: true
            )
            .opacity(0.92)
        }
        .allowsHitTesting(false)
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.centerX, y: frame.centerY)
    }

}

struct TimelineCurrentTimeOverlay: View {
    let date: Date
    let totalWidth: CGFloat
    let metrics: TimelineMetrics
    let style: TimelineBlockStyle
    let showDot: Bool

    private var minutesFromMidnight: Int {
        let calendar = Calendar.current
        return calendar.component(.hour, from: Date()) * 60 + calendar.component(.minute, from: Date())
    }

    private var yOffset: CGFloat {
        metrics.yOffset(for: minutesFromMidnight)
    }

    var body: some View {
        let calendar = Calendar.current
        let mins = minutesFromMidnight

        if calendar.isDateInToday(date),
           mins >= metrics.startHour * 60,
           mins <= metrics.endHour * 60 {
            ZStack(alignment: .topLeading) {
                if showDot {
                    Circle()
                        .fill(Theme.red)
                        .frame(width: 8, height: 8)
                        .offset(x: style.leadingInset - 4, y: yOffset - 4)
                }

                Rectangle()
                    .fill(Theme.red)
                    .frame(
                        width: max(0, totalWidth - style.leadingInset - style.trailingInset + (showDot ? 4 : 0)),
                        height: 1
                    )
                    .offset(x: showDot ? style.leadingInset - 4 : style.leadingInset, y: yOffset)
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Rendering helpers

@ViewBuilder
func timelineBlockBody(
    task: AppTask,
    durationMinutes: Int,
    timeRangeLabel: String,
    frame: TimelineBlockFrame,
    style: TimelineBlockStyle,
    showSelection: Bool
) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        if frame.height >= 40 {
            Text(timeRangeLabel)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)
        }
        Text(task.title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(2)
        if durationMinutes > 0 {
            Text("\(durationMinutes)m")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.75))
        }
    }
    .padding(.horizontal, style.horizontalPadding)
    .padding(.vertical, style.verticalPadding)
    .frame(width: frame.width, height: frame.height, alignment: .topLeading)
    .background(
        RoundedRectangle(cornerRadius: style.cornerRadius)
            .fill(Color(hex: task.containerColor).opacity(task.isDone ? 0.45 : 0.85))
    )
    .overlay(
        RoundedRectangle(cornerRadius: style.cornerRadius)
            .stroke(.white.opacity(showSelection ? 0.22 : 0.08), lineWidth: 1)
    )
    .overlay(alignment: .top) {
        Rectangle()
            .fill(.white.opacity(showSelection ? 0.95 : 0.35))
            .frame(height: showSelection ? 2 : 1)
            .padding(.horizontal, 1)
    }
    .opacity(task.isDone ? 0.65 : 1.0)
}

func timelineDragPreview(task: AppTask, style: TimelineBlockStyle) -> some View {
    Text(task.title)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, style.horizontalPadding)
        .padding(.vertical, style.verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .fill(Color(hex: task.containerColor).opacity(0.85))
        )
}
#endif
