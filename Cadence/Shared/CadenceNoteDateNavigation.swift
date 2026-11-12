import Foundation

/// What the mobile Notes header's title says, and what date the panel is therefore showing.
///
/// The title used to be the constant word "Notes" — a slot in a full header row spending itself on
/// a word that never changed, while the panel had no way to reach any day but today. Both problems
/// have the same fix: the title becomes the date, and it *is* the control that changes it. Daily
/// reads `Monday, August 17` where the row has room and `Aug 17` where it does not ([[T-15527]]),
/// Weekly reads `Aug 17–23`, and the two tabs with no date of their own (Notepad,
/// Event Notes) fall back to the word. A note's own title — the editor header on the Mac, the
/// editor cover on iOS — is `noteTitle(for:)`, one builder for both platforms ([[T-15493]]).
///
/// Lives in `Shared/` rather than beside the view because `Cadence/iOS/` sits inside `#if os(iOS)`
/// and is invisible to the macOS-built test target — the arithmetic here is the part worth pinning.
enum CadenceNoteDateNavigation {
    /// The title for a tab showing `dayKey`, or `nil` when the tab has no date and the caller
    /// should use its constant title instead.
    ///
    /// `nil` rather than the string "Notes": the fallback is the *host's* word, and only the host
    /// knows it.
    ///
    /// `now` is the reference year: a date outside it carries its year, one inside it does not
    /// ([[T-6431]], following `DateFormatters.absoluteDay`).
    static func title(
        for tab: CadenceNotesTabVocabulary,
        dayKey: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String? {
        switch tab {
        case .today:
            // [[T-15493]]: the short form, the FALLBACK beside `wideTitle`'s "Monday, August 17".
            // On the phone this label shares one 390pt row with four tabs and sometimes a back
            // control, which leaves it about 84pt (`iOSDateJumpTitleMetrics.inline`); "Aug 17"
            // fits there and "Monday, August 17" (about twice that) would truncate to a date with
            // no day in it. Where the row has room -- the iPad's Notes pane -- the header draws the
            // long form instead ([[T-15527]]); the choice is the width offered, not the platform.
            return dayLabel(forDayKey: dayKey, now: now)
        case .week:
            return weekRangeLabel(forDayKey: dayKey, now: now, calendar: calendar)
        case .notepad, .events:
            return nil
        }
    }

    /// [[T-15527]]: the long reading the Notes header's date button draws in place of
    /// `title(for:dayKey:)` wherever its row has room for it, or `nil` when there is no longer
    /// reading. Daily: `noteTitle`'s "Monday, August 17" -- so a header with the room titles the
    /// day exactly as the note's own editor does. Weekly: `nil`, because the range already IS
    /// `noteTitle`'s week reading and has no longer form. Undated tabs: `nil`.
    ///
    /// Under [[T-8201]] the short form answers one constraint, the row's width, so the header picks
    /// between the two by the width it is offered (`iOSDateJumpTitle`'s `ViewThatFits`), never by
    /// platform or size class: a 390pt phone and the 320pt Today inspector fall back, the iPad's
    /// 646pt+ Notes pane does not.
    static func wideTitle(
        for tab: CadenceNotesTabVocabulary,
        dayKey: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String? {
        switch tab {
        case .today:
            return noteTitle(kind: .daily, dateKey: dayKey, weekKey: "", now: now, calendar: calendar)
        case .week, .notepad, .events:
            return nil
        }
    }

    /// **The title a daily or weekly note carries on both platforms** ([[T-15493]]), or `nil` for a
    /// kind with no date of its own, or a key that does not parse — the caller falls back to
    /// `Note.displayTitle`, as the Mac editor header always has.
    ///
    /// Daily: the long day, `"Monday, August 17"` (`DateFormatters.absoluteLongDay`, with a year
    /// outside `now`'s). Weekly: the range, `"Aug 17–23"` (`weekRangeLabel`), on both platforms.
    /// The Mac used to say `"Week of Aug 17"` and iOS the range: not a shorter spelling of the same
    /// thing but a different reading, one that never states the week's end. Under [[T-8201]] a
    /// platform difference has to answer to the hardware, and that one answered to nothing.
    ///
    /// Callers: the macOS editor header (`NoteEditorPane.headerTitle`) and the iOS editor cover
    /// (`iOSNotesView.coverTitle`, and `iOSNoteEditorCover(reachedFrom:)` for a `[[link]]`,
    /// [[T-16666]]). The iOS Notes header's date button reaches it through
    /// `wideTitle`, drawn where it fits; see `title(for:dayKey:)` for the width-bound short form.
    nonisolated static func noteTitle(
        kind: NoteKind,
        dateKey: String,
        weekKey: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String? {
        switch kind {
        case .daily:
            guard let date = DateFormatters.date(from: dateKey) else { return nil }
            return DateFormatters.absoluteLongDay(date, relativeTo: now)
        case .weekly:
            // Through the Monday, because `weekRangeLabel` takes a day key and, given one that does
            // not parse, falls back to today's week — which would name a malformed key as a real one.
            guard let monday = DateFormatters.weekStartDate(forWeekKey: weekKey, calendar: calendar) else { return nil }
            return weekRangeLabel(forDayKey: DateFormatters.dateKey(from: monday), now: now, calendar: calendar)
        case .meeting, .permanent, .list:
            return nil
        }
    }

    /// `noteTitle(kind:dateKey:weekKey:now:calendar:)` for a stored note.
    static func noteTitle(for note: Note, now: Date = Date(), calendar: Calendar = .current) -> String? {
        noteTitle(kind: note.kind, dateKey: note.dateKey, weekKey: note.weekKey, now: now, calendar: calendar)
    }

    /// `"Aug 17"`, or `"Aug 17, 2025"` outside `now`'s year. Returns the key itself if it does not
    /// parse, which is what the rest of the app does with a malformed key (see
    /// `DateFormatters.weekLabel`) — a visibly wrong label beats a crash or a silent substitution
    /// of today.
    nonisolated static func dayLabel(forDayKey dayKey: String, now: Date = Date()) -> String {
        DateFormatters.noteDayLabel(forDayKey: dayKey, now: now)
    }

    /// `"Aug 17–23"` for a week inside one month, `"Aug 31 – Sep 6"` when it straddles two.
    ///
    /// The en dash is tight in the first form and spaced in the second, because `Aug 31 – Sep 6`
    /// set tight reads as one date. Same rule the timeline's `TimeFormatters.timeRange` follows.
    ///
    /// Outside `now`'s year the range carries a year ([[T-6431]]): once, at the end, when both ends
    /// share it (`"Aug 17–23, 2025"`, `"Mar 30 – Apr 5, 2025"`); otherwise on each end that is
    /// outside it, through `DateFormatters.absoluteDay` (`"Dec 28 – Jan 3, 2027"`). Inside `now`'s
    /// year the output is unchanged.
    ///
    /// Both bodies live on `DateFormatters` because `CadenceMCPServer` compiles that file and not
    /// this one, and search titles notes through them in `NoteReferenceSupport` ([[T-7205]]).
    nonisolated static func weekRangeLabel(forDayKey dayKey: String, now: Date = Date(), calendar: Calendar = .current) -> String {
        DateFormatters.noteWeekRangeLabel(forDayKey: dayKey, now: now, calendar: calendar)
    }

    /// **[[T-16664]]: the day a dated tab's date control stands on — the open note's, not the last
    /// day picked.** A note can be opened two ways: by picking a day, which moves the control, or
    /// by tapping its row, which did not. On the iPad the row tap left the header naming the day
    /// picked before ("Wednesday, November 11", no "Today" control because that IS today) over an
    /// editor showing October 26 — and picking November 11 did nothing, because nothing changed.
    /// The Mac's editor header always names the open note (`NoteEditorPane.headerTitle`), so the
    /// iPad was the one platform whose title could misname the note under it ([[T-8201]]).
    ///
    /// - Daily: the open daily note's `dateKey`.
    /// - Weekly: `pickedDayKey` when it already falls in the open note's week (a Thursday picked
    ///   stays Thursday in the picker), otherwise that week's Monday.
    /// - No open note, a note of another kind, a key that does not parse, or an undated tab:
    ///   `pickedDayKey`, unchanged.
    ///
    /// Pure, so it writes nothing: a row tap must not manufacture the standing notes a picked day
    /// does (`CadenceCoreNoteSupport.loadOrCreateCoreNotes`).
    static func shownDayKey(
        for tab: CadenceNotesTabVocabulary,
        pickedDayKey: String,
        openNoteKind: NoteKind?,
        openNoteDateKey: String,
        openNoteWeekKey: String,
        calendar: Calendar = .current
    ) -> String {
        switch tab {
        case .today:
            guard openNoteKind == .daily, DateFormatters.date(from: openNoteDateKey) != nil else { return pickedDayKey }
            return openNoteDateKey
        case .week:
            guard openNoteKind == .weekly,
                  let monday = DateFormatters.weekStartDate(forWeekKey: openNoteWeekKey, calendar: calendar)
            else { return pickedDayKey }
            if DateFormatters.date(from: pickedDayKey) != nil, weekKey(forDayKey: pickedDayKey) == openNoteWeekKey {
                return pickedDayKey
            }
            return DateFormatters.dateKey(from: monday)
        case .notepad, .events:
            return pickedDayKey
        }
    }

    /// `shownDayKey(for:pickedDayKey:openNoteKind:openNoteDateKey:openNoteWeekKey:calendar:)` for a
    /// stored note, or none.
    static func shownDayKey(for tab: CadenceNotesTabVocabulary, pickedDayKey: String, openNote: Note?) -> String {
        shownDayKey(
            for: tab,
            pickedDayKey: pickedDayKey,
            openNoteKind: openNote?.kind,
            openNoteDateKey: openNote?.dateKey ?? "",
            openNoteWeekKey: openNote?.weekKey ?? ""
        )
    }

    /// True when the panel is showing the note it would have shown before this control existed.
    /// The header uses it to decide whether the title needs a "jump back" affordance beside it —
    /// a date picker with no way home is a trap on a phone.
    static func isCurrentPeriod(tab: CadenceNotesTabVocabulary, dayKey: String, today: String = DateFormatters.todayKey()) -> Bool {
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

    /// The calendar the tab's date picker lays its month grid out in ([[T-15492]]).
    ///
    /// Weekly notes are ISO weeks, Monday to Sunday, and stay that way: `Note.weekKey` is
    /// persisted and synced, and habit and goal weeks agree with it. The picker grid followed the
    /// system first weekday, so on a Sunday-first (US) device each row ran Sun-Sat and straddled
    /// two ISO weeks -- tapping the row's Sunday opened the week that Sunday *closes*, the row
    /// above. On Weekly the grid is laid out Monday-first so the row you tap is the week that
    /// opens. Only `firstWeekday` changes -- it is all a month grid's row breaks read; the time
    /// zone and locale stay the base calendar's, so "today" and the day cells are the same days
    /// `weekKey` reads.
    /// Daily keeps the system week start, as Calendar does.
    static func pickerCalendar(
        for tab: CadenceNotesTabVocabulary,
        base: Calendar = .current
    ) -> Calendar {
        guard tab == .week else { return base }
        var calendar = base
        calendar.firstWeekday = 2
        return calendar
    }

    /// The ISO week key the day falls in. Falls back to *that day's* week via `Date()` only when the
    /// key is unparseable.
    static func weekKey(forDayKey dayKey: String) -> String {
        DateFormatters.weekKey(from: DateFormatters.date(from: dayKey) ?? Date())
    }

    /// Whether the tab's note is addressed by a day key at all. Notepad is one standing note and
    /// Event Notes is a list, so neither takes a date — the picker is hidden rather than disabled,
    /// because there is nothing to pick.
    static func supportsDateSelection(_ tab: CadenceNotesTabVocabulary) -> Bool {
        switch tab {
        case .today, .week: return true
        case .notepad, .events: return false
        }
    }
}
