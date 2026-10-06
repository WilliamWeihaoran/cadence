#if os(macOS)
import SwiftUI

struct CalendarTimelineTimeRail: View {
    let hourHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ForEach(calStartHour..<calEndHour, id: \.self) { hour in
                CalTimeRailLabel(hour: hour, hourHeight: hourHeight)
                    .id("tl_\(hour)")
            }
        }
        .frame(width: calTimeTotalWidth)
        .background(Theme.surface)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.borderSubtle.opacity(CalendarVisualStyle.dividerOpacity))
                .frame(width: 0.5)
        }
    }
}

struct CalendarTimelineDayScroller: View {
    let bufferStart: Date
    let allTasks: [AppTask]
    let allBundles: [TaskBundle]
    let areas: [Area]
    let projects: [Project]
    let tasksByDate: [String: [AppTask]]
    let bundlesByDate: [String: [TaskBundle]]
    let hourHeight: CGFloat
    let colWidth: CGFloat
    let showHalfHourMarks: Bool
    let totalDaysWidth: CGFloat
    let timelineViewportWidth: CGFloat
    let todayDayIdx: Int
    @Binding var visibleTimelineDayIndex: Int?
    @Binding var isRestoringHorizontalScroll: Bool
    @Binding var didRestoreTimelineScroll: Bool
    @Binding var externalJumpDayIndex: Int?
    let externalJumpToken: UUID?
    let timelineScrollState: CalendarTimelineScrollState
    let eventCache: CalendarEventDayCache
    let onPersistVisibleTimelineDay: (Int) -> Void
    let onRestoreTimelineScrollIfNeeded: (ScrollViewProxy) -> Void
    let scrollToTodayTrigger: Bool

    private let cal = Calendar.current

    var body: some View {
        ScrollViewReader { hProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 0) {
                    ForEach(0..<calRenderDays, id: \.self) { dayIdx in
                        let date = cal.date(byAdding: .day, value: dayIdx, to: bufferStart)!
                        let key = DateFormatters.dateKey(from: date)
                        CalDayColumn(
                            date: date,
                            tasks: tasksByDate[key] ?? [],
                            bundles: bundlesByDate[key] ?? [],
                            allTasks: allTasks,
                            allBundles: allBundles,
                            areas: areas,
                            projects: projects,
                            eventCache: eventCache,
                            colWidth: colWidth,
                            hourHeight: hourHeight,
                            showHalfHourMarks: showHalfHourMarks
                        )
                        .frame(width: colWidth)
                        .id("day_\(dayIdx)")
                    }
                }
                .scrollTargetLayout()
                .frame(width: totalDaysWidth, alignment: .leading)
            }
            .frame(width: timelineViewportWidth, alignment: .leading)
            .scrollTargetBehavior(DayBoundaryScrollTargetBehavior(dayWidth: colWidth))
            .scrollBounceBehavior(.basedOnSize, axes: [.horizontal])
            .transaction { $0.animation = nil }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, x in
                timelineScrollState.setHeaderOffset(-x)
                if isRestoringHorizontalScroll {
                    if CalendarTimelineScrollSupport.shouldFinishHorizontalJump(
                        offsetX: x,
                        targetDay: visibleTimelineDayIndex,
                        colWidth: colWidth
                    ) {
                        DispatchQueue.main.async {
                            isRestoringHorizontalScroll = false
                        }
                    }
                    return
                }
                let clampedDay = CalendarTimelineScrollSupport.clampedDayIndex(
                    offsetX: x,
                    colWidth: colWidth
                )
                if visibleTimelineDayIndex != clampedDay {
                    visibleTimelineDayIndex = clampedDay
                }

                // **T-1498.** Guarded on `lastReportedDay`, not on the binding above it. The
                // binding's `if` already refuses an unchanged day, but it is written by the
                // jump paths too, so persistence keyed off it would go silent after a jump to
                // today. Below this guard sits a date-key format, a work-item cancel, an
                // allocation, a main-queue schedule and a `@State` write on `CalendarPageView` —
                // all of which used to run on every changed pixel of a horizontal fling.
                CalendarTimelineScrollSupport.persistVisibleDay(
                    clampedDay: clampedDay,
                    didRestoreTimelineScroll: didRestoreTimelineScroll,
                    state: timelineScrollState,
                    persist: onPersistVisibleTimelineDay
                )
            }
            .onAppear {
                // The restore is about to move the scroll without a report, for the same reason
                // a jump does (T-1498). Start with no memory.
                timelineScrollState.lastReportedDay = nil
                onRestoreTimelineScrollIfNeeded(hProxy)
                if let day = visibleTimelineDayIndex {
                    CalendarTimelineScrollSupport.syncHeaderOffset(
                        to: day,
                        scrollState: timelineScrollState,
                        colWidth: colWidth
                    )
                }
                if externalJumpToken != nil, let day = externalJumpDayIndex {
                    DispatchQueue.main.async {
                        CalendarTimelineScrollSupport.syncHeaderOffset(
                            to: day,
                            scrollState: timelineScrollState,
                            colWidth: colWidth
                        )
                        hProxy.scrollTo("day_\(day)", anchor: .leading)
                    }
                }
            }
            .onChange(of: scrollToTodayTrigger) {
                CalendarTimelineScrollSupport.applyTodayHorizontalJump(
                    todayDayIdx: todayDayIdx,
                    visibleTimelineDayIndex: $visibleTimelineDayIndex,
                    isRestoringHorizontalScroll: $isRestoringHorizontalScroll,
                    hProxy: hProxy,
                    scrollState: timelineScrollState,
                    colWidth: colWidth
                )
            }
            .onChange(of: externalJumpToken) { _, _ in
                guard let day = externalJumpDayIndex else { return }
                CalendarTimelineScrollSupport.applyExternalHorizontalJump(
                    day: day,
                    visibleTimelineDayIndex: $visibleTimelineDayIndex,
                    isRestoringHorizontalScroll: $isRestoringHorizontalScroll,
                    hProxy: hProxy,
                    scrollState: timelineScrollState,
                    colWidth: colWidth
                )
            }
        }
    }
}
#endif
