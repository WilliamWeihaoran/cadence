#if os(macOS)
import SwiftUI
import SwiftData

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
    @Environment(\.modelContext) private var modelContext
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
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
            showHover: isHovered,
            onToggleDone: { task.status = task.isDone ? .todo : .done }
        )
        .frame(width: frame.width, height: frame.height)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                hoveredTaskManager.beginHovering(task, source: .timeline)
                hoveredEditableManager.beginHovering(id: "timeline-task-\(task.id.uuidString)") {
                    onSelect()
                    activeDragTaskID = nil
                    selectedTaskID = task.id
                } onDelete: {
                    deleteConfirmationManager.present(
                        title: "Delete Task?",
                        message: "This will permanently delete \"\(task.title.isEmpty ? "Untitled" : task.title)\"."
                    ) {
                        if hoveredTaskManager.hoveredTask?.id == task.id {
                            hoveredTaskManager.hoveredTask = nil
                        }
                        if selectedTaskID == task.id {
                            selectedTaskID = nil
                        }
                        if activeDragTaskID == task.id {
                            activeDragTaskID = nil
                        }
                        modelContext.delete(task)
                    }
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

// MARK: - Diagonal stripe pattern for completed tasks

private struct DiagonalStripeOverlay: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 10
            let lineWidth: CGFloat = 3
            let totalLines = Int((size.width + size.height) / spacing) + 2
            for i in 0..<totalLines {
                let offset = CGFloat(i) * spacing
                var path = Path()
                path.move(to: CGPoint(x: offset - size.height, y: 0))
                path.addLine(to: CGPoint(x: offset, y: size.height))
                context.stroke(path, with: .color(.white.opacity(0.10)), lineWidth: lineWidth)
            }
        }
        .allowsHitTesting(false)
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
    showHover: Bool = false,
    onToggleDone: (() -> Void)? = nil
) -> some View {
    let taskColor = Color(hex: task.containerColor)
    HStack(alignment: .top, spacing: 0) {
        // Left color bar
        taskColor
            .opacity(task.isDone ? 0.4 : 1)
            .frame(width: 3)
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: style.cornerRadius,
                bottomLeadingRadius: style.cornerRadius
            ))

        // Completion button + text
        HStack(alignment: .top, spacing: 4) {
            if let onToggleDone {
                Button(action: onToggleDone) {
                    Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12))
                        .foregroundStyle(task.isDone ? Theme.green : Theme.dim)
                }
                .buttonStyle(.cadencePlain)
                .padding(.top, 1)
            }

            VStack(alignment: .leading, spacing: 2) {
                if frame.height >= 58 {
                    Text(timeRangeLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(taskColor.opacity(0.9))
                        .lineLimit(1)
                }
                if frame.height >= 38 {
                    Text(task.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(task.isDone ? Theme.dim : Theme.text)
                        .lineLimit(2)
                    let label = TimeFormatters.durationLabel(actual: task.actualMinutes, estimated: durationMinutes)
                    if label != "-/-" {
                        Text(label)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.dim)
                    }
                } else {
                    let label = TimeFormatters.durationLabel(actual: task.actualMinutes, estimated: durationMinutes)
                    HStack(spacing: 4) {
                        Text(task.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(task.isDone ? Theme.dim : Theme.text)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if label != "-/-" {
                            Text(label)
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.dim)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, style.horizontalPadding)
        .padding(.vertical, style.verticalPadding)

        Spacer(minLength: 0)
    }
    .frame(width: frame.width, height: frame.height, alignment: .topLeading)
    .clipped()
    .background(
        ZStack {
            // Opaque base — grid lines never bleed through
            RoundedRectangle(cornerRadius: style.cornerRadius).fill(Theme.bg)
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .fill(taskColor.opacity(task.isDone ? 0.08 : 0.18))
            if showHover {
                RoundedRectangle(cornerRadius: style.cornerRadius)
                    .fill(Theme.blue.opacity(0.06))
            }
        }
    )
    .overlay {
        if task.isDone {
            DiagonalStripeOverlay()
                .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius))
        }
    }
    .overlay(
        RoundedRectangle(cornerRadius: style.cornerRadius)
            .stroke(
                showSelection
                    ? taskColor.opacity(0.6)
                    : (showHover ? taskColor.opacity(0.54) : taskColor.opacity(0.22)),
                lineWidth: showHover ? 1.2 : 1
            )
    )
    .shadow(color: showHover ? taskColor.opacity(0.12) : .clear, radius: 10, y: 2)
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
