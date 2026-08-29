#if os(iOS)
import EventKit
import SwiftData
import SwiftUI

struct iOSCalendarView: View {
    /// Set when this is the Calendar tab's root. A pushed Calendar keeps its back chevron; a tab
    /// root has nothing behind it, and a chevron there would be a control that looks tappable and
    /// does nothing.
    var isCompactTabRoot = false
    @Environment(iOSCalendarManager.self) private var calendarManager
    @Environment(CadenceDeepLinkManager.self) private var deepLinkManager
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query private var allBundles: [TaskBundle]
    @AppStorage("ios.calendar.viewMode") private var viewModeRaw = CadenceCalendarViewMode.week.rawValue
    @AppStorage("ios.calendar.presentation") private var presentationRaw = CadenceCalendarPresentation.timeline.rawValue
    /// Continuous now, and a real multiplier of the base hour height. The key is unchanged because
    /// a value the old `− 1x +` control stored is still a legal one — see `CadenceCalendarZoom`.
    @AppStorage(CadenceCalendarZoom.storageKey) private var zoomLevel = CadenceCalendarZoom.defaultZoom
    /// Month's Agenda/Day toggle. Written from a tap on that control and from nowhere else — never
    /// from `paneWidth`, the size class, or anything else the window decides. See
    /// `CadenceCalendarMonthLayout`.
    @AppStorage("ios.calendar.monthDetail") private var monthDetailRaw = CadenceCalendarMonthLayout.defaultDetail.rawValue
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var anchorDate = Calendar.current.startOfDay(for: Date())
    @State private var quickCreateSeed: iOSCalendarQuickCreateSeed?
    @State private var didRestorePersistedDates = false
    /// The fetched events, cached against `eventWindowKey`. See that property for why this is not
    /// computed on demand any more.
    @State private var visibleEventsByDate: [String: [EKEvent]] = [:]
    /// The width of this page, which on iPad is the window less the shell sidebar. See
    /// `hasInspector`.
    @State private var paneWidth: CGFloat = 0
    /// Holds the pending position write. `@State` so it survives a body pass, a plain class so
    /// scheduling a write is not itself a reason to re-render this page.
    @State private var positionWriter = CadenceCalendarDateMemoryWriter()

    private let calendar = Calendar.current
    /// Where the calendar left off. Read once on appear; written once the scroll settles rather
    /// than once per column — see `CadenceCalendarDateMemory` for what the per-column write cost.
    private let dateMemory = CadenceCalendarDateMemory()

    // Read-only, like `monthDetail` below. Both of these used to carry a setter writing the raw
    // value back, and nothing could call it: a `View`'s `body` cannot mutate `self`, and every
    // write here goes through `setViewMode` / `setPresentation`, which do more than store the value.
    // A setter that looks like the write path but is not is how one of those extra steps gets lost.
    private var viewMode: CadenceCalendarViewMode {
        CadenceCalendarViewMode(rawValue: viewModeRaw) ?? .week
    }

    private var presentation: CadenceCalendarPresentation {
        CadenceCalendarPresentation(rawValue: presentationRaw) ?? .timeline
    }

    /// The month the grid is currently reading as, derived from the week row at its top. Month's
    /// `anchorDate` is a scroll position, not a month — see `CadenceCalendarMonthWindow`.
    private var displayedMonth: Date {
        CadenceCalendarMonthWindow.displayedMonth(topRowStart: anchorDate, calendar: calendar)
    }

    private var selectedKey: String {
        DateFormatters.dateKey(from: selectedDate)
    }

    private var scheduledTasksByDate: [String: [AppTask]] {
        CadenceScheduleSupport.tasksByScheduledDate(allTasks, includeCompleted: false)
    }

    private var unscheduledTasksByDate: [String: [AppTask]] {
        CadenceScheduleSupport.unscheduledTasksByDate(allTasks)
    }

    private var monthTasksByDate: [String: [AppTask]] {
        CadenceScheduleSupport.monthTasksByDate(allTasks)
    }

    private var bundlesByDate: [String: [TaskBundle]] {
        CadenceScheduleSupport.bundlesByDate(allBundles, includeCompleted: false)
    }

    /// The days the timed grid holds *event data* for.
    ///
    /// This used to be the grid's contents — `CadenceScheduleSupport.dates(containing:mode:)`, a
    /// week or a fortnight, rebuilt by the toolbar chevrons. The grid builds its own columns now
    /// and scrolls through hundreds of them, so what is left here is only the fetch window: a
    /// week-aligned four-week span around the leading column, which changes identity once a week
    /// rather than once a column. See `CadenceCalendarTimelineWindow.eventWindowDates`.
    private var timelineEventDates: [Date] {
        CadenceCalendarTimelineWindow.eventWindowDates(leadingDate: anchorDate, calendar: calendar)
    }

    private var visibleDayCount: Int {
        CadenceCalendarWeekGridLayout.visibleDayCount(for: viewMode)
    }

    private var selectedTasks: [AppTask] {
        CadenceScheduleSupport.calendarDayTasks(on: selectedKey, from: allTasks)
    }

    private var selectedBundles: [TaskBundle] {
        CadenceScheduleSupport.items(on: selectedKey, in: bundlesByDate)
    }

    private var selectedEvents: [EKEvent] {
        calendarManager.fetchEvents(for: selectedDate)
    }

    private var calendarEventDates: [Date] {
        if presentation == .board {
            return boardEventDates
        }
        if viewMode == .month {
            return CadenceCalendarMonthWindow.eventWindowDates(displayedMonth: displayedMonth, calendar: calendar)
        }
        return timelineEventDates
    }

    /// The identity of the fetch window, for deciding when to re-run it.
    ///
    /// `visibleEventsByDate` used to be a computed property, so every body evaluation of this view
    /// ran one EventKit query per visible day. That was seven queries and survivable while the only
    /// thing that moved the window was a chevron. The timed grid now writes `anchorDate` back on
    /// every column the user scrolls past, so the same computed property would have run its whole
    /// fetch several times a second, on the main thread, mid-gesture. Keying the fetch on a *coarse*
    /// window and caching the result is what makes scrolling free: on the grids the key only changes
    /// when the leading column crosses into another week.
    private var eventWindowKey: String {
        if presentation == .board {
            return "board:\(DateFormatters.dateKey(from: anchorDate))"
        }
        // The month grid scrolls a week row at a time, so keying on the leading row would re-run the
        // fetch every week crossed. `displayedMonth` changes once a month, and the window it fetches
        // is wide enough to cover every row position that reads as that month. Same shape as the
        // timed grids' week-aligned key below.
        if viewMode == .month {
            return "month:\(DateFormatters.monthYear.string(from: displayedMonth))"
        }
        return "timeline:\(DateFormatters.dateKey(from: CadenceCalendarTimelineWindow.eventWindowStart(leadingDate: anchorDate, calendar: calendar)))"
    }

    private var boardEventDates: [Date] {
        (0..<CalendarBoardPlannerSupport.visibleDayCount).map { offset in
            calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: anchorDate) ?? anchorDate)
        }
    }

    private var selectedUnscheduledTasks: [AppTask] {
        CadenceScheduleSupport.items(on: selectedKey, in: unscheduledTasksByDate)
    }

    private var selectedDueOnlyTasks: [AppTask] {
        CadenceScheduleSupport.dueOnlyTasks(on: selectedKey, from: allTasks)
    }

    /// What unit the toolbar's date title reads `anchorDate` in. Month scrolls week rows and is read
    /// a month at a time; every other surface scrolls day columns and is read a day at a time.
    private var titleFormat: CadenceCalendarDateTitleFormat {
        isMonthTimeline ? .month : .day
    }

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    /// Whether this pane carries the day inspector beside the calendar. The rule, and why the Board
    /// is not in it, are in `CadenceCalendarPaneLayout.showsDayInspector`.
    ///
    /// `paneWidth` starts at 0, so the first frame resolves to `false` and the calendar takes the
    /// whole pane until the measurement lands. That is the right way round: a pane that opens
    /// full-width and gains an inspector reads as the inspector arriving, where the reverse reads as
    /// content being taken away.
    private var hasInspector: Bool {
        CadenceCalendarPaneLayout.showsDayInspector(
            isCompact: isCompact,
            presentation: presentation,
            viewMode: viewMode,
            paneWidth: paneWidth
        )
    }

    private var isMonthTimeline: Bool {
        presentation == .timeline && viewMode == .month
    }

    /// Week or 2 Weeks — the two surfaces `iOSCalendarTimelineGrid` draws, and the two that scroll
    /// their own days. What the toolbar shows and what the event window is keyed on both hinge on
    /// this, so it is named once.
    private var isTimedGrid: Bool {
        presentation == .timeline && viewMode != .month
    }

    /// What Month shows beside or under its grid. This used to be `!hasInspector` — the window
    /// deciding which of the two mechanisms you were using, so rotating an 11" iPad swapped the
    /// agenda for the day inspector and back. It is a stored choice now; the width only decides
    /// where that choice is drawn.
    private var monthDetail: CadenceCalendarMonthDetail {
        CadenceCalendarMonthLayout.detail(storedRawValue: monthDetailRaw, isCompact: isCompact)
    }

    /// Beside the grid where the inspector already fits, under it where it does not.
    private var monthPlacement: CadenceCalendarMonthLayout.Placement {
        isCompact ? .below : CadenceCalendarMonthLayout.placement(paneWidth: paneWidth)
    }

    var body: some View {
        VStack(spacing: 0) {
            iOSCalendarToolbar(
                onBack: isCompact && !isCompactTabRoot ? { dismiss() } : nil,
                viewMode: Binding(get: { viewMode }, set: setViewMode),
                presentation: Binding(get: { presentation }, set: setPresentation),
                leadingDate: $anchorDate,
                titleFormat: titleFormat,
                monthDetail: Binding(get: { monthDetail }, set: setMonthDetail),
                showsMonthDetailControl: CadenceCalendarMonthLayout.showsDetailControl(
                    isCompact: isCompact,
                    presentation: presentation,
                    viewMode: viewMode
                )
            )

            if isMonthTimeline {
                // Month splits itself: it has two possible details and two possible placements, and
                // the pane-wide `hasInspector` branch below can express neither.
                monthContent
            } else if hasInspector {
                HStack(spacing: 0) {
                    calendarContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.surface)

                    Divider().background(Theme.borderSubtle)

                    dayInspector
                        .frame(
                            width: CadenceCalendarPaneLayout.inspectorWidth(
                                forPaneWidth: paneWidth,
                                calendarMinimumWidth: CadenceCalendarPaneLayout.calendarMinimumWidth(
                                    for: viewMode
                                )
                            )
                        )
                        .frame(maxHeight: .infinity)
                }
            } else {
                // Every mode fills the pane once there is no inspector taking a third of it.
                calendarContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Measured, not wrapped. A `GeometryReader` around this `VStack` reads the same width, but
        // it also becomes the layout container, and this stack holds scroll views that size
        // themselves from what is left over. Reading the width into state leaves the stack laying
        // itself out exactly as it did before.
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            paneWidth = newWidth
        }
        .background(Theme.bg.ignoresSafeArea())
        .iOSHidesCompactNavigationBar()
        .onAppear(perform: restorePersistedCalendarDates)
        // A calendar link that arrives while this page is already standing. `onAppear` covers the
        // cold-start tap; this covers the warm one, and the token is what makes a *repeat* tap on
        // the same day still count as a new request.
        .onChange(of: deepLinkManager.route?.token) { _, _ in
            applyCalendarDeepLinkDate()
        }
        .onChange(of: eventWindowKey, initial: true) { _, _ in
            refreshVisibleEvents()
        }
        .onChange(of: calendarManager.storeVersion) { _, _ in
            refreshVisibleEvents()
        }
        .onChange(of: selectedDate) { _, _ in
            rememberCalendarPosition()
        }
        .onChange(of: anchorDate) { _, _ in
            keepSelectedDateInView()
            rememberCalendarPosition()
        }
        // The two ways the settle never arrives: the page goes away, or the app does.
        .onDisappear(perform: flushCalendarPosition)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { flushCalendarPosition() }
        }
        .sheet(item: $quickCreateSeed) { seed in
            iOSCalendarQuickCreateSheet(dateKey: seed.dateKey, initialStartMinute: seed.startMinute)
        }
    }

    @ViewBuilder
    private var calendarContent: some View {
        if presentation == .board {
            iOSCalendarBoardPlanner(
                anchorDate: $anchorDate,
                selectedDate: $selectedDate,
                allTasks: allTasks,
                allBundles: allBundles,
                bundlesByDate: bundlesByDate,
                eventsByDate: visibleEventsByDate,
                onAddItem: openQuickCreate
            )
        } else {
            iOSCalendarTimelineGrid(
                leadingDate: $anchorDate,
                selectedDate: $selectedDate,
                visibleDayCount: visibleDayCount,
                scheduledTasksByDate: scheduledTasksByDate,
                unscheduledTasksByDate: unscheduledTasksByDate,
                bundlesByDate: bundlesByDate,
                eventsByDate: visibleEventsByDate,
                allTasks: allTasks,
                zoom: $zoomLevel,
                onCreateAt: openQuickCreate
            )
        }
    }

    /// Month: the grid, and the chosen reading of a day either beside it or under it.
    ///
    /// Beside, the grid is the full-size one whose 104pt cells chip what each day holds; under, it
    /// is the compact grid sized so that **every** week of the month is on screen with the detail
    /// still visible below it. Both were already here — what is new is that either detail can go in
    /// either place, instead of the pane width choosing one pairing and hiding the other.
    @ViewBuilder
    private var monthContent: some View {
        switch monthPlacement {
        case .beside:
            HStack(spacing: 0) {
                iOSCalendarMonthGrid(
                    topRowDate: $anchorDate,
                    selectedDate: $selectedDate,
                    monthTasksByDate: monthTasksByDate,
                    bundlesByDate: bundlesByDate,
                    eventsByDate: visibleEventsByDate
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider().background(Theme.borderSubtle)

                monthDetailPane
                    .frame(width: CadenceCalendarPaneLayout.inspectorWidth(forPaneWidth: paneWidth))
                    .frame(maxHeight: .infinity)
            }

        case .below:
            iOSCalendarMonthStack(
                topRowDate: $anchorDate,
                selectedDate: $selectedDate,
                monthTasksByDate: monthTasksByDate,
                bundlesByDate: bundlesByDate,
                eventsByDate: visibleEventsByDate
            ) {
                monthDetailPane
            }
        }
    }

    @ViewBuilder
    private var monthDetailPane: some View {
        switch monthDetail {
        case .agenda:
            iOSCalendarMonthAgendaList(
                monthDate: displayedMonth,
                selectedDate: $selectedDate,
                monthTasksByDate: monthTasksByDate,
                bundlesByDate: bundlesByDate,
                eventsByDate: visibleEventsByDate
            )
        case .day:
            dayInspector
        }
    }

    private var dayInspector: some View {
        iOSCalendarDayInspector(
            date: selectedDate,
            tasks: selectedTasks,
            bundles: selectedBundles,
            events: selectedEvents,
            unscheduledTasks: selectedUnscheduledTasks,
            dueOnlyTasks: selectedDueOnlyTasks
        ) {
            openQuickCreate(on: selectedKey)
        }
    }

    private func refreshVisibleEvents() {
        guard calendarManager.isAuthorized else {
            if !visibleEventsByDate.isEmpty { visibleEventsByDate = [:] }
            return
        }
        var grouped: [String: [EKEvent]] = [:]
        for date in calendarEventDates {
            grouped[DateFormatters.dateKey(from: date)] = calendarManager.fetchEvents(for: date)
        }
        visibleEventsByDate = grouped
    }

    /// Keeps the day the inspector and the summary band are describing on screen.
    ///
    /// The grid reports its leading column back into `anchorDate` as it scrolls, and the selected
    /// day is a separate thing — it is what a tap on a day header sets. Scrolling a fortnight away
    /// from the selected day used to be impossible, because the chevrons moved both; now it is a
    /// flick, and an inspector describing a column nowhere near the screen is worse than one that
    /// follows. So the selection only moves when it has actually left the visible span.
    private func keepSelectedDateInView() {
        guard isTimedGrid else { return }
        let leading = calendar.startOfDay(for: anchorDate)
        guard let last = calendar.date(byAdding: .day, value: visibleDayCount - 1, to: leading) else { return }
        let selected = calendar.startOfDay(for: selectedDate)
        guard selected < leading || selected > last else { return }
        selectedDate = leading
    }

    private func openQuickCreate(on dateKey: String) {
        quickCreateSeed = iOSCalendarQuickCreateSeed(dateKey: dateKey)
    }

    private func openQuickCreate(on dateKey: String, startMinute: Int) {
        if let date = DateFormatters.date(from: dateKey) {
            selectedDate = calendar.startOfDay(for: date)
        }
        quickCreateSeed = iOSCalendarQuickCreateSeed(dateKey: dateKey, startMinute: startMinute)
    }

    private func setViewMode(_ newMode: CadenceCalendarViewMode) {
        presentationRaw = CadenceCalendarPresentation.timeline.rawValue
        viewModeRaw = newMode.rawValue
        // Switching into a timed grid puts the selected day at the leading edge, snapped back to
        // the start of its week so Week opens on a week rather than mid-one. It used to check
        // whether the selected day was inside the fixed window and leave the anchor alone if it
        // was; there is no fixed window to be inside any more.
        if newMode == .month {
            // Month's anchor is the week row at the top of its grid, not a day. Entering on the
            // selected day's month means the first row of that month's grid, so the six visible rows
            // are that month rather than a window straddling two.
            anchorDate = CadenceCalendarMonthWindow.topRow(forMonthContaining: selectedDate, calendar: calendar)
        } else {
            anchorDate = CadenceScheduleSupport.startOfWeek(containing: selectedDate, calendar: calendar)
        }
    }

    /// The **only** writer of `ios.calendar.monthDetail`. A persisted navigation value written from
    /// anything other than a tap compounds across launches (`ecaf80f`), so nothing derived from
    /// `paneWidth` or the size class ever reaches this.
    private func setMonthDetail(_ newDetail: CadenceCalendarMonthDetail) {
        monthDetailRaw = newDetail.rawValue
    }

    private func setPresentation(_ newPresentation: CadenceCalendarPresentation) {
        presentationRaw = newPresentation.rawValue
        if newPresentation == .board {
            anchorDate = selectedDate
        }
    }

    // `moveAnchor(by:)` and `jumpToToday()` are gone with the `‹ ➤ ›` cluster that called them.
    // Every calendar surface scrolls in the axis those chevrons moved, and jump-to-today is the
    // `Today` row in the toolbar title's popover (`iOSDateJumpTitle`) — see
    // `CadenceCalendarDateTitleSupport`.

    /// **T-405.** A thin caller. The ordering — remembered position first, then a dated link over
    /// the top of it — is `CadenceCalendarDateMemory.restoredPosition`, because it is the whole of
    /// T-369 and `CadenceTests` cannot see this file to pin it here.
    private func restorePersistedCalendarDates() {
        guard !didRestorePersistedDates else { return }
        didRestorePersistedDates = true

        let restored = CadenceCalendarDateMemory.restoredPosition(
            fallback: selectedDate,
            storedSelection: dateMemory.storedSelectionKey,
            storedAnchor: dateMemory.storedAnchorKey,
            deepLinkDateKey: standingCalendarDeepLinkDateKey,
            calendar: calendar
        )
        selectedDate = restored.selectedDate
        anchorDate = restored.anchorDate
    }

    /// The day the standing route names, if it is a calendar link. `nil` for every other route —
    /// including no route at all. A bare `cadence://calendar` means today, and
    /// `calendarDateKey(todayKey:)` is where that is decided for both shells.
    private var standingCalendarDeepLinkDateKey: String? {
        deepLinkManager.route?.deepLink.calendarDateKey()
    }

    /// Moves to the day a `cadence://calendar` link names, if the standing route is one.
    ///
    /// **T-369.** The Calendar widget draws a fortnight from its snapshot's date and its "Open
    /// Calendar" link used to carry no date at all, so the tap landed on `dateMemory`'s remembered
    /// position — not the day on screen, and not today either. The link now names a day, and a
    /// bare one means today; `CadenceDeepLink.calendarDateKey(todayKey:)` is that single answer,
    /// shared with the macOS root so the two shells cannot read one URL two ways.
    private func applyCalendarDeepLinkDate() {
        guard let day = CadenceCalendarDateMemory.date(
            fromStored: standingCalendarDeepLinkDateKey,
            calendar: calendar
        ) else { return }

        selectedDate = day
        anchorDate = day
    }

    private func rememberCalendarPosition() {
        positionWriter.remember(anchor: anchorDate, selection: selectedDate, calendar: calendar)
    }

    private func flushCalendarPosition() {
        positionWriter.flush(anchor: anchorDate, selection: selectedDate, calendar: calendar)
    }
}

private struct iOSCalendarQuickCreateSeed: Identifiable {
    let dateKey: String
    var startMinute: Int? = nil
    var id: String {
        if let startMinute {
            return "\(dateKey)-\(startMinute)"
        }
        return dateKey
    }
}

#endif
