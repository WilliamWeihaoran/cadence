#if os(macOS)
import AppKit
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
        self.calendarColor = Color(cgColor: event.calendar?.cgColor ?? Theme.nsDim.cgColor)
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

/// Time text for a month-cell event chip, split out so the segment rule is testable without a view.
enum CalendarEventChipTimeSupport {
    /// `nil` whenever no single time describes the chip: an all-day event has none, and a middle
    /// segment of a multi-day event fills its whole day, so either endpoint would name a time that
    /// day never sees.
    static func label(
        isAllDay: Bool,
        isMultiDayTimedEvent: Bool,
        isFirstSegment: Bool,
        isLastSegment: Bool,
        eventStartMin: Int,
        eventEndMin: Int
    ) -> String? {
        guard !isAllDay else { return nil }
        guard isMultiDayTimedEvent else { return TimeFormatters.timeString(from: eventStartMin) }
        if isFirstSegment { return TimeFormatters.timeString(from: eventStartMin) }
        if isLastSegment { return "ends \(TimeFormatters.timeString(from: eventEndMin))" }
        return nil
    }
}

extension CalendarEventItem {
    /// Start time for the day the event begins, `ends <time>` on the day it finishes, nothing in
    /// between. Minutes come off the event's own stored values and off `eventEndDate` measured in
    /// the same calendar the segment was cut in — never a separately-zoned formatter.
    func chipTimeLabel(calendar: Calendar = .current) -> String? {
        CalendarEventChipTimeSupport.label(
            isAllDay: ekEvent.isAllDay,
            isMultiDayTimedEvent: isMultiDayTimedEvent,
            isFirstSegment: isFirstSegment,
            isLastSegment: isLastSegment,
            eventStartMin: eventStartMin,
            eventEndMin: CalendarEventIdentity.startMinute(for: eventEndDate, calendar: calendar)
        )
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
        calendarColor = Color(cgColor: event.calendar?.cgColor ?? Theme.nsDim.cgColor)
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

/// macOS-facing name for event identity. Every member forwards to `CadenceEventNoteSupport`, which
/// is the one implementation — this used to be a byte-for-byte copy of it, and the two drifted in
/// exactly the way a duplicate always does: a wrong recurrence predicate had to be found and fixed
/// twice. Keep the forwarding; do not re-inline a body here.
enum CalendarEventIdentity {
    static func rawIdentifier(for event: EKEvent) -> String {
        CadenceEventNoteSupport.rawIdentifier(for: event)
    }

    static func identifier(for event: EKEvent) -> String {
        CadenceEventNoteSupport.identifier(for: event)
    }

    static func occurrenceIdentifier(
        baseIdentifier: String,
        occurrenceDate: Date,
        calendar: Calendar = .current
    ) -> String {
        CadenceEventNoteSupport.occurrenceIdentifier(
            baseIdentifier: baseIdentifier,
            occurrenceDate: occurrenceDate,
            calendar: calendar
        )
    }

    static func lookupIdentifier(from identifier: String) -> String {
        CadenceEventNoteSupport.lookupIdentifier(from: identifier)
    }

    static func matches(_ event: EKEvent, identifier: String) -> Bool {
        CadenceEventNoteSupport.matches(event, identifier: identifier)
    }

    static func isRecurringSeriesMember(_ event: EKEvent) -> Bool {
        CadenceEventNoteSupport.isRecurringSeriesMember(event)
    }

    static func startMinute(for date: Date, calendar: Calendar = .current) -> Int {
        CadenceEventNoteSupport.startMinute(for: date, calendar: calendar)
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

/// macOS's name for `CadenceCalendarEventStyle`.
///
/// The luminance solve, the label tiers and the opacity ladders all live in
/// `Shared/CadenceCalendarEventStyle.swift` now, so macOS and iOS paint an event the same way by
/// construction rather than by two people writing the same colour rule twice. This forwarder keeps
/// the macOS call sites — and their `isHovered:` vocabulary, which has no iOS counterpart — intact.
enum CalendarEventVisualStyle {
    static var fillSaturationScale: Double { CadenceCalendarEventStyle.fillSaturationScale }

    static func fillLuminance(isSelected: Bool = false, isHovered: Bool = false) -> Double {
        CadenceCalendarEventStyle.fillLuminance(isSelected: isSelected, isActive: isHovered)
    }

    static func fill(for calendarColor: Color, isSelected: Bool = false, isHovered: Bool = false) -> Color {
        CadenceCalendarEventStyle.fill(for: calendarColor, isSelected: isSelected, isActive: isHovered)
    }

    static func chipFill(for calendarColor: Color, isActive: Bool = false) -> Color {
        CadenceCalendarEventStyle.chipFill(for: calendarColor, isActive: isActive)
    }

    static var primaryLabelColor: Color { CadenceCalendarEventStyle.primaryLabelColor }

    static func secondaryLabelColor(isSelected: Bool = false, isHovered: Bool = false) -> Color {
        CadenceCalendarEventStyle.secondaryLabelColor(isSelected: isSelected, isActive: isHovered)
    }

    static func tertiaryLabelColor(isSelected: Bool = false, isHovered: Bool = false) -> Color {
        CadenceCalendarEventStyle.tertiaryLabelColor(isSelected: isSelected, isActive: isHovered)
    }

    static func blockAccentOpacity(isSelected: Bool = false, isHovered: Bool = false) -> Double {
        CadenceCalendarEventStyle.blockAccentOpacity(isSelected: isSelected, isActive: isHovered)
    }

    static func chipBorderOpacity(isActive: Bool = false) -> Double {
        CadenceCalendarEventStyle.chipBorderOpacity(isActive: isActive)
    }

    static func surfaceOpacity(isActive: Bool) -> Double {
        CadenceCalendarEventStyle.surfaceOpacity(isActive: isActive)
    }

    static func tintOpacity(isSelected: Bool = false, isHovered: Bool = false) -> Double {
        CadenceCalendarEventStyle.tintOpacity(isSelected: isSelected, isActive: isHovered)
    }

    static func borderOpacity(isSelected: Bool = false, isHovered: Bool = false) -> Double {
        CadenceCalendarEventStyle.borderOpacity(isSelected: isSelected, isActive: isHovered)
    }

    static func chipTintOpacity(isActive: Bool = false) -> Double {
        CadenceCalendarEventStyle.chipTintOpacity(isActive: isActive)
    }
}
#endif
