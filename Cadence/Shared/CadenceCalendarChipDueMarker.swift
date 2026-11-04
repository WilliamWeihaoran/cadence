import SwiftUI

/// Label text for `CalendarChipDueMarker`, split out so the wording is testable without a view.
///
/// **Shared since [[T-10821]]**: it lived in the Mac's month support file, and the iPad chip now
/// draws the same marker, so it moved here whole rather than being respelled on the iOS side --
/// the way the done/urgency tint rule moved into `CadenceCalendarTaskDoneStyle`.
enum CalendarChipDueMarkerSupport {
    /// `nil` when the chip already sits on its due date — the grid position states that itself.
    static func label(dueDateKey: String, dayKey: String, calendar: Calendar = .current) -> String? {
        guard !dueDateKey.isEmpty, dueDateKey != dayKey else { return nil }
        guard let due = DateFormatters.date(from: dueDateKey, in: calendar) else { return dueDateKey }
        let dueParts = calendar.dateComponents([.month, .day], from: due)
        guard let dueMonth = dueParts.month, let dueDay = dueParts.day else { return dueDateKey }

        // Ordinal day while the deadline stays inside the chip's own month, where the surrounding
        // grid supplies the month; "MMM d" once it crosses into another month, where a bare day
        // would be ambiguous. Both forms read as a date — a bare number next to a task title
        // reads as a count of items, which is the mistake this replaces.
        if let day = DateFormatters.date(from: dayKey, in: calendar),
           calendar.isDate(due, equalTo: day, toGranularity: .month) {
            return ordinal(dueDay)
        }

        // Month name taken from the same calendar the key was parsed in. A shared
        // `DateFormatter` carries the *system* zone, so formatting a date parsed in some other
        // calendar there is the parse-in-one-zone/measure-in-another mistake all over again.
        let symbols = calendar.shortMonthSymbols
        guard dueMonth >= 1, dueMonth <= symbols.count else { return dueDateKey }
        return "\(symbols[dueMonth - 1]) \(dueDay)"
    }

    /// **Whether a chip at this width draws the marker at all** ([[T-10821]], owner call (a)
    /// decided under [[T-8201]]).
    ///
    /// The marker takes layout priority OVER the title, so it costs the title its width. Every Mac
    /// chip and every regular-width iOS chip -- the iPad month cell (~115pt) and the iPad week
    /// header's all-day band -- has the width to pay that. A compact-width chip does not: the
    /// iPhone's month and week columns leave the title a few characters, and a marker that wins
    /// the contest would leave none, so there the urgency TINT
    /// (`CadenceCalendarTaskDoneStyle.chipGlyphTint`) is the deadline channel alone. That is the
    /// one hardware reason, screen width, stated as the size class that carries it rather than as
    /// a device check.
    static func drawsMarker(isCompactWidth: Bool) -> Bool {
        !isCompactWidth
    }

    static func ordinal(_ day: Int) -> String {
        switch day % 100 {
        case 11, 12, 13: return "\(day)th"
        default:
            switch day % 10 {
            case 1: return "\(day)st"
            case 2: return "\(day)nd"
            case 3: return "\(day)rd"
            default: return "\(day)th"
            }
        }
    }
}

/// Compact deadline marker for calendar chips.
///
/// A chip is bucketed onto its scheduled day first (`CadenceScheduleSupport.monthTasksByDate`),
/// so a chip's position asserts a date that is frequently NOT the deadline. The marker therefore
/// carries the real due day: a bare "this has a deadline somewhere" dot would repeat the omission
/// it exists to fix. Nothing is drawn when the chip already sits on its due date — the grid
/// position states that itself.
///
/// It is plain tinted text rather than a filled pill: a badge-shaped `7` beside a task title
/// reads as "7 items", and the whole point of the marker is to name a date.
struct CalendarChipDueMarker: View {
    let dueDateKey: String
    /// `yyyy-MM-dd` of the day cell / column this chip is drawn in.
    let dayKey: String
    var todayKey: String = DateFormatters.todayKey()
    var isDone: Bool = false
    var calendar: Calendar = .current

    private var urgency: CadenceDueUrgency? {
        guard !dueDateKey.isEmpty, dueDateKey != dayKey else { return nil }
        return CadenceDueUrgency.evaluate(dueDateKey: dueDateKey, isDone: isDone, todayKey: todayKey)
    }

    var body: some View {
        if let urgency,
           let label = CalendarChipDueMarkerSupport.label(dueDateKey: dueDateKey, dayKey: dayKey, calendar: calendar) {
            Text(label)
                // 9pt, as it always was on the Mac, where scaling is `.fixed`; an iOS chip that is
                // laid out for larger text grows the marker with the title beside it.
                .cadenceFont(.metadata, base: 9, weight: .semibold)
                .foregroundStyle(urgency.tint)
                .lineLimit(1)
                .fixedSize()
                // The chip is single-line and non-wrapping, so in a narrow month column the title
                // must be what truncates — never the date this marker exists to show.
                .layoutPriority(1)
        }
    }
}
