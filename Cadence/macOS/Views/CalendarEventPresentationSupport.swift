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

    // MARK: - Event fill
    //
    // A calendar event is drawn as a SOLID plate of the calendar's own colour — in the week/day
    // timeline, in the month grid, and in the all-day banner. That fill has now been tuned in both
    // directions, so both constraints are written down here rather than rediscovered a third time.
    //
    // 1. It must not read as a task. A task block is a neutral `Theme.surfaceElevated` card
    //    wearing a ~14% wash of its list colour, plus a 3pt leading colour strip and a completion
    //    circle. An event has none of those; the plate *is* the affordance. So the plate cannot
    //    simply be the raw calendar colour — a day of raw iCal hues would shout louder than the
    //    tasks beside it, which is backwards for the half of the schedule you cannot edit.
    // 2. It must still be recognisably *that* hue. The previous rule hit the colour twice — half
    //    the saturation *and* a hard brightness ceiling of 0.4 — which is what left an orange
    //    calendar rendering as brown (#6B573A) and a green one as olive (#476B50).
    //
    // The rule below separates the two jobs the old one conflated. Saturation is left nearly
    // intact, because saturation is the whole of "which calendar is this". What gets pulled down
    // is *luminance*, and it is solved to a fixed target rather than clamped by a brightness
    // ceiling. Solving for luminance is what makes the result hue-neutral: a yellow at brightness
    // 0.4 is far lighter than a blue at brightness 0.4, so one shared ceiling had to be set dark
    // enough for the lightest calendar in the list and over-darkened everything else. Every fill
    // now lands on the same luminance, so white-on-fill contrast is one number for every calendar
    // rather than a per-hue gamble.

    /// Fraction of the calendar's own saturation the fill keeps.
    ///
    /// Deliberately near 1: this is the component that says *which* calendar, and pulling it back
    /// is exactly what produced the brown/olive fills. The 10% it does give up is what keeps a
    /// fully-saturated primary from reading as raw paint next to a task card.
    static let fillSaturationScale: Double = 0.90

    /// Relative luminance (WCAG Y) the fill is solved to, per interaction state.
    ///
    /// Rest sits at 0.098 because that is where the *secondary* label clears AA: `Theme.onColor`
    /// lands at 7.09:1 and `Theme.onColorSecondary` — the 9pt time range and calendar name — at
    /// 4.64:1, for the lightest calendar colour worth planning for (a pale mint or pale yellow).
    /// Anywhere brighter and that 9pt line drops under 4.5:1, which is the ceiling on this whole
    /// change; hue is bought with saturation above, not with luminance here.
    ///
    /// The ladder is 4.4 L* then 3.8 L* wide — several times the ~1 L* just-noticeable step, so
    /// rest/hover/selected stay legibly separate — and `Theme.onColor` never falls below 5.25:1
    /// even at the top. The secondary tier follows the fill up via `secondaryLabelColor` rather
    /// than being left behind at 0.75 alpha.
    static func fillLuminance(isSelected: Bool = false, isHovered: Bool = false) -> Double {
        if isSelected { return 0.150 }
        if isHovered { return 0.124 }
        return 0.098
    }

    /// Fill for a timeline event block.
    static func fill(for calendarColor: Color, isSelected: Bool = false, isHovered: Bool = false) -> Color {
        solvedFill(for: calendarColor, luminance: fillLuminance(isSelected: isSelected, isHovered: isHovered))
    }

    /// Fill for a month-grid or all-day event chip. The same solve as `fill(for:)` — a chip and a
    /// block are the same object at two sizes, and they used to drift apart because the chip
    /// composited the raw colour over the cell instead of being solved for its own luminance.
    static func chipFill(for calendarColor: Color, isActive: Bool = false) -> Color {
        solvedFill(for: calendarColor, luminance: fillLuminance(isHovered: isActive))
    }

    /// Primary content on an event fill. Unconditionally `Theme.onColor` — the fill is solved so
    /// that this always holds, which is the point of solving it.
    static let primaryLabelColor = Theme.onColor

    /// Secondary content on an event fill: the time range, the calendar name.
    ///
    /// Rises to the primary tier while the block is hovered or selected. At rest 0.75 alpha clears
    /// 4.5:1, but the hover and selected fills are brighter by design, and a fixed 0.75 would sink
    /// to 3.57:1 there. Lifting the label instead of holding the fill down is what lets the state
    /// ladder exist at all.
    static func secondaryLabelColor(isSelected: Bool = false, isHovered: Bool = false) -> Color {
        isSelected || isHovered ? Theme.onColor : Theme.onColorSecondary
    }

    /// Tertiary content on an event fill: incidental glyphs such as the recurrence marker. Lifted
    /// one tier on hover/selection for the same reason as `secondaryLabelColor`; as a glyph rather
    /// than text it only owes the 3:1 non-text bar, which it holds in every state.
    static func tertiaryLabelColor(isSelected: Bool = false, isHovered: Bool = false) -> Color {
        isSelected || isHovered ? Theme.onColorSecondary : Theme.onColorTertiary
    }

    static func blockAccentOpacity(isSelected: Bool = false, isHovered: Bool = false) -> Double {
        if isSelected { return 0.48 }
        if isHovered { return 0.34 }
        return 0.18
    }

    /// Hairline of the calendar's *raw* colour drawn on the solved fill, so the edge reads as a
    /// lit rim of the same hue. Raised alongside the fill — at the old 0.34/0.46 the rim was
    /// barely separable from the plate now that the plate carries the hue properly.
    static func chipBorderOpacity(isActive: Bool = false) -> Double {
        isActive ? 0.60 : 0.45
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

    // MARK: - Luminance solve

    /// Keeps the calendar's hue, scales its saturation by `fillSaturationScale`, and picks the
    /// brightness whose sRGB relative luminance is `target`.
    private static func solvedFill(for calendarColor: Color, luminance target: Double) -> Color {
        let source = NSColor(calendarColor).usingColorSpace(.sRGB) ?? NSColor(calendarColor)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        source.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let scaledSaturation = Double(saturation) * fillSaturationScale
        // Luminance is monotonic in brightness at fixed hue/saturation, so a bisection converges
        // without inverting the sRGB transfer curve. 16 steps resolve brightness far finer than
        // one 8-bit code point, and the whole solve is plain arithmetic — no allocation per step,
        // which matters because a month grid runs this once per chip.
        var low = 0.0
        var high = 1.0
        for _ in 0..<16 {
            let mid = (low + high) / 2
            if relativeLuminance(hue: Double(hue), saturation: scaledSaturation, brightness: mid) < target {
                low = mid
            } else {
                high = mid
            }
        }
        return Color(hue: Double(hue), saturation: scaledSaturation, brightness: (low + high) / 2)
    }

    private static func relativeLuminance(hue: Double, saturation: Double, brightness: Double) -> Double {
        let components = rgbComponents(hue: hue, saturation: saturation, brightness: brightness)
        return (0.2126 * linearized(components.red))
            + (0.7152 * linearized(components.green))
            + (0.0722 * linearized(components.blue))
    }

    private static func linearized(_ component: Double) -> Double {
        component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }

    private static func rgbComponents(
        hue: Double,
        saturation: Double,
        brightness: Double
    ) -> (red: Double, green: Double, blue: Double) {
        let sector = (hue - hue.rounded(.down)) * 6
        let index = Int(sector) % 6
        let fraction = sector - sector.rounded(.down)
        let low = brightness * (1 - saturation)
        let falling = brightness * (1 - (saturation * fraction))
        let rising = brightness * (1 - (saturation * (1 - fraction)))
        switch index {
        case 0: return (brightness, rising, low)
        case 1: return (falling, brightness, low)
        case 2: return (low, brightness, rising)
        case 3: return (low, falling, brightness)
        case 4: return (rising, low, brightness)
        default: return (brightness, low, falling)
        }
    }
}
#endif
