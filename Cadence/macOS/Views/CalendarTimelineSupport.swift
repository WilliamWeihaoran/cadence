#if os(macOS)
import Combine
import EventKit
import SwiftUI

let calBaseHourHeight: CGFloat = 60
let calStartHour = 0
let calEndHour = 24
let calTimeWidth: CGFloat = 44
let calTimeInset: CGFloat = 10
let calTimeTotalWidth: CGFloat = 54
let calDayHeaderHeight: CGFloat = 52
let calAllDayBannerHeight: CGFloat = 90
let calRenderDays = 3650

struct CalendarTimelineViewportMetrics {
    let colWidth: CGFloat
    let timelineViewportWidth: CGFloat
    let totalDaysWidth: CGFloat
    let scrollViewportHeight: CGFloat
    let hourHeight: CGFloat

    init(geoSize: CGSize, viewMode: CalViewMode, zoomLevel: Int) {
        let availableTimelineWidth = max(0, geoSize.width - calTimeTotalWidth)
        let targetDayCount = CGFloat(viewMode.daysCount)
        let naturalColWidth = availableTimelineWidth / max(targetDayCount, 1)
        let computedColWidth: CGFloat
        let computedViewportWidth: CGFloat
        if naturalColWidth >= 80 || availableTimelineWidth <= 0 {
            computedColWidth = max(80, naturalColWidth)
            computedViewportWidth = availableTimelineWidth
        } else {
            let visibleWholeDays = max(1, floor(availableTimelineWidth / 80))
            computedColWidth = availableTimelineWidth / visibleWholeDays
            computedViewportWidth = computedColWidth * visibleWholeDays
        }
        let computedScrollViewportHeight = max(0, geoSize.height - calDayHeaderHeight - calAllDayBannerHeight - 1)
        let targetHours: CGFloat = zoomLevel == 1 ? 12 : zoomLevel == 2 ? 8 : 4

        colWidth = computedColWidth
        timelineViewportWidth = computedViewportWidth
        totalDaysWidth = computedColWidth * CGFloat(calRenderDays)
        scrollViewportHeight = computedScrollViewportHeight
        hourHeight = computedScrollViewportHeight / targetHours
    }
}

struct DayBoundaryScrollTargetBehavior: ScrollTargetBehavior {
    let dayWidth: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let safeDayWidth = max(dayWidth, 1)
        let maxOffsetX = max(0, context.contentSize.width - context.containerSize.width)
        let snappedX = (target.rect.minX / safeDayWidth).rounded(.toNearestOrAwayFromZero) * safeDayWidth
        target.rect.origin.x = min(max(snappedX, 0), maxOffsetX)
    }
}

final class CalendarTimelineScrollState: ObservableObject {
    @Published private(set) var headerOffset: CGFloat = 0

    func setHeaderOffset(_ newValue: CGFloat) {
        guard abs(headerOffset - newValue) >= 0.5 else { return }
        headerOffset = newValue
    }

    func jumpHeaderOffset(to newValue: CGFloat) {
        guard abs(headerOffset - newValue) >= 0.5 else { return }
        headerOffset = newValue
    }
}

final class CalendarEventDayCache {
    private var cachedStoreVersion: Int?
    private var timedEventsByDate: [String: [EKEvent]] = [:]
    private var allDayEventsByDate: [String: [EKEvent]] = [:]

    func timedEvents(for date: Date, calendarManager: CalendarManager) -> [EKEvent] {
        guard calendarManager.isAuthorized else {
            clear()
            return []
        }
        refreshIfNeeded(storeVersion: calendarManager.storeVersion)
        let key = DateFormatters.dateKey(from: date)
        if let cached = timedEventsByDate[key] { return cached }
        let events = calendarManager.fetchEvents(for: date)
        timedEventsByDate[key] = events
        return events
    }

    func allDayEvents(for date: Date, calendarManager: CalendarManager) -> [EKEvent] {
        guard calendarManager.isAuthorized else {
            clear()
            return []
        }
        refreshIfNeeded(storeVersion: calendarManager.storeVersion)
        let key = DateFormatters.dateKey(from: date)
        if let cached = allDayEventsByDate[key] { return cached }
        let events = calendarManager.fetchAllDayEvents(for: date)
        allDayEventsByDate[key] = events
        return events
    }

    private func refreshIfNeeded(storeVersion: Int) {
        guard cachedStoreVersion != storeVersion else { return }
        cachedStoreVersion = storeVersion
        timedEventsByDate.removeAll(keepingCapacity: true)
        allDayEventsByDate.removeAll(keepingCapacity: true)
    }

    private func clear() {
        cachedStoreVersion = nil
        timedEventsByDate.removeAll(keepingCapacity: true)
        allDayEventsByDate.removeAll(keepingCapacity: true)
    }
}
#endif
