import Foundation
import Testing
@testable import Cadence

/// [[T-7086]]: a page header draws no count capsule for zero, on both platforms.
///
/// macOS's `DesktopPageHeader` hid a zero badge inline; `iOSPageHeader` drew any non-nil count, so
/// an empty Today, Inbox or Focus picker on iPhone read "Today 0" beside the Mac's bare "Today".
/// Both headers ask `CadencePageHeaderMetrics.drawsCountBadge(_:)` now.
struct CadencePageHeaderZeroCountTests {
    @Test func aZeroOrMissingCountDrawsNoBadgeAndAnyPositiveCountDoes() {
        #expect(!CadencePageHeaderMetrics.drawsCountBadge(nil))
        #expect(!CadencePageHeaderMetrics.drawsCountBadge(0))
        #expect(CadencePageHeaderMetrics.drawsCountBadge(1))
        #expect(CadencePageHeaderMetrics.drawsCountBadge(42))
    }

    /// `Cadence/iOS/` is invisible to this macOS-built target, so the iPhone header is read as
    /// source: both of its badge sites (the single row and the stacked accessibility-size row)
    /// must ask the shared predicate, and neither may fall back to a bare `if let count {`.
    @Test func bothPlatformsHeadersAskTheSharedPredicate() throws {
        let iOSSource = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSFeatureComponents.swift")
        let mobile = try #require(CadenceSourceScan.declarationBody("struct iOSPageHeader<", in: iOSSource))
        #expect(mobile.contains("iOSPageHeaderCountBadge"), "non-vacuity: the slice holds the badge")
        #expect(CadenceSourceScan.matchCount(#"CadencePageHeaderMetrics\.drawsCountBadge\(count\)"#, in: mobile) == 2)
        #expect(CadenceSourceScan.matchCount(#"if let count \{"#, in: mobile) == 0, "an iOS badge site draws a zero again")

        let macSource = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/macOSRootSupportViews.swift")
        let desktop = try #require(CadenceSourceScan.declarationBody("struct DesktopPageHeader", in: macSource))
        #expect(desktop.contains("countBadge("), "non-vacuity: the slice holds the badge")
        #expect(CadenceSourceScan.matchCount(#"CadencePageHeaderMetrics\.drawsCountBadge\(count\)"#, in: desktop) == 1)
    }
}

/// [[T-7087]]: the iPhone Focus session header wraps its chips rather than truncating them.
///
/// Four one-line chips in an `HStack` overflowed the ~329pt a 393pt iPhone leaves the row, and
/// each chip truncated its own words. Read as source for the same reason as above.
struct CadenceIOSFocusSessionHeaderWrapTests {
    @Test func theSessionHeaderChipsSitInAWrappingStack() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSFocusView.swift")
        let header = try #require(CadenceSourceScan.declarationBody("private func sessionHeader<", in: source))
        #expect(header.contains("chips()"), "non-vacuity: the slice holds the chip row")
        #expect(header.contains("CadenceWrappingHStack("), "the session header's chips no longer wrap")
        #expect(!header.contains("HStack(spacing: 8) {"), "the chips are back in a one-line HStack")
    }
}

/// [[T-7088]]: the iOS sort chip says it sorts.
///
/// It drew only the mode, so VoiceOver announced "Priority, button" on Today, Inbox and All Tasks.
/// It is labelled "Sort" with the mode as its value now — macOS's `CadenceEnumPickerBadge` reads
/// "Sort, Priority".
struct CadenceIOSSortChipAccessibilityTests {
    @Test func theSortChipIsLabelledSortWithTheModeAsItsValue() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskViews.swift")
        let bar = try #require(CadenceSourceScan.declarationBody("struct iOSTaskViewOptionsBar: View", in: source))
        #expect(bar.contains("showSortPicker = true"), "non-vacuity: the slice holds the sort button")
        #expect(bar.contains(".accessibilityLabel(\"Sort\")"))
        #expect(bar.contains(".accessibilityValue(sortMode.title)"))
    }
}
