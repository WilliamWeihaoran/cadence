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
    /// Optional: called when an all-day event chip is dropped onto the timeline, with the event identifier and target minute.
    var onDropAllDayEventAtMinute: ((String, Int) -> Void)? = nil

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
        TimelineDayCanvasStateSupport.clearDraftCreation(
            dragStartMin: &dragStartMin,
            dragEndMin: &dragEndMin,
            pendingStartMin: &pendingStartMin,
            pendingEndMin: &pendingEndMin,
            showNewTaskPopover: &showNewTaskPopover,
            selectedEventID: &selectedEventID
        )
    }

    var body: some View {
        let unified = computeUnifiedLayouts(tasks: tasks, events: externalEvents)
        let layouts = unified.tasks
        let eventLayouts = unified.events
        let previewTask = TimelineDayCanvasOverlaySupport.previewTask(
            activeDragTaskID: activeDragTaskID,
            dropPreviewTaskID: dropPreviewTaskID,
            allTasks: allTasks
        )
        let ghostRange = TimelineDayCanvasOverlaySupport.ghostRange(
            dragStartMin: dragStartMin,
            dragEndMin: dragEndMin,
            pendingStartMin: pendingStartMin,
            pendingEndMin: pendingEndMin
        )

        ZStack(alignment: .topLeading) {
            TimelineCanvasDropSurface(
                width: width,
                totalHeight: metrics.totalHeight,
                isDropTargeted: isDropTargeted,
                hasPreviewTask: dropPreviewTaskID != nil,
                dropDelegate: TimelineDropDelegate(
                    metrics: metrics,
                    allTasks: allTasks,
                    onDropTaskAtMinute: onDropTaskAtMinute,
                    onDropAllDayEventAtMinute: onDropAllDayEventAtMinute,
                    isTargeted: $isDropTargeted,
                    previewTaskID: $dropPreviewTaskID,
                    previewStartMin: $dropPreviewStartMin,
                    activeDragTaskID: $activeDragTaskID,
                    selectedTaskID: $selectedTaskID,
                    dragYOffset: $dragYOffset
                ),
                onTap: {
                    TimelineDayCanvasStateSupport.resetCanvasSelection(
                        selectedTaskID: &selectedTaskID,
                        selectedEventID: &selectedEventID,
                        activeDragTaskID: &activeDragTaskID,
                        dragStartMin: &dragStartMin,
                        dragEndMin: &dragEndMin,
                        pendingStartMin: &pendingStartMin,
                        pendingEndMin: &pendingEndMin,
                        showNewTaskPopover: &showNewTaskPopover
                    )
                }
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

            TimelineCreateGridLayer(
                metrics: metrics,
                taskFrames: taskFrames,
                activeDragTaskID: $activeDragTaskID,
                onTapBackground: {
                    clearDraftCreation()
                    selectedTaskID = nil
                    activeDragTaskID = nil
                },
                onDragChanged: { startMin, endMin in
                    TimelineDayCanvasStateSupport.beginDraftSelection(
                        startMin: startMin,
                        endMin: endMin,
                        dragStartMin: &dragStartMin,
                        dragEndMin: &dragEndMin,
                        pendingStartMin: &pendingStartMin,
                        pendingEndMin: &pendingEndMin,
                        showNewTaskPopover: &showNewTaskPopover,
                        selectedTaskID: &selectedTaskID
                    )
                },
                onDragEnded: { startMin, endMin in
                    TimelineDayCanvasStateSupport.commitDraftSelection(
                        startMin: startMin,
                        endMin: endMin,
                        dragStartMin: &dragStartMin,
                        dragEndMin: &dragEndMin,
                        pendingStartMin: &pendingStartMin,
                        pendingEndMin: &pendingEndMin,
                        showNewTaskPopover: &showNewTaskPopover
                    )
                }
            )

            TimelineDraftCreationOverlay(
                ghostRange: ghostRange,
                width: width,
                metrics: metrics,
                style: style,
                showNewTaskPopover: $showNewTaskPopover,
                onDismissed: {
                    if pendingStartMin != nil {
                        clearDraftCreation()
                    }
                }
            ) { start, end in
                AnyView(
                    QuickCreateChoicePopover(
                        startMin: start,
                        endMin: end,
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
                )
            }

            TimelineDropPreviewOverlay(
                isDropTargeted: isDropTargeted,
                previewTask: previewTask,
                dropPreviewStartMin: dropPreviewStartMin,
                layouts: layouts,
                width: width,
                metrics: metrics,
                style: style
            )

            TimelineScheduledBlocksLayer(
                eventLayouts: eventLayouts,
                taskLayouts: layouts,
                width: width,
                metrics: metrics,
                style: style,
                selectedTaskID: $selectedTaskID,
                selectedEventID: $selectedEventID,
                activeDragTaskID: $activeDragTaskID,
                onTaskSelected: {
                    clearDraftCreation()
                    selectedEventID = nil
                }
            )

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
#endif
