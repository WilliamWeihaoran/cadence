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

    @State private var viewMode: CalViewMode = .week
    @State private var scrollToTodayTrigger = false
    @AppStorage("calendarZoomLevel") private var zoomLevel: Int = 1
    @AppStorage("calendarRememberedTimelineHour") private var rememberedScrollHour: Int = -1
    @AppStorage("calendarRememberedTimelineDateKey") private var rememberedDateKey: String = ""
    @State private var visibleMonthIdx: Int = 60  // index into MonthGridView's 120-month window
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

    var body: some View {
        VStack(spacing: 0) {
            CalendarPageToolbar(
                calendarTitleLabel: calendarTitleLabel,
                viewMode: viewMode,
                scrollToToday: { scrollToTodayTrigger.toggle() },
                setViewMode: { viewMode = $0 },
                zoomLevel: $zoomLevel
            )

            Divider().background(Theme.borderSubtle)

            if viewMode == .month {
                MonthGridView(
                    allTasks: allTasks,
                    tasksByDate: tasksByDateForMonth,
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
                        rememberedDateKey: $rememberedDateKey,
                        bufferStart: bufferStart,
                        allTasks: allTasks,
                        tasksByDate: tasksByDate,
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
                        onPersistVisibleTimelineDay: { day in
                            schedulePersistVisibleTimelineDay(day)
                        },
                        onPersistVisibleTimelineHour: { hour in
                            schedulePersistVisibleTimelineHour(hour)
                        },
                        onRestoreTimelineScrollIfNeeded: { vProxy, hProxy, colWidth in
                            restoreTimelineScrollIfNeeded(vProxy: vProxy, hProxy: hProxy, colWidth: colWidth)
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
        .onChange(of: viewMode) { _, newMode in
            CalendarPageDataSupport.handleViewModeChange(
                newMode: newMode,
                visibleMonthIdx: &visibleMonthIdx,
                monthGridResetNonce: &monthGridResetNonce,
                didRestoreTimelineScroll: &didRestoreTimelineScroll
            )
        }
    }

    private var calendarTitleLabel: String {
        CalendarPageLifecycleSupport.calendarTitleLabel(
            viewMode: viewMode,
            visibleMonthIdx: visibleMonthIdx,
            visibleTimelineDayIndex: visibleTimelineDayIndex,
            rememberedDateKey: rememberedDateKey,
            bufferStart: bufferStart,
            todayDayIdx: todayDayIdx,
            calendar: cal
        )
    }

    private func restoreTimelineScrollIfNeeded(vProxy: ScrollViewProxy, hProxy: ScrollViewProxy, colWidth: CGFloat) {
        CalendarPageLifecycleSupport.restoreTimelineScrollIfNeeded(
            didRestoreTimelineScroll: &didRestoreTimelineScroll,
            rememberedScrollHour: rememberedScrollHour,
            rememberedDateKey: rememberedDateKey,
            bufferStart: bufferStart,
            todayDayIdx: todayDayIdx,
            visibleTimelineDayIndex: &visibleTimelineDayIndex,
            visibleTimelineHour: &visibleTimelineHour,
            timelineScrollState: timelineScrollState,
            vProxy: vProxy,
            hProxy: hProxy,
            colWidth: colWidth,
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
            persist: { rememberedDateKey = $0 }
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

    private func applyExternalCalendarJump(_ request: CalendarNavigationManager.Request) {
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
            rememberedDateKey: &rememberedDateKey,
            timelineScrollState: timelineScrollState
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
