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
            Rectangle().fill(Theme.borderSubtle.opacity(0.7)).frame(width: 1)
        }
    }
}

struct CalendarTimelineDayScroller: View {
    let bufferStart: Date
    let allTasks: [AppTask]
    let tasksByDate: [String: [AppTask]]
    let hourHeight: CGFloat
    let colWidth: CGFloat
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
                            allTasks: allTasks,
                            colWidth: colWidth,
                            hourHeight: hourHeight
                        )
                        .frame(width: colWidth)
                        .id("day_\(dayIdx)")
                    }
                }
                .frame(width: totalDaysWidth, alignment: .leading)
            }
            .frame(width: timelineViewportWidth, alignment: .leading)
            .scrollBounceBehavior(.basedOnSize, axes: [.horizontal])
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, x in
                timelineScrollState.setHeaderOffset(-x)
                guard didRestoreTimelineScroll, !isRestoringHorizontalScroll else { return }
                let clampedDay = CalendarTimelineScrollSupport.clampedDayIndex(
                    offsetX: x,
                    colWidth: colWidth
                )
                guard visibleTimelineDayIndex != clampedDay else { return }
                visibleTimelineDayIndex = clampedDay
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
