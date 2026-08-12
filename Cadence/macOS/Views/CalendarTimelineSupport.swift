#if os(macOS)
import Combine
import EventKit
import SwiftUI

let calBaseHourHeight: CGFloat = 60
let calStartHour = 0
let calEndHour = 24
let calTimeWidth: CGFloat = 44
let calTimeInset: CGFloat = 10
let calTimeTotalWidth: CGFloat = calTimeWidth + calTimeInset
let calDayHeaderHeight: CGFloat = 52
let calAllDayBannerHeight: CGFloat = 90
let calRenderDays = 3650

struct CalendarTimelineViewportMetrics {
    let colWidth: CGFloat
    let timelineViewportWidth: CGFloat
    let totalDaysWidth: CGFloat
    let scrollViewportHeight: CGFloat
    let hourHeight: CGFloat

    init(geoSize: CGSize, viewMode: CadenceCalendarViewMode, zoomLevel: Int) {
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
        colWidth = computedColWidth
        timelineViewportWidth = computedViewportWidth
        totalDaysWidth = computedColWidth * CGFloat(calRenderDays)
        scrollViewportHeight = computedScrollViewportHeight
        hourHeight = TimelineZoom.hourHeight(viewportHeight: computedScrollViewportHeight, level: zoomLevel)
    }
}

struct DayBoundaryScrollTargetBehavior: ScrollTargetBehavior {
    let dayWidth: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let safeDayWidth = max(dayWidth, 1)
        let maxOffsetX = max(0, context.contentSize.width - context.containerSize.width)
        let rawDay = target.rect.minX / safeDayWidth
        let baseDay = floor(rawDay)
        let progress = rawDay - baseDay
        let velocityX = context.velocity.dx
        let velocityThreshold: CGFloat = 80
        let snappedDay: CGFloat

        if velocityX > velocityThreshold {
            snappedDay = progress > 0.14 ? baseDay + 1 : baseDay
        } else if velocityX < -velocityThreshold {
            snappedDay = progress < 0.86 ? baseDay : baseDay + 1
        } else {
            snappedDay = rawDay.rounded(.toNearestOrAwayFromZero)
        }

        let snappedX = snappedDay * safeDayWidth
        target.rect.origin.x = min(max(snappedX, 0), maxOffsetX)
        target.rect.size.width = context.containerSize.width
    }
}

/// `@Observable`, deliberately not `ObservableObject`. `headerOffset` is written on every
/// horizontal scroll frame, and `ObservableObject` invalidates *every* subscriber on any
/// `@Published` change regardless of what each one reads — which meant the whole
/// `CalendarPageView` body (three filter/group passes over every task) re-ran per scroll
/// frame just because it holds the object. With `@Observable`, only the views that actually
/// read `headerOffset` — `CalendarTimelineHeaderStrip` — are invalidated.
@Observable
final class CalendarTimelineScrollState {
    private(set) var headerOffset: CGFloat = 0

    func setHeaderOffset(_ newValue: CGFloat) {
        guard abs(headerOffset - newValue) >= 0.1 else { return }
        headerOffset = newValue
    }

    func jumpHeaderOffset(to newValue: CGFloat) {
        guard abs(headerOffset - newValue) >= 0.1 else { return }
        headerOffset = newValue
    }
}

final class CalendarEventDayCache {
    /// Sized for the *month grid*, which is the largest consumer: a realized month block is 42
    /// cells and two or three blocks can be alive in the lazy stack at once. At the old bound of
    /// 42 the grid evicted its own working set within a single pass and every rebuild went back
    /// to EventKit for all of them. Correctness does not depend on this number — the whole cache
    /// is dropped when `CalendarManager.storeVersion` changes.
    private let maxCachedDays = 256
    private var cachedStoreVersion: Int?
    private var timedEventsByDate: [String: [EKEvent]] = [:]
    private var allDayEventsByDate: [String: [EKEvent]] = [:]
    private var recentlyAccessedDateKeys: [String] = []

    func timedEvents(for date: Date, calendarManager: CalendarManager) -> [EKEvent] {
        guard calendarManager.isAuthorized else {
            clear()
            return []
        }
        refreshIfNeeded(storeVersion: calendarManager.storeVersion)
        let key = DateFormatters.dateKey(from: date)
        touch(key)
        if let cached = timedEventsByDate[key] { return cached }
        let events = calendarManager.fetchEvents(for: date)
        timedEventsByDate[key] = events
        pruneIfNeeded()
        return events
    }

    func allDayEvents(for date: Date, calendarManager: CalendarManager) -> [EKEvent] {
        guard calendarManager.isAuthorized else {
            clear()
            return []
        }
        refreshIfNeeded(storeVersion: calendarManager.storeVersion)
        let key = DateFormatters.dateKey(from: date)
        touch(key)
        if let cached = allDayEventsByDate[key] { return cached }
        let events = calendarManager.fetchAllDayEvents(for: date)
        allDayEventsByDate[key] = events
        pruneIfNeeded()
        return events
    }

    private func refreshIfNeeded(storeVersion: Int) {
        guard cachedStoreVersion != storeVersion else { return }
        cachedStoreVersion = storeVersion
        timedEventsByDate.removeAll(keepingCapacity: true)
        allDayEventsByDate.removeAll(keepingCapacity: true)
        recentlyAccessedDateKeys.removeAll(keepingCapacity: true)
    }

    private func clear() {
        cachedStoreVersion = nil
        timedEventsByDate.removeAll(keepingCapacity: true)
        allDayEventsByDate.removeAll(keepingCapacity: true)
        recentlyAccessedDateKeys.removeAll(keepingCapacity: true)
    }

    private func touch(_ key: String) {
        recentlyAccessedDateKeys.removeAll { $0 == key }
        recentlyAccessedDateKeys.append(key)
    }

    private func pruneIfNeeded() {
        guard recentlyAccessedDateKeys.count > maxCachedDays else { return }
        let staleKeys = recentlyAccessedDateKeys.prefix(recentlyAccessedDateKeys.count - maxCachedDays)
        for key in staleKeys {
            timedEventsByDate.removeValue(forKey: key)
            allDayEventsByDate.removeValue(forKey: key)
        }
        recentlyAccessedDateKeys.removeFirst(recentlyAccessedDateKeys.count - maxCachedDays)
    }
}
#endif
