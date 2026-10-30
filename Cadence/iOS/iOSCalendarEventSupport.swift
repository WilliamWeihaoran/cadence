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

    /// The **dark tinted plate** behind an event block, so the leading rail — not the plate — is
    /// what carries the calendar's colour.
    ///
    /// This used to be a local `saturation * 0.55, brightness * 0.6` rule — the same double-hit
    /// rule macOS abandoned because it rendered an orange calendar brown and a green one olive.
    /// It has gone through the shared luminance solve ever since, so an event is the same colour
    /// on both platforms; **T-3160 moved it from the `plate` treatment to the `rail` one**, which
    /// is Apple Calendar's look and the one an event now wears. The three `rail*` label tiers are
    /// solved against this exact luminance, so this is the function to change if the plate is ever
    /// to move — not the labels drawn on it.
    static func fillColor(for calendar: EKCalendar?) -> Color {
        CadenceCalendarEventStyle.railFill(for: color(for: calendar))
    }

    static func timeRangeLabel(for event: EKEvent) -> String {
        if event.isAllDay {
            return "All day"
        }
        // A list row names the whole event, not one day of it ([[T-8574]]): `minuteRange` clamps
        // to the start day and printed "10 PM – 12 AM" under both days of a 10 PM -> 2 AM event.
        let startDate = event.startDate ?? Date()
        let endDate = event.endDate ?? startDate.addingTimeInterval(30 * 60)
        return CadenceScheduleSupport.eventListTimeRangeLabel(from: startDate, to: endDate)
    }

    /// The event's span on `day`, in minutes from that day's midnight.
    ///
    /// The day matters: this used to read only the hour/minute of each end, so a 23:00 → 00:00
    /// event produced `end < start` and fell through to the 15-minute floor, and every column of
    /// a multi-day timed event drew the same 15-minute sliver. Defaults to the event's own start
    /// day. A list row's label does not read this -- it is `timeRangeLabel(for:)`, the whole span.
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
