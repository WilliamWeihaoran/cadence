import Foundation

/// What the mobile Notes header's title says, and what date the panel is therefore showing.
///
/// The title used to be the constant word "Notes" — a slot in a full header row spending itself on
/// a word that never changed, while the panel had no way to reach any day but today. Both problems
/// have the same fix: the title becomes the date, and it *is* the control that changes it. Daily
/// reads `Aug 17`, Weekly reads `Aug 17–23`, and the two tabs with no date of their own (Notepad,
/// Event Notes) fall back to the word.
///
/// Lives in `Shared/` rather than beside the view because `Cadence/iOS/` sits inside `#if os(iOS)`
/// and is invisible to the macOS-built test target — the arithmetic here is the part worth pinning.
enum CadenceNoteDateNavigation {
    /// The title for a tab showing `dayKey`, or `nil` when the tab has no date and the caller
    /// should use its constant title instead.
    ///
    /// `nil` rather than the string "Notes": the fallback is the *host's* word, and only the host
    /// knows it.
    static func title(for tab: CadenceMobileNotesTab, dayKey: String, calendar: Calendar = .current) -> String? {
        switch tab {
        case .today:
            return dayLabel(forDayKey: dayKey)
        case .week:
            return weekRangeLabel(forDayKey: dayKey, calendar: calendar)
        case .notepad, .events:
            return nil
        }
    }

    /// `"Aug 17"`. Returns the key itself if it does not parse, which is what the rest of the app
    /// does with a malformed key (see `DateFormatters.weekLabel`) — a visibly wrong label beats a
    /// crash or a silent substitution of today.
    static func dayLabel(forDayKey dayKey: String) -> String {
        guard let date = DateFormatters.date(from: dayKey) else { return dayKey }
        return DateFormatters.shortDate.string(from: date)
    }

    /// `"Aug 17–23"` for a week inside one month, `"Aug 31 – Sep 6"` when it straddles two.
    ///
    /// The en dash is tight in the first form and spaced in the second, because `Aug 31 – Sep 6`
    /// set tight reads as one date. Same rule the timeline's `TimeFormatters.timeRange` follows.
    static func weekRangeLabel(forDayKey dayKey: String, calendar: Calendar = .current) -> String {
        let key = DateFormatters.weekKey(from: DateFormatters.date(from: dayKey) ?? Date())
        guard let monday = DateFormatters.weekStartDate(forWeekKey: key, calendar: calendar),
              let sunday = calendar.date(byAdding: .day, value: 6, to: monday) else {
            return DateFormatters.weekLabel(from: key)
        }

        let sameMonth = calendar.isDate(monday, equalTo: sunday, toGranularity: .month)
        if sameMonth {
            return "\(DateFormatters.shortDate.string(from: monday))–\(DateFormatters.dayNumber.string(from: sunday))"
        }
        return "\(DateFormatters.shortDate.string(from: monday)) – \(DateFormatters.shortDate.string(from: sunday))"
    }

    /// True when the panel is showing the note it would have shown before this control existed.
    /// The header uses it to decide whether the title needs a "jump back" affordance beside it —
    /// a date picker with no way home is a trap on a phone.
    static func isCurrentPeriod(tab: CadenceMobileNotesTab, dayKey: String, today: String = DateFormatters.todayKey()) -> Bool {
        switch tab {
        case .today:
            return dayKey == today
        case .week:
            return weekKey(forDayKey: dayKey) == weekKey(forDayKey: today)
        case .notepad, .events:
            // Neither is dated, so neither can be away from now. Answering `false` here would put a
            // "back to today" control on a tab with no today.
            return true
        }
    }

    /// The ISO week key the day falls in. Falls back to *that day's* week via `Date()` only when the
    /// key is unparseable.
    static func weekKey(forDayKey dayKey: String) -> String {
        DateFormatters.weekKey(from: DateFormatters.date(from: dayKey) ?? Date())
    }

    /// Whether the tab's note is addressed by a day key at all. Notepad is one standing note and
    /// Event Notes is a list, so neither takes a date — the picker is hidden rather than disabled,
    /// because there is nothing to pick.
    static func supportsDateSelection(_ tab: CadenceMobileNotesTab) -> Bool {
        switch tab {
        case .today, .week: return true
        case .notepad, .events: return false
        }
    }
}
