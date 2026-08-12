import Foundation
import Testing
@testable import Cadence

/// `2026-W33` → the Monday that opens that ISO week. The construction was written out twice —
/// once inside `DateFormatters.weekLabel` and once in `NotesListGrouping.weekStartDateKey` — and
/// neither copy inherited a time zone, so the same week key could resolve to different days
/// depending on which one you asked.
@MainActor
struct WeekKeyResolutionTests {
    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier) ?? .current
        return calendar
    }

    @Test func aWeekKeyResolvesToThatWeeksMonday() throws {
        let utc = calendar("UTC")
        let monday = try #require(DateFormatters.weekStartDate(forWeekKey: "2026-W33", calendar: utc))

        #expect(DateFormatters.dateKey(from: monday, calendar: utc) == "2026-08-10")
        // ISO weekday 2 is Monday in the calendar the key was built in.
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = utc.timeZone
        #expect(iso.component(.weekday, from: monday) == 2)
    }

    /// Round-trips against the key generator, which is the property that actually matters: the
    /// week a date belongs to must resolve back to a Monday inside that same week.
    @Test func everyWeekKeyRoundTripsBackIntoItsOwnWeek() throws {
        let utc = calendar("UTC")

        for dayOffset in 0..<400 {
            guard let date = utc.date(byAdding: .day, value: dayOffset, to: try #require(DateFormatters.date(from: "2026-01-01", in: utc))) else { continue }
            let key = DateFormatters.weekKey(from: date)
            let monday = try #require(DateFormatters.weekStartDate(forWeekKey: key, calendar: utc))
            #expect(DateFormatters.weekKey(from: monday) == key, "week key \(key) did not round-trip")
        }
    }

    /// The time zone is the caller's, so a key resolves to midnight of that Monday *there* rather
    /// than in whatever zone happened to be current.
    @Test func theResolvedMondayIsMidnightInTheCallersZone() throws {
        for zone in ["UTC", "Asia/Tokyo", "America/New_York"] {
            let calendar = calendar(zone)
            let monday = try #require(DateFormatters.weekStartDate(forWeekKey: "2026-W33", calendar: calendar))

            #expect(DateFormatters.dateKey(from: monday, calendar: calendar) == "2026-08-10", "wrong day in \(zone)")
            #expect(calendar.component(.hour, from: monday) == 0, "not midnight in \(zone)")
        }
    }

    @Test func aMalformedKeyResolvesToNothingRatherThanAWrongDay() {
        #expect(DateFormatters.weekStartDate(forWeekKey: "") == nil)
        #expect(DateFormatters.weekStartDate(forWeekKey: "2026") == nil)
        #expect(DateFormatters.weekStartDate(forWeekKey: "not-a-week") == nil)
        #expect(DateFormatters.weekStartDate(forWeekKey: "2026-Wxx") == nil)

        // And the callers degrade to echoing the key rather than inventing a date.
        #expect(DateFormatters.weekLabel(from: "not-a-week") == "not-a-week")
    }
}
