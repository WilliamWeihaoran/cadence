import CoreGraphics
import Foundation
import Testing
@testable import Cadence

/// The compact day-column geometry the iOS board leans on, which is not itself a view.
///
/// This used to cover a one-line day summary as well. Both the summary and the context strip that
/// carried it were deleted when the standalone day chip came off every calendar surface — the
/// header's date title says which day you are on, so a band restating it had no subject left.
@MainActor
struct CalendarBoardCompactLayoutTests {

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
