#if os(macOS)
import SwiftUI

struct TimelineTaskBlock: View {
    private enum ResizeEdge {
        case start
        case end
    }

    let task: AppTask
    let column: Int
    let totalColumns: Int
    let totalWidth: CGFloat
    let metrics: TimelineMetrics
    let style: TimelineBlockStyle
    @Environment(HoveredTaskManager.self) private var hoveredTaskManager
    @Environment(HoveredEditableManager.self) private var hoveredEditableManager
    @Binding var selectedTaskID: UUID?
    @Binding var activeDragTaskID: UUID?
    let onSelect: () -> Void

    @State private var activeResizeEdge: ResizeEdge? = nil
    @State private var resizeOriginStartMin: Int? = nil
    @State private var resizeOriginEndMin: Int? = nil
    @State private var isHovered = false

    private let resizeHandleHeight: CGFloat = 8

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
            showSelection: selectedTaskID == task.id,
            showHover: isHovered
        )
        .frame(width: frame.width, height: frame.height)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                hoveredTaskManager.beginHovering(task)
                hoveredEditableManager.beginHovering(id: "timeline-task-\(task.id.uuidString)") {
                    onSelect()
                    activeDragTaskID = nil
                    selectedTaskID = task.id
                }
            } else {
                hoveredTaskManager.endHovering(task)
                hoveredEditableManager.endHovering(id: "timeline-task-\(task.id.uuidString)")
            }
        }
        .onTapGesture {
            onSelect()
            activeDragTaskID = nil
            selectedTaskID = task.id
        }
        .onDrag {
            guard activeResizeEdge == nil else {
                return NSItemProvider()
            }
            selectedTaskID = nil
            activeDragTaskID = task.id
            return NSItemProvider(object: task.id.uuidString as NSString)
        } preview: {
            timelineDragPreview(task: task, style: style)
        }
        .overlay(alignment: .top) {
            resizeHandle(edge: .start)
        }
        .overlay(alignment: .bottom) {
            resizeHandle(edge: .end)
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

    @ViewBuilder
    private func resizeHandle(edge: ResizeEdge) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: resizeHandleHeight)
            .contentShape(Rectangle())
            .overlay {
                let isEmphasized = activeResizeEdge == edge || isHovered || selectedTaskID == task.id
                Capsule()
                    .fill(.white.opacity(isEmphasized ? 0.4 : 0.16))
                    .frame(width: min(18, max(10, frame.width - 18)), height: 2)
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        beginResizeIfNeeded(edge: edge)
                        updateResize(edge: edge, localY: value.location.y)
                    }
                    .onEnded { value in
                        updateResize(edge: edge, localY: value.location.y)
                        endResize()
                    }
            )
    }

    private func beginResizeIfNeeded(edge: ResizeEdge) {
        guard activeResizeEdge == nil else { return }
        onSelect()
        selectedTaskID = nil
        activeDragTaskID = nil
        activeResizeEdge = edge
        resizeOriginStartMin = task.scheduledStartMin
        resizeOriginEndMin = task.scheduledStartMin + max(task.estimatedMinutes, 5)
    }

    private func updateResize(edge: ResizeEdge, localY: CGFloat) {
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

    private func endResize() {
        activeResizeEdge = nil
        resizeOriginStartMin = nil
        resizeOriginEndMin = nil
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
    showSelection: Bool,
    showHover: Bool = false
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
            .stroke(
                showSelection
                ? .white.opacity(0.22)
                : (showHover ? Theme.blue.opacity(0.32) : .white.opacity(0.08)),
                lineWidth: 1
            )
    )
    .overlay(alignment: .top) {
        Rectangle()
            .fill(
                showSelection
                ? .white.opacity(0.95)
                : (showHover ? Theme.blue.opacity(0.7) : .white.opacity(0.35))
            )
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
