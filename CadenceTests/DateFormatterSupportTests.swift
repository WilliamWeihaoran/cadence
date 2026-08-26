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

    /// `normalizedDateKey` is the single spelling of "this text is a storage key".
    ///
    /// The rule under test is normalize-when-unambiguous, reject-when-the-century-is-a-guess:
    /// `"2026-8-20"` names one day and becomes `"2026-08-20"`, while `"26-8-2"` parses just as
    /// happily to the year 26 AD and is refused rather than stored as `"0026-08-02"`.
    @Test func normalizedDateKeyCanonicalizesUnambiguousSpellingsAndRefusesAShortYear() {
        #expect(DateFormatters.normalizedDateKey("2026-08-20") == "2026-08-20")
        #expect(DateFormatters.normalizedDateKey("2026-8-20") == "2026-08-20")
        #expect(DateFormatters.normalizedDateKey("2026-8-2") == "2026-08-02")
        #expect(DateFormatters.normalizedDateKey("  2026-8-20  ") == "2026-08-20")
        #expect(DateFormatters.normalizedDateKey("2026-008-020") == "2026-08-20")
        #expect(DateFormatters.normalizedDateKey("2026/08/20") == "2026-08-20")

        // Refused, and the first two are the interesting ones: the parse succeeds, so nothing but
        // this function stands between them and a stored key.
        #expect(DateFormatters.date(from: "26-8-2") != nil)
        #expect(DateFormatters.normalizedDateKey("26-8-2") == nil)
        #expect(DateFormatters.normalizedDateKey("0026-08-02") == "0026-08-02")
        #expect(DateFormatters.normalizedDateKey("2026-13-01") == nil)
        #expect(DateFormatters.normalizedDateKey("2026-02-30") == nil)
        #expect(DateFormatters.normalizedDateKey("2026-08-20T10:00") == nil)
        #expect(DateFormatters.normalizedDateKey("next Tuesday") == nil)
        #expect(DateFormatters.normalizedDateKey("") == nil)
    }

    /// Why the padding is not pedantry: the app compares storage keys as strings, so a key that is
    /// not fixed-width sorts into a different day than it means.
    @Test func aLenientlySpelledKeyOrdersWrongUntilItIsNormalized() throws {
        let raw = "2026-8-20"
        let canonical = try #require(DateFormatters.normalizedDateKey(raw))

        #expect((raw < "2026-08-25") == false)
        #expect(canonical < "2026-08-25")
        #expect(DateFormatters.date(from: raw) == DateFormatters.date(from: canonical))
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
    ///
    /// The assertion has to name every surface that renders a duration, not just the canonical
    /// helper: this test passed for months while `TimelineEventBlockSupportViews` and
    /// `GoalContributionSummary.focusLabel` shipped their own copies with a breakable space in
    /// them. The subject of a test has to be the code that can break.
    @Test func durationLabelsUseANonBreakingSpaceBetweenHoursAndMinutes() {
        #expect(!CadenceTaskPresentationSupport.estimateLabel(minutes: 90).contains(" "))
        #expect(!TimeFormatters.durationLabel(actual: 90, estimated: 90).contains(" "))
        #expect(!TimeFormatters.durationLabel(minutes: 90, emptyPlaceholder: "–").contains(" "))

        let summary = GoalContributionSummary(
            progressType: .hours,
            targetHours: 4,
            totalTasks: 0,
            completedTasks: 0,
            directTaskCount: 0,
            linkedListCount: 0,
            focusMinutes: 165,
            overdueTaskCount: 0,
            recentCompletedCount: 0,
            nextActionTitle: nil,
            nextActionDueDate: nil
        )
        #expect(summary.focusLabel == "2h\u{00A0}45m")
        #expect(!summary.focusLabel.contains(" "))
    }

    /// The empty sentinel is the only thing the duration surfaces ever disagreed about, so it is
    /// the only thing that is a parameter. Everything else must come out identical.
    @Test func durationLabelKeepsOneShapeAcrossItsThreeEmptySentinels() {
        #expect(TimeFormatters.durationLabel(minutes: 0, emptyPlaceholder: "0m") == "0m")
        #expect(TimeFormatters.durationLabel(minutes: 0, emptyPlaceholder: "-") == "-")
        #expect(TimeFormatters.durationLabel(minutes: -5, emptyPlaceholder: "–") == "–")
        #expect(TimeFormatters.durationLabel(minutes: 90, emptyPlaceholder: "–") == "1h\u{00A0}30m")
        #expect(CadenceTaskPresentationSupport.estimateLabel(minutes: 0, emptyPlaceholder: "–") == "–")

        for minutes in [1, 30, 59, 60, 61, 90, 120, 1_439] {
            #expect(
                CadenceTaskPresentationSupport.estimateLabel(minutes: minutes)
                    == TimeFormatters.durationLabel(minutes: minutes, emptyPlaceholder: "–")
            )
        }
    }

    @Test func durationLabelPairsActualWithEstimatedAndDashesMissingValues() {
        #expect(TimeFormatters.durationLabel(actual: 0, estimated: 0) == "-/-")
        #expect(TimeFormatters.durationLabel(actual: -5, estimated: -5) == "-/-")
        #expect(TimeFormatters.durationLabel(actual: 1, estimated: 59) == "1m/59m")
        #expect(TimeFormatters.durationLabel(actual: 60, estimated: 61) == "1h/1h\u{00A0}1m")
        #expect(TimeFormatters.durationLabel(actual: 120, estimated: 1439) == "2h/23h\u{00A0}59m")
    }
}
