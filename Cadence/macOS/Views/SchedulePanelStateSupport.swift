#if os(macOS)
import SwiftUI

enum SchedulePanelStateSupport {
    static func clampedRememberedHour(offsetY: CGFloat, geoHeight: CGFloat, zoomLevel: Int) -> Int {
        let hourHeight = TimelineZoom.hourHeight(viewportHeight: geoHeight, level: zoomLevel)
        let rawHour = schedStartHour + Int(offsetY / max(hourHeight, 1))
        return min(max(rawHour, schedStartHour), schedEndHour - 1)
    }

    /// The hour Today's timeline opens at: **the iPad's rule, through the iPad's function**
    /// ([[T-18863]]). `iOSTodaySchedulePanel` draws today in `iOSCalendarTimelineGrid`, which asks
    /// `CadenceScheduleSupport.initialTimelineHour` on every appearance -- one hour above the day's
    /// first timed item, else the current hour less one -- and writes nothing. This pane shows
    /// only today, so `showsToday` is always true and the work-hours rung is unreachable here.
    ///
    /// It used to return `@AppStorage("scheduleRememberedScrollHour")` whenever that was at or
    /// past `schedStartHour`, which is 0 -- so after the first scroll ever, every launch on every
    /// later day opened wherever the last scroll had stopped, above or below the day's items. That
    /// key arrived with the March UI rework (`7dddba83`) with no reason recorded; [[T-1498]] only
    /// made its writes cheaper. Nothing reads it now ([[T-18869]]).
    static func restoreScrollHour(firstTimedMinute: Int?) -> Int {
        openingHour(firstTimedMinute: firstTimedMinute, now: DateFormatters.now())
    }

    /// `restoreScrollHour`, with the clock passed in so a test can pin it.
    static func openingHour(firstTimedMinute: Int?, now: Date, calendar: Calendar = .current) -> Int {
        CadenceScheduleSupport.initialTimelineHour(
            firstTimedMinute: firstTimedMinute,
            showsToday: true,
            now: now,
            startHour: schedStartHour,
            endHour: schedEndHour,
            calendar: calendar
        )
    }

    /// The earliest minute a block starts at on today's ladder: the scheduled tasks and the timed
    /// event segments `TimelineDayCanvas` draws, the two inputs the iPad grid's
    /// `timedStartMinutes` reads.
    static func firstTimedMinute(taskStartMinutes: [Int], eventStartMinutes: [Int]) -> Int? {
        CadenceScheduleSupport.earliestTimedStartMinute(taskStartMinutes + eventStartMinutes)
    }

    static func focusTargetHour() -> Int {
        let currentHour = Calendar.current.component(.hour, from: DateFormatters.now())
        return max(schedStartHour, min(currentHour - 1, schedEndHour - 1))
    }

    static func highlightFocus(setHighlighted: @escaping (Bool) -> Void) {
        withAnimation(.easeOut(duration: 0.16)) {
            setHighlighted(true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(.easeOut(duration: 0.24)) {
                setHighlighted(false)
            }
        }
    }
}
#endif
