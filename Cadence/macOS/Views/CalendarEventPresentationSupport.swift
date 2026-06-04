#if os(macOS)
import EventKit
import SwiftUI

struct CalendarEventItem: Identifiable {
    let id: String
    let eventIdentifier: String
    let title: String
    let dateKey: String
    let startMin: Int
    let durationMinutes: Int
    let calendarColor: Color
    let calendarTitle: String
    let ekEvent: EKEvent

    init(event: EKEvent) {
        let start = event.startDate ?? Date()
        let end = event.endDate ?? start
        self.init(event: event, segmentStart: start, segmentEnd: max(end, start.addingTimeInterval(5 * 60)), day: start)
    }

    init?(event: EKEvent, clippedTo date: Date, calendar: Calendar = .current) {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let eventStart = event.startDate ?? event.occurrenceDate ?? dayStart
        let fallbackEnd = calendar.date(byAdding: .minute, value: 5, to: eventStart) ?? eventStart
        let eventEnd = max(event.endDate ?? fallbackEnd, fallbackEnd)
        let segmentStart = max(eventStart, dayStart)
        let segmentEnd = min(eventEnd, dayEnd)
        guard segmentEnd > segmentStart else { return nil }
        self.init(event: event, segmentStart: segmentStart, segmentEnd: segmentEnd, day: dayStart)
    }

    static func timedSegments(from events: [EKEvent], for date: Date, calendar: Calendar = .current) -> [CalendarEventItem] {
        events.compactMap { CalendarEventItem(event: $0, clippedTo: date, calendar: calendar) }
    }

    private init(event: EKEvent, segmentStart: Date, segmentEnd: Date, day: Date, calendar: Calendar = .current) {
        self.eventIdentifier = CalendarEventIdentity.rawIdentifier(for: event)
        self.id = CalendarEventIdentity.identifier(for: event)
        self.title = event.title ?? "Untitled"
        let dayStart = calendar.startOfDay(for: day)
        self.dateKey = DateFormatters.dateKey(from: dayStart)
        let comps = calendar.dateComponents([.hour, .minute], from: segmentStart)
        self.startMin = max(0, (comps.hour ?? 0) * 60 + (comps.minute ?? 0))
        let raw = max(5, Int(segmentEnd.timeIntervalSince(segmentStart) / 60))
        self.durationMinutes = min(raw, 24 * 60 - self.startMin)
        self.calendarColor = Color(cgColor: event.calendar?.cgColor ?? CGColor(gray: 0.5, alpha: 1))
        self.calendarTitle = event.calendar?.title ?? ""
        self.ekEvent = event
    }
}

struct CalendarBoardEventDisplayItem: Identifiable {
    let id: String
    let title: String
    let dateKey: String
    let startMin: Int
    let durationMinutes: Int
    let isAllDay: Bool
    let calendarColor: Color
    let calendarTitle: String
    let ekEvent: EKEvent

    init(timed item: CalendarEventItem) {
        id = item.id
        title = item.title
        dateKey = item.dateKey
        startMin = item.startMin
        durationMinutes = item.durationMinutes
        isAllDay = false
        calendarColor = item.calendarColor
        calendarTitle = item.calendarTitle
        ekEvent = item.ekEvent
    }

    init(allDay event: EKEvent, date: Date, calendar: Calendar = .current) {
        id = CalendarEventIdentity.identifier(for: event)
        title = event.title ?? "Untitled"
        dateKey = DateFormatters.dateKey(from: calendar.startOfDay(for: date))
        startMin = CalendarBoardPlannerSupport.allDaySortMinute
        durationMinutes = 24 * 60
        isAllDay = true
        calendarColor = Color(cgColor: event.calendar?.cgColor ?? CGColor(gray: 0.5, alpha: 1))
        calendarTitle = event.calendar?.title ?? ""
        ekEvent = event
    }

    var sortKey: CalendarBoardSortKey {
        CalendarBoardPlannerSupport.sortKeyForCalendarEvent(
            id: id,
            startMinute: startMin,
            isAllDay: isAllDay,
            kindRank: 0
        )
    }

    var editItem: CalendarEventItem {
        if isAllDay {
            return CalendarEventItem(event: ekEvent)
        }
        return CalendarEventItem(event: ekEvent, clippedTo: DateFormatters.date(from: dateKey) ?? ekEvent.startDate ?? Date()) ?? CalendarEventItem(event: ekEvent)
    }
}

struct CalendarAllDayEventItem: Identifiable {
    let id: String
    let event: EKEvent

    init(event: EKEvent) {
        self.id = CalendarEventIdentity.identifier(for: event)
        self.event = event
    }
}

enum CalendarEventIdentity {
    private static let occurrenceSeparator = "#occurrence="

    static func rawIdentifier(for event: EKEvent) -> String {
        if let eventIdentifier = event.eventIdentifier, !eventIdentifier.isEmpty {
            return eventIdentifier
        }
        let itemIdentifier = event.calendarItemIdentifier
        return itemIdentifier.isEmpty ? fallbackIdentifier(for: event) : itemIdentifier
    }

    static func identifier(for event: EKEvent) -> String {
        let baseIdentifier = rawIdentifier(for: event)
        guard let occurrenceDate = recurringOccurrenceDate(for: event) else {
            return baseIdentifier
        }
        return occurrenceIdentifier(baseIdentifier: baseIdentifier, occurrenceDate: occurrenceDate)
    }

    static func occurrenceIdentifier(
        baseIdentifier: String,
        occurrenceDate: Date,
        calendar: Calendar = .current
    ) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: occurrenceDate)
        let occurrenceMinute = ((components.hour ?? 0) * 60) + (components.minute ?? 0)
        return "\(baseIdentifier)\(occurrenceSeparator)\(DateFormatters.dateKey(from: occurrenceDate)):\(occurrenceMinute)"
    }

    static func lookupIdentifier(from identifier: String) -> String {
        identifier.components(separatedBy: occurrenceSeparator).first ?? identifier
    }

    static func matches(_ event: EKEvent, identifier: String) -> Bool {
        identifier == self.identifier(for: event) || identifier == rawIdentifier(for: event)
    }

    private static func recurringOccurrenceDate(for event: EKEvent) -> Date? {
        guard event.hasRecurrenceRules || event.isDetached else { return nil }
        return event.occurrenceDate
    }

    private static func fallbackIdentifier(for event: EKEvent) -> String {
        let start = event.startDate ?? event.occurrenceDate ?? Date.distantPast
        let components = Calendar.current.dateComponents([.hour, .minute], from: start)
        let startMinute = ((components.hour ?? 0) * 60) + (components.minute ?? 0)
        let calendarID = event.calendar?.calendarIdentifier ?? "calendar"
        let title = (event.title ?? "untitled")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "|", with: "-")
        return "event-fallback|\(calendarID)|\(DateFormatters.dateKey(from: start))|\(startMinute)|\(title)"
    }
}

struct CalendarAllDayEventDropPayload {
    let sourceDateKey: String
    let eventIdentifier: String
}

enum CalendarEventDragPayload {
    private static let prefix = "allDayEvent:"
    private static let separator = "|"

    static func string(for event: EKEvent) -> String {
        let sourceDate = event.startDate ?? event.occurrenceDate ?? Date()
        return "\(prefix)\(DateFormatters.dateKey(from: sourceDate))\(separator)\(CalendarEventIdentity.identifier(for: event))"
    }

    static func allDayEventPayload(from rawValue: String) -> CalendarAllDayEventDropPayload? {
        guard rawValue.hasPrefix(prefix) else { return nil }
        let body = String(rawValue.dropFirst(prefix.count))
        let parts = body.split(separator: Character(separator), maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            return nil
        }
        return CalendarAllDayEventDropPayload(sourceDateKey: parts[0], eventIdentifier: parts[1])
    }
}

enum CalendarEventPresentationDiagnostics {
    static func summary(for item: CalendarEventItem) -> String {
        [
            "eventID=\(item.eventIdentifier)",
            "segmentID=\(item.id)",
            "date=\(item.dateKey)",
            "start=\(item.startMin)",
            "duration=\(item.durationMinutes)",
            "title=\(item.title)"
        ].joined(separator: " ")
    }
}

enum CalendarEventVisualStyle {
    static func blockFillOpacity(isSelected: Bool = false, isHovered: Bool = false) -> Double {
        if isSelected { return 0.80 }
        if isHovered { return 0.74 }
        return 0.66
    }

    static func blockHighlightOpacity(isSelected: Bool = false, isHovered: Bool = false) -> Double {
        if isSelected { return 0.08 }
        if isHovered { return 0.05 }
        return 0.035
    }

    static func blockAccentOpacity(isSelected: Bool = false, isHovered: Bool = false) -> Double {
        if isSelected { return 0.48 }
        if isHovered { return 0.34 }
        return 0.18
    }

    static func chipFillOpacity(isActive: Bool = false) -> Double {
        isActive ? 0.66 : 0.58
    }

    static func chipBorderOpacity(isActive: Bool = false) -> Double {
        isActive ? 0.46 : 0.34
    }

    static func surfaceOpacity(isActive: Bool) -> Double {
        isActive ? 0.92 : 0.82
    }

    static func tintOpacity(isSelected: Bool = false, isHovered: Bool = false) -> Double {
        if isSelected { return 0.24 }
        if isHovered { return 0.18 }
        return 0.12
    }

    static func borderOpacity(isSelected: Bool = false, isHovered: Bool = false) -> Double {
        if isSelected { return 0.46 }
        if isHovered { return 0.34 }
        return 0.22
    }

    static func chipTintOpacity(isActive: Bool = false) -> Double {
        isActive ? 0.18 : 0.11
    }
}
#endif
