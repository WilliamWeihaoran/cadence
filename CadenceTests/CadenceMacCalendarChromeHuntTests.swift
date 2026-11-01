#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// Three visible macOS Calendar chrome defects from one source hunt (agent `hunt1933mac`,
/// [[T-9840]]'s range). Each test names the one file it reads; none sweeps a directory.
@Suite struct CadenceMacCalendarChromeHuntTests {
    private static func code(_ path: String) throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }

    /// [[T-9841]]: the Month grid's weekday row is set at the shared weekday-header size, in the
    /// shared month band, like the Week columns' labels and both iOS month grids.
    @Test func theMonthWeekdayRowReadsTheSharedWeekdayMetrics() throws {
        let source = try Self.code("Cadence/macOS/Views/CalendarPageMonthGridSupport.swift")
        let header = try #require(CadenceSourceScan.declarationBody(
            "struct MonthGridWeekdayHeader: View", in: source
        ))
        #expect(header.contains(".font(.system(size: CadenceCalendarWeekdayHeaderMetrics.labelSize, weight: .semibold))"),
                "the Month weekday row is not at the shared weekday-header size")
        #expect(header.contains(".frame(height: CadenceCalendarWeekdayHeaderMetrics.bandHeight)"),
                "the Month weekday row is not in the shared month band")
        // The defect by name: a literal size, and a band made of padding instead of the metric.
        #expect(!header.contains(".font(.system(size: 11"), "the Month weekday row is back at a literal 11pt")
        #expect(!header.contains(".padding(.vertical,"), "the Month weekday row's band is padding again")
        // The relation the fix rests on: the shared row is smaller than the literal it replaced.
        #expect(CadenceCalendarWeekdayHeaderMetrics.labelSize < 11)
    }

    /// [[T-9842]]: the timeline corner's "all-day" sits in the hour rail's column, right-aligned on
    /// the hour labels' edge, at the top of the all-day band beside its first chip.
    @Test func theTimelineAllDayLabelSitsOnTheHourRailsEdge() throws {
        let source = try Self.code("Cadence/macOS/Views/CalendarPageSupportViews.swift")
        let viewport = try #require(CadenceSourceScan.declarationBody(
            "struct CalendarTimelineViewport: View", in: source
        ))
        let label = try #require(viewport.range(of: "Text(\"all-day\")"), "the corner no longer draws \"all-day\"")
        let overlayStart = try #require(viewport.range(of: ".overlay(alignment:", options: .backwards, range: viewport.startIndex..<label.lowerBound))
        let tail = viewport[label.upperBound...]
        let close = try #require(tail.range(of: "\n                    }"))
        let overlay = String(viewport[overlayStart.lowerBound..<close.lowerBound])
        #expect(overlay.hasPrefix(".overlay(alignment: .topTrailing)"), "the label is not anchored top-trailing")
        #expect(overlay.contains(".frame(width: calTimeWidth, alignment: .trailing)"),
                "the label is not right-aligned in the hour labels' column")
        #expect(overlay.contains(".padding(.trailing, calTimeInset)"),
                "the label does not stop at the hour labels' trailing inset")
        #expect(overlay.contains(".padding(.top, calDayHeaderHeight + 4)"),
                "the label is not level with the band's first chip")
        #expect(!overlay.contains(".padding(.leading,"), "the label is pushed in from the left again")
        #expect(!overlay.contains(".padding(.bottom,"), "the label hangs off the corner's bottom again")
        // The hour labels it now lines up with are drawn on the same two figures.
        let rail = try #require(CadenceSourceScan.declarationBody(
            "struct CalTimeRailLabel: View",
            in: try Self.code("Cadence/macOS/Views/CalendarPageComponents.swift")
        ))
        #expect(rail.contains(".frame(width: calTimeWidth, alignment: .topTrailing)"))
        #expect(rail.contains(".padding(.trailing, calTimeInset)"))
    }

    /// [[T-9843]]: the Calendar access card stands on the page gutter, not a literal 16.
    @Test func theCalendarAccessCardStandsOnThePageGutter() throws {
        let source = try Self.code("Cadence/macOS/Views/CalendarPageSupportViews.swift")
        let strip = try #require(CadenceSourceScan.declarationBody(
            "struct CalendarPageAccessNoticeStrip: View", in: source
        ))
        let card = try #require(strip.range(of: ".cadenceCard("), "the access strip no longer draws its card")
        let outside = String(strip[card.upperBound...])
        #expect(outside.contains(".padding(.horizontal, CadenceDesktopMetrics.pageHorizontalPadding)"),
                "the access card is not on the page gutter")
        #expect(!outside.contains(".padding(.horizontal, 16)"), "the access card is back on a literal 16")
        #expect(CadenceDesktopMetrics.pageHorizontalPadding != 16, "non-vacuity: the gutter is 16, so the fix moved nothing")
    }
}
#endif
