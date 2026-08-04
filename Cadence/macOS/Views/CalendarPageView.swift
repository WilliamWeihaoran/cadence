#if os(macOS)
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import EventKit
import Combine

struct CalendarPageView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CalendarNavigationManager.self) private var calendarNavigationManager
    @Query private var allTasks: [AppTask]
    @Query private var allBundles: [TaskBundle]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]

    @State private var viewMode: CadenceCalendarViewMode = .week
    @State private var presentation: CadenceCalendarPresentation = .timeline
    @State private var selectedBoardDate = Calendar.current.startOfDay(for: Date())
    @State private var scrollToTodayTrigger = false
    @AppStorage("calendarZoomLevel") private var zoomLevel: Int = 1
    @AppStorage("calendarRememberedTimelineHour") private var rememberedScrollHour: Int = -1
    @AppStorage("calendarRememberedTimelineDateKey") private var anchorDateKey: String = ""
    @State private var visibleMonthIdx: Int = CalendarMonthGridMetrics.todayMonthIndex  // index into MonthGridView's month window (CalendarMonthGridMetrics.totalMonths months wide)
    @State private var monthGridResetNonce: Int = 0
    @State private var isRestoringVerticalScroll = true
    @State private var isRestoringHorizontalScroll = true
    @State private var didRestoreTimelineScroll = false
    @State private var visibleTimelineDayIndex: Int?
    @State private var visibleTimelineHour: Int?
    @State private var pendingDayPersistence: DispatchWorkItem?
    @State private var pendingHourPersistence: DispatchWorkItem?
    @State private var externalJumpDayIndex: Int?
    @State private var externalJumpHour: Int?
    @State private var externalJumpToken: UUID?
    @State private var calendarEventDayCache = CalendarEventDayCache()
    @StateObject private var timelineScrollState = CalendarTimelineScrollState()

    private let cal = Calendar.current
    private var bufferStart: Date {
        CalendarPageDataSupport.bufferStart(calendar: cal)
    }
    private var todayDayIdx: Int {
        CalendarPageDataSupport.todayDayIndex(bufferStart: bufferStart, calendar: cal)
    }
    private var tasksByDate: [String: [AppTask]] {
        CalendarPageDataSupport.tasksByScheduledDate(allTasks)
    }
    private var bundlesByDate: [String: [TaskBundle]] {
        CalendarPageDataSupport.bundlesByDate(allBundles)
    }

    var body: some View {
        VStack(spacing: 0) {
            CalendarPageToolbar(
                calendarTitleLabel: calendarTitleLabel,
                viewMode: viewMode,
                presentation: presentation,
                scrollToToday: { jumpToToday() },
                setViewMode: { setTimelineMode($0) },
                setPresentation: { setPresentation($0) },
                moveBoardWindow: { moveBoardWindow(by: $0) },
                zoomLevel: $zoomLevel
            )

            Divider().background(Theme.borderSubtle.opacity(CalendarVisualStyle.dividerOpacity))

            if presentation == .board {
                CalendarPageBoardView(
                    anchorDate: selectedBoardDate,
                    selectedDate: $selectedBoardDate,
                    allTasks: allTasks,
                    allBundles: allBundles,
                    areas: areas,
                    projects: projects,
                    bundlesByDate: bundlesByDate
                )
            } else if viewMode == .month {
                MonthGridView(
                    allTasks: allTasks,
                    tasksByDate: tasksByDateForMonth,
                    bundlesByDate: bundlesByDate,
                    visibleMonthIdx: $visibleMonthIdx,
                    scrollToTodayTrigger: scrollToTodayTrigger
                )
                .id("month-grid-\(monthGridResetNonce)")
            } else {
                GeometryReader { geo in
                    CalendarTimelineViewport(
                        geoSize: geo.size,
                        viewMode: viewMode,
                        zoomLevel: $zoomLevel,
                        rememberedScrollHour: $rememberedScrollHour,
                        anchorDateKey: $anchorDateKey,
                        bufferStart: bufferStart,
                        allTasks: allTasks,
                        allBundles: allBundles,
                        areas: areas,
                        projects: projects,
                        tasksByDate: tasksByDate,
                        bundlesByDate: bundlesByDate,
                        unscheduledTasksByDate: unscheduledTasksByDate,
                        todayDayIdx: todayDayIdx,
                        scrollToTodayTrigger: $scrollToTodayTrigger,
                        isRestoringVerticalScroll: $isRestoringVerticalScroll,
                        isRestoringHorizontalScroll: $isRestoringHorizontalScroll,
                        didRestoreTimelineScroll: $didRestoreTimelineScroll,
                        visibleTimelineDayIndex: $visibleTimelineDayIndex,
                        visibleTimelineHour: $visibleTimelineHour,
                        externalJumpDayIndex: $externalJumpDayIndex,
                        externalJumpHour: $externalJumpHour,
                        externalJumpToken: externalJumpToken,
                        timelineScrollState: timelineScrollState,
                        eventCache: calendarEventDayCache,
                        onPersistVisibleTimelineDay: { day in
                            schedulePersistVisibleTimelineDay(day)
                        },
                        onPersistVisibleTimelineHour: { hour in
                            schedulePersistVisibleTimelineHour(hour)
                        },
                        onRestoreTimelineScrollIfNeeded: { vProxy, hProxy in
                            restoreTimelineScrollIfNeeded(vProxy: vProxy, hProxy: hProxy)
                        }
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.bg)
        .onAppear {
            if let request = calendarNavigationManager.request {
                applyExternalCalendarJump(request)
            }
        }
        .onChange(of: calendarNavigationManager.request?.token) { _, _ in
            guard let request = calendarNavigationManager.request else { return }
            applyExternalCalendarJump(request)
        }
        .onChange(of: viewMode) { oldMode, newMode in
            guard presentation == .timeline else { return }
            pendingDayPersistence?.cancel()
            pendingDayPersistence = nil
            CalendarPageDataSupport.handleViewModeChange(
                oldMode: oldMode,
                newMode: newMode,
                visibleMonthIdx: &visibleMonthIdx,
                monthGridResetNonce: &monthGridResetNonce,
                didRestoreTimelineScroll: &didRestoreTimelineScroll,
                visibleTimelineDayIndex: &visibleTimelineDayIndex,
                anchorDateKey: &anchorDateKey,
                bufferStart: bufferStart,
                todayDayIdx: todayDayIdx,
                calendar: cal
            )
        }
        .onChange(of: selectedBoardDate) { _, newDate in
            guard presentation == .board else { return }
            anchorDateKey = DateFormatters.dateKey(from: newDate)
        }
    }

    private var calendarTitleLabel: String {
        if presentation == .board {
            return CalendarBoardPlannerSupport.title(for: selectedBoardDate, calendar: cal)
        }

        return CalendarPageLifecycleSupport.calendarTitleLabel(
            viewMode: viewMode,
            visibleMonthIdx: visibleMonthIdx,
            visibleTimelineDayIndex: visibleTimelineDayIndex,
            anchorDateKey: anchorDateKey,
            bufferStart: bufferStart,
            todayDayIdx: todayDayIdx,
            calendar: cal
        )
    }

    private func setTimelineMode(_ mode: CadenceCalendarViewMode) {
        if presentation == .board {
            anchorDateKey = DateFormatters.dateKey(from: selectedBoardDate)
            visibleTimelineDayIndex = CalendarPageStateSupport.timelineDayIndex(
                anchorDateKey: anchorDateKey,
                bufferStart: bufferStart,
                todayDayIdx: todayDayIdx,
                calendar: cal
            )
            if mode == .month {
                visibleMonthIdx = CalendarPageStateSupport.monthIndexForTimelineAnchor(
                    anchorDateKey: anchorDateKey,
                    currentMonthStart: CalendarMonthGridSupport.currentMonthStart(calendar: cal),
                    calendar: cal
                )
                monthGridResetNonce += 1
            }
        }

        presentation = .timeline
        viewMode = mode
        didRestoreTimelineScroll = false
    }

    private func setPresentation(_ newPresentation: CadenceCalendarPresentation) {
        guard newPresentation != presentation else { return }

        if newPresentation == .board {
            prepareBoardSelectionFromCurrentCalendarState()
        }

        presentation = newPresentation
    }

    private func prepareBoardSelectionFromCurrentCalendarState() {
        pendingDayPersistence?.cancel()
        pendingDayPersistence = nil

        anchorDateKey = CalendarPageStateSupport.boardAnchorDateKey(
            viewMode: viewMode,
            visibleMonthIdx: visibleMonthIdx,
            visibleTimelineDayIndex: visibleTimelineDayIndex,
            anchorDateKey: anchorDateKey,
            bufferStart: bufferStart,
            currentMonthStart: CalendarMonthGridSupport.currentMonthStart(calendar: cal),
            calendar: cal
        )

        selectedBoardDate = cal.startOfDay(for: DateFormatters.date(from: anchorDateKey) ?? Date())
    }

    private func moveBoardWindow(by delta: Int) {
        guard presentation == .board else { return }
        selectedBoardDate = CalendarBoardPlannerSupport.dateByMovingWindow(
            selectedBoardDate,
            by: delta,
            calendar: cal
        )
        anchorDateKey = DateFormatters.dateKey(from: selectedBoardDate)
    }

    private func restoreTimelineScrollIfNeeded(vProxy: ScrollViewProxy, hProxy: ScrollViewProxy) {
        CalendarPageLifecycleSupport.restoreTimelineScrollIfNeeded(
            didRestoreTimelineScroll: &didRestoreTimelineScroll,
            rememberedScrollHour: rememberedScrollHour,
            anchorDateKey: anchorDateKey,
            bufferStart: bufferStart,
            todayDayIdx: todayDayIdx,
            visibleTimelineDayIndex: &visibleTimelineDayIndex,
            visibleTimelineHour: &visibleTimelineHour,
            vProxy: vProxy,
            hProxy: hProxy,
            setHorizontalRestoring: { isRestoringHorizontalScroll = $0 },
            setVerticalRestoring: { isRestoringVerticalScroll = $0 }
        )
    }

    private func schedulePersistVisibleTimelineDay(_ dayIndex: Int) {
        CalendarPageInteractionSupport.persistVisibleTimelineDay(
            dayIndex: dayIndex,
            calendar: cal,
            bufferStart: bufferStart,
            cancelPending: { pendingDayPersistence?.cancel() },
            storePending: { pendingDayPersistence = $0 },
            persist: { anchorDateKey = $0 }
        )
    }

    private func schedulePersistVisibleTimelineHour(_ hour: Int) {
        CalendarPageInteractionSupport.persistVisibleTimelineHour(
            hour: hour,
            cancelPending: { pendingHourPersistence?.cancel() },
            storePending: { pendingHourPersistence = $0 },
            persist: { rememberedScrollHour = $0 }
        )
    }

    private func jumpToToday() {
        pendingDayPersistence?.cancel()
        pendingDayPersistence = nil
        pendingHourPersistence?.cancel()
        pendingHourPersistence = nil

        let target = CalendarPageInteractionSupport.todayTimelineJumpTarget(
            calendar: cal,
            bufferStart: bufferStart,
            todayDayIdx: todayDayIdx
        )
        selectedBoardDate = cal.startOfDay(for: DateFormatters.date(from: target.dateKey) ?? Date())
        CalendarPageInteractionSupport.applyTimelineJump(
            target,
            token: nil,
            visibleTimelineDayIndex: &visibleTimelineDayIndex,
            visibleTimelineHour: &visibleTimelineHour,
            externalJumpDayIndex: &externalJumpDayIndex,
            externalJumpHour: &externalJumpHour,
            externalJumpToken: &externalJumpToken,
            anchorDateKey: &anchorDateKey
        )
        if presentation == .timeline && viewMode != .month {
            rememberedScrollHour = target.hour
            didRestoreTimelineScroll = true
            isRestoringHorizontalScroll = true
            isRestoringVerticalScroll = true
        }
        if viewMode == .month || presentation == .board {
            visibleMonthIdx = CalendarMonthGridMetrics.todayMonthIndex
        }
        scrollToTodayTrigger.toggle()
    }

    private func applyExternalCalendarJump(_ request: CalendarNavigationManager.Request) {
        presentation = .timeline
        viewMode = .week
        CalendarPageInteractionSupport.applyExternalCalendarJump(
            request: request,
            calendar: cal,
            bufferStart: bufferStart,
            todayDayIdx: todayDayIdx,
            visibleTimelineDayIndex: &visibleTimelineDayIndex,
            visibleTimelineHour: &visibleTimelineHour,
            externalJumpDayIndex: &externalJumpDayIndex,
            externalJumpHour: &externalJumpHour,
            externalJumpToken: &externalJumpToken,
            anchorDateKey: &anchorDateKey
        ) {
            calendarNavigationManager.clear()
        }
    }

    private var unscheduledTasksByDate: [String: [AppTask]] {
        CalendarPageDataSupport.unscheduledTasksByDate(allTasks)
    }

    // tasksByDate for month view — all tasks with a due date or scheduled date
    private var tasksByDateForMonth: [String: [AppTask]] {
        CalendarPageDataSupport.monthTasksByDate(allTasks)
    }
}
#endif
