#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

struct TimelineDayCanvas: View {
    let date: Date
    let dateKey: String
    let tasks: [AppTask]
    let bundles: [TaskBundle]
    let allTasks: [AppTask]
    let allBundles: [TaskBundle]
    let metrics: TimelineMetrics
    let width: CGFloat
    let style: TimelineBlockStyle
    let showCurrentTimeDot: Bool
    var showHalfHourMarks: Bool = false
    let dropBehavior: TimelineDropBehavior
    let onCreateTask: (String, Int, Int, TaskContainerSelection, String) -> Void
    let onCreateBundle: (String, Int, Int) -> Void
    let onDropTaskAtMinute: (AppTask, Int) -> Void
    let onDropBundleAtMinute: (TaskBundle, Int) -> Void
    let onDropTaskOnBundle: (AppTask, TaskBundle) -> Void
    var externalEvents: [CalendarEventItem] = []
    /// Optional: if provided, the drag-to-create popover will offer a "Calendar Event" tab.
    var onCreateEvent: ((String, Int, Int, String, String) -> Void)? = nil
    /// Calendar pages should treat dragged time slots as events first; task timelines keep time blocks first.
    var prefersCalendarEventCreation = false
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
    @State private var selectedBundleID: UUID? = nil
    @State private var selectedEventID: String? = nil
    @State private var activeDragTaskID: UUID? = nil
    @State private var activeDragBundleID: UUID? = nil
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
        let unified = computeUnifiedLayouts(tasks: tasks, bundles: bundles, events: externalEvents)
        let layouts = unified.tasks
        let bundleLayouts = unified.bundles
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
                    allBundles: allBundles,
                    onDropTaskAtMinute: onDropTaskAtMinute,
                    onDropBundleAtMinute: onDropBundleAtMinute,
                    onDropAllDayEventAtMinute: onDropAllDayEventAtMinute,
                    isTargeted: $isDropTargeted,
                    previewTaskID: $dropPreviewTaskID,
                    previewStartMin: $dropPreviewStartMin,
                    activeDragTaskID: $activeDragTaskID,
                    activeDragBundleID: $activeDragBundleID,
                    selectedTaskID: $selectedTaskID,
                    selectedBundleID: $selectedBundleID,
                    dragYOffset: $dragYOffset
                ),
                onTap: {
                    TimelineDayCanvasStateSupport.resetCanvasSelection(
                        selectedTaskID: &selectedTaskID,
                        selectedEventID: &selectedEventID,
                        activeDragTaskID: &activeDragTaskID,
                        selectedBundleID: &selectedBundleID,
                        activeDragBundleID: &activeDragBundleID,
                        dragStartMin: &dragStartMin,
                        dragEndMin: &dragEndMin,
                        pendingStartMin: &pendingStartMin,
                        pendingEndMin: &pendingEndMin,
                        showNewTaskPopover: &showNewTaskPopover
                    )
                }
            )

            let blockedFrames = layouts.map { layout in
                computeTimelineBlockFrame(
                    startMinute: layout.task.scheduledStartMin,
                    durationMinutes: layout.task.estimatedMinutes,
                    column: layout.column,
                    totalColumns: layout.totalColumns,
                    totalWidth: width,
                    metrics: metrics,
                    style: style
                )
            } + bundleLayouts.map { layout in
                computeTimelineBlockFrame(
                    startMinute: layout.bundle.startMin,
                    durationMinutes: layout.bundle.durationMinutes,
                    column: layout.column,
                    totalColumns: layout.totalColumns,
                    totalWidth: width,
                    metrics: metrics,
                    style: style
                )
            } + eventLayouts.map { layout in
                computeTimelineBlockFrame(
                    startMinute: layout.item.startMin,
                    durationMinutes: layout.item.durationMinutes,
                    column: layout.column,
                    totalColumns: layout.totalColumns,
                    totalWidth: width,
                    metrics: metrics,
                    style: style
                )
            }

            TimelineCreateGridLayer(
                metrics: metrics,
                blockedFrames: blockedFrames,
                showHalfHourMarks: showHalfHourMarks,
                activeDragTaskID: $activeDragTaskID,
                onTapBackground: {
                    clearDraftCreation()
                    selectedTaskID = nil
                    selectedBundleID = nil
                    activeDragTaskID = nil
                    activeDragBundleID = nil
                },
                onDragChanged: { startMin, endMin in
                    selectedBundleID = nil
                    activeDragBundleID = nil
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
                        onCreateTask: { title, containerSelection, sectionName in
                            if let start = pendingStartMin, let end = pendingEndMin {
                                onCreateTask(
                                    title.isEmpty ? "New Task" : title,
                                    start,
                                    end,
                                    containerSelection,
                                    sectionName
                                )
                            }
                            showNewTaskPopover = false
                            pendingStartMin = nil
                            pendingEndMin = nil
                        },
                        onCreateBundle: { title in
                            if let start = pendingStartMin, let end = pendingEndMin {
                                onCreateBundle(title.isEmpty ? "Task Bundle" : title, start, end)
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
                        },
                        defaultsToCalendarEvent: prefersCalendarEventCreation
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
                bundleLayouts: bundleLayouts,
                taskLayouts: layouts,
                allTasks: allTasks,
                width: width,
                metrics: metrics,
                style: style,
                selectedTaskID: $selectedTaskID,
                selectedBundleID: $selectedBundleID,
                selectedEventID: $selectedEventID,
                activeDragTaskID: $activeDragTaskID,
                activeDragBundleID: $activeDragBundleID,
                onTaskDroppedOnBundle: onDropTaskOnBundle,
                onTaskSelected: {
                    clearDraftCreation()
                    selectedEventID = nil
                    selectedBundleID = nil
                },
                onBundleSelected: {
                    clearDraftCreation()
                    selectedEventID = nil
                    selectedTaskID = nil
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
