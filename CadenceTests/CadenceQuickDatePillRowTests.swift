import Foundation
import SwiftUI
import Testing
@testable import Cadence

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// T-1492. The quick-date pills fell from one row straight to three.
///
/// `ViewThatFits` was given two candidates and no middle, so a row that missed by a few points
/// became three stacked lines above the grid the reader opened the popover for. The mechanism was
/// never wrong — it picks the first candidate that fits, and neither of the two it had did anything
/// but the extremes. The fix is a third candidate, and these tests say what a third candidate has
/// to be worth: it must sit **between** the other two in the list, and its widest row must actually
/// fit the popover, or it is a candidate `ViewThatFits` will skip on its way to the same three rows.
///
/// Everything measured here is a **relation** — a row against the width it has to fit inside, a
/// candidate against the candidate before it. No point figure is pinned, because the font metrics
/// behind these widths are a toolchain's to change (T-1279/T-1296).
struct CadenceQuickDatePillRowTests {
    private static let path = "Cadence/Shared/Components/CadenceDatePicker.swift"

    private static func source() throws -> String {
        // Comments blanked, string literals kept: the pill LABELS are literals and they are what
        // the arrangement is read from.
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }

    private static func popoverBody(_ source: String) throws -> String {
        let declaration = try #require(
            CadenceSourceScan.declarationBody("struct CadenceQuickDatePopover: View", in: source)
        )
        return try #require(CadenceSourceScan.declarationBody("var body: some View", in: declaration))
    }

    /// The single number a candidate has to fit inside: the popover's width less the padding the
    /// quick-action strip is drawn in. Both halves are read from source rather than restated.
    private static func contentWidth(at size: DynamicTypeSize, horizontalPadding: CGFloat) -> CGFloat {
        CadenceDateSelectionMetrics.width(at: size) - horizontalPadding * 2
    }

    private static func labelWidth(_ label: String, fontSize: CGFloat) -> CGFloat {
        #if canImport(AppKit)
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        #else
        let font = UIFont.systemFont(ofSize: fontSize, weight: .medium)
        #endif
        return (label as NSString).size(withAttributes: [.font: font]).width
    }

    /// Pill width = its text, its own horizontal padding, and the hover plate wrapped around it.
    private static func rowWidth(
        _ labels: [String],
        fontSize: CGFloat,
        pillPadding: CGFloat,
        hoverPadding: CGFloat,
        spacing: CGFloat
    ) -> CGFloat {
        let pills = labels.reduce(CGFloat.zero) { total, label in
            total + labelWidth(label, fontSize: fontSize) + pillPadding * 2 + hoverPadding * 2
        }
        return pills + spacing * CGFloat(max(labels.count - 1, 0))
    }

    private static func integer(_ pattern: String, in text: String) throws -> CGFloat {
        let captured = CadenceSourceScan.captures(pattern, in: text)
        let value = try #require(captured.first.flatMap { Double($0.text) })
        return CGFloat(value)
    }

    /// The candidate list is three long, widest first, with the two-row arrangement in the middle.
    ///
    /// Order is the whole assertion. `ViewThatFits` takes the FIRST candidate that fits, so a
    /// two-row arrangement listed after the stacked one can never be reached, and one listed before
    /// the single row would take a row the single row could have had.
    @Test func quickDateStripOffersThreeCandidatesWithTheTwoRowArrangementInTheMiddle() throws {
        let body = try Self.popoverBody(try Self.source())
        let candidates = try #require(
            CadenceSourceScan.declarationBody("ViewThatFits(in: .horizontal)", in: body)
        )

        let oneRow = try #require(candidates.range(of: "HStack(spacing: 6) { quickActions }"))
        let twoRows = try #require(candidates.range(of: "VStack(spacing: 6) { quickActionRows }"))
        let stacked = try #require(candidates.range(of: "VStack(spacing: 6) { quickActions }"))

        #expect(oneRow.lowerBound < twoRows.lowerBound, "the single row must still be tried first")
        #expect(twoRows.lowerBound < stacked.lowerBound, "a candidate after the stack is unreachable")
        // Exactly three: a count, so adding a fourth arrangement has to come back through this test.
        #expect(CadenceSourceScan.matchCount(#"[HV]Stack\(spacing: 6\) \{ quickAction"#, in: candidates) == 3)
        // The single-row candidate keeps its ideal width, or it would report a compressed one and
        // be accepted at a width that then squeezes its own pills.
        #expect(candidates.contains(".fixedSize(horizontal: true, vertical: false)"))
    }

    /// The middle candidate is two rows, and between them they draw the same three pills as the
    /// other two candidates — a rearrangement, not a different set of shortcuts.
    @Test func theTwoRowCandidateRearrangesTheSameThreePills() throws {
        let source = try Self.source()
        let declaration = try #require(
            CadenceSourceScan.declarationBody("struct CadenceQuickDatePopover: View", in: source)
        )
        let rows = try #require(
            CadenceSourceScan.declarationBody("private var quickActionRows: some View", in: declaration)
        )
        let flat = try #require(
            CadenceSourceScan.declarationBody("private var quickActions: some View", in: declaration)
        )

        let pairedRow = try #require(CadenceSourceScan.declarationBody("HStack(spacing: 6)", in: rows))
        let paired = Self.pillLabels(in: pairedRow)
        let all = Self.pillLabels(in: rows)
        #expect(Self.pillLabels(in: flat) == all, "the rows must offer the same pills as the flat strip")
        #expect(all.count == paired.count + 1, "exactly one pill drops to the second row")
        #expect(paired.count == 2, "the middle candidate is two rows, not one and not three")
        // The pair is the two SHORT labels — the arrangement that fits; pairing the long one with a
        // short one is a wider first row for the same number of rows.
        let widest = try #require(all.max(by: { $0.count < $1.count }))
        #expect(!paired.contains(widest))
    }

    /// Every ordinary text size reaches the two-row candidate, so the three-row fallback is the
    /// accessibility path's and nobody else's.
    ///
    /// The bound is each row against the popover's own content width. The slack at the default size
    /// is large — the paired row is well under half the strip — which is exactly why this survives a
    /// toolchain changing a glyph advance by a fraction of a point.
    @Test func theTwoRowCandidateFitsThePopoverAtEveryOrdinaryTextSize() throws {
        let source = try Self.source()
        let declaration = try #require(
            CadenceSourceScan.declarationBody("struct CadenceQuickDatePopover: View", in: source)
        )
        let stripPadding = try Self.integer(
            #"\.padding\(\.horizontal, (\d+)\)"#,
            in: try Self.popoverBody(source)
        )
        let pill = try #require(CadenceSourceScan.functionBody(named: "quickPill", in: source))
        let pillPadding = try Self.integer(#"\.padding\(\.horizontal, (\d+)\)"#, in: pill)
        let hoverPadding = try Self.integer(
            #"var padding: CGFloat = (\d+)"#,
            in: try #require(CadenceSourceScan.declarationBody("private struct PickerHoverHighlight", in: source))
        )
        let rows = try #require(
            CadenceSourceScan.declarationBody("private var quickActionRows: some View", in: declaration)
        )
        let paired = Self.pillLabels(in: try #require(CadenceSourceScan.declarationBody("HStack(spacing: 6)", in: rows)))
        let all = Self.pillLabels(in: rows)
        let trailing = all.filter { !paired.contains($0) }

        var ordinarySizes = 0
        for size in DynamicTypeSize.allCases where !CadenceTypeScale.isAccessibilitySize(size) {
            ordinarySizes += 1
            let fontSize = CadenceTypeScale.size(.controlLabel, base: 11, at: size, scaling: .enabled)
            func width(_ labels: [String]) -> CGFloat {
                Self.rowWidth(
                    labels, fontSize: fontSize,
                    pillPadding: pillPadding, hoverPadding: hoverPadding, spacing: 6
                )
            }
            let available = Self.contentWidth(at: size, horizontalPadding: stripPadding)
            let widestRow = max(width(paired), width(trailing))
            #expect(widestRow <= available, "the two-row candidate overflows at \(size)")
            // Candidates must narrow as the list goes on, or "first that fits" picks arbitrarily.
            #expect(width(all) > widestRow)
            #expect(widestRow > all.map { width([$0]) }.max() ?? 0)
        }
        #expect(ordinarySizes > 0)
    }

    private static func pillLabels(in body: String) -> [String] {
        CadenceSourceScan.captures(#"quickPill\("([^"]+)""#, in: body).map(\.text)
    }
}
