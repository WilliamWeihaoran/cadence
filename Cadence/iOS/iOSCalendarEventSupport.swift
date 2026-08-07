#if os(iOS)
import EventKit
import SwiftUI
import UIKit

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

    /// Desaturated, darkened variant of the calendar's own bright color, used as a solid
    /// event-block fill so vivid EventKit calendar colors stay legible against the dark theme.
    static func fillColor(for calendar: EKCalendar?) -> Color {
        fillColor(from: color(for: calendar))
    }

    static func fillColor(from base: Color) -> Color {
        let uiColor = UIColor(base)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Color(UIColor(
            hue: hue,
            saturation: min(saturation * 0.55, 1),
            brightness: max(brightness * 0.6, 0.22),
            alpha: alpha
        ))
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
