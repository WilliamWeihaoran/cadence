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
    @Binding var rememberedDateKey: String
    @Binding var visibleTimelineDayIndex: Int?
    @Binding var isRestoringHorizontalScroll: Bool
    @Binding var didRestoreTimelineScroll: Bool
    @Binding var externalJumpDayIndex: Int?
    let externalJumpToken: UUID?
    @ObservedObject var timelineScrollState: CalendarTimelineScrollState
    let eventCache: CalendarEventDayCache
    let onPersistVisibleTimelineDay: (Int) -> Void
    let onRestoreTimelineScrollIfNeeded: (ScrollViewProxy, CGFloat) -> Void
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
                .frame(width: totalDaysWidth, alignment: .leading)
            }
            .frame(width: timelineViewportWidth, alignment: .leading)
            .scrollTargetBehavior(DayBoundaryScrollTargetBehavior(dayWidth: colWidth))
            .scrollBounceBehavior(.basedOnSize, axes: [.horizontal])
            .transaction { $0.animation = nil }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, x in
                guard !isRestoringHorizontalScroll else { return }
                timelineScrollState.setHeaderOffset(-x)
                let clampedDay = CalendarTimelineScrollSupport.clampedDayIndex(
                    offsetX: x,
                    colWidth: colWidth
                )
                if visibleTimelineDayIndex != clampedDay {
                    visibleTimelineDayIndex = clampedDay
                }

                guard didRestoreTimelineScroll else { return }
                onPersistVisibleTimelineDay(clampedDay)
            }
            .onAppear {
                onRestoreTimelineScrollIfNeeded(hProxy, colWidth)
                if externalJumpToken != nil, let day = externalJumpDayIndex {
                    timelineScrollState.jumpHeaderOffset(to: -CGFloat(day) * colWidth)
                    DispatchQueue.main.async {
                        hProxy.scrollTo("day_\(day)", anchor: .leading)
                    }
                }
            }
            .onChange(of: scrollToTodayTrigger) {
                CalendarTimelineScrollSupport.applyTodayHorizontalJump(
                    todayDayIdx: todayDayIdx,
                    colWidth: colWidth,
                    rememberedDateKey: $rememberedDateKey,
                    visibleTimelineDayIndex: $visibleTimelineDayIndex,
                    isRestoringHorizontalScroll: $isRestoringHorizontalScroll,
                    timelineScrollState: timelineScrollState,
                    hProxy: hProxy
                )
            }
            .onChange(of: externalJumpToken) { _, _ in
                guard let day = externalJumpDayIndex else { return }
                CalendarTimelineScrollSupport.applyExternalHorizontalJump(
                    day: day,
                    colWidth: colWidth,
                    visibleTimelineDayIndex: $visibleTimelineDayIndex,
                    isRestoringHorizontalScroll: $isRestoringHorizontalScroll,
                    timelineScrollState: timelineScrollState,
                    hProxy: hProxy
                )
            }
        }
    }
}
#endif
