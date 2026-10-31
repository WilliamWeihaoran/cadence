import Foundation
import Testing
@testable import Cadence

/// iOS cards whose shadow a scroll view sliced off (agent `hunt1610ios`).
///
/// `Cadence/iOS/` is invisible to this macOS-built target, so the control is read as source.
/// A `ScrollView` clips to its own frame; a card that fills that frame on an axis loses the part of
/// its shadow that falls outside, and draws a hard line where every other card fades.

/// [[T-9541]]: the read-only markdown preview's table card (the Focus page's task notes) keeps the
/// shadow its horizontal scroller used to cut flat along its leading edge and its bottom.
struct CadenceIOSMarkdownPreviewTableShadowTests {
    @Test func theTableScrollerDoesNotClipTheCardShadow() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSMarkdownPreview.swift")
        let block = try #require(CadenceSourceScan.declarationBody("private struct iOSMarkdownPreviewTableBlock: View", in: source))
        let body = CadenceSourceScan.strippingComments(block)
        let start = try #require(body.range(of: "ScrollView(.horizontal)"), "non-vacuity: the slice holds the table scroller")
        let tail = String(body[start.upperBound...])
        let scroller = try #require(tail.components(separatedBy: "private func value(").first)
        #expect(scroller.contains(".cadenceCard("), "non-vacuity: the scroller still draws the shadowed card")
        #expect(CadenceSourceScan.matchCount(#"\.scrollIndicators\(\.hidden\)\s*\.scrollClipDisabled\(\)"#, in: scroller) == 1,
                "the table scroller clips its own card's shadow")
    }
}
