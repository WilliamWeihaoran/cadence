#if os(iOS)
import EventKit
import SwiftUI

enum iOSCalendarEventSupport {
    static func title(for event: EKEvent) -> String {
        guard let title = event.title, !title.isEmpty else {
            return "Untitled Event"
        }
        return title
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

    static func minuteRange(for event: EKEvent) -> (start: Int, end: Int) {
        let calendar = Calendar.current
        let startDate = event.startDate ?? Date()
        let endDate = event.endDate ?? startDate.addingTimeInterval(30 * 60)
        let startComponents = calendar.dateComponents([.hour, .minute], from: startDate)
        let endComponents = calendar.dateComponents([.hour, .minute], from: endDate)
        let start = (startComponents.hour ?? CadenceScheduleSupport.calendarStartHour) * 60 + (startComponents.minute ?? 0)
        let end = (endComponents.hour ?? CadenceScheduleSupport.calendarStartHour) * 60 + (endComponents.minute ?? 0)
        return (start, max(start + 15, end))
    }
}
#endif
