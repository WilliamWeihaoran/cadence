import Foundation
import Testing
@testable import Cadence

/// [[T-17441]]: a day whose midnight does not exist is still a day.
///
/// Chile, Cuba, Lebanon, Egypt and the Azores move their clocks forward **at midnight**, so on
/// that one day a year the local clock reads 23:59:59 and then 01:00:00. `DateFormatters.ymd` is a
/// `DateFormatter`, and a non-lenient `DateFormatter` answers `nil` for a wall time that does not
/// exist -- so `date(from: "2026-09-06")` in Santiago came back `nil`, and every caller treated a
/// task due that day as carrying a malformed key: its chip read the raw `2026-09-06` instead of
/// `Today`, a daily repeat ticked that day respawned on the same day (`shiftedDateKey` could not
/// parse it and the workflow kept the old date), and `normalizedDateKey` refused the day outright.
///
/// Every zone here is stated on the formatter or the calendar; nothing reads the host's zone.
struct StorageKeyMissingMidnightTests {
    /// `DateFormatters.ymd`'s configuration, in `identifier`'s zone.
    private func storageKeyFormatter(_ identifier: String) throws -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = try CadenceTestTimeZones.calendar(identifier).timeZone
        return formatter
    }

    /// The spring-forward day of each zone, each one a midnight that is skipped.
    static let missingMidnights: [(zone: String, key: String)] = [
        ("America/Santiago", "2026-09-06"),
        ("America/Havana", "2026-03-08"),
        ("Asia/Beirut", "2026-03-29"),
    ]

    @Test func theDayWhoseMidnightIsSkippedStillParses() throws {
        for (zone, key) in Self.missingMidnights {
            let formatter = try storageKeyFormatter(zone)
            let calendar = try CadenceTestTimeZones.calendar(zone)
            // The premise: the formatter alone really refuses this day, or the test is free.
            #expect(formatter.date(from: key) == nil, "\(zone) \(key) has a midnight after all")

            let parsed = try #require(DateFormatters.date(from: key, using: formatter), "\(zone) \(key)")
            #expect(DateFormatters.dateKey(from: parsed, calendar: calendar) == key, "\(zone) \(key)")
            // The day's first instant, which is what midnight stands for everywhere else.
            #expect(calendar.startOfDay(for: parsed) == parsed, "\(zone) \(key)")
        }
    }

    @Test func anOrdinaryDayAndANonDayAreUnchanged() throws {
        let formatter = try storageKeyFormatter("America/Santiago")
        let calendar = try CadenceTestTimeZones.calendar("America/Santiago")

        let dayBefore = try #require(DateFormatters.date(from: "2026-09-05", using: formatter))
        #expect(dayBefore == formatter.date(from: "2026-09-05"))
        #expect(DateFormatters.dateKey(from: dayBefore, calendar: calendar) == "2026-09-05")

        // The fallback must not make a non-day into a day.
        for bogus in ["2026-02-30", "2026-13-01", "2026-09-06T10:00", "", "2026-09"] {
            #expect(DateFormatters.date(from: bogus, using: formatter) == nil, "\(bogus)")
        }
    }

    @Test func theChipOnThatDayReadsToday() throws {
        let calendar = try CadenceTestTimeZones.calendar("America/Santiago")
        // 2026-09-06 15:00 UTC is noon in Santiago on the spring-forward day (UTC-3 by then).
        let noon = Date(timeIntervalSince1970: 1_788_706_800)
        #expect(DateFormatters.dateKey(from: noon, calendar: calendar) == "2026-09-06")

        #expect(DateFormatters.dayOffset(from: "2026-09-06", relativeTo: noon, calendar: calendar) == 0)
        #expect(DateFormatters.dayOffset(from: "2026-09-07", relativeTo: noon, calendar: calendar) == 1)
        #expect(DateFormatters.dayOffset(from: "2026-09-05", relativeTo: noon, calendar: calendar) == -1)
    }

    /// [[T-17766]]: the due-date vocabulary's "tomorrow" on that day. `dueLabel` counted
    /// `dateComponents([.day])` between the two parsed day starts, and 2026-09-06 starts at 01:00
    /// in Santiago while 2026-09-07 starts at 00:00 -- 23 hours, zero days -- so every row, card,
    /// widget and sidebar badge said "Due Sep 7" for tomorrow.
    @Test func dueTomorrowOnTheDayWhoseMidnightIsSkipped() throws {
        let calendar = try CadenceTestTimeZones.calendar("America/Santiago")
        // The premise: the two day starts really are less than a day apart, or the test is free.
        let today = try #require(DateFormatters.date(from: "2026-09-06", in: calendar))
        let tomorrow = try #require(DateFormatters.date(from: "2026-09-07", in: calendar))
        #expect(calendar.dateComponents([.day], from: today, to: tomorrow).day == 0)

        #expect(
            CadenceWidgetDateSupport.dueLabel(for: "2026-09-07", todayKey: "2026-09-06", calendar: calendar)
                == "Due tomorrow"
        )
        // The neighbours keep their words: today, the day after tomorrow, and the night before.
        #expect(CadenceWidgetDateSupport.dueLabel(for: "2026-09-06", todayKey: "2026-09-06", calendar: calendar) == "Due today")
        #expect(CadenceWidgetDateSupport.dueLabel(for: "2026-09-08", todayKey: "2026-09-06", calendar: calendar) != "Due tomorrow")
        #expect(CadenceWidgetDateSupport.dueLabel(for: "2026-09-06", todayKey: "2026-09-05", calendar: calendar) == "Due tomorrow")
    }
}
