import Foundation

// MARK: - Date Formatters
// All DateFormatter instances live here as statics. Never create DateFormatter() inline elsewhere.

/// `nonisolated`, and this one is worth spelling out because it is the only mark in the T-87 sweep
/// that puts shared state within reach of another thread.
///
/// The project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so this enum used to be
/// main-actor isolated — which meant every date-shaped helper that wanted to be `nonisolated` for
/// the widget target had to route around it. `CadenceWidgetDateSupport` exists precisely because
/// of that (see the note on `CadenceFocusPlanningSupport.dueLabel`), and a second copy of the
/// due-date vocabulary drifted while it did.
///
/// Three things make it safe rather than merely convenient:
/// - `DateFormatter` is documented thread-safe on macOS 10.9+ / iOS 7+ **as long as it is not
///   mutated**, and every formatter below is configured inside its initializer closure and never
///   touched again. Swift's lazy static initialization is itself thread-safe.
/// - This file already compiles into `CadenceMCPServer`, which sets no default actor isolation and
///   is on `SWIFT_VERSION = 6.0` — so these statics have been nonisolated in a shipping target all
///   along. This aligns the app with what that target already does.
/// - The calendar-based half (`storageCalendar`, `dateKey(from:calendar:)`, `date(from:in:)`,
///   `weekKey(from:)`, `weekStartDate(forWeekKey:calendar:)`) touches no shared instance at all.
///
/// If a formatter here ever needs to be *reconfigured* at runtime, that is the point at which this
/// stops being true — make it a computed property rather than re-isolating the enum.
nonisolated enum DateFormatters {
    /// `yyyy-MM-dd` — storage format used in all SwiftData model date strings
    static let ymd: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// `yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX` in UTC — the ISO-8601 timestamp `CadenceDataExportService`
    /// writes into a data archive. Storage, not display: it is here rather than in the exporter
    /// because this file's opening rule is categorical ("never create `DateFormatter()` inline
    /// elsewhere"), and because a document format is the one kind of date text that must never
    /// follow the host — an archive written on a German Mac has to be readable by an English one.
    ///
    /// Milliseconds, deliberately, and it is the archive's stated precision rather than an
    /// incidental one: `JSONEncoder`'s stock `.iso8601` writes whole seconds, which silently
    /// truncated every timestamp the first cut of the exporter wrote. `TaskOrdering` breaks ties on
    /// `createdAt`, and rows written together share a second routinely, so second precision turns a
    /// total order into ties. `ISO8601DateFormatter` would spell the same text and is not
    /// `Sendable`, so a static of one warns here where a `DateFormatter` does not.
    static let archiveTimestamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        return f
    }()

    /// `yyyyMMdd-HHmmss` — the local-time stamp `PersistenceController` names a store backup
    /// folder with, as in `20260827-014233-preMigration`.
    ///
    /// Storage rather than display, like `archiveTimestamp`: nobody reads it as a sentence, but a
    /// directory name is a name, and one that followed the host would sort differently and could
    /// contain a slash. It is here rather than beside the backup code because this file's opening
    /// rule is categorical — an agent looking for every date format Cadence writes has this file
    /// and nothing else to look in, and a formatter declared privately somewhere else is invisible
    /// to that search however correct it is.
    ///
    /// Local time, not UTC, and that is the one difference from `archiveTimestamp`: this string is
    /// shown back to the user as the backup they are being offered, so it has to name the hour
    /// they remember. Uniqueness does not rest on it — `uniqueBackupDirectory` suffixes a
    /// collision — so a DST fallback repeating an hour costs a `-2`, not a lost backup.
    static let backupFolderTimestamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    /// The six formatters below are locale-pinned for the reason `monthYear` and `shortMonthYear`
    /// state: **this repo pins every fixed-format formatter**, because the app is English-only and
    /// an unpinned one follows the host's locale. They were the only fixed-format formatters that
    /// did not, which shipped half-translated dates beside English chrome — on a German Mac
    /// `"EEEE, MMMM d"` rendered `Montag, August 24` and `"EEE"` rendered `Mo.`, next to untranslated
    /// buttons and headings. `dayNumber` is pinned too even though it is only `"d"`: numerals follow
    /// the locale as well, so an Arabic-Indic locale rendered the month grid in digits the rest of
    /// the UI never uses.
    ///
    /// **When localisation actually happens this inverts** (`docs/TODO.md` T-18): the pins come off,
    /// and the fixed patterns must become `setLocalizedDateFormatFromTemplate` or `Date.FormatStyle`,
    /// because idiomatic zh is `8月24日` rather than a translated `MMMM d`. Pinning is right only
    /// while there is exactly one language.
    /// `EEEE, MMMM d` — "Saturday, March 28"
    static let longDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    /// `EEEE, MMMM d, yyyy` — "Saturday, October 25, 2025". `longDate` with the year, for a day
    /// outside the reference year only; reach it through `absoluteLongDay`, never directly, so a
    /// same-year header keeps `longDate`'s width ([[T-6432]]).
    static let longDateWithYear: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE, MMMM d, yyyy"
        return f
    }()

    /// `EEE, MMM d` — "Tue, Sep 29". **`longDate`'s abbreviated spelling, and only that.**
    ///
    /// It exists because a page header's eyebrow has to be able to say the same day in less room
    /// (T-1702). On an iPad Pro 11" in portrait with the shell sidebar folded, Today is two panes
    /// and its task column is 513pt — of which the eyebrow line receives about 160 after the count
    /// capsule and the sort/completed bar beside it have taken their intrinsic widths. "TUESDAY,
    /// SEPTEMBER 29 · 3 timed · 1 done" needs about 250, so the owner saw the day's summary clipped
    /// to "· 3 ti…" — the one place on the page that summary appears.
    ///
    /// **There was no abbreviated weekday-plus-date formatter before this**, which is why the
    /// header had nothing narrower to fall back to: the list was `EEEE, MMMM d`, `MMM d`, `EEE`,
    /// `d` and `MMM`, so the day and the date could each be abbreviated alone but not together.
    ///
    /// Locale-pinned for this file's standing reason, and specifically so the pair cannot diverge:
    /// a header that read "Tuesday, September 29" at one width and "mar., 29 sept." at another
    /// would be two dates rather than two spellings of one.
    static let compactLongDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    /// `MMMM yyyy` — "March 2026"
    ///
    /// Locale-pinned like `ymd`, and for the same reason this repo pins every fixed-format
    /// formatter: without it the month name follows the host's locale, so the notes list's month
    /// headers and the calendar's month title read "AOÛT 2026" on a French Mac while every other
    /// string in the app — which is English-only, with no localizations — stays English. Pinning
    /// also makes `NotesListVisibilityTests.monthGroupingFormsRunsOverTheFilteredList` test the
    /// implementation rather than the tester's `Language & Region` setting.
    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    /// `MMM yyyy` — "Mar 2026". The month spelling the **iOS date selectors** read in.
    ///
    /// `monthYear` above is the long form and stays long: it renders the macOS calendar title, the
    /// notes list's month headings and `MonthCalendarPanel`'s header, none of which are this
    /// control. What this one exists for is `iOSDateJumpTitle` — the title-as-date-button shared by
    /// the four iOS calendar surfaces and the Notes header. Every other reading that control shows
    /// already abbreviates the month (`shortDate`'s "Aug 17", the notes week range's "Aug 17–23"),
    /// because it is a phone-width row that also holds a back chevron and two pill groups; the
    /// month grid was the one label in it still spelling "August 2026" in full, so one control read
    /// in two month vocabularies depending on which surface you were on.
    ///
    /// Locale-pinned for the same reason as `ymd` and `monthYear`: the app is English-only, so
    /// without it a French Mac or phone would read "août 2026" beside otherwise-English chrome.
    static let shortMonthYear: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM yyyy"
        return f
    }()

    /// `MMM d` — "Mar 28"
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f
    }()

    /// `MMM d, yyyy` — "Mar 28, 2026"
    static let fullShortDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    /// `EEE` — "Sat"
    static let dayOfWeek: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE"
        return f
    }()

    /// `d` — day-of-month number only: "28"
    static let dayNumber: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d"
        return f
    }()

    /// `MMM` — "Mar"
    static let monthAbbrev: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM"
        return f
    }()

    // MARK: - Convenience

    /// Returns today's date as a `yyyy-MM-dd` storage key
    static func todayKey() -> String {
        ymd.string(from: Date())
    }

    /// Converts a `Date` to a `yyyy-MM-dd` storage key
    static func dateKey(from date: Date) -> String {
        ymd.string(from: date)
    }

    /// The calendar every `yyyy-MM-dd` storage key is expressed in: **always Gregorian**, with
    /// the time zone taken from `calendar`.
    ///
    /// `ymd` pins `en_US_POSIX`, so every key ever written to the store is Gregorian. Anything
    /// that derives the same key from `calendar.dateComponents` instead must therefore force
    /// Gregorian too, or it produces a string that cannot match stored data. `Calendar.current`
    /// is not Gregorian everywhere: region Thailand defaults to Buddhist, and Japanese and
    /// Islamic calendars are one Settings tap away. For 2026-08-11 those yield `2569-08-11`,
    /// `0008-08-11` (the year is era-relative) and `1448-02-27` respectively — none of which
    /// matches anything on disk.
    ///
    /// The time zone still comes from the caller, because *that* genuinely differs by call site
    /// and getting it wrong is the off-by-one-day DST bug this file already documents below.
    static func storageCalendar(inheritingTimeZoneFrom calendar: Calendar) -> Calendar {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian
    }

    /// Converts a `Date` to a `yyyy-MM-dd` storage key, read in `calendar`'s time zone.
    static func dateKey(from date: Date, calendar: Calendar) -> String {
        let components = storageCalendar(inheritingTimeZoneFrom: calendar)
            .dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 1,
            components.day ?? 1
        )
    }

    /// Parses a `yyyy-MM-dd` storage key back to a `Date`
    static func date(from key: String) -> Date? {
        ymd.date(from: key)
    }

    /// Parses a date the way `date(from:)` does and returns the **canonical** `yyyy-MM-dd` spelling
    /// of it, or `nil` when the text is not a date this app will accept.
    ///
    /// This exists because `ymd` is lenient and every date comparison in Cadence is a string
    /// comparison. Measured on this toolchain: `"2026-8-20"` parses happily, `"2026/08/20"` parses,
    /// and `"2026-008-020"` parses — while `"2026-08-20T10:00"`, `"2026-13-01"` and `"2026-02-30"`
    /// do not. So "it parsed" is not the same claim as "it is a storage key", and code that
    /// validates by parsing and then keeps the raw string writes a key nothing can match:
    /// `"2026-8-20" < "2026-08-25"` is **`false`**, so a task due before the 25th sorts after it,
    /// misses "due today", misses overdue, and lands in the wrong group. `AppTask` states the
    /// fixed-width invariant in as many words; this is the one function that enforces it.
    ///
    /// **Normalize, don't reject, when the meaning is unambiguous.** `"2026-8-20"` and `"2026-8-2"`
    /// each name exactly one day, and refusing them would only push a caller into guessing our
    /// padding rules. The single exception is a **year that is not four digits**: `"26-8-2"` parses
    /// to the year 26 AD and formats back as `"0026-08-02"`, so normalizing it silently would store
    /// a date two millennia from the one that was meant. A century is a guess, not a spelling, so
    /// that one is rejected and the caller sees an error.
    ///
    /// `AIActionService.normalizedDate` reached the same conclusion for model-authored dates before
    /// this helper existed; it stays as the empty-string-returning wrapper its call sites want.
    static func normalizedDateKey(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let date = ymd.date(from: trimmed) else { return nil }
        guard trimmed.prefix(while: \.isNumber).count == 4 else { return nil }
        return dateKey(from: date)
    }

    /// Resolves a `yyyy-MM-dd` key to midnight **in `calendar`'s own time zone**.
    ///
    /// `ymd` pins a locale but not a time zone, so it parses in the system zone. That is fine
    /// whenever the result is measured with `Calendar.current` too, but any code that takes a
    /// calendar as a parameter has to parse in that calendar or the two disagree: parsing
    /// "2026-03-09" in UTC+8 and then counting days from it in America/New_York lands on the
    /// previous day, which is how a DST-boundary offset silently became off-by-one.
    static func date(from key: String, in calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        // Keys are Gregorian (see `storageCalendar`); only the time zone is the caller's.
        return storageCalendar(inheritingTimeZoneFrom: calendar)
            .date(from: DateComponents(year: year, month: month, day: day))
    }

    /// Converts a `yyyy-MM-dd` storage key to a short display string: "Jan 15" inside the
    /// reference date's year, "Jan 15, 2027" outside it (`absoluteDay`, [[T-6252]]) -- so a
    /// project deadline, the Today widget's due line or a recurrence's "Until" a year out no
    /// longer reads exactly like one next month. `relativeTo` is for a caller that already knows
    /// what "today" is (the widget's `todayKey`, a drop's `todayKey`); everyone else gets the clock.
    static func shortDateString(from key: String, relativeTo referenceDate: Date = Date()) -> String {
        guard let date = ymd.date(from: key) else { return key }
        return absoluteDay(date, relativeTo: referenceDate)
    }

    static func dayOffset(from key: String, relativeTo referenceDate: Date = Date()) -> Int? {
        guard let date = ymd.date(from: key) else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: referenceDate)
        let target = cal.startOfDay(for: date)
        return cal.dateComponents([.day], from: today, to: target).day
    }

    /// Converts a `yyyy-MM-dd` storage key to a relative string using task-friendly rules:
    /// "Today", "Tomorrow", "Yesterday", "in 5 days", "30 days ago", or "Mar 28" ("Mar 28, 2027" in
    /// another year — see `absoluteDay`)
    ///
    /// `relativeTo` exists so a caller that has already decided what "today" is can say so.
    /// `dayOffset` took one from the start; this did not, so Today's since-deleted past-due
    /// summary line (removed under [[T-3335]]) honoured its injected day for `isLate` and silently
    /// read the system clock for the words beside it — the two halves of one line disagreeing
    /// about the date.
    static func relativeDate(from key: String, relativeTo referenceDate: Date = Date()) -> String {
        guard let date = ymd.date(from: key) else { return key }
        let diff = dayOffset(from: key, relativeTo: referenceDate) ?? Int.max
        // The original window, unchanged: forward as far as a fortnight, backward without a limit.
        guard diff <= 13 else { return absoluteDay(date, relativeTo: referenceDate) }
        return relativeWords(dayOffset: diff)
    }

    /// `relativeDate(from:)` with a **symmetric cutoff**, for surfaces where the words stop being
    /// the shorter way to say it.
    ///
    /// The unbounded backward arm above is right for a summary line that is *about* lateness —
    /// `30 days ago` is the point there. It is wrong on a chip: a chip states a date, and once the
    /// offset is big enough that the reader has to do the arithmetic themselves to know which day
    /// it is, `Oct 19` is both shorter and the thing they wanted. `withinDays` is where that turns
    /// over, and it is the caller's to choose because it depends on what the surface is for.
    ///
    /// Inside the window the words are the same ones, spelled in the same place, so the two forms
    /// cannot drift into saying `Tomorrow` differently.
    static func relativeDate(from key: String, relativeTo referenceDate: Date = Date(), withinDays: Int) -> String {
        guard let date = ymd.date(from: key) else { return key }
        guard let diff = dayOffset(from: key, relativeTo: referenceDate), abs(diff) <= withinDays else {
            return absoluteDay(date, relativeTo: referenceDate)
        }
        return relativeWords(dayOffset: diff)
    }

    /// The spelled-out day once the words have stopped: `shortDate` ("Nov 15") inside the reference
    /// date's own year, `fullShortDate` ("Nov 15, 2027") outside it ([[T-6252]]). Without the year
    /// a deadline a year out read exactly like one next month. Same-year output is unchanged, so
    /// no chip widens in the common case. The year is compared in `Calendar.current`, the calendar
    /// `dayOffset` already measures in. Not private: Cmd+K's event and event-note subtitles spell a
    /// bare `Date` through it too, so their year follows the same rule.
    static func absoluteDay(_ date: Date, relativeTo referenceDate: Date) -> String {
        let cal = Calendar.current
        guard cal.component(.year, from: date) != cal.component(.year, from: referenceDate) else {
            return shortDate.string(from: date)
        }
        return fullShortDate.string(from: date)
    }

    /// `absoluteDay`'s long spelling: `longDate` ("Saturday, October 25") inside the reference
    /// date's year, `longDateWithYear` ("Saturday, October 25, 2025") outside it. The macOS note
    /// editor's daily header is the caller; the list's month heading, the only other year on that
    /// page, scrolls away from the open note ([[T-6432]]).
    static func absoluteLongDay(_ date: Date, relativeTo referenceDate: Date) -> String {
        let cal = Calendar.current
        guard cal.component(.year, from: date) != cal.component(.year, from: referenceDate) else {
            return longDate.string(from: date)
        }
        return longDateWithYear.string(from: date)
    }

    /// The words themselves, for a day offset a caller has already decided is inside its window.
    private static func relativeWords(dayOffset diff: Int) -> String {
        switch diff {
        case 0:     return "Today"
        case 1:     return "Tomorrow"
        case -1:    return "Yesterday"
        case 2...:  return "in \(diff) days"
        default:    return "\(-diff) days ago"
        }
    }

    // MARK: - Week keys

    /// Returns the current ISO week key: "2026-W13"
    static func currentWeekKey() -> String { weekKey(from: Date()) }

    /// Converts a Date to an ISO week key: "2026-W13", read in `calendar`'s time zone.
    ///
    /// The time zone is the caller's for the same reason `weekStartDate(forWeekKey:calendar:)`
    /// below takes one, and the two must agree or they do not round-trip: `weekStartDate` returned
    /// Monday-00:00 in the calendar it was handed, and this used to name that instant in whatever
    /// zone the *device* happened to be in. West of UTC that instant is still Sunday, so the pair
    /// disagreed by a whole ISO week — on every date, silently, and only on machines west of UTC
    /// (T-1115). `WeekKeyResolutionTests.everyWeekKeyRoundTripsBackIntoItsOwnWeek` had been passing
    /// on the author's longitude rather than on the arithmetic.
    ///
    /// The default is `.current`, which is what this always used, so **no existing caller changes
    /// what it computes** — load-bearing, because this output is persisted as `Note.weekKey` and
    /// syncs through CloudKit, and a key whose meaning shifted would re-address a stored note.
    static func weekKey(from date: Date, calendar: Calendar = .current) -> String {
        var cal = Calendar(identifier: .iso8601)
        cal.locale = Locale(identifier: "en_US_POSIX")
        cal.timeZone = calendar.timeZone
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let year = comps.yearForWeekOfYear ?? cal.component(.year, from: date)
        let week = comps.weekOfYear ?? 1
        return String(format: "%d-W%02d", year, week)
    }

    /// The Monday that opens the ISO week named by `weekKey` ("2026-W33"), or `nil` if the key is
    /// malformed.
    ///
    /// This construction — `Calendar(identifier: .iso8601)` + `en_US_POSIX` + `weekday = 2` — was
    /// written out twice, here and in `NotesListGrouping.weekStartDateKey`, and neither copy
    /// inherited a time zone the way `storageCalendar(inheritingTimeZoneFrom:)` requires. One
    /// definition, and the time zone is the caller's, so the resulting date is measured in the
    /// same zone the key was written in.
    static func weekStartDate(forWeekKey weekKey: String, calendar: Calendar = .current) -> Date? {
        let parts = weekKey.components(separatedBy: "-W")
        guard parts.count == 2,
              let year = Int(parts[0]), let week = Int(parts[1]) else { return nil }
        var iso = Calendar(identifier: .iso8601)
        iso.locale = Locale(identifier: "en_US_POSIX")
        iso.timeZone = calendar.timeZone
        var components = DateComponents()
        components.yearForWeekOfYear = year
        components.weekOfYear = week
        components.weekday = 2 // Monday
        return iso.date(from: components)
    }

    /// Converts an ISO week key to a human-readable label: "Week of Mar 23", or "Week of Mar 23,
    /// 2025" when the Monday falls outside the reference date's year (`absoluteDay`, [[T-6432]]).
    static func weekLabel(from weekKey: String, relativeTo referenceDate: Date = Date()) -> String {
        guard let monday = weekStartDate(forWeekKey: weekKey) else { return weekKey }
        return "Week of \(absoluteDay(monday, relativeTo: referenceDate))"
    }
}

// MARK: - Time Formatters

nonisolated enum TimeFormatters {
    /// Does `locale` name hours `0…23`, rather than `1…12` with AM/PM?
    ///
    /// **T-1135.** Every clock face in the app used to be hard-coded 12-hour, so a user whose Mac
    /// or phone is set to a 24-hour clock read `1 PM` on every timed grid, schedule row, block
    /// label and task sheet. 24-hour is the default in most of the world — `en_GB`, `de_DE`,
    /// `fr_FR` and `ja_JP` all report `.zeroToTwentyThree`, measured 2026-09-12 — so this was not a
    /// minority setting, and it is not covered by the translation backlog in [[T-18]] either: the
    /// OS answers this question in English, with no localisation work behind it.
    ///
    /// `Locale.hourCycle` rather than `DateFormatter.dateFormat(fromTemplate: "j", …)`, and the
    /// choice is measured rather than assumed. On macOS 26.1 the two agree in every case that was
    /// reachable from a test process — `Locale.hourCycle`, an instance `DateFormatter` with
    /// `.timeStyle = .short`, `DateFormatter.dateFormat(fromTemplate:)` and `Date.FormatStyle` all
    /// derive from the same `Locale` and returned the same answer under `en_US`, `en_GB`, `de_DE`,
    /// `fr_FR`, `ja_JP` and an explicit `en_US@hours=h23`. They differ only in cost:
    /// `Locale.current.hourCycle` measured **0.048 µs** and
    /// `DateFormatter.dateFormat(fromTemplate:)` **3.4–5.1 µs**, which matters because
    /// several call sites (`MarkdownTaskEmbedDrawingSupport`, `iOSMarkdownTaskEmbedLayoutInfo`) are
    /// in draw paths.
    ///
    /// **Not measured, and worth saying so:** that the macOS/iOS *"24-Hour Time"* switch reaches
    /// `Locale.current`. `AppleICUForce24HourTime` is read from the **global** preferences domain,
    /// which a test process cannot write without changing the machine's own settings, and the
    /// per-process argument domain is not consulted for it (it *is* for `AppleLocale`, which is how
    /// the test scheme pins this — see `CadenceTestClocks`). What is measured is that `Locale`
    /// carries the answer once it is set: `Locale(identifier: "en_US@hours=h23").hourCycle` is
    /// `.zeroToTwentyThree` and formats `HH:mm`. [[T-1163]] asks the repository owner to confirm the
    /// last link on their own Mac.
    ///
    /// A locale parameter rather than a read of `Locale.current` inside the formatter, so a test
    /// can state the hour cycle the way `CadenceTestTimeZones` lets it state the zone — the
    /// [[T-1115]] lesson, which cost a session when a suite passed on the host's longitude.
    static func usesTwentyFourHourClock(_ locale: Locale = .current) -> Bool {
        switch locale.hourCycle {
        case .zeroToTwentyThree, .oneToTwentyFour:
            return true
        default:
            return false
        }
    }

    /// Formats minutes-from-midnight for the clock `locale` names: 75 → "1:15 AM" or "01:15",
    /// 720 → "12 PM" or "12:00".
    ///
    /// One canonical spelling per hour cycle, not the locale's own rendering, and that is the line
    /// between this ticket and [[T-18]]. `Date.FormatStyle` would spell `ja_JP` as `13時` and
    /// `de_DE` as `13 Uhr` — translated chrome beside an English app — and it renders `en_US` with a
    /// NARROW NO-BREAK SPACE (U+202F) before AM/PM, so adopting it would have silently changed every
    /// 12-hour string in the app as well. Both measured 2026-09-12.
    ///
    /// The 12-hour branch is byte-for-byte what it was, so nothing that already reads `1:15 AM`
    /// moves. The 24-hour branch is always zero-padded `HH:mm`, including on the hour: a bare `13`
    /// beside a bare `9` does not read as a clock, and the hour rails are a column of these.
    ///
    /// `.oneToTwentyFour` (`h24`, where midnight is `24:00`) is folded into the `h23` spelling
    /// deliberately: one 24-hour face for the app, the way there is one 12-hour face.
    static func timeString(from minutes: Int, locale: Locale = .current) -> String {
        let normalized = ((minutes % (24 * 60)) + (24 * 60)) % (24 * 60)
        let h = normalized / 60
        let m = normalized % 60
        if usesTwentyFourHourClock(locale) {
            return String(format: "%02d:%02d", h, m)
        }
        let h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        let ampm = h < 12 ? "AM" : "PM"
        return m == 0 ? "\(h12) \(ampm)" : String(format: "%d:%02d %@", h12, m, ampm)
    }

    /// The month-chip spelling of `timeString`: 75 → "1:15a", 780 → "1p", or "13:00" unchanged on a
    /// 24-hour face. Kept here, beside the hour-cycle check, so a surface that wants the compact
    /// face never spells AM or PM itself (T-1135's population sweep).
    static func compactTimeString(from minutes: Int, locale: Locale = .current) -> String {
        let full = timeString(from: minutes, locale: locale)
        guard !usesTwentyFourHourClock(locale) else { return full }
        return full
            .replacingOccurrences(of: " AM", with: "a")
            .replacingOccurrences(of: " PM", with: "p")
    }

    /// Formats a start/end minute pair as a range: "1:15 AM – 2:15 AM", or "01:15 – 02:15".
    static func timeRange(startMin: Int, endMin: Int, locale: Locale = .current) -> String {
        "\(timeString(from: startMin, locale: locale)) – \(timeString(from: endMin, locale: locale))"
    }

    /// Canonical minutes → duration label for the whole app: "45m", "2h", "1h 24m". Never renders
    /// a decimal hour — the hour and minute components are shown separately, and a zero component
    /// is omitted.
    ///
    /// The gap between the hour and the minute component is a NON-BREAKING SPACE (U+00A0) on
    /// purpose. These labels are drawn inside hard-clipped fixed-size chrome (timeline blocks can
    /// be ~50pt wide when three tasks overlap); an ordinary space is a line-break opportunity, so
    /// "1h 30m" would wrap and the clipped second line would leave the badge reading "1h" for a
    /// 90-minute task — wrong information, not just truncation.
    ///
    /// `emptyPlaceholder` is what a zero/negative duration renders as, because the surfaces do not
    /// agree on that and should not have to fork the formatter to disagree: the estimate chips say
    /// `"0m"`, the actual/estimated pair says `"-"`, and the timeline event editor says an en dash.
    /// That difference is the *only* thing those call sites ever needed of their own — this was
    /// written out six times in three spellings, and two of the copies used a breakable space.
    ///
    /// It lives here rather than beside `CadenceTaskPresentationSupport.estimateLabel` (which now
    /// forwards to it) because `Shared/` is not compiled into the widget or MCP targets and
    /// `Models/GoalContributionSummary` needs it. `DateFormatters.swift` is in all three.
    static func durationLabel(minutes: Int, emptyPlaceholder: String) -> String {
        guard minutes > 0 else { return emptyPlaceholder }
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder)m" }
        if remainder == 0 { return "\(hours)h" }
        return "\(hours)h\u{00A0}\(remainder)m"
    }

    /// Compact actual/estimated label: "3m/15m", "1h/2h", "-/30m", "45m/-", etc.
    /// Returns "-" for either side when it is zero or negative.
    static func durationLabel(actual: Int, estimated: Int) -> String {
        let actualLabel = durationLabel(minutes: actual, emptyPlaceholder: "-")
        let estimatedLabel = durationLabel(minutes: estimated, emptyPlaceholder: "-")
        return "\(actualLabel)/\(estimatedLabel)"
    }
}
