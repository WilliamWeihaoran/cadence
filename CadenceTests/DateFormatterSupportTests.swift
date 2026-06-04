import Foundation
import Testing
@testable import Cadence

struct DateFormatterSupportTests {
    @Test func weekKeyUsesIsoWeekYearAcrossNewYearBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

        let janFirst = try #require(calendar.date(from: DateComponents(year: 2021, month: 1, day: 1, hour: 12)))
        let janFourth = try #require(calendar.date(from: DateComponents(year: 2021, month: 1, day: 4, hour: 12)))

        #expect(DateFormatters.weekKey(from: janFirst) == "2020-W53")
        #expect(DateFormatters.weekKey(from: janFourth) == "2021-W01")
    }

    @Test func relativeDateAndDurationLabelsFollowTaskFriendlyDisplayRules() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: today))
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        let inThirteenDays = try #require(calendar.date(byAdding: .day, value: 13, to: today))
        let inFourteenDays = try #require(calendar.date(byAdding: .day, value: 14, to: today))

        #expect(DateFormatters.relativeDate(from: DateFormatters.dateKey(from: today)) == "Today")
        #expect(DateFormatters.relativeDate(from: DateFormatters.dateKey(from: tomorrow)) == "Tomorrow")
        #expect(DateFormatters.relativeDate(from: DateFormatters.dateKey(from: yesterday)) == "Yesterday")
        #expect(DateFormatters.relativeDate(from: DateFormatters.dateKey(from: inThirteenDays)) == "in 13 days")
        #expect(
            DateFormatters.relativeDate(from: DateFormatters.dateKey(from: inFourteenDays)) ==
            DateFormatters.shortDate.string(from: inFourteenDays)
        )

        #expect(TimeFormatters.durationLabel(actual: 45, estimated: 0) == "45m/-")
        #expect(TimeFormatters.durationLabel(actual: 90, estimated: 120) == "1.5h/2h")
        #expect(TimeFormatters.durationLabel(actual: 0, estimated: 30) == "-/30m")
    }

    @Test func timeLabelsWrapEndOfDayToMidnight() throws {
        #expect(TimeFormatters.timeString(from: 24 * 60) == "12 AM")
        #expect(TimeFormatters.timeRange(startMin: 18 * 60, endMin: 24 * 60) == "6 PM – 12 AM")
    }
}
