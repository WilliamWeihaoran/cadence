#if os(macOS)
import Combine
import EventKit
import SwiftUI

struct CalendarPageToolbar: View {
    let calendarTitleLabel: String
    let viewMode: CadenceCalendarViewMode
    let presentation: CadenceCalendarPresentation
    let scrollToToday: () -> Void
    let setViewMode: (CadenceCalendarViewMode) -> Void
    let setPresentation: (CadenceCalendarPresentation) -> Void
    let moveBoardWindow: (Int) -> Void
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

            if presentation == .timeline && viewMode != .month {
                CalendarToolbarZoomControl(zoomLevel: $zoomLevel, range: 1...3)
            }

            if presentation == .board {
                CalendarBoardWindowNavigationControl(moveWindow: moveBoardWindow)
            }

            CalendarViewModeControl(
                viewMode: viewMode,
                presentation: presentation,
                setViewMode: setViewMode,
                setPresentation: setPresentation
            )

            CalendarGhostButton(title: "Today", systemImage: "location.fill", action: scrollToToday)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.surface)
    }
}

private struct CalendarViewModeControl: View {
    let viewMode: CadenceCalendarViewMode
    let presentation: CadenceCalendarPresentation
    let setViewMode: (CadenceCalendarViewMode) -> Void
    let setPresentation: (CadenceCalendarPresentation) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(CadenceCalendarViewMode.pickerCases, id: \.self) { mode in
                Button { setViewMode(mode) } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 11, weight: presentation == .timeline && viewMode == mode ? .semibold : .medium))
                        .foregroundStyle(presentation == .timeline && viewMode == mode ? Theme.blue : Theme.dim)
                        .frame(minWidth: 68, minHeight: 28)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(presentation == .timeline && viewMode == mode ? Theme.blue.opacity(0.10) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(presentation == .timeline && viewMode == mode ? Theme.blue.opacity(0.26) : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.cadencePlain)
            }

            Button { setPresentation(.board) } label: {
                Text("Board")
                    .font(.system(size: 11, weight: presentation == .board ? .semibold : .medium))
                    .foregroundStyle(presentation == .board ? Theme.blue : Theme.dim)
                    .frame(minWidth: 68, minHeight: 28)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(presentation == .board ? Theme.blue.opacity(0.10) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(presentation == .board ? Theme.blue.opacity(0.26) : Color.clear, lineWidth: 1)
                    )
            }
            .buttonStyle(.cadencePlain)
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Theme.borderSubtle.opacity(0.18), lineWidth: 1)
                )
        )
    }
}

private struct CalendarBoardWindowNavigationControl: View {
    let moveWindow: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            CalendarIconGhostButton(systemImage: "chevron.left", isEnabled: true) {
                moveWindow(-1)
            }
            .help("Previous 7 days")

            CalendarIconGhostButton(systemImage: "chevron.right", isEnabled: true) {
                moveWindow(1)
            }
            .help("Next 7 days")
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Theme.borderSubtle.opacity(0.18), lineWidth: 1)
                )
        )
    }
}

private struct CalendarToolbarZoomControl: View {
    @Binding var zoomLevel: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 6) {
            CalendarIconGhostButton(
                systemImage: "minus",
                isEnabled: zoomLevel > range.lowerBound
            ) {
                if zoomLevel > range.lowerBound { zoomLevel -= 1 }
            }

            Text("\(zoomLevel)x")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .frame(minWidth: 24)

            CalendarIconGhostButton(
                systemImage: "plus",
                isEnabled: zoomLevel < range.upperBound
            ) {
                if zoomLevel < range.upperBound { zoomLevel += 1 }
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Theme.borderSubtle.opacity(0.18), lineWidth: 1)
                )
        )
    }
}

private struct CalendarGhostButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Theme.blue)
            .frame(minHeight: 28)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(Theme.blue.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Theme.blue.opacity(0.24), lineWidth: 1)
            )
        }
        .buttonStyle(.cadencePlain)
    }
}

private struct CalendarIconGhostButton: View {
    let systemImage: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isEnabled ? Theme.dim : Theme.dim.opacity(0.32))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Theme.borderSubtle.opacity(isEnabled ? 0.18 : 0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.cadencePlain)
        .disabled(!isEnabled)
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
    let viewMode: CadenceCalendarViewMode
    @Binding var zoomLevel: Int
    @Binding var rememberedScrollHour: Int
    @Binding var anchorDateKey: String
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
    let onRestoreTimelineScrollIfNeeded: (ScrollViewProxy, ScrollViewProxy) -> Void

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
                            anchorDateKey: $anchorDateKey,
                            visibleTimelineDayIndex: $visibleTimelineDayIndex,
                            isRestoringHorizontalScroll: $isRestoringHorizontalScroll,
                            didRestoreTimelineScroll: $didRestoreTimelineScroll,
                            externalJumpDayIndex: $externalJumpDayIndex,
                            externalJumpToken: externalJumpToken,
                            timelineScrollState: timelineScrollState,
                            eventCache: eventCache,
                            onPersistVisibleTimelineDay: onPersistVisibleTimelineDay,
                            onRestoreTimelineScrollIfNeeded: { hProxy in
                                onRestoreTimelineScrollIfNeeded(vProxy, hProxy)
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
