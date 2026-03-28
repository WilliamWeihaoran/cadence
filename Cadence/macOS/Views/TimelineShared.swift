#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

struct TimelineMetrics {
    let startHour: Int
    let endHour: Int
    let hourHeight: CGFloat

    var totalMinutes: Int { (endHour - startHour) * 60 }
    var totalHeight: CGFloat { CGFloat(endHour - startHour) * hourHeight }

    func snap5(_ mins: Int) -> Int { (mins / 5) * 5 }

    func yToMins(_ y: CGFloat) -> Int {
        let mins = Int(y / hourHeight * 60) + startHour * 60
        return max(startHour * 60, min(endHour * 60 - 5, mins))
    }

    func snappedMinute(fromY y: CGFloat) -> Int {
        snap5(yToMins(y))
    }

    func yOffset(for minute: Int) -> CGFloat {
        CGFloat(minute - startHour * 60) * hourHeight / 60
    }

    func height(for durationMinutes: Int, minHeight: CGFloat) -> CGFloat {
        max(minHeight, CGFloat(max(durationMinutes, 5)) * hourHeight / 60)
    }
}

struct TimelineBlockStyle {
    let leadingInset: CGFloat
    let trailingInset: CGFloat
    let sideMarginFraction: CGFloat
    let columnSpacing: CGFloat
    let minHeight: CGFloat
    let cornerRadius: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat

    static let schedule = TimelineBlockStyle(
        leadingInset: 8,
        trailingInset: 0,
        sideMarginFraction: 0,
        columnSpacing: 2,
        minHeight: 24,
        cornerRadius: 6,
        horizontalPadding: 8,
        verticalPadding: 4
    )

    static let calendar = TimelineBlockStyle(
        leadingInset: 4,
        trailingInset: 4,
        sideMarginFraction: 0,
        columnSpacing: 2,
        minHeight: 22,
        cornerRadius: 5,
        horizontalPadding: 6,
        verticalPadding: 3
    )
}

enum TimelineDropBehavior {
    case wholeColumn
    case perHour
}

struct TimelineBlockLayout {
    let task: AppTask
    let column: Int
    let totalColumns: Int
}

private struct TimelineBlockFrame {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    var centerX: CGFloat { x + (width / 2) }
    var centerY: CGFloat { y + (height / 2) }
}

private func computeTimelineBlockFrame(
    startMinute: Int,
    durationMinutes: Int,
    column: Int,
    totalColumns: Int,
    totalWidth: CGFloat,
    metrics: TimelineMetrics,
    style: TimelineBlockStyle
) -> TimelineBlockFrame {
    let y = metrics.yOffset(for: startMinute)
    let height = metrics.height(
        for: durationMinutes > 0 ? durationMinutes : 60,
        minHeight: style.minHeight
    )
    let availableWidth = max(0, totalWidth - style.leadingInset - style.trailingInset)
    let innerAvailableWidth = availableWidth * max(0, 1 - (style.sideMarginFraction * 2))
    let leftMargin = style.leadingInset + availableWidth * style.sideMarginFraction
    let columnWidth = innerAvailableWidth / CGFloat(max(totalColumns, 1))
    let width = max(0, columnWidth - style.columnSpacing)
    let x = leftMargin + CGFloat(column) * columnWidth
    return TimelineBlockFrame(x: x, y: y, width: width, height: height)
}

func computeTimelineLayouts(_ tasks: [AppTask]) -> [TimelineBlockLayout] {
    let sorted = tasks.sorted { $0.scheduledStartMin < $1.scheduledStartMin }
    var layouts: [TimelineBlockLayout] = []

    for task in sorted {
        let tStart = task.scheduledStartMin
        let tEnd = tStart + max(task.estimatedMinutes > 0 ? task.estimatedMinutes : 60, 5)
        let overlapping = layouts.filter { layout in
            let oStart = layout.task.scheduledStartMin
            let oEnd = oStart + max(layout.task.estimatedMinutes > 0 ? layout.task.estimatedMinutes : 60, 5)
            return tStart < oEnd && tEnd > oStart
        }
        let usedCols = Set(overlapping.map(\.column))
        var col = 0
        while usedCols.contains(col) { col += 1 }
        layouts.append(TimelineBlockLayout(task: task, column: col, totalColumns: 1))
    }

    return layouts.map { layout in
        let tStart = layout.task.scheduledStartMin
        let tEnd = tStart + max(layout.task.estimatedMinutes > 0 ? layout.task.estimatedMinutes : 60, 5)
        let overlapping = layouts.filter { candidate in
            let oStart = candidate.task.scheduledStartMin
            let oEnd = oStart + max(candidate.task.estimatedMinutes > 0 ? candidate.task.estimatedMinutes : 60, 5)
            return tStart < oEnd && tEnd > oStart
        }
        let totalCols = (overlapping.map(\.column).max() ?? 0) + 1
        return TimelineBlockLayout(task: layout.task, column: layout.column, totalColumns: totalCols)
    }
}

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

private struct TimelineDraggedTaskPreview: View {
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

struct TimelineDayCanvas: View {
    let date: Date
    let dateKey: String
    let tasks: [AppTask]
    let allTasks: [AppTask]
    let metrics: TimelineMetrics
    let width: CGFloat
    let style: TimelineBlockStyle
    let showCurrentTimeDot: Bool
    let dropBehavior: TimelineDropBehavior
    let onCreateTask: (String, Int, Int) -> Void
    let onDropTaskAtMinute: (AppTask, Int) -> Void

    @State private var dragStartMin: Int? = nil
    @State private var dragEndMin: Int? = nil
    @State private var pendingStartMin: Int? = nil
    @State private var pendingEndMin: Int? = nil
    @State private var showNewTaskPopover = false
    @State private var newTaskTitle = ""
    @State private var isDropTargeted = false
    @State private var dropPreviewTaskID: UUID? = nil
    @State private var dropPreviewStartMin: Int? = nil
    @State private var selectedTaskID: UUID? = nil
    @State private var activeDragTaskID: UUID? = nil
    @State private var dragYOffset: CGFloat = 0

    private func clearDraftCreation() {
        dragStartMin = nil
        dragEndMin = nil
        pendingStartMin = nil
        pendingEndMin = nil
        showNewTaskPopover = false
        newTaskTitle = ""
    }

    var body: some View {
        let layouts = computeTimelineLayouts(tasks)
        // Show preview for both incoming drops and within-canvas moves.
        // We no longer hide the original block — it stays interactive throughout.
        let previewTaskID: UUID? = activeDragTaskID ?? dropPreviewTaskID
        let previewTask = allTasks.first(where: { $0.id == previewTaskID })
        let previewLayout = layouts.first(where: { $0.task.id == previewTaskID })

        ZStack(alignment: .topLeading) {
            Color.clear
                .background(isDropTargeted && dropPreviewTaskID == nil ? Theme.blue.opacity(0.06) : Color.clear)
                .contentShape(Rectangle())
                .frame(width: width, height: metrics.totalHeight)
                .onTapGesture {
                    clearDraftCreation()
                    selectedTaskID = nil
                    activeDragTaskID = nil
                }
                .onDrop(
                    of: [UTType.text.identifier],
                    delegate: TimelineDropDelegate(
                        metrics: metrics,
                        allTasks: allTasks,
                        onDropTaskAtMinute: onDropTaskAtMinute,
                        isTargeted: $isDropTargeted,
                        previewTaskID: $dropPreviewTaskID,
                        previewStartMin: $dropPreviewStartMin,
                        activeDragTaskID: $activeDragTaskID,
                        selectedTaskID: $selectedTaskID,
                        dragYOffset: $dragYOffset
                    )
                )

            let taskFrames = layouts.map { layout in
                computeTimelineBlockFrame(
                    startMinute: layout.task.scheduledStartMin,
                    durationMinutes: layout.task.estimatedMinutes,
                    column: layout.column,
                    totalColumns: layout.totalColumns,
                    totalWidth: width,
                    metrics: metrics,
                    style: style
                )
            }

            VStack(spacing: 0) {
                ForEach(metrics.startHour..<metrics.endHour, id: \.self) { hour in
                    TimelineCreateRow(
                        hour: hour,
                        metrics: metrics,
                        taskFrames: taskFrames,
                        activeDragTaskID: $activeDragTaskID,
                        onTapBackground: {
                            clearDraftCreation()
                            selectedTaskID = nil
                            activeDragTaskID = nil
                        },
                        onDragChanged: { startMin, endMin in
                            showNewTaskPopover = false
                            pendingStartMin = nil
                            pendingEndMin = nil
                            newTaskTitle = ""
                            selectedTaskID = nil
                            if dragStartMin == nil { dragStartMin = startMin }
                            dragEndMin = max(endMin, (dragStartMin ?? 0) + 5)
                        },
                        onDragEnded: { startMin, endMin in
                            let actualStart = dragStartMin ?? startMin
                            let actualEnd = max(endMin, actualStart + 5)
                            pendingStartMin = actualStart
                            pendingEndMin = actualEnd
                            newTaskTitle = ""
                            showNewTaskPopover = true
                            dragStartMin = nil
                            dragEndMin = nil
                        }
                    )
                }
            }

            let ghostS = dragStartMin ?? pendingStartMin
            let ghostE = dragEndMin ?? pendingEndMin
            if let s = ghostS, let e = ghostE, e > s {
                let y = metrics.yOffset(for: s)
                let h = metrics.height(for: e - s, minHeight: style.minHeight)
                let ghostWidth = max(0, width - style.leadingInset - style.trailingInset)

                // Visual ghost — .offset() positions correctly without affecting layout size
                RoundedRectangle(cornerRadius: style.cornerRadius)
                    .fill(Theme.blue.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: style.cornerRadius)
                            .stroke(Theme.blue.opacity(0.55), lineWidth: 1)
                    )
                    .frame(width: ghostWidth, height: h)
                    .offset(x: style.leadingInset, y: y)
                    .allowsHitTesting(false)

                // Popover anchor — padding moves actual layout position so popover opens at the right spot
                // Note: onCreate/onCancel read pendingStartMin/pendingEndMin directly (not captured s/e)
                // to avoid stale closure captures if SwiftUI caches popover content.
                Color.clear
                    .frame(width: ghostWidth, height: h)
                    .popover(
                        isPresented: $showNewTaskPopover,
                        attachmentAnchor: .rect(.bounds),
                        arrowEdge: .trailing
                    ) {
                        QuickCreatePopover(
                            title: $newTaskTitle,
                            startMin: s,
                            endMin: e,
                            todayKey: dateKey,
                            onCreate: { title in
                                if let start = pendingStartMin, let end = pendingEndMin {
                                    onCreateTask(title.isEmpty ? "New Task" : title, start, end)
                                }
                                showNewTaskPopover = false
                                pendingStartMin = nil
                                pendingEndMin = nil
                                newTaskTitle = ""
                            },
                            onCancel: {
                                showNewTaskPopover = false
                                pendingStartMin = nil
                                pendingEndMin = nil
                                newTaskTitle = ""
                            }
                        )
                    }
                    .onChange(of: showNewTaskPopover) { _, isPresented in
                        if !isPresented && pendingStartMin != nil {
                            clearDraftCreation()
                        }
                    }
                    .padding(.top, y)
                    .padding(.leading, style.leadingInset)
            }

            if isDropTargeted, let previewTask, let previewLayout, let previewStartMin = dropPreviewStartMin {
                TimelineDraggedTaskPreview(
                    task: previewTask,
                    startMinute: previewStartMin,
                    durationMinutes: previewTask.estimatedMinutes > 0 ? previewTask.estimatedMinutes : 60,
                    column: previewLayout.column,
                    totalColumns: previewLayout.totalColumns,
                    totalWidth: width,
                    metrics: metrics,
                    style: style
                )
                .zIndex(3)
            }

            ForEach(layouts, id: \.task.id) { layout in
                TimelineTaskBlock(
                    task: layout.task,
                    column: layout.column,
                    totalColumns: layout.totalColumns,
                    totalWidth: width,
                    metrics: metrics,
                    style: style,
                    selectedTaskID: $selectedTaskID,
                    activeDragTaskID: $activeDragTaskID,
                    onSelect: clearDraftCreation
                )
                .zIndex(2)
            }

            TimelineCurrentTimeOverlay(
                date: date,
                totalWidth: width,
                metrics: metrics,
                style: style,
                showDot: showCurrentTimeDot
            )
            .zIndex(1)
        }
        .frame(width: width, height: metrics.totalHeight)
    }
}

private struct TimelineCreateRow: View {
    let hour: Int
    let metrics: TimelineMetrics
    let taskFrames: [TimelineBlockFrame]
    @Binding var activeDragTaskID: UUID?
    let onTapBackground: () -> Void
    let onDragChanged: (Int, Int) -> Void
    let onDragEnded: (Int, Int) -> Void

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(maxWidth: .infinity)
            .frame(height: metrics.hourHeight)
            .overlay(alignment: .top) {
                Divider().background(Theme.borderSubtle.opacity(0.5))
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTapBackground)
            .gesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .local)
                    .onChanged { value in
                        guard activeDragTaskID == nil else { return }
                        let absY = absoluteY(forLocalY: value.startLocation.y)
                        guard !isInsideTaskBlock(y: absY) else { return }
                        onDragChanged(
                            absoluteMinute(forLocalY: value.startLocation.y),
                            absoluteMinute(forLocalY: value.location.y)
                        )
                    }
                    .onEnded { value in
                        guard activeDragTaskID == nil else { return }
                        let absY = absoluteY(forLocalY: value.startLocation.y)
                        guard !isInsideTaskBlock(y: absY) else { return }
                        onDragEnded(
                            absoluteMinute(forLocalY: value.startLocation.y),
                            absoluteMinute(forLocalY: value.location.y)
                        )
                    }
            )
    }

    private func absoluteY(forLocalY y: CGFloat) -> CGFloat {
        CGFloat(hour - metrics.startHour) * metrics.hourHeight + y
    }

    private func absoluteMinute(forLocalY y: CGFloat) -> Int {
        metrics.snappedMinute(fromY: absoluteY(forLocalY: y))
    }

    private func isInsideTaskBlock(y: CGFloat) -> Bool {
        taskFrames.contains { frame in
            y >= frame.y && y <= frame.y + frame.height
        }
    }
}

private struct TimelineDropDelegate: DropDelegate {
    let metrics: TimelineMetrics
    let allTasks: [AppTask]
    let onDropTaskAtMinute: (AppTask, Int) -> Void

    @Binding var isTargeted: Bool
    @Binding var previewTaskID: UUID?
    @Binding var previewStartMin: Int?
    @Binding var activeDragTaskID: UUID?
    @Binding var selectedTaskID: UUID?
    @Binding var dragYOffset: CGFloat

    func validateDrop(info: DropInfo) -> Bool {
        !info.itemProviders(for: [UTType.text]).isEmpty
    }

    func dropEntered(info: DropInfo) {
        isTargeted = true
        // Compute where within the card the user grabbed it (for within-canvas drags)
        if let taskID = activeDragTaskID,
           let task = allTasks.first(where: { $0.id == taskID }) {
            let taskTopY = metrics.yOffset(for: task.scheduledStartMin)
            dragYOffset = info.location.y - taskTopY
        } else {
            dragYOffset = 0
        }
        updatePreview(with: info)
        resolveTaskID(from: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard isTargeted else { return DropProposal(operation: .cancel) }
        updatePreview(with: info)
        resolveTaskID(from: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
        previewTaskID = nil
        previewStartMin = nil
        activeDragTaskID = nil
        dragYOffset = 0
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        let startMin = previewStartMin ?? metrics.snappedMinute(fromY: info.location.y - dragYOffset)

        // Clear all drag/preview/selection state immediately so the block reappears right away
        previewTaskID = nil
        previewStartMin = nil
        activeDragTaskID = nil
        selectedTaskID = nil
        dragYOffset = 0

        guard let provider = info.itemProviders(for: [UTType.text]).first else {
            return false
        }

        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let uuidString = object as? NSString,
                  let uuid = UUID(uuidString: uuidString as String) else { return }

            Task { @MainActor in
                guard let task = allTasks.first(where: { $0.id == uuid }) else { return }
                onDropTaskAtMinute(task, startMin)
            }
        }
        return true
    }

    private func updatePreview(with info: DropInfo) {
        previewStartMin = metrics.snappedMinute(fromY: info.location.y - dragYOffset)
    }

    private func resolveTaskID(from info: DropInfo) {
        guard previewTaskID == nil,
              let provider = info.itemProviders(for: [UTType.text]).first else { return }

        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let uuidString = object as? NSString,
                  let uuid = UUID(uuidString: uuidString as String) else { return }

            Task { @MainActor in
                guard isTargeted else { return }  // Drop already completed — discard stale result
                previewTaskID = uuid
            }
        }
    }
}

@ViewBuilder
private func timelineBlockBody(
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

private func timelineDragPreview(task: AppTask, style: TimelineBlockStyle) -> some View {
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
