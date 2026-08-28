#if os(iOS)
import EventKit
import SwiftUI

enum iOSCalendarEventSupport {
    static func title(for event: EKEvent) -> String {
        CadenceEventTitleSupport.displayTitle(event.title)
    }

    static func color(for calendar: EKCalendar?) -> Color {
        guard let cgColor = calendar?.cgColor else {
            return Theme.blue
        }
        return Color(cgColor: cgColor)
    }

    /// Solid fill for an event block, so vivid EventKit calendar colors stay legible against the
    /// dark theme.
    ///
    /// This used to be a local `saturation * 0.55, brightness * 0.6` rule — the same double-hit
    /// rule macOS abandoned because it rendered an orange calendar brown and a green one olive.
    /// It now goes through the shared luminance solve, so an event is the same colour on both
    /// platforms and `Theme.onColor` / `onColorSecondary` are guaranteed to clear AA on top of it.
    static func fillColor(for calendar: EKCalendar?) -> Color {
        CadenceCalendarEventStyle.fill(for: color(for: calendar))
    }

    static func timeRangeLabel(for event: EKEvent) -> String {
        if event.isAllDay {
            return "All day"
        }
        let range = minuteRange(for: event)
        return CadenceScheduleSupport.timeRangeLabel(startMinute: range.start, endMinute: range.end)
    }

    /// The event's span on `day`, in minutes from that day's midnight.
    ///
    /// The day matters: this used to read only the hour/minute of each end, so a 23:00 → 00:00
    /// event produced `end < start` and fell through to the 15-minute floor, and every column of
    /// a multi-day timed event drew the same 15-minute sliver. Defaults to the event's own start
    /// day, which is what a label with no column context wants.
    static func minuteRange(for event: EKEvent, on day: Date? = nil) -> (start: Int, end: Int) {
        let calendar = Calendar.current
        let startDate = event.startDate ?? Date()
        let endDate = event.endDate ?? startDate.addingTimeInterval(30 * 60)
        return CadenceScheduleSupport.minuteRange(
            from: startDate,
            to: endDate,
            on: day ?? startDate,
            calendar: calendar
        )
    }
}
#endif
