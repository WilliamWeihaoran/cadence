#if os(macOS)
import Combine
import EventKit
import SwiftUI

enum CalViewMode: String, CaseIterable {
    case week = "Week"
    case twoWeeks = "2 Weeks"
    case month = "Month"

    var daysCount: Int {
        switch self {
        case .week: return 7
        case .twoWeeks: return 14
        case .month: return 1
        }
    }
}

struct CalendarPageToolbar: View {
    let calendarTitleLabel: String
    let viewMode: CalViewMode
    let scrollToToday: () -> Void
    let setViewMode: (CalViewMode) -> Void
    @Binding var zoomLevel: Int

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Text("Calendar")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.dim)
                Text("·")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.dim.opacity(0.5))
                Text(calendarTitleLabel)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .animation(.none, value: calendarTitleLabel)
            }
            Spacer()
            Button("Today", action: scrollToToday)
                .buttonStyle(.cadencePlain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.blue)
                .frame(minWidth: 70, minHeight: 30)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
                .background(Theme.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 5))

            TimelineZoomControl(zoomLevel: $zoomLevel, range: 1...3)

            HStack(spacing: 2) {
                ForEach(CalViewMode.allCases, id: \.self) { mode in
                    Button(mode.rawValue) { setViewMode(mode) }
                        .buttonStyle(.cadencePlain)
                        .font(.system(size: 11, weight: viewMode == mode ? .semibold : .regular))
                        .foregroundStyle(viewMode == mode ? Theme.blue : Theme.dim)
                        .frame(minWidth: 78, minHeight: 30)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                        .background(viewMode == mode ? Theme.blue.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Theme.surface)
    }
}

struct CalendarTimelineHeaderStrip: View {
    let bufferStart: Date
    let colWidth: CGFloat
    let totalDaysWidth: CGFloat
    let timelineViewportWidth: CGFloat
    @ObservedObject var scrollState: CalendarTimelineScrollState
    let eventCache: CalendarEventDayCache
    let unscheduledTasksByDate: [String: [AppTask]]

    @Environment(CalendarManager.self) private var calendarManager
    private let cal = Calendar.current

    private var visibleRange: Range<Int> {
        calendarTimelineHeaderVisibleRange(
            headerOffset: scrollState.headerOffset,
            colWidth: colWidth,
            viewportWidth: timelineViewportWidth,
            renderDays: calRenderDays
        )
    }

    var body: some View {
        let range = visibleRange

        ZStack(alignment: .leading) {
            Color.clear
                .frame(width: totalDaysWidth, alignment: .leading)

            HStack(spacing: 0) {
                ForEach(range, id: \.self) { dayIdx in
                    let date = cal.date(byAdding: .day, value: dayIdx, to: bufferStart)!
                    let key = DateFormatters.dateKey(from: date)
                    CalDayHeaderView(
                        date: date,
                        allDayEvents: eventCache.allDayEvents(for: date, calendarManager: calendarManager),
                        unscheduledTasks: unscheduledTasksByDate[key] ?? []
                    )
                    .frame(width: colWidth)
                }
            }
            .offset(x: CGFloat(range.lowerBound) * colWidth + scrollState.headerOffset)
        }
        .frame(width: totalDaysWidth, alignment: .leading)
        .transaction { $0.animation = nil }
        .frame(width: timelineViewportWidth, alignment: .leading)
        .clipped()
    }
}

func calendarTimelineHeaderVisibleRange(
    headerOffset: CGFloat,
    colWidth: CGFloat,
    viewportWidth: CGFloat,
    renderDays: Int
) -> Range<Int> {
    guard renderDays > 0 else { return 0..<0 }

    let safeColWidth = max(colWidth, 1)
    let maxDayIndex = renderDays - 1
    let rawLeadingDay = Int(floor((-headerOffset) / safeColWidth))
    let leadingDay = min(max(rawLeadingDay, 0), maxDayIndex)
    let visibleCount = max(1, Int(ceil(max(viewportWidth, 0) / safeColWidth)))
    let lowerBound = max(0, leadingDay - 2)
    let upperExclusive = min(renderDays, leadingDay + visibleCount + 3)
    return lowerBound..<max(lowerBound, upperExclusive)
}

struct CalendarTimelineViewport: View {
    let geoSize: CGSize
    let viewMode: CalViewMode
    @Binding var zoomLevel: Int
    @Binding var rememberedScrollHour: Int
    @Binding var rememberedDateKey: String
    let bufferStart: Date
    let allTasks: [AppTask]
    let allBundles: [TaskBundle]
    let areas: [Area]
    let projects: [Project]
    let tasksByDate: [String: [AppTask]]
    let bundlesByDate: [String: [TaskBundle]]
    let unscheduledTasksByDate: [String: [AppTask]]
    let todayDayIdx: Int
    @Binding var scrollToTodayTrigger: Bool
    @Binding var isRestoringVerticalScroll: Bool
    @Binding var isRestoringHorizontalScroll: Bool
    @Binding var didRestoreTimelineScroll: Bool
    @Binding var visibleTimelineDayIndex: Int?
    @Binding var visibleTimelineHour: Int?
    @Binding var externalJumpDayIndex: Int?
    @Binding var externalJumpHour: Int?
    let externalJumpToken: UUID?
    @ObservedObject var timelineScrollState: CalendarTimelineScrollState
    let eventCache: CalendarEventDayCache
    let onPersistVisibleTimelineDay: (Int) -> Void
    let onPersistVisibleTimelineHour: (Int) -> Void
    let onRestoreTimelineScrollIfNeeded: (ScrollViewProxy, ScrollViewProxy, CGFloat) -> Void

    private let cal = Calendar.current

    var body: some View {
        let viewportMetrics = CalendarTimelineViewportMetrics(
            geoSize: geoSize,
            viewMode: viewMode,
            zoomLevel: zoomLevel
        )

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Theme.surface)
                    .frame(width: calTimeTotalWidth, height: calDayHeaderHeight + calAllDayBannerHeight)
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(Theme.borderSubtle.opacity(CalendarVisualStyle.dividerOpacity))
                            .frame(width: 0.5)
                    }
                    .overlay(alignment: .bottomLeading) {
                        Text("all-day")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Theme.dim)
                            .padding(.leading, 4)
                    .padding(.bottom, 6)
                    }
                CalendarTimelineHeaderStrip(
                    bufferStart: bufferStart,
                    colWidth: viewportMetrics.colWidth,
                    totalDaysWidth: viewportMetrics.totalDaysWidth,
                    timelineViewportWidth: viewportMetrics.timelineViewportWidth,
                    scrollState: timelineScrollState,
                    eventCache: eventCache,
                    unscheduledTasksByDate: unscheduledTasksByDate
                )
            }
            .frame(height: calDayHeaderHeight + calAllDayBannerHeight)
            .background(Theme.surface)

            Divider().background(Theme.borderSubtle.opacity(CalendarVisualStyle.dividerOpacity))

            ScrollViewReader { vProxy in
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        CalendarTimelineTimeRail(hourHeight: viewportMetrics.hourHeight)

                        CalendarTimelineDayScroller(
                            bufferStart: bufferStart,
                            allTasks: allTasks,
                            allBundles: allBundles,
                            areas: areas,
                            projects: projects,
                            tasksByDate: tasksByDate,
                            bundlesByDate: bundlesByDate,
                            hourHeight: viewportMetrics.hourHeight,
                            colWidth: viewportMetrics.colWidth,
                            showHalfHourMarks: zoomLevel == 3,
                            totalDaysWidth: viewportMetrics.totalDaysWidth,
                            timelineViewportWidth: viewportMetrics.timelineViewportWidth,
                            todayDayIdx: todayDayIdx,
                            rememberedDateKey: $rememberedDateKey,
                            visibleTimelineDayIndex: $visibleTimelineDayIndex,
                            isRestoringHorizontalScroll: $isRestoringHorizontalScroll,
                            didRestoreTimelineScroll: $didRestoreTimelineScroll,
                            externalJumpDayIndex: $externalJumpDayIndex,
                            externalJumpToken: externalJumpToken,
                            timelineScrollState: timelineScrollState,
                            eventCache: eventCache,
                            onPersistVisibleTimelineDay: onPersistVisibleTimelineDay,
                            onRestoreTimelineScrollIfNeeded: { hProxy, colWidth in
                                onRestoreTimelineScrollIfNeeded(vProxy, hProxy, colWidth)
                            },
                            scrollToTodayTrigger: scrollToTodayTrigger
                        )
                    }
                }
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
                    guard didRestoreTimelineScroll, !isRestoringVerticalScroll else { return }
                    let clampedHour = CalendarTimelineScrollSupport.clampedHour(
                        offsetY: y,
                        hourHeight: viewportMetrics.hourHeight
                    )
                    guard visibleTimelineHour != clampedHour else { return }
                    visibleTimelineHour = clampedHour
                    onPersistVisibleTimelineHour(clampedHour)
                }
                .onAppear {
                    didRestoreTimelineScroll = false
                    isRestoringVerticalScroll = true
                    isRestoringHorizontalScroll = true
                    if externalJumpToken != nil, let hour = externalJumpHour {
                        DispatchQueue.main.async {
                            vProxy.scrollTo("tl_\(hour)", anchor: .top)
                        }
                    }
                }
                .scrollBounceBehavior(.always, axes: [.vertical])
                .onChange(of: scrollToTodayTrigger) {
                    CalendarTimelineScrollSupport.applyTodayVerticalJump(
                        visibleTimelineHour: $visibleTimelineHour,
                        rememberedScrollHour: $rememberedScrollHour,
                        isRestoringVerticalScroll: $isRestoringVerticalScroll,
                        vProxy: vProxy
                    )
                }
                .onChange(of: externalJumpToken) { _, _ in
                    guard let hour = externalJumpHour else { return }
                    CalendarTimelineScrollSupport.applyExternalVerticalJump(
                        hour: hour,
                        visibleTimelineHour: $visibleTimelineHour,
                        isRestoringVerticalScroll: $isRestoringVerticalScroll,
                        vProxy: vProxy
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
#endif
