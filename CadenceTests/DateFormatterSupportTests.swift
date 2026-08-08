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
        #expect(TimeFormatters.durationLabel(actual: 90, estimated: 120) == "1h\u{00A0}30m/2h")
        #expect(TimeFormatters.durationLabel(actual: 0, estimated: 30) == "-/30m")
    }

    @Test func timeLabelsWrapEndOfDayToMidnight() throws {
        #expect(TimeFormatters.timeString(from: 24 * 60) == "12 AM")
        #expect(TimeFormatters.timeRange(startMin: 18 * 60, endMin: 24 * 60) == "6 PM – 12 AM")
    }

    @Test func estimateLabelSplitsHoursAndMinutesAndNeverRendersADecimalHour() {
        #expect(CadenceTaskPresentationSupport.estimateLabel(minutes: 0) == "0m")
        #expect(CadenceTaskPresentationSupport.estimateLabel(minutes: -30) == "0m")
        #expect(CadenceTaskPresentationSupport.estimateLabel(minutes: 1) == "1m")
        #expect(CadenceTaskPresentationSupport.estimateLabel(minutes: 59) == "59m")
        #expect(CadenceTaskPresentationSupport.estimateLabel(minutes: 60) == "1h")
        #expect(CadenceTaskPresentationSupport.estimateLabel(minutes: 61) == "1h\u{00A0}1m")
        #expect(CadenceTaskPresentationSupport.estimateLabel(minutes: 90) == "1h\u{00A0}30m")
        #expect(CadenceTaskPresentationSupport.estimateLabel(minutes: 120) == "2h")
        #expect(CadenceTaskPresentationSupport.estimateLabel(minutes: 1439) == "23h\u{00A0}59m")
    }

    /// These labels are drawn inside hard-clipped fixed-size chrome (timeline blocks get as
    /// narrow as ~50pt when tasks overlap). A plain space is a line-break opportunity, so a
    /// wrapped "1h 30m" would lose its clipped second line and report "1h" for a 90-minute
    /// task — wrong information, not truncation. The separator must stay non-breaking.
    @Test func durationLabelsUseANonBreakingSpaceBetweenHoursAndMinutes() {
        #expect(!CadenceTaskPresentationSupport.estimateLabel(minutes: 90).contains(" "))
        #expect(!TimeFormatters.durationLabel(actual: 90, estimated: 90).contains(" "))
    }

    @Test func durationLabelPairsActualWithEstimatedAndDashesMissingValues() {
        #expect(TimeFormatters.durationLabel(actual: 0, estimated: 0) == "-/-")
        #expect(TimeFormatters.durationLabel(actual: -5, estimated: -5) == "-/-")
        #expect(TimeFormatters.durationLabel(actual: 1, estimated: 59) == "1m/59m")
        #expect(TimeFormatters.durationLabel(actual: 60, estimated: 61) == "1h/1h\u{00A0}1m")
        #expect(TimeFormatters.durationLabel(actual: 120, estimated: 1439) == "2h/23h\u{00A0}59m")
    }
}
