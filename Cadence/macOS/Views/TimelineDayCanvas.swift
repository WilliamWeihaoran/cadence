#if os(macOS)
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TimelineDayCanvas: View {
    /// The canvas's own coordinate space. Every gesture that needs a canvas Y reads this rather
    /// than reconstructing one from a subview's local space.
    static let coordinateSpaceName = "timelineCanvas"

    let date: Date
    let dateKey: String
    let tasks: [AppTask]
    let bundles: [TaskBundle]
    let allTasks: [AppTask]
    let allBundles: [TaskBundle]
    let areas: [Area]
    let projects: [Project]
    let metrics: TimelineMetrics
    let width: CGFloat
    let style: TimelineBlockStyle
    let showCurrentTimeDot: Bool
    var showHalfHourMarks: Bool = false
    var showWorkHoursHighlight = false
    var usesTaskPanelForTaskCreation = true
    let onCreateTask: (String, Int, Int, TaskContainerSelection, String, String, [String]) -> Void
    let onCreateBundle: (String, Int, Int, [AppTask]) -> Void
    let onDropTaskAtMinute: (AppTask, Int) -> Void
    let onDropBundleAtMinute: (TaskBundle, Int) -> Void
    let onDropTaskOnBundle: (AppTask, TaskBundle) -> Void
    var externalEvents: [CalendarEventItem] = []
    /// Optional: if provided, the drag-to-create popover will offer a "Calendar Event" tab.
    var onCreateEvent: ((String, Int, Int, String, String) -> Void)? = nil
    /// Calendar pages should treat dragged time slots as events first; task timelines keep time blocks first.
    var prefersCalendarEventCreation = false
    /// Optional: called when an all-day event chip is dropped onto the timeline, with the event identifier and target minute.
    var onDropAllDayEventAtMinute: ((CalendarAllDayEventDropPayload, Int) -> Void)? = nil

    @State private var draftSelection: TimelineDraftSelection? = nil
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
    @AppStorage(CalendarWorkHoursPreferences.startMinuteKey) private var workHoursStartMinute = CalendarWorkHoursPreferences.defaultStartMinute
    @AppStorage(CalendarWorkHoursPreferences.endMinuteKey) private var workHoursEndMinute = CalendarWorkHoursPreferences.defaultEndMinute
    @Environment(\.modelContext) private var modelContext

    private func clearDraftCreation() {
        TimelineDayCanvasStateSupport.clearDraftCreation(
            draft: &draftSelection,
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
                    bundleShelfFrames: bundleShelfFrames(layouts: layouts),
                    isTargeted: $isDropTargeted,
                    previewTaskID: $dropPreviewTaskID,
                    previewStartMin: $dropPreviewStartMin,
                    activeDragTaskID: $activeDragTaskID,
                    activeDragBundleID: $activeDragBundleID,
                    selectedTaskID: $selectedTaskID,
                    selectedBundleID: $selectedBundleID,
                    dragYOffset: $dragYOffset
                ),
                onTap: resetCanvasSelection
            )

            if showWorkHoursHighlight && CalendarWorkHoursPreferences.shouldShowHighlight(on: date) {
                TimelineWorkHoursHighlightLayer(
                    width: width,
                    metrics: metrics,
                    startMinute: workHoursStartMinute,
                    endMinute: workHoursEndMinute
                )
            }

            TimelineCreateGridLayer(
                metrics: metrics,
                blockedFrames: blockedFrames(layouts: layouts, bundleLayouts: bundleLayouts, eventLayouts: eventLayouts),
                showHalfHourMarks: showHalfHourMarks,
                activeDragTaskID: $activeDragTaskID,
                onTapBackground: clearCreateGridSelection,
                onDragChanged: beginDraftSelection,
                onDragEnded: commitDraftSelection
            )

            TimelineDraftCreationOverlay(
                draft: draftSelection,
                width: width,
                metrics: metrics,
                style: style,
                showNewTaskPopover: $showNewTaskPopover,
                onDismissed: {
                    if draftSelection?.isPending == true {
                        clearDraftCreation()
                    }
                }
            ) { start, end in
                quickCreatePopover(start: start, end: end)
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
                areas: areas,
                projects: projects,
                width: width,
                metrics: metrics,
                style: style,
                selectedTaskID: $selectedTaskID,
                selectedBundleID: $selectedBundleID,
                selectedEventID: $selectedEventID,
                activeDragTaskID: $activeDragTaskID,
                activeDragBundleID: $activeDragBundleID,
                onTaskDroppedOnBundle: onDropTaskOnBundle,
                onCreateBundleFromTasks: { targetTask, draggedTask in
                    _ = SchedulingActions.createBundle(from: targetTask, adding: draggedTask, in: modelContext)
                },
                onTaskSelected: selectTaskBlock,
                onBundleSelected: selectBundleBlock
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
        .coordinateSpace(name: Self.coordinateSpaceName)
    }

    private func resetCanvasSelection() {
        TimelineDayCanvasStateSupport.resetCanvasSelection(
            selectedTaskID: &selectedTaskID,
            selectedEventID: &selectedEventID,
            activeDragTaskID: &activeDragTaskID,
            selectedBundleID: &selectedBundleID,
            activeDragBundleID: &activeDragBundleID,
            draft: &draftSelection,
            showNewTaskPopover: &showNewTaskPopover
        )
    }

    private func clearCreateGridSelection() {
        clearDraftCreation()
        selectedTaskID = nil
        selectedBundleID = nil
        activeDragTaskID = nil
        activeDragBundleID = nil
    }

    private func beginDraftSelection(startMin: Int, endMin: Int) {
        selectedBundleID = nil
        activeDragBundleID = nil
        TimelineDayCanvasStateSupport.beginDraftSelection(
            startMin: startMin,
            endMin: endMin,
            draft: &draftSelection,
            showNewTaskPopover: &showNewTaskPopover,
            selectedTaskID: &selectedTaskID
        )
    }

    private func commitDraftSelection(startMin: Int, endMin: Int) {
        TimelineDayCanvasStateSupport.commitDraftSelection(
            startMin: startMin,
            endMin: endMin,
            draft: &draftSelection,
            showNewTaskPopover: &showNewTaskPopover
        )
    }

    private func selectTaskBlock() {
        clearDraftCreation()
        selectedEventID = nil
        selectedBundleID = nil
    }

    private func selectBundleBlock() {
        clearDraftCreation()
        selectedEventID = nil
        selectedTaskID = nil
    }

    private func finishDraftCreation() {
        showNewTaskPopover = false
        draftSelection = nil
    }

    /// `start`/`end` are the range the ghost is drawing and the popover is anchored to. Every
    /// closure below creates *that* range: they used to shadow these parameters and re-read
    /// `pendingStartMin`/`pendingEndMin`, so the popover displayed one range and made another.
    private func quickCreatePopover(start: Int, end: Int) -> AnyView {
        AnyView(
            QuickCreateChoicePopover(
                startMin: start,
                endMin: end,
                dateKey: dateKey,
                onCreateTask: { title, containerSelection, sectionName, notes, subtaskTitles in
                    onCreateTask(
                        title.isEmpty ? "New Task" : title,
                        start,
                        end,
                        containerSelection,
                        sectionName,
                        notes,
                        subtaskTitles
                    )
                    finishDraftCreation()
                },
                onCreateBundle: { title, selectedTasks in
                    onCreateBundle(title.isEmpty ? "Task Bundle" : title, start, end, selectedTasks)
                    finishDraftCreation()
                },
                onCreateEvent: onCreateEvent == nil ? nil : { title, calendarID, notes in
                    onCreateEvent?(title.isEmpty ? "New Event" : title, start, end, calendarID, notes)
                    finishDraftCreation()
                },
                onCancel: finishDraftCreation,
                usesTaskPanelForTaskCreation: usesTaskPanelForTaskCreation,
                defaultsToCalendarEvent: prefersCalendarEventCreation
            )
        )
    }

    /// Shelf rects for the task blocks currently offering to bundle the dragged task. Derived
    /// from the same `TimelineBlockFrame`s the blocks are drawn from, so the region the canvas
    /// defers on is exactly the region the shelf draws.
    private func bundleShelfFrames(layouts: [TimelineBlockLayout]) -> [TimelineBlockFrame] {
        guard let draggedTaskID = activeDragTaskID else { return [] }
        return layouts.compactMap { layout in
            guard layout.task.id != draggedTaskID else { return nil }
            return TimelineMetricsSupport.bundleDropShelfFrame(
                blockFrame: timelineFrame(
                    startMinute: layout.task.scheduledStartMin,
                    durationMinutes: layout.task.timelineDurationMinutes,
                    column: layout.column,
                    totalColumns: layout.totalColumns
                )
            )
        }
    }

    private func blockedFrames(
        layouts: [TimelineBlockLayout],
        bundleLayouts: [TimelineBundleLayout],
        eventLayouts: [TimelineEventLayout]
    ) -> [TimelineBlockFrame] {
        layouts.map { layout in
            timelineFrame(
                startMinute: layout.task.scheduledStartMin,
                durationMinutes: layout.task.timelineDurationMinutes,
                column: layout.column,
                totalColumns: layout.totalColumns
            )
        } + bundleLayouts.map { layout in
            timelineFrame(
                startMinute: layout.bundle.startMin,
                durationMinutes: layout.bundle.durationMinutes,
                column: layout.column,
                totalColumns: layout.totalColumns
            )
        } + eventLayouts.map { layout in
            timelineFrame(
                startMinute: layout.item.startMin,
                durationMinutes: layout.item.durationMinutes,
                column: layout.column,
                totalColumns: layout.totalColumns
            )
        }
    }

    private func timelineFrame(
        startMinute: Int,
        durationMinutes: Int,
        column: Int,
        totalColumns: Int
    ) -> TimelineBlockFrame {
        computeTimelineBlockFrame(
            startMinute: startMinute,
            durationMinutes: durationMinutes,
            column: column,
            totalColumns: totalColumns,
            totalWidth: width,
            metrics: metrics,
            style: style
        )
    }
}
#endif
