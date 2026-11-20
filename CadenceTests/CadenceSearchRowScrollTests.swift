import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// [[T-18659]]: iOS Search's hardware-keyboard highlight is scrolled into view by ROW.
///
/// Each section is one `List` row, so `scrollTo` can only target the whole group; a
/// minimal-distance scroll to a group taller than the viewport did nothing once part of it was on
/// screen, and Down walked the highlight off the bottom of a 24-row Tasks card.
/// `CadenceSearchRowScroll` picks the anchor that shows the row inside its group.
struct CadenceSearchRowScrollTests {

    /// A 24-row card of 56 pt rows -- the ticket's Tasks section -- in a 700 pt viewport.
    private static let rowHeight: CGFloat = 56
    private static let groupHeight: CGFloat = 24 * rowHeight
    private static let viewport: CGFloat = 700

    private static func rowTop(_ index: Int) -> CGFloat { CGFloat(index) * rowHeight }

    /// Where the row lands on screen once the group is scrolled with `anchor`: the group's top
    /// sits at `-f * (groupHeight - viewport)` (see `CadenceSearchRowScroll`).
    private static func landedTop(_ index: Int, anchor: UnitPoint?) -> CGFloat {
        let fraction = anchor?.y ?? 0
        return rowTop(index) - fraction * (groupHeight - viewport)
    }

    @Test func aRowBelowTheViewportInsideATallGroupIsScrolledFullyIntoView() throws {
        // The group's top is on screen and row 15 sits far below the bottom edge.
        let plan = CadenceSearchRowScroll.plan(
            rowTop: Self.rowTop(15), rowBottom: Self.rowTop(15) + Self.rowHeight,
            groupTop: 100, groupHeight: Self.groupHeight, viewportHeight: Self.viewport
        )
        guard case .group(let anchor) = plan else {
            Issue.record("a row below the viewport is left off screen: \(plan)")
            return
        }
        // The pre-fix scroll was the group's minimal scroll, which cannot reach row 15.
        let unwrapped = try #require(anchor, "the group's minimal scroll does not reach a row inside it")
        let top = Self.landedTop(15, anchor: unwrapped)
        #expect(top >= 0)
        #expect(top + Self.rowHeight <= Self.viewport)
        // Minimal: the row lands at the bottom edge, not re-centred.
        #expect(top + Self.rowHeight >= Self.viewport - CadenceSearchRowScroll.margin - 1)
    }

    @Test func aRowAboveTheViewportInsideATallGroupIsScrolledFullyIntoView() throws {
        // Scrolled to the bottom of the card; Up reaches row 2, above the top edge.
        let groupTop = Self.viewport - Self.groupHeight
        let plan = CadenceSearchRowScroll.plan(
            rowTop: Self.rowTop(2), rowBottom: Self.rowTop(2) + Self.rowHeight,
            groupTop: groupTop, groupHeight: Self.groupHeight, viewportHeight: Self.viewport
        )
        guard case .group(let anchor) = plan, let anchor else {
            Issue.record("a row above the viewport is left off screen: \(plan)")
            return
        }
        let top = Self.landedTop(2, anchor: anchor)
        #expect(top >= 0)
        #expect(top <= CadenceSearchRowScroll.margin + 1)
    }

    @Test func aRowAlreadyOnScreenLeavesTheListWhereItIs() {
        let plan = CadenceSearchRowScroll.plan(
            rowTop: Self.rowTop(3), rowBottom: Self.rowTop(3) + Self.rowHeight,
            groupTop: 100, groupHeight: Self.groupHeight, viewportHeight: Self.viewport
        )
        #expect(plan == .none)
    }

    @Test func aGroupThatFitsTheViewportTakesTheMinimalGroupScroll() {
        let plan = CadenceSearchRowScroll.plan(
            rowTop: Self.rowTop(3), rowBottom: Self.rowTop(3) + Self.rowHeight,
            groupTop: 900, groupHeight: 6 * Self.rowHeight, viewportHeight: Self.viewport
        )
        #expect(plan == .group(anchor: nil))
    }

    #if os(iOS)
    /// The view wiring: every result row and the continuation row report a frame, and the
    /// highlight scroll plans from them with an anchor instead of the bare group scroll.
    @Test func iOSSearchScrollsTheHighlightByTheMeasuredRow() throws {
        let group = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSearchSupportViews.swift"))
        let body = try #require(CadenceSourceScan.declarationBody("struct iOSSearchResultGroup<Row: View>: View", in: group))
        #expect(body.contains("reportRowFrame?(index, frame)"), "a result row reports no frame")
        #expect(body.contains("reportRowFrame?(nil, frame)"), "the continuation row reports no frame")
        #expect(body.contains(".coordinateSpace(.named(Self.rowSpace))"))

        let view = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSearchView.swift"))
        let scroll = try #require(CadenceSourceScan.declarationBody(
            "private func scrollToHighlighted(_ id: String?, proxy: ScrollViewProxy)", in: view
        ))
        #expect(scroll.contains("highlightGeometry.plan(rowID: id"))
        #expect(scroll.contains("anchor: anchor"))
        #expect(view.contains("highlightGeometry.groupFrames[title] = frame"))
        #expect(view.contains("highlightGeometry.viewport = visible"))
    }
    #endif
}
