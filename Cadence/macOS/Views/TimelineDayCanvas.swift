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
    var todayKey: String = DateFormatters.todayKey()
    let tasks: [AppTask]
    let allTasks: [AppTask]
    let areas: [Area]
    let projects: [Project]
    let metrics: TimelineMetrics
    let width: CGFloat
    let style: TimelineBlockStyle
    let showCurrentTimeDot: Bool
    var showHalfHourMarks: Bool = false
    var showWorkHoursHighlight = false
    var usesTaskPanelForTaskCreation = true
    let onCreateTask: (QuickCreateTaskDraft) -> Void
    let onDropTaskAtMinute: (AppTask, Int) -> Void
    var externalEvents: [CalendarEventItem] = []
    /// Optional: if provided, the drag-to-create popover will offer a "Calendar Event" tab.
    ///
    /// It answers with the typed `CalendarWriteFailure?` rather than `Void` (T-658). The narrowing
    /// to `Void` happened here: `CalendarManager.createStandaloneEvent` has returned a cause since
    /// T-339, the hosts threw it away on the way in, and this canvas then dismissed the popover the
    /// user had typed the event into whatever the store answered.
    var onCreateEvent: ((String, Int, Int, String, String) -> CalendarWriteFailure?)? = nil
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
    @State private var selectedEventID: String? = nil
    @State private var activeDragTaskID: UUID? = nil
    @State private var dragYOffset: CGFloat = 0
    @AppStorage(CalendarWorkHoursPreferences.startMinuteKey) private var workHoursStartMinute = CalendarWorkHoursPreferences.defaultStartMinute
    @AppStorage(CalendarWorkHoursPreferences.endMinuteKey) private var workHoursEndMinute = CalendarWorkHoursPreferences.defaultEndMinute
    @Environment(\.modelContext) private var modelContext
    @Environment(CalendarManager.self) private var calendarManager
    @State private var eventCreateFailureNotice: String?

    private func clearDraftCreation() {
        TimelineDayCanvasStateSupport.clearDraftCreation(
            draft: &draftSelection,
            showNewTaskPopover: &showNewTaskPopover,
            selectedEventID: &selectedEventID
        )
    }

    var body: some View {
        let unified = computeUnifiedLayouts(
            tasks: tasks,
            events: externalEvents,
            cascadeGapMinutes: cascadeGapMinutes
        )
        let layouts = unified.tasks
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
                    onDropTaskAtMinute: onDropTaskAtMinute,
                    onDropAllDayEventAtMinute: onDropAllDayEventAtMinute,
                    // [[T-3170]]: no task block draws a bundle shelf any more, so no region of
                    // the canvas defers a task drop to one — and the delegate's parameter for
                    // those rects is gone with them, now the grant has let that file go.
                    isTargeted: $isDropTargeted,
                    previewTaskID: $dropPreviewTaskID,
                    previewStartMin: $dropPreviewStartMin,
                    activeDragTaskID: $activeDragTaskID,
                    selectedTaskID: $selectedTaskID,
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
                blockedFrames: blockedFrames(layouts: layouts, eventLayouts: eventLayouts),
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
                todayKey: todayKey,
                eventLayouts: eventLayouts,
                taskLayouts: layouts,
                allTasks: allTasks,
                areas: areas,
                projects: projects,
                width: width,
                metrics: metrics,
                style: style,
                selectedTaskID: $selectedTaskID,
                selectedEventID: $selectedEventID,
                activeDragTaskID: $activeDragTaskID,
                onTaskSelected: selectTaskBlock
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
        // T-1844: the rectangle the drag-to-create gesture is measured in, named so a UI test can
        // derive its press-and-drag from a LIVE frame rather than from a normalized guess at where
        // the pane sits. Keyed by the day, because the calendar's timeline draws seven of these
        // side by side and the one with no seeded block on it is the one a draft can be made in.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(CadenceAccessibilityIdentifiers.timelineDayCanvas(dateKey: dateKey))
    }

    private func resetCanvasSelection() {
        TimelineDayCanvasStateSupport.resetCanvasSelection(
            selectedTaskID: &selectedTaskID,
            selectedEventID: &selectedEventID,
            activeDragTaskID: &activeDragTaskID,
            draft: &draftSelection,
            showNewTaskPopover: &showNewTaskPopover
        )
    }

    private func clearCreateGridSelection() {
        clearDraftCreation()
        selectedTaskID = nil
        activeDragTaskID = nil
    }

    private func beginDraftSelection(startMin: Int, endMin: Int) {
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
    }

    private func finishDraftCreation() {
        showNewTaskPopover = false
        draftSelection = nil
        eventCreateFailureNotice = nil
    }

    /// `start`/`end` are the range the ghost is drawing and the popover is anchored to — the
    /// **seed**, and nothing more.
    ///
    /// **Neither closure supplies the slot any more** ([[T-3171]]'s seventh adoption slice; the
    /// Task half since T-1433). The popover is `CadenceSchedulePanel` now and its Start and End
    /// rollers move the range for both kinds, so what the user confirmed travels back in the
    /// closure arguments and reading `start`/`end` here would be the displays-one-makes-another
    /// split this comment has warned about since the Event closure shadowed its own parameters.
    private func quickCreatePopover(start: Int, end: Int) -> AnyView {
        AnyView(
            QuickCreateChoicePopover(
                startMin: start,
                endMin: end,
                dateKey: dateKey,
                // **T-688.** The fallback here is *stored*, not drawn. Both hosts of this canvas
                // take the string as a task's actual name: the Calendar page hands it straight to
                // `SchedulingActions.insertTask`, and `SchedulePanel` seeds the create sheet's
                // title field with it, where confirming without typing stores it unchanged. It
                // read `"New Task"`, which `CadenceEventTitleSupport`'s own header already argues
                // against for the sibling case — `"New Event"` was retired for `"Untitled Event"`
                // because a thing created last year is not new but is still untitled — and the
                // argument is stronger for a stored name than for a drawn one. It now reads the
                // shared task placeholder, the same word every other task surface shows.
                // [[T-609]] left it deliberately, under a "route through the trim, change no copy"
                // rule that has since expired.
                onCreateTask: { draft in
                    var resolved = draft
                    resolved.title = TaskTitleSupport.displayTitle(draft.title, fallback: TaskTitleSupport.defaultDisplayTitle)
                    onCreateTask(resolved)
                    finishDraftCreation()
                },
                onCreateEvent: onCreateEvent == nil ? nil : { title, startMin, endMin, calendarID, notes in
                    let failure = onCreateEvent?(
                        CadenceEventTitleSupport.storedTitle(title),
                        startMin,
                        endMin,
                        calendarID,
                        notes
                    ) ?? nil
                    calendarManager.report(
                        CadenceCalendarEventEditingSupport.saveOutcome(for: failure),
                        into: $eventCreateFailureNotice
                    ) { finishDraftCreation() }
                },
                onCancel: finishDraftCreation,
                createFailureNotice: $eventCreateFailureNotice,
                usesTaskPanelForTaskCreation: usesTaskPanelForTaskCreation,
                defaultsToCalendarEvent: prefersCalendarEventCreation
            )
        )
    }

    private func blockedFrames(
        layouts: [TimelineBlockLayout],
        eventLayouts: [TimelineEventLayout]
    ) -> [TimelineBlockFrame] {
        layouts.map { layout in
            timelineFrame(
                startMinute: layout.task.scheduledStartMin,
                durationMinutes: layout.task.timelineDurationMinutes,
                column: layout.column,
                totalColumns: layout.totalColumns
            )
        } + eventLayouts.map { layout in
            // `cascadeDepth` is passed, not dropped. These rects are what the drag-to-create layer
            // treats as occupied, and an event drawn indented at depth 2 occupies a *narrower*
            // rect than its column — without the depth the canvas would refuse a drag in a strip
            // the user can see is empty (T-3161).
            timelineFrame(
                startMinute: layout.item.startMin,
                durationMinutes: layout.item.durationMinutes,
                column: layout.column,
                totalColumns: layout.totalColumns,
                cascadeDepth: layout.cascadeDepth
            )
        }
    }

    /// Start-gap, in minutes, at which an event may be drawn over an event it overlaps.
    ///
    /// The event block's own header height divided by this canvas's points-per-minute — so it
    /// follows the zoom control without anyone having to remember that it should. See
    /// `CadenceCalendarOverlapLayout`.
    private var cascadeGapMinutes: Int {
        CadenceCalendarOverlapLayout.cascadeGapMinutes(
            headerHeight: CadenceCalendarOverlapLayout.macEventHeaderHeight(
                verticalPadding: style.verticalPadding
            ),
            hourHeight: metrics.hourHeight
        )
    }

    private func timelineFrame(
        startMinute: Int,
        durationMinutes: Int,
        column: Int,
        totalColumns: Int,
        cascadeDepth: Int = 0
    ) -> TimelineBlockFrame {
        computeTimelineBlockFrame(
            startMinute: startMinute,
            durationMinutes: durationMinutes,
            column: column,
            totalColumns: totalColumns,
            cascadeDepth: cascadeDepth,
            totalWidth: width,
            metrics: metrics,
            style: style
        )
    }
}
#endif
