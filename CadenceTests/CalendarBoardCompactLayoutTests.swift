import CoreGraphics
import Foundation
import Testing
@testable import Cadence

/// Covers the two pieces of calendar logic the iOS board and context strip lean on that are not
/// themselves views: the one-line day summary, and the compact day-column geometry that leaves the
/// next day peeking.
@MainActor
struct CalendarBoardCompactLayoutTests {

    // MARK: - Day summary line

    @Test func summaryIsNilWhenTheDayHoldsNothing() {
        #expect(CadenceCalendarDaySummary.line(taskCount: 0, timedCount: 0, bundleCount: 0, eventCount: 0) == nil)
    }

    @Test func summaryOmitsEveryZeroCount() {
        #expect(
            CadenceCalendarDaySummary.line(taskCount: 3, timedCount: 0, bundleCount: 0, eventCount: 0)
                == "3 tasks"
        )
    }

    @Test func summaryJoinsOnlyTheNonZeroCounts() {
        #expect(
            CadenceCalendarDaySummary.line(taskCount: 4, timedCount: 2, bundleCount: 1, eventCount: 3)
                == "4 tasks · 2 timed · 1 block · 3 events"
        )
    }

    @Test func summarySingularizesEachNoun() {
        #expect(
            CadenceCalendarDaySummary.line(taskCount: 1, timedCount: 1, bundleCount: 1, eventCount: 1)
                == "1 task · 1 timed · 1 block · 1 event"
        )
    }

    /// Blocks and events are counted separately on purpose: summing them made a day of two blocks
    /// and one event read identically to a day of no blocks and three events.
    @Test func summaryKeepsBlocksAndEventsApart() {
        let blocksHeavy = CadenceCalendarDaySummary.line(taskCount: 0, timedCount: 0, bundleCount: 2, eventCount: 1)
        let eventsOnly = CadenceCalendarDaySummary.line(taskCount: 0, timedCount: 0, bundleCount: 0, eventCount: 3)

        #expect(blocksHeavy == "2 blocks · 1 event")
        #expect(eventsOnly == "3 events")
        #expect(blocksHeavy != eventsOnly)
    }

    // MARK: - Compact column geometry

    @Test func compactColumnLeavesTheNextDayPeeking() {
        let containerWidth: CGFloat = 402
        let leadingInset: CGFloat = 14
        let spacing: CGFloat = 10

        let width = CalendarBoardPlannerSupport.compactColumnWidth(
            containerWidth: containerWidth,
            leadingInset: leadingInset,
            columnSpacing: spacing
        )

        // What is visible of the following column once this one is paged to the leading edge.
        let peek = containerWidth - leadingInset - width - spacing
        #expect(peek > 0)
        #expect(peek / containerWidth > 0.14)
        #expect(peek / containerWidth < 0.21)
    }

    @Test func compactColumnNeverCollapsesOnANarrowContainer() {
        let width = CalendarBoardPlannerSupport.compactColumnWidth(
            containerWidth: 120,
            leadingInset: 14,
            columnSpacing: 10,
            minimumWidth: 200
        )

        #expect(width == 200)
    }

    @Test func compactColumnPeekFractionIsClamped() {
        let width = CalendarBoardPlannerSupport.compactColumnWidth(
            containerWidth: 402,
            leadingInset: 0,
            columnSpacing: 0,
            peekFraction: -3
        )

        #expect(width == 402)
    }
}
