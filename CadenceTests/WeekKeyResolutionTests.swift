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
    ///
    /// **Both halves take the same calendar, and that is the assertion** (T-1115). This used to ask
    /// `weekStartDate` for a Monday in `utc` and then ask `weekKey` to name it with no calendar at
    /// all — so the second half read the *device's* zone, and west of UTC that Monday-00:00-UTC is
    /// still Sunday, one whole ISO week earlier. All 400 iterations failed on a Mac in
    /// `America/Los_Angeles` and none of them on one in `Asia/Shanghai`: the test was measuring the
    /// machine's longitude alongside the arithmetic and reporting the sum.
    ///
    /// The zone sweep is the guard against that recurring. A single zone cannot tell a correct
    /// round-trip from one that happens to agree with the host, and `TZ=` does not reach the
    /// spawned macOS test host, so the zones have to be varied from inside the test.
    @Test func everyWeekKeyRoundTripsBackIntoItsOwnWeek() throws {
        for zone in ["UTC", "Asia/Shanghai", "America/Los_Angeles", "Pacific/Auckland"] {
            let calendar = calendar(zone)

            for dayOffset in 0..<400 {
                guard let date = calendar.date(byAdding: .day, value: dayOffset, to: try #require(DateFormatters.date(from: "2026-01-01", in: calendar))) else { continue }
                let key = DateFormatters.weekKey(from: date, calendar: calendar)
                let monday = try #require(DateFormatters.weekStartDate(forWeekKey: key, calendar: calendar))
                #expect(DateFormatters.weekKey(from: monday, calendar: calendar) == key, "week key \(key) did not round-trip in \(zone)")
            }
        }
    }

    /// The zone a key is *read* in is the caller's, and it is a different question from the one
    /// the round-trip asks: a pair of helpers that both ignored the calendar would round-trip
    /// perfectly and still name the wrong week. So this one states the answer outright.
    ///
    /// `2026-01-01` is a Thursday in ISO week 1 of 2026. Midnight UTC on that day is `2025-12-31`
    /// in `America/Los_Angeles` — a Wednesday, in ISO week 1 of 2026 as well, because the ISO week
    /// spans the year boundary. The Monday **that** week opens on is `2025-12-29`.
    @Test func aWeekKeyIsReadInTheCallersZoneRatherThanTheDevices() throws {
        let utc = calendar("UTC")
        let losAngeles = calendar("America/Los_Angeles")
        let midnightUTC = try #require(DateFormatters.date(from: "2026-01-01", in: utc))

        #expect(DateFormatters.weekKey(from: midnightUTC, calendar: utc) == "2026-W01")
        #expect(DateFormatters.weekKey(from: midnightUTC, calendar: losAngeles) == "2026-W01")

        // The instant is a different *day* in the two zones even though it is the same week, so a
        // key one week earlier is what a naive reader would produce for the Monday below.
        #expect(DateFormatters.dateKey(from: midnightUTC, calendar: utc) == "2026-01-01")
        #expect(DateFormatters.dateKey(from: midnightUTC, calendar: losAngeles) == "2025-12-31")

        let monday = try #require(DateFormatters.weekStartDate(forWeekKey: "2026-W01", calendar: utc))
        #expect(DateFormatters.dateKey(from: monday, calendar: utc) == "2025-12-29")
        // The whole bug in one line: naming that instant without a calendar is the device's answer.
        #expect(DateFormatters.weekKey(from: monday, calendar: utc) == "2026-W01")
        #expect(DateFormatters.weekKey(from: monday, calendar: losAngeles) == "2025-W52")
    }

    /// The default is `.current` and it must stay byte-identical to what the parameterless version
    /// computed, because `weekKey` output is persisted (`Note.weekKey`, `WeeklyNote.weekKey`) and
    /// syncs through CloudKit — in Production. A defaulted parameter that changed any existing
    /// caller's answer would re-address stored notes; this pins that it does not.
    ///
    /// The reference is spelled out here rather than taken from `DateFormatters`, and that is the
    /// whole point: `weekKey(from: date) == weekKey(from: date, calendar: .current)` is the *same
    /// function called twice*, so it holds no matter what either one computes. It passed under a
    /// mutation that pinned `weekKey` to UTC, which is exactly the class of change it exists to
    /// catch. `iso` below is the pre-T-1115 construction, verbatim — `Calendar(identifier:
    /// .iso8601)` with a POSIX locale and **no** time zone, so it reads the device's.
    @Test func theDefaultCalendarIsTheDeviceZoneTheParameterlessVersionUsed() throws {
        var iso = Calendar(identifier: .iso8601)
        iso.locale = Locale(identifier: "en_US_POSIX")

        let start = try #require(DateFormatters.date(from: "2020-01-01", in: .current))
        for hourOffset in stride(from: 0, to: 366 * 24 * 6, by: 7) {
            let date = start.addingTimeInterval(Double(hourOffset) * 3600)
            let components = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            let expected = String(
                format: "%d-W%02d",
                try #require(components.yearForWeekOfYear),
                try #require(components.weekOfYear)
            )

            #expect(DateFormatters.weekKey(from: date) == expected)
            #expect(DateFormatters.weekKey(from: date, calendar: .current) == expected)
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
