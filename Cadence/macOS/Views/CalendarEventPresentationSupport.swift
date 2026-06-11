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
    let eventStartDate: Date
    let eventEndDate: Date
    let eventDateKey: String
    let eventStartMin: Int
    let eventDurationMinutes: Int
    let isMultiDayTimedEvent: Bool
    let isFirstSegment: Bool
    let isLastSegment: Bool
    let calendarColor: Color
    let calendarTitle: String
    let seriesIdentifier: String
    let occurrenceDateKey: String
    let occurrenceStartMin: Int
    let isRecurringSeriesMember: Bool
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
        let eventStart = event.startDate ?? event.occurrenceDate ?? segmentStart
        let fallbackEventEnd = calendar.date(byAdding: .minute, value: 5, to: eventStart) ?? eventStart
        let eventEnd = max(event.endDate ?? fallbackEventEnd, fallbackEventEnd)
        self.eventIdentifier = CalendarEventIdentity.rawIdentifier(for: event)
        self.id = CalendarEventIdentity.identifier(for: event)
        self.title = event.title ?? "Untitled"
        let dayStart = calendar.startOfDay(for: day)
        self.dateKey = DateFormatters.dateKey(from: dayStart)
        let comps = calendar.dateComponents([.hour, .minute], from: segmentStart)
        self.startMin = max(0, (comps.hour ?? 0) * 60 + (comps.minute ?? 0))
        let raw = max(5, Int(segmentEnd.timeIntervalSince(segmentStart) / 60))
        self.durationMinutes = min(raw, 24 * 60 - self.startMin)
        self.eventStartDate = eventStart
        self.eventEndDate = eventEnd
        self.eventDateKey = DateFormatters.dateKey(from: eventStart)
        self.eventStartMin = CalendarEventIdentity.startMinute(for: eventStart, calendar: calendar)
        self.eventDurationMinutes = max(5, Int(eventEnd.timeIntervalSince(eventStart) / 60))
        self.isMultiDayTimedEvent = !calendar.isDate(eventStart, inSameDayAs: eventEnd)
        self.isFirstSegment = abs(segmentStart.timeIntervalSince(eventStart)) < 1
        self.isLastSegment = abs(segmentEnd.timeIntervalSince(eventEnd)) < 1
        self.calendarColor = Color(cgColor: event.calendar?.cgColor ?? CGColor(gray: 0.5, alpha: 1))
        self.calendarTitle = event.calendar?.title ?? ""
        self.seriesIdentifier = CalendarEventIdentity.lookupIdentifier(from: self.id)
        self.occurrenceDateKey = DateFormatters.dateKey(from: event.startDate ?? event.occurrenceDate ?? dayStart)
        self.occurrenceStartMin = CalendarEventIdentity.startMinute(for: event.startDate ?? event.occurrenceDate ?? segmentStart, calendar: calendar)
        self.isRecurringSeriesMember = CalendarEventIdentity.isRecurringSeriesMember(event)
        self.ekEvent = event
    }

    func eventDateRangeForEditedSegment(
        startMin editedStartMin: Int,
        durationMinutes editedDurationMinutes: Int,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date)? {
        guard let segmentDay = DateFormatters.date(from: dateKey) else { return nil }
        let segmentStart = calendar.date(byAdding: .minute, value: editedStartMin, to: segmentDay) ?? segmentDay
        let segmentEnd = calendar.date(byAdding: .minute, value: max(5, editedDurationMinutes), to: segmentStart) ?? segmentStart

        guard isMultiDayTimedEvent else {
            return segmentEnd > segmentStart ? (segmentStart, segmentEnd) : nil
        }

        var nextStart = eventStartDate
        var nextEnd = eventEndDate
        if isFirstSegment {
            nextStart = segmentStart
        }
        if isLastSegment {
            nextEnd = segmentEnd
        }
        guard nextEnd > nextStart else { return nil }
        return (nextStart, nextEnd)
    }

    func eventDateRangeForMovedSegment(startMin movedStartMin: Int, calendar: Calendar = .current) -> (start: Date, end: Date)? {
        guard isMultiDayTimedEvent else {
            return eventDateRangeForEditedSegment(
                startMin: movedStartMin,
                durationMinutes: durationMinutes,
                calendar: calendar
            )
        }
        let deltaMinutes = movedStartMin - startMin
        let nextStart = calendar.date(byAdding: .minute, value: deltaMinutes, to: eventStartDate) ?? eventStartDate
        let nextEnd = calendar.date(byAdding: .minute, value: deltaMinutes, to: eventEndDate) ?? eventEndDate
        guard nextEnd > nextStart else { return nil }
        return (nextStart, nextEnd)
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
    let seriesIdentifier: String
    let occurrenceDateKey: String
    let occurrenceStartMin: Int
    let isRecurringSeriesMember: Bool
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
        seriesIdentifier = item.seriesIdentifier
        occurrenceDateKey = item.occurrenceDateKey
        occurrenceStartMin = item.occurrenceStartMin
        isRecurringSeriesMember = item.isRecurringSeriesMember
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
        seriesIdentifier = CalendarEventIdentity.lookupIdentifier(from: id)
        let sourceDate = event.startDate ?? event.occurrenceDate ?? date
        occurrenceDateKey = DateFormatters.dateKey(from: sourceDate)
        occurrenceStartMin = CalendarEventIdentity.startMinute(for: sourceDate, calendar: calendar)
        isRecurringSeriesMember = CalendarEventIdentity.isRecurringSeriesMember(event)
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

    static func isRecurringSeriesMember(_ event: EKEvent) -> Bool {
        event.hasRecurrenceRules || event.isDetached || event.occurrenceDate != nil
    }

    static func startMinute(for date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return ((components.hour ?? 0) * 60) + (components.minute ?? 0)
    }

    private static func recurringOccurrenceDate(for event: EKEvent) -> Date? {
        guard isRecurringSeriesMember(event) else { return nil }
        return event.occurrenceDate
    }

    private static func fallbackIdentifier(for event: EKEvent) -> String {
        let start = event.startDate ?? event.occurrenceDate ?? Date.distantPast
        let startMinute = startMinute(for: start)
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
            "seriesID=\(item.seriesIdentifier)",
            "recurring=\(item.isRecurringSeriesMember)",
            "occurrence=\(item.occurrenceDateKey):\(item.occurrenceStartMin)",
            "date=\(item.dateKey)",
            "start=\(item.startMin)",
            "duration=\(item.durationMinutes)",
            "eventDate=\(item.eventDateKey)",
            "eventStart=\(item.eventStartMin)",
            "eventDuration=\(item.eventDurationMinutes)",
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
