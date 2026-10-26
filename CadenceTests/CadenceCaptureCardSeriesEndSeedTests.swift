import Foundation
import Testing
@testable import Cadence

/// **The capture card seeds a fresh *Ends: On Date* with the shared one-month-ahead default, not
/// the draft's own start day** ([[T-3233]]).
///
/// The start-day seed was a series that ends the day it begins, and since [[T-3229]] an event's
/// end reaches EventKit as `EKRecurrenceEnd(end:)` — so a weekly event switched to On Date and
/// committed untouched was a single occurrence in Apple Calendar. Shared code: this suite runs on
/// both the macOS and the iOS leg. No `EKEventStore` is involved; the seam is the draft value.
@MainActor
struct CadenceCaptureCardSeriesEndSeedTests {
    private static let calendar = Calendar.current

    private static func day(_ key: String) throws -> Date {
        try #require(DateFormatters.date(from: key, in: calendar))
    }

    private static func weeklyDraft(startingOn key: String) -> CadenceScheduleDraft {
        var draft = CadenceScheduleDraft(dateKey: key, startMin: 600, kind: .event)
        draft.repeatRule = .weekly
        return draft
    }

    @Test func choosingOnDateSeedsTheSharedDefaultRatherThanTheStartDay() throws {
        let today = try Self.day("2026-10-21")
        var draft = Self.weeklyDraft(startingOn: "2026-10-21")
        draft.seriesEndMode = .onDate
        draft.seedSeriesEnd(for: .onDate, reference: today, calendar: Self.calendar)

        #expect(draft.seriesEndDateKey != draft.startDateKey, "the series ends the day it begins")
        #expect(draft.seriesEndDateKey > draft.startDateKey)
        #expect(
            draft.seriesEndDateKey
                == CadenceTaskRecurrenceEndPresentation.defaultEndDateKey(from: today, calendar: Self.calendar)
        )
        #expect(draft.seriesEndDateKey == "2026-11-21")
    }

    @Test func aFutureStartAnchorsTheSeededEndOnTheStartSoItNeverPrecedesIt() throws {
        let today = try Self.day("2026-10-21")
        var draft = Self.weeklyDraft(startingOn: "2027-03-02")
        draft.seedSeriesEnd(for: .onDate, reference: today, calendar: Self.calendar)

        #expect(draft.seriesEndDateKey > draft.startDateKey)
        #expect(draft.seriesEndDateKey == "2027-04-02")
    }

    @Test func aPastStartAnchorsTheSeededEndOnTodayLikeTheOtherEndsControls() throws {
        let today = try Self.day("2026-10-21")
        var draft = Self.weeklyDraft(startingOn: "2026-06-01")
        draft.seedSeriesEnd(for: .onDate, reference: today, calendar: Self.calendar)

        #expect(
            draft.seriesEndDateKey
                == CadenceTaskRecurrenceEndPresentation.defaultEndDateKey(from: today, calendar: Self.calendar)
        )
    }

    @Test func anEndDayTheUserAlreadyChoseSurvivesReselectingOnDate() throws {
        let today = try Self.day("2026-10-21")
        var draft = Self.weeklyDraft(startingOn: "2026-10-21")
        draft.seriesEndDateKey = "2026-12-25"
        draft.seedSeriesEnd(for: .onDate, reference: today, calendar: Self.calendar)
        #expect(draft.seriesEndDateKey == "2026-12-25")
    }

    /// [[T-6931]]: this seeded `max(1, count)` -- a fresh After was a series ending on its first
    /// occurrence -- while every other Ends control seeds the shared count.
    @Test func choosingAfterCountSeedsTheSharedCountAndLeavesTheEndDayAlone() throws {
        var draft = Self.weeklyDraft(startingOn: "2026-10-21")
        draft.seedSeriesEnd(for: .afterCount, reference: try Self.day("2026-10-21"), calendar: Self.calendar)
        #expect(draft.seriesEndCount == CadenceTaskRecurrenceEndPresentation.seededEndCount)
        #expect(draft.seriesEndCount > 1, "a fresh After ends the series on its first occurrence")
        #expect(draft.seriesEndDateKey.isEmpty)
    }

    @Test func choosingAfterCountKeepsACountTheUserAlreadyChose() throws {
        var draft = Self.weeklyDraft(startingOn: "2026-10-21")
        draft.seriesEndCount = 3
        draft.seedSeriesEnd(for: .afterCount, reference: try Self.day("2026-10-21"), calendar: Self.calendar)
        #expect(draft.seriesEndCount == 3)
    }

    @Test func choosingAfterCountFloorsTheSeedAtTheCurrentOccurrence() throws {
        var draft = Self.weeklyDraft(startingOn: "2026-10-21")
        draft.seriesOccurrenceNumber = 15
        draft.seedSeriesEnd(for: .afterCount, reference: try Self.day("2026-10-21"), calendar: Self.calendar)
        #expect(draft.seriesEndCount == 15)
    }

    /// The capture card and the standard panel seed the same After count for the same draft.
    @Test func captureCardAndStandardPanelSeedTheSameAfterCount() throws {
        let reference = try Self.day("2026-10-21")
        for occurrence in [1, 15] {
            var card = Self.weeklyDraft(startingOn: "2026-10-21")
            card.seriesOccurrenceNumber = occurrence
            var panel = card
            card.seedSeriesEnd(for: .afterCount, reference: reference, calendar: Self.calendar)
            panel.selectSeriesEnd(.afterCount, reference: reference, calendar: Self.calendar)
            #expect(card.seriesEndCount == panel.seriesEndCount)
        }
    }

    /// The seam above is only the fix if the card calls it: SwiftUI's `.onChange` is not reachable
    /// from a unit test, so the wiring is source-scanned.
    @Test func theCaptureCardSeedsItsEndsChoiceThroughTheTestedSeam() throws {
        let card = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Shared/Components/CadenceScheduleCaptureCard.swift")
        )
        let onChange = try #require(
            CadenceSourceScan.declarationBody(".onChange(of: draft.seriesEndMode)", in: card)
        )
        #expect(onChange.contains("draft.seedSeriesEnd(for: mode)"))
        #expect(!onChange.contains("draft.startDateKey"), "the Ends seed reads the start day again")
        #expect(card.contains("return draft.captureRepeatSummary"))
    }

    @Test func theRepeatChipSpellsACountOfOneInTheSingular() {
        var draft = Self.weeklyDraft(startingOn: "2026-10-21")
        draft.seriesEndMode = .afterCount
        draft.seriesEndCount = 1
        #expect(draft.captureRepeatSummary.hasSuffix("1 time"))
        draft.seriesEndCount = 10
        #expect(draft.captureRepeatSummary.hasSuffix("10 times"))
    }
}
