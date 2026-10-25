import Foundation
import Testing
@testable import Cadence

// [[T-6252]]: iOS Search's event row says the year for a day outside the reference year, in the
// spelling Cmd+K's event subtitle uses (`GlobalSearchEventResultsTests`).
//
// `iOSSearchView` is iOS-only, so the label is tested on an iOS destination; that the row's
// `eventDetail` actually reads it is pinned from source and runs on both legs.

#if os(iOS)
@Suite @MainActor
struct iOSSearchEventDayLabelTests {
    /// Local noon on a day, so the year compared is the one the reader's calendar shows.
    private func localDay(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// Reference Mon 25 Oct 2027 -- deliberately not the year the suite runs in, so a label that
    /// read the clock instead of its reference would be caught.
    @Test func anIOSSearchEventInAnotherYearSaysWhichYearAndOneThisYearDoesNot() {
        let reference = localDay(2027, 10, 25)

        // Same year: byte-for-byte the old `EEE, MMM d` label.
        #expect(iOSSearchView.eventDayLabel(localDay(2027, 11, 15, hour: 10), relativeTo: reference) == "Mon, Nov 15")
        #expect(iOSSearchView.eventDayLabel(localDay(2028, 11, 15, hour: 10), relativeTo: reference) == "Wed, Nov 15, 2028")
        #expect(iOSSearchView.eventDayLabel(localDay(2026, 10, 1, hour: 10), relativeTo: reference) == "Thu, Oct 1, 2026")
    }
}
#endif

@Suite
struct iOSSearchEventDayLabelWiringTests {
    /// The row's detail spells its day through `eventDayLabel`, and nothing in the file spells a
    /// bare `shortDate` again.
    @Test func theIOSSearchEventRowReadsTheYearAwareDayLabel() throws {
        let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSearchView.swift"))
        let detail = try #require(
            CadenceSourceScan.declarationBody("private func eventDetail(_ event: EKEvent) -> String", in: code),
            "could not read iOSSearchView.eventDetail"
        )
        #expect(detail.contains("Self.eventDayLabel(startDate)"))
        #expect(!code.contains("DateFormatters.shortDate"))
    }
}
