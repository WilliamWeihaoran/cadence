import Foundation
import Testing
@testable import Cadence

/// The header title on the mobile Notes surface, which is also the date-jump control.
///
/// `Cadence/iOS/` is inside `#if os(iOS)` and invisible to this macOS-built target, so the view
/// itself cannot be tested here — the arithmetic it reads is what these pin.
struct CadenceNoteDateNavigationTests {
    /// Monday 2026-08-17 through Sunday 2026-08-23: an ISO week wholly inside August.
    private let midWeekMonday = "2026-08-17"
    /// The reference year for every 2026 fixture below: without it the titles follow the run
    /// year, and a 2026 day would carry ", 2026" once the suite runs in 2027 ([[T-6431]]).
    private let now = DateFormatters.ymd.date(from: "2026-10-25")!.addingTimeInterval(12 * 60 * 60)

    @Test func dailyTitleIsTheDay() {
        #expect(CadenceNoteDateNavigation.title(for: .today, dayKey: midWeekMonday, now: now) == "Aug 17")
    }

    @Test func weeklyTitleIsTheRange() {
        #expect(CadenceNoteDateNavigation.title(for: .week, dayKey: midWeekMonday, now: now) == "Aug 17–23")
    }

    /// Any day in the week names the same week, not the day you happened to pick. Picking Thursday
    /// from the calendar must open the Monday-to-Sunday note, exactly as macOS's weekly picker does.
    @Test func weeklyTitleIsStableAcrossTheWeek() {
        let expected = CadenceNoteDateNavigation.title(for: .week, dayKey: midWeekMonday, now: now)
        for day in ["2026-08-17", "2026-08-19", "2026-08-23"] {
            #expect(CadenceNoteDateNavigation.title(for: .week, dayKey: day, now: now) == expected)
        }
        // ...and the next day is a different week.
        #expect(CadenceNoteDateNavigation.title(for: .week, dayKey: "2026-08-24", now: now) != expected)
    }

    /// A week straddling two months gets the spaced dash and both month names. Set tight,
    /// "Aug 31–Sep 6" reads as one date.
    @Test func weekAcrossAMonthBoundarySpellsBothMonths() {
        // Mon 2026-08-31 … Sun 2026-09-06.
        #expect(CadenceNoteDateNavigation.weekRangeLabel(forDayKey: "2026-09-02", now: now) == "Aug 31 – Sep 6")
    }

    /// Outside the reference year the title carries the year; inside it nothing changes
    /// ([[T-6431]], `DateFormatters.absoluteDay`). A week inside one other year says it once at the
    /// end; a week straddling New Year puts it on the end that is outside.
    @Test func titlesCarryTheYearOnlyOutsideTheReferenceYear() throws {
        #expect(CadenceNoteDateNavigation.title(for: .today, dayKey: "2025-08-17", now: now) == "Aug 17, 2025")
        #expect(CadenceNoteDateNavigation.title(for: .today, dayKey: "2027-01-05", now: now) == "Jan 5, 2027")
        #expect(CadenceNoteDateNavigation.title(for: .today, dayKey: "2026-12-31", now: now) == "Dec 31")
        // Mon 2025-08-18 … Sun 2025-08-24, and Mon 2025-03-31 … Sun 2025-04-06.
        #expect(CadenceNoteDateNavigation.title(for: .week, dayKey: "2025-08-20", now: now) == "Aug 18–24, 2025")
        #expect(CadenceNoteDateNavigation.weekRangeLabel(forDayKey: "2025-04-02", now: now) == "Mar 31 – Apr 6, 2025")
        // Mon 2026-12-28 … Sun 2027-01-03: only the Sunday is outside 2026; from 2027 only the Monday.
        #expect(CadenceNoteDateNavigation.weekRangeLabel(forDayKey: "2026-12-30", now: now) == "Dec 28 – Jan 3, 2027")
        let midJanuary = try #require(DateFormatters.ymd.date(from: "2027-01-15")).addingTimeInterval(12 * 60 * 60)
        #expect(CadenceNoteDateNavigation.weekRangeLabel(forDayKey: "2026-12-30", now: midJanuary) == "Dec 28, 2026 – Jan 3")

        // The calendar's day title (Week / 2 Weeks / Board) follows the same rule; Month already had a year.
        let nextJanuary = try #require(DateFormatters.ymd.date(from: "2027-01-05"))
        let thisDecember = try #require(DateFormatters.ymd.date(from: "2026-12-31"))
        #expect(CadenceCalendarDateTitleSupport.label(for: nextJanuary, format: .day, now: now) == "Jan 5, 2027")
        #expect(CadenceCalendarDateTitleSupport.label(for: thisDecember, format: .day, now: now) == "Dec 31")
        #expect(CadenceCalendarDateTitleSupport.label(for: nextJanuary, format: .day, now: midJanuary) == "Jan 5")
    }

    // MARK: - One note title on both platforms (T-15493)

    /// [[T-15493]]: the same note fed to the builder each platform's editor reads. The Mac header
    /// said "Week of Aug 17" and iOS "Aug 17–23"; the range wins on both, because it states the end.
    /// A daily note is the long day on both. The iOS Notes header's date button keeps "Aug 17" for
    /// the phone row's width, and must still name the same day and the same week.
    @Test func dailyAndWeeklyNotesReadTheSameOnBothPlatforms() throws {
        let daily = Note(kind: .daily, title: midWeekMonday, dateKey: midWeekMonday)
        let weekly = Note(kind: .weekly, title: "2026-W34", weekKey: "2026-W34")

        #expect(CadenceNoteDateNavigation.noteTitle(for: daily, now: now) == "Monday, August 17")
        #expect(CadenceNoteDateNavigation.noteTitle(for: weekly, now: now) == "Aug 17–23")
        // The iOS header's week button and the editor title for the same week are one string.
        #expect(CadenceNoteDateNavigation.noteTitle(for: weekly, now: now)
            == CadenceNoteDateNavigation.title(for: .week, dayKey: midWeekMonday, now: now))
        // Its day button is the short spelling of the same day, not another day.
        #expect(CadenceNoteDateNavigation.title(for: .today, dayKey: midWeekMonday, now: now) == "Aug 17")

        // Outside the reference year the year rides along on both forms ([[T-6431]], [[T-6432]]).
        let lastYearDaily = Note(kind: .daily, dateKey: "2025-08-18")
        let lastYearWeekly = Note(kind: .weekly, weekKey: "2025-W34")
        #expect(CadenceNoteDateNavigation.noteTitle(for: lastYearDaily, now: now) == "Monday, August 18, 2025")
        #expect(CadenceNoteDateNavigation.noteTitle(for: lastYearWeekly, now: now) == "Aug 18–24, 2025")

        // Undated kinds and malformed keys answer nil, and each caller falls back to displayTitle.
        #expect(CadenceNoteDateNavigation.noteTitle(for: Note(kind: .permanent, title: "Pad"), now: now) == nil)
        #expect(CadenceNoteDateNavigation.noteTitle(for: Note(kind: .weekly, weekKey: "not-a-week"), now: now) == nil)
        #expect(CadenceNoteDateNavigation.noteTitle(for: Note(kind: .daily, dateKey: "not-a-date"), now: now) == nil)
    }

    /// [[T-15527]]: the Notes header's Daily title is "Monday, August 17" wherever its row has room
    /// -- the note's own editor title -- and "Aug 17" only as the width fallback. Weekly has no
    /// longer reading (the range is already the editor's), and the undated tabs have none at all.
    @Test func theDailyHeaderTitlePrefersTheEditorsLongFormWhereItFits() {
        #expect(CadenceNoteDateNavigation.wideTitle(for: .today, dayKey: midWeekMonday, now: now) == "Monday, August 17")
        #expect(CadenceNoteDateNavigation.wideTitle(for: .today, dayKey: midWeekMonday, now: now)
            == CadenceNoteDateNavigation.noteTitle(for: Note(kind: .daily, dateKey: midWeekMonday), now: now))
        #expect(CadenceNoteDateNavigation.wideTitle(for: .today, dayKey: "2025-08-18", now: now) == "Monday, August 18, 2025")
        // The fallback is the same day, short.
        #expect(CadenceNoteDateNavigation.title(for: .today, dayKey: midWeekMonday, now: now) == "Aug 17")
        #expect(CadenceNoteDateNavigation.wideTitle(for: .week, dayKey: midWeekMonday, now: now) == nil)
        #expect(CadenceNoteDateNavigation.wideTitle(for: .notepad, dayKey: midWeekMonday, now: now) == nil)
        #expect(CadenceNoteDateNavigation.wideTitle(for: .events, dayKey: midWeekMonday, now: now) == nil)
        // A malformed key has no long form; the header shows the short label's raw key instead.
        #expect(CadenceNoteDateNavigation.wideTitle(for: .today, dayKey: "not-a-date", now: now) == nil)
    }

    /// The view half, read from source because `Cadence/iOS/` does not compile here. Under
    /// [[T-8201]] the short form answers only the row's width, so the pick is a `ViewThatFits`
    /// over the width offered -- long first, because it takes the FIRST candidate that fits --
    /// and never a size-class or platform branch.
    @Test func theNotesHeaderPicksTheDailyFormByTheWidthOffered() throws {
        let control = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSDateJumpTitle.swift"))
        let body = try #require(CadenceSourceScan.declarationBody("var body: some View", in: control))
        let fits = try #require(CadenceSourceScan.declarationBody("ViewThatFits(in: .horizontal)", in: body),
                                "the label no longer chooses by width")
        let wide = try #require(fits.range(of: "labelRow(wideLabel)"))
        let short = try #require(fits.range(of: "labelRow(label)"))
        #expect(wide.lowerBound < short.lowerBound, "the short form is asked first, so the long one never draws")

        let notes = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSNotesView.swift"))
        let title = try #require(CadenceSourceScan.declarationBody("struct iOSNotesDateTitle: View", in: notes))
        #expect(title.contains("CadenceNoteDateNavigation.wideTitle(for: tab, dayKey: dayKey)"))
        #expect(title.contains("wideLabel: wideLabel,"), "the header does not hand the control its long form")
        #expect(!title.contains("horizontalSizeClass"), "the form is chosen by size class, not by width")
    }

    /// Both editors call that one builder, so the strings above are what each platform draws. The
    /// iOS half is in `#if os(iOS)` and cannot run here; its source is read instead.
    @Test func bothEditorsTitleANoteThroughTheOneBuilder() throws {
        let mac = try #require(CadenceSourceScan.declarationBody(
            "private var headerTitle: String",
            in: CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/NoteEditorPane.swift"))
        ))
        let iOS = try #require(CadenceSourceScan.declarationBody(
            "private func coverTitle(for note: Note) -> String",
            in: CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSNotesView.swift"))
        ))
        for (platform, body) in [("macOS", mac), ("iOS", iOS)] {
            #expect(body.contains("CadenceNoteDateNavigation.noteTitle(for: note"), "\(platform) editor title skips the shared builder")
            #expect(!body.contains("weekLabel("), "\(platform) editor title reads \"Week of\" again")
            #expect(!body.contains("absoluteLongDay("), "\(platform) editor title spells the day itself")
            #expect(!body.contains("CadenceNoteDateNavigation.title("), "\(platform) editor title uses the header's short form")
        }
    }

    /// The two undated tabs return `nil` rather than a string, so the host supplies its own
    /// constant word. Returning "Notes" here would put the fallback in the wrong layer.
    @Test func undatedTabsHaveNoDateTitle() {
        #expect(CadenceNoteDateNavigation.title(for: .notepad, dayKey: midWeekMonday) == nil)
        #expect(CadenceNoteDateNavigation.title(for: .events, dayKey: midWeekMonday) == nil)
        #expect(CadenceNoteDateNavigation.supportsDateSelection(.notepad) == false)
        #expect(CadenceNoteDateNavigation.supportsDateSelection(.events) == false)
        #expect(CadenceNoteDateNavigation.supportsDateSelection(.today))
        #expect(CadenceNoteDateNavigation.supportsDateSelection(.week))
    }

    /// A malformed key shows itself rather than silently becoming today. Substituting today would
    /// let the user write into a day the header is not naming.
    @Test func malformedKeyIsShownRatherThanSubstituted() {
        #expect(CadenceNoteDateNavigation.dayLabel(forDayKey: "not-a-date") == "not-a-date")
        #expect(CadenceNoteDateNavigation.title(for: .today, dayKey: "") == "")
    }

    @Test func currentPeriodDrivesTheAwayTreatment() {
        let today = DateFormatters.todayKey()
        #expect(CadenceNoteDateNavigation.isCurrentPeriod(tab: .today, dayKey: today, today: today))
        #expect(CadenceNoteDateNavigation.isCurrentPeriod(tab: .today, dayKey: "2026-08-17", today: "2026-08-18") == false)
        // Same week, different day: the weekly note has not moved, so the header must not claim it has.
        #expect(CadenceNoteDateNavigation.isCurrentPeriod(tab: .week, dayKey: "2026-08-17", today: "2026-08-19"))
        #expect(CadenceNoteDateNavigation.isCurrentPeriod(tab: .week, dayKey: "2026-08-17", today: "2026-08-24") == false)
    }

    /// Notepad and Event Notes are never "away", or the popover would offer a way back to a today
    /// they do not have.
    @Test func undatedTabsAreAlwaysCurrent() {
        #expect(CadenceNoteDateNavigation.isCurrentPeriod(tab: .notepad, dayKey: "2020-01-01", today: "2026-08-17"))
        #expect(CadenceNoteDateNavigation.isCurrentPeriod(tab: .events, dayKey: "2020-01-01", today: "2026-08-17"))
    }

    /// The week key the panel loads is derived from the day key, so the title and the note on
    /// screen cannot disagree about which week is showing.
    @Test func weekKeyMatchesTheDateFormattersSpelling() {
        for day in ["2026-08-17", "2026-01-01", "2025-12-31"] {
            let date = DateFormatters.date(from: day)
            #expect(date != nil)
            #expect(CadenceNoteDateNavigation.weekKey(forDayKey: day) == DateFormatters.weekKey(from: date!))
        }
    }

    // MARK: - [[T-15492]] the weekly picker's rows are ISO weeks

    /// A Sunday-first (US) calendar, pinned so the run's own locale and zone cannot decide it.
    private var usCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.firstWeekday = 1
        return calendar
    }

    /// How many drawn rows of `month`'s picker grid hold days from more than one ISO week.
    private func rowsSpanningTwoWeekKeys(month: String, pickerCalendar: Calendar) -> Int {
        var monthDate = DateComponents()
        let parts = month.split(separator: "-").compactMap { Int($0) }
        monthDate.year = parts[0]
        monthDate.month = parts[1]
        monthDate.day = 15
        let days = MonthCalendarPanel.gridDays(for: usCalendar.date(from: monthDate)!, calendar: pickerCalendar)
        #expect(days.count % 7 == 0)
        return stride(from: 0, to: days.count, by: 7).filter { start in
            let keys = Set(days[start..<start + 7].compactMap { $0 }.map {
                DateFormatters.weekKey(from: $0, calendar: usCalendar)
            })
            return keys.count > 1
        }.count
    }

    /// On a Sunday-first device the weekly picker's grid was Sun-Sat, so every full row straddled
    /// two ISO weeks and tapping its Sunday opened the week above. Laid out in the weekly picker's
    /// calendar, every row is exactly one week key across a year of months; the daily picker keeps
    /// the system's Sunday-first rows, which is what makes the first count non-vacuous.
    @Test func weeklyPickerRowsAreEachExactlyOneISOWeek() {
        let weekly = CadenceNoteDateNavigation.pickerCalendar(for: .week, base: usCalendar)
        let daily = CadenceNoteDateNavigation.pickerCalendar(for: .today, base: usCalendar)
        #expect(daily.firstWeekday == 1)
        #expect(weekly.timeZone == usCalendar.timeZone)
        let months = (1...12).map { String(format: "2026-%02d", $0) }
        #expect(months.map { rowsSpanningTwoWeekKeys(month: $0, pickerCalendar: daily) }.reduce(0, +) > 0)
        #expect(months.map { rowsSpanningTwoWeekKeys(month: $0, pickerCalendar: weekly) }.reduce(0, +) == 0)
    }

    /// The grid's first column is Monday on Weekly, so the heading row the panel reads from the
    /// same calendar starts "Mo" -- headings and cells cannot disagree.
    @Test func weeklyPickerHeadingsStartOnMonday() {
        let weekly = CadenceNoteDateNavigation.pickerCalendar(for: .week, base: usCalendar)
        #expect(CadenceScheduleSupport.weekdaySymbols(calendar: weekly, width: .compact).first == "Mo")
        #expect(CadenceScheduleSupport.weekdaySymbols(calendar: usCalendar, width: .compact).first == "Su")
    }

    /// [[T-16664]]: a note opened from its row moves the date control onto that note's day. On the
    /// iPad the header is the only date on the page; it went on naming the day picked before over
    /// an editor showing another day, and picking that day back did nothing.
    @Test func theDateControlStandsOnTheOpenNotesDay() {
        let picked = "2026-11-11"
        // Daily: the open note's day, not the one picked.
        #expect(CadenceNoteDateNavigation.shownDayKey(
            for: .today, pickedDayKey: picked,
            openNoteKind: .daily, openNoteDateKey: "2026-10-26", openNoteWeekKey: "") == "2026-10-26")
        // Weekly, another week: that week's Monday, so the range reads the open week.
        let shownWeek = CadenceNoteDateNavigation.shownDayKey(
            for: .week, pickedDayKey: picked,
            openNoteKind: .weekly, openNoteDateKey: "", openNoteWeekKey: "2026-W34")
        #expect(shownWeek == midWeekMonday)
        #expect(CadenceNoteDateNavigation.title(for: .week, dayKey: shownWeek, now: now) == "Aug 17–23")
        // Weekly, the picked day's own week: the picked day stays put.
        #expect(CadenceNoteDateNavigation.shownDayKey(
            for: .week, pickedDayKey: "2026-08-20",
            openNoteKind: .weekly, openNoteDateKey: "", openNoteWeekKey: "2026-W34") == "2026-08-20")
        // Nothing to follow: no note, a malformed key, a note of another kind, an undated tab.
        for (tab, kind, dateKey, weekKey) in [
            (CadenceNotesTabVocabulary.today, NoteKind?.none, "", ""),
            (.today, .daily, "not-a-day", ""),
            (.week, .weekly, "", "garbage"),
            (.today, .weekly, "", "2026-W34"),
            (.notepad, .permanent, "", ""),
        ] {
            #expect(CadenceNoteDateNavigation.shownDayKey(
                for: tab, pickedDayKey: picked,
                openNoteKind: kind, openNoteDateKey: dateKey, openNoteWeekKey: weekKey) == picked)
        }
    }

    /// [[T-16664]]: both platforms' date controls read the open note's day through the one helper.
    @Test func bothDateControlsFollowTheOpenNote() throws {
        let iOS = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSNotesView.swift"))
        let header = try #require(CadenceSourceScan.declarationBody("private var notesHeader: some View", in: iOS))
        #expect(header.contains("iOSNotesDateTitle(tab: activeTab, dayKey: shownDayKey)"), "the iOS header binds the picked day, not the shown one")
        let binding = try #require(CadenceSourceScan.declarationBody("private var shownDayKey: Binding<String>", in: iOS))
        #expect(binding.contains("CadenceNoteDateNavigation.shownDayKey(for: activeTab, pickedDayKey: selectedDayKey, openNote: selectedNote)"))
        #expect(binding.contains("openNoteForSelectedDay()"), "a pick of the stored day is a dead button")

        let mac = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/NotesView.swift"))
        #expect(mac.components(separatedBy: "pickedDayKey: observedDay.todayKey, openNote: selectedNote)").count - 1 == 2,
                "a Mac dated page's picker does not open on its note's day")
    }
}
