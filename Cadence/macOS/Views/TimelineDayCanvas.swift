#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

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
    var externalEvents: [CalendarEventItem] = []
    /// Optional: if provided, the drag-to-create popover will offer a "Calendar Event" tab.
    var onCreateEvent: ((String, Int, Int, String, String) -> Void)? = nil

    @State private var dragStartMin: Int? = nil
    @State private var dragEndMin: Int? = nil
    @State private var pendingStartMin: Int? = nil
    @State private var pendingEndMin: Int? = nil
    @State private var showNewTaskPopover = false
    @State private var isDropTargeted = false
    @State private var dropPreviewTaskID: UUID? = nil
    @State private var dropPreviewStartMin: Int? = nil
    @State private var selectedTaskID: UUID? = nil
    @State private var selectedEventID: String? = nil
    @State private var activeDragTaskID: UUID? = nil
    @State private var dragYOffset: CGFloat = 0

    private func clearDraftCreation() {
        dragStartMin = nil
        dragEndMin = nil
        pendingStartMin = nil
        pendingEndMin = nil
        showNewTaskPopover = false
        selectedEventID = nil
    }

    var body: some View {
        let unified = computeUnifiedLayouts(tasks: tasks, events: externalEvents)
        let layouts = unified.tasks
        let eventLayouts = unified.events
        // Show preview for both incoming drops and within-canvas moves.
        // We no longer hide the original block — it stays interactive throughout.
        let previewTaskID: UUID? = activeDragTaskID ?? dropPreviewTaskID
        let previewTask = allTasks.first(where: { $0.id == previewTaskID })

        ZStack(alignment: .topLeading) {
            Color.clear
                .background(isDropTargeted && dropPreviewTaskID == nil ? Theme.blue.opacity(0.06) : Color.clear)
                .contentShape(Rectangle())
                .frame(width: width, height: metrics.totalHeight)
                .onTapGesture {
                    clearDraftCreation()
                    selectedTaskID = nil
                    selectedEventID = nil
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
                            selectedTaskID = nil
                            if dragStartMin == nil { dragStartMin = startMin }
                            dragEndMin = max(endMin, (dragStartMin ?? 0) + 5)
                        },
                        onDragEnded: { startMin, endMin in
                            let actualStart = dragStartMin ?? startMin
                            let actualEnd = max(endMin, actualStart + 5)
                            pendingStartMin = actualStart
                            pendingEndMin = actualEnd
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
                        QuickCreateChoicePopover(
                            startMin: s,
                            endMin: e,
                            onCreateTask: { title in
                                if let start = pendingStartMin, let end = pendingEndMin {
                                    onCreateTask(title.isEmpty ? "New Task" : title, start, end)
                                }
                                showNewTaskPopover = false
                                pendingStartMin = nil
                                pendingEndMin = nil
                            },
                            onCreateEvent: onCreateEvent == nil ? nil : { title, calendarID, notes in
                                if let start = pendingStartMin, let end = pendingEndMin {
                                    onCreateEvent?(title.isEmpty ? "New Event" : title, start, end, calendarID, notes)
                                }
                                showNewTaskPopover = false
                                pendingStartMin = nil
                                pendingEndMin = nil
                            },
                            onCancel: {
                                showNewTaskPopover = false
                                pendingStartMin = nil
                                pendingEndMin = nil
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

            if isDropTargeted, let previewTask, let previewStartMin = dropPreviewStartMin {
                let previewLayout = layouts.first(where: { $0.task.id == previewTask.id })
                TimelineDraggedTaskPreview(
                    task: previewTask,
                    startMinute: previewStartMin,
                    durationMinutes: previewTask.estimatedMinutes > 0 ? previewTask.estimatedMinutes : 60,
                    column: previewLayout?.column ?? 0,
                    totalColumns: previewLayout?.totalColumns ?? 1,
                    totalWidth: width,
                    metrics: metrics,
                    style: style
                )
                .zIndex(3)
            }

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
                    onSelect: { clearDraftCreation(); selectedEventID = nil }
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
            .zIndex(10)
        }
        .frame(width: width, height: metrics.totalHeight)
        .coordinateSpace(name: "timelineCanvas")
    }
}

// MARK: - Create Row

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

// MARK: - Drop Delegate

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
            guard let payload = object as? NSString,
                  let uuid = taskID(from: payload as String) else { return }

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
            guard let payload = object as? NSString,
                  let uuid = taskID(from: payload as String) else { return }

            Task { @MainActor in
                guard isTargeted else { return }  // Drop already completed — discard stale result
                previewTaskID = uuid
            }
        }
    }

    private func taskID(from payload: String) -> UUID? {
        if payload.hasPrefix("listTask:") {
            return UUID(uuidString: String(payload.dropFirst(9)))
        }
        return UUID(uuidString: payload)
    }
}
#endif
