import Foundation
import Testing
@testable import Cadence

/// Two defects that shipped together and were wrong for anyone outside a US locale, fixed under
/// T-18's "date defects only" scope.
///
/// These are behavioural, not source scans, deliberately: the previous test in this family asserted
/// a property's *declared type* rather than the decision made with it, and a verifier proved a
/// mutation could restore the bug with the whole suite still green.
struct CadenceDateLocaleSurfaceTests {

    // MARK: - Defect 1: fixed-format formatters followed the host locale

    /// Every fixed-format formatter is pinned. `monthYear` and `shortMonthYear` already said this
    /// was the repo's rule in their own doc comments while six others quietly broke it.
    @Test func everyFixedFormatFormatterIsPinnedToOneLanguage() {
        let formatters: [(String, DateFormatter)] = [
            ("ymd", DateFormatters.ymd), ("longDate", DateFormatters.longDate),
            ("monthYear", DateFormatters.monthYear), ("shortMonthYear", DateFormatters.shortMonthYear),
            ("shortDate", DateFormatters.shortDate), ("fullShortDate", DateFormatters.fullShortDate),
            ("dayOfWeek", DateFormatters.dayOfWeek), ("dayNumber", DateFormatters.dayNumber),
            ("monthAbbrev", DateFormatters.monthAbbrev),
        ]
        for (name, f) in formatters {
            #expect(f.locale.identifier == "en_US_POSIX", "\(name) follows the host locale")
        }
    }

    /// The observable half: a fixed date renders in English whatever the host is set to. Before the
    /// fix a German Mac rendered `Montag, August 24` beside untranslated buttons.
    @Test func aFixedDateRendersInEnglishRegardlessOfHostLocale() throws {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 8; comps.day = 24
        let date = try #require(Calendar(identifier: .gregorian).date(from: comps))
        #expect(DateFormatters.longDate.string(from: date) == "Monday, August 24")
        #expect(DateFormatters.dayOfWeek.string(from: date) == "Mon")
        #expect(DateFormatters.monthAbbrev.string(from: date) == "Aug")
        #expect(DateFormatters.dayNumber.string(from: date) == "24")
    }

    // MARK: - Defect 2: one month grid was Sunday-first unconditionally

    /// Language pinned, week start not. `firstWeekday` is a real preference — a UK user wants
    /// Monday first in an English app — so honouring it is correct rather than half-localised.
    @Test func weekdayHeadingsAreEnglishButStartWhereTheLocaleStartsItsWeek() {
        var sundayFirst = Calendar(identifier: .gregorian); sundayFirst.firstWeekday = 1
        var mondayFirst = Calendar(identifier: .gregorian); mondayFirst.firstWeekday = 2

        #expect(CadenceScheduleSupport.weekdaySymbols(calendar: sundayFirst).first == "Sun")
        #expect(CadenceScheduleSupport.weekdaySymbols(calendar: mondayFirst).first == "Mon")
        #expect(CadenceScheduleSupport.weekdaySymbols(calendar: mondayFirst).last == "Sun")
    }

    /// A German locale must not produce German headings while the rest of the UI is English.
    @Test func aLocalizedCalendarStillYieldsEnglishHeadings() {
        var german = Calendar(identifier: .gregorian)
        german.locale = Locale(identifier: "de_DE")
        german.firstWeekday = 2
        let symbols = CadenceScheduleSupport.weekdaySymbols(calendar: german)
        #expect(symbols == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        #expect(!symbols.contains("Mo."), "German abbreviations leaked through")
    }

    /// The compact width the date-picker panel uses is the same array, shortened — not a second
    /// hand-rolled list, which is how the two grids drifted apart in the first place.
    @Test func theCompactWidthIsTheSameOrderJustShorter() {
        var mondayFirst = Calendar(identifier: .gregorian); mondayFirst.firstWeekday = 2
        let short = CadenceScheduleSupport.weekdaySymbols(calendar: mondayFirst, width: .short)
        let compact = CadenceScheduleSupport.weekdaySymbols(calendar: mondayFirst, width: .compact)
        #expect(compact == ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"])
        #expect(compact.count == short.count)
        for (s, c) in zip(short, compact) { #expect(s.hasPrefix(c)) }
    }

    /// The cells have to start where the headings do. The macOS picker computed `weekday - 1`,
    /// which is Sunday-first, so in a Monday-first region its grid sat one column off its own
    /// headings.
    @Test func leadingBlanksAgreeWithWhereTheHeadingsStart() throws {
        // 1 August 2026 is a Saturday.
        var comps = DateComponents(); comps.year = 2026; comps.month = 8; comps.day = 1
        var sundayFirst = Calendar(identifier: .gregorian); sundayFirst.firstWeekday = 1
        var mondayFirst = Calendar(identifier: .gregorian); mondayFirst.firstWeekday = 2
        let first = try #require(sundayFirst.date(from: comps))

        #expect(CadenceScheduleSupport.leadingBlankCount(forFirstOf: first, calendar: sundayFirst) == 6)
        #expect(CadenceScheduleSupport.leadingBlankCount(forFirstOf: first, calendar: mondayFirst) == 5)
    }

    /// Non-vacuity: the blank count must actually vary with `firstWeekday`, or the test above would
    /// pass against a hard-coded constant.
    @Test func theBlankCountTracksFirstWeekdayRatherThanBeingConstant() throws {
        var comps = DateComponents(); comps.year = 2026; comps.month = 8; comps.day = 1
        var cal = Calendar(identifier: .gregorian); cal.firstWeekday = 1
        let first = try #require(cal.date(from: comps))
        var seen = Set<Int>()
        for start in 1...7 {
            var c = Calendar(identifier: .gregorian); c.firstWeekday = start
            seen.insert(CadenceScheduleSupport.leadingBlankCount(forFirstOf: first, calendar: c))
        }
        #expect(seen.count == 7, "blank count ignores firstWeekday")
    }
}
