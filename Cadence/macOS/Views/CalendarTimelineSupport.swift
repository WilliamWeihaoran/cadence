#if os(macOS)
import Combine
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
        let computedColWidth = max(80, (geoSize.width - calTimeTotalWidth) / CGFloat(viewMode.daysCount))
        let computedViewportWidth = max(0, geoSize.width - calTimeTotalWidth)
        let computedScrollViewportHeight = max(0, geoSize.height - calDayHeaderHeight - calAllDayBannerHeight - 1)
        let targetHours: CGFloat = zoomLevel == 1 ? 12 : zoomLevel == 2 ? 8 : 4

        colWidth = computedColWidth
        timelineViewportWidth = computedViewportWidth
        totalDaysWidth = computedColWidth * CGFloat(calRenderDays)
        scrollViewportHeight = computedScrollViewportHeight
        hourHeight = computedScrollViewportHeight / targetHours
    }
}

final class CalendarTimelineScrollState: ObservableObject {
    @Published private(set) var headerOffset: CGFloat = 0

    func setHeaderOffset(_ newValue: CGFloat) {
        let snappedValue = newValue.rounded(.toNearestOrAwayFromZero)
        guard abs(headerOffset - snappedValue) >= 1 else { return }
        headerOffset = snappedValue
    }

    func jumpHeaderOffset(to newValue: CGFloat) {
        let snappedValue = newValue.rounded(.toNearestOrAwayFromZero)
        guard headerOffset != snappedValue else { return }
        headerOffset = snappedValue
    }
}
#endif
