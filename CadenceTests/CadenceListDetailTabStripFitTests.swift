// T-3244: compiled for macOS only. This suite measures label widths through AppKit, and
// `CadenceTests` also builds for an iOS destination, where that import does not resolve.
#if os(macOS)
import AppKit
import Foundation
import Testing
@testable import Cadence

/// T-6985: the iOS list-detail tab strip (`Tasks / Kanban / Notes / Links / Completed`) ran
/// "Completed" off the right edge of a 393 pt iPhone once the counts beside Tasks, Kanban and
/// Completed showed, inside a horizontal scroll view whose indicator is hidden.
///
/// **The widths are measured, not pinned.** Each label is laid out in the system font at the role's
/// base sizes (13 pt semibold label, 11 pt semibold monospaced count) and summed through
/// `ListDetailTabStripMetrics.stripWidth`, the same sum `ViewThatFits` makes of the real views. The
/// assertions are relations against the iPhone's room — the loosest tier overruns it, the tightest
/// does not — so a font revision that moves a glyph by a point does not redden them.
///
/// `Cadence/iOS/` is invisible to this macOS-hosted target, so the view's half is a source scan of
/// `iOSListDetailPagePicker`: it chooses among the tiers rather than always scrolling, and its
/// scrolling fallback shows that it scrolls.
struct CadenceListDetailTabStripFitTests {

    /// The owner's iPhone 15 is 393 pt wide; `iOSListDetailView` insets the strip 12 pt either side
    /// at compact width.
    private static let iPhoneStripRoom: CGFloat = 393 - 12 * 2

    private static let countedTabs: Set<ListDetailPage> = [.tasks, .kanban, .completed]

    private static func width(_ text: String, size: CGFloat, monospacedDigits: Bool = false) -> CGFloat {
        let font = monospacedDigits
            ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
            : NSFont.systemFont(ofSize: size, weight: .semibold)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Each tab's content width: its label, and where `count` is non-nil on a counted tab, the
    /// label-count spacing and the count.
    private static func contentWidths(count: (ListDetailPage) -> String?) -> [CGFloat] {
        ListDetailPage.allCases.map { page in
            var width = width(page.rawValue, size: 13)
            if countedTabs.contains(page), let count = count(page) {
                width += ListDetailTabStripMetrics.labelCountSpacing + self.width(count, size: 11, monospacedDigits: true)
            }
            return width
        }
    }

    private static let tiers = ListDetailTabStripMetrics.horizontalPaddingTiers

    @Test func theTiersRunLoosestToTightestAndKeepATouchTarget() throws {
        #expect(Self.tiers.count >= 2)
        #expect(Self.tiers == Self.tiers.sorted(by: >))
        #expect(Set(Self.tiers).count == Self.tiers.count)
        #expect(ListDetailTabStripMetrics.minimumTabWidth >= 44)
        // The floor is what `stripWidth` charges a tab, whatever its label measures.
        #expect(ListDetailTabStripMetrics.stripWidth(contentWidths: [0], horizontalPadding: 0)
            == ListDetailTabStripMetrics.minimumTabWidth + ListDetailTabStripMetrics.stripInset * 2)
    }

    /// The defect, and the fix, on one phone: with two-digit counts the original 12 pt padding
    /// cannot hold the five tabs, and the tightest tier can.
    @Test func twoDigitCountsOverranTheIPhoneAtTheOldPaddingAndFitAtTheTightestTier() throws {
        let widths = Self.contentWidths(count: { _ in "24" })
        let loosest = try #require(Self.tiers.first)
        let tightest = try #require(Self.tiers.last)

        #expect(loosest == 12, "the loosest tier is the strip's original padding; nothing gets looser")
        #expect(ListDetailTabStripMetrics.stripWidth(contentWidths: widths, horizontalPadding: loosest) > Self.iPhoneStripRoom)
        #expect(ListDetailTabStripMetrics.stripWidth(contentWidths: widths, horizontalPadding: tightest) <= Self.iPhoneStripRoom)
    }

    /// An empty list draws no counts, and keeps the original padding.
    @Test func withoutCountsTheStripKeepsItsOriginalPadding() throws {
        let widths = Self.contentWidths(count: { _ in nil })
        let loosest = try #require(Self.tiers.first)
        #expect(ListDetailTabStripMetrics.stripWidth(contentWidths: widths, horizontalPadding: loosest) <= Self.iPhoneStripRoom)
    }

    /// The view takes the first tier that fits and scrolls only past the last; the scrolling
    /// fallback fades the edge that has tabs behind it and brings the selected tab into view.
    @Test func thePickerChoosesATierBeforeItScrollsAndItsScrollingSaysSo() throws {
        let source = try CadenceSourceScan.strippedSourceReader()("Cadence/iOS/iOSListSupportViews.swift")
        let picker = try #require(CadenceSourceScan.declarationBody("struct iOSListDetailPagePicker: View", in: source))
        #expect(picker.count > 1_000, "the declaration slice is suspiciously short")

        let compact = picker.filter { !$0.isWhitespace }
        // Every tier, then the scroll view — in that order, so scrolling is the last resort.
        #expect(compact.contains(#"ViewThatFits(in:.horizontal){ForEach(ListDetailTabStripMetrics.horizontalPaddingTiers,id:\.self){paddingintabRow(horizontalPadding:padding)}scrollingStrip}"#))
        #expect(compact.contains("tabRow(horizontalPadding:ListDetailTabStripMetrics.horizontalPaddingTiers.last"))
        #expect(compact.contains(".padding(.horizontal,horizontalPadding)"))
        #expect(compact.contains(".frame(minWidth:ListDetailTabStripMetrics.minimumTabWidth)"))

        #expect(picker.contains("ScrollViewReader"))
        #expect(picker.contains("proxy.scrollTo(page"))
        #expect(picker.contains("proxy.scrollTo(newPage"))
        #expect(picker.contains(".onScrollGeometryChange("))
        #expect(compact.contains("overflow.trailing?.clear:.black"))
        #expect(compact.contains("overflow.leading?.clear:.black"))
    }
}

#endif
