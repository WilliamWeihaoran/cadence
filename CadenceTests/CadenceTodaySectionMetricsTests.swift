import CoreGraphics
import Foundation
import Testing
@testable import Cadence

/// Today's list of task groups was drawn twice — once by the phone's `iOSCompactTodayView` and once
/// by the two-pane task column — and the two copies had drifted: groups stacked 14pt apart on one
/// and 15pt on the other, the same empty state padded 14 on one and 18 on the other. It is one view
/// now, and `CadenceTodaySectionMetrics` is the only thing left that varies between its two hosts.
///
/// `Cadence/iOS/` sits inside `#if os(iOS)` and is invisible to this macOS-built target, so what
/// these pin is the part worth pinning: the numbers themselves, which is why they live outside the
/// platform guard.
///
/// **Deliberately not `@MainActor`.** The type is `nonisolated`, and every `==` below runs in the
/// nonisolated closure swift-testing expands to — so losing that marking re-emits the isolated
/// conformance error rather than passing quietly. Same reasoning as `NonisolatedValueTypeTests`.
struct CadenceTodaySectionMetricsTests {
    private static let layouts: [CadenceTodayLayout] = [.compact, .twoPane]

    private static func metrics(_ layout: CadenceTodayLayout) -> CadenceTodaySectionMetrics {
        CadenceTodaySectionMetrics.metrics(layout: layout)
    }

    // MARK: - What must not vary

    /// The drift this type was written to close. A gap between "Overdue" and "Planned Today" is not
    /// something a wider pane needs more of, and nobody chose 14-against-15 — it is what two copies
    /// of one list become after a few edits each.
    @Test func bothLayoutsStackTheirGroupsAtTheSameSpacing() {
        #expect(Self.metrics(.compact).groupSpacing == Self.metrics(.twoPane).groupSpacing)
    }

    /// The same figure Inbox and All Tasks stack their groups at, so the three segments of one tab
    /// bar agree about what a gap between groups is.
    @Test func theGroupSpacingIsTheSpacingTheOtherTaskSurfacesUse() {
        #expect(Self.metrics(.compact).groupSpacing == 14)
    }

    // MARK: - What varies, and why

    /// The card is a fact about the **host's background**, not about the device: the compact layout
    /// is drawn on a `Theme.bg` page, where a card separates the day's list from the page, and the
    /// two-pane task column already *is* `Theme.surface`, where the same card would be invisible.
    /// That is also why the shared empty state had to settle on `Theme.surfaceElevated`.
    @Test func onlyTheLayoutDrawnOnThePageBackgroundGetsACard() {
        #expect(Self.metrics(.compact).drawsCard)
        #expect(!Self.metrics(.twoPane).drawsCard)
    }

    /// A call site must not be able to pad for a card it is not drawing — an inset with no fill
    /// behind it is a 12pt indent that reads as a broken gutter.
    @Test func cardPaddingExistsExactlyWhereTheCardDoes() {
        for layout in Self.layouts {
            let metrics = Self.metrics(layout)
            #expect(metrics.drawsCard == (metrics.cardPadding > 0), "\(layout)")
        }
    }

    /// The one measurement that legitimately differs, and it has to differ in the right direction or
    /// the parameter is not earning its place: a two-pane task column starts at `taskPaneMinWidth`
    /// and grows from there, so it can hold a wider readable column than a phone.
    @Test func theTwoPaneColumnIsAllowedToBeWiderThanTheCompactOne() {
        #expect(Self.metrics(.twoPane).contentMaxWidth > Self.metrics(.compact).contentMaxWidth)
    }

    /// A cap narrower than the screen it is drawn on letterboxes the list — the rows would sit in a
    /// column with dead space either side on the phone's own Today. 440pt is the widest phone the
    /// app targets, and the compact cap has to clear it. (It does not bind on a phone at all; it
    /// binds in the iPad's narrow single-column fallback, which is the other host of this layout.)
    @Test func theCompactCapNeverNarrowsThePhoneItIsDrawnOn() {
        #expect(Self.metrics(.compact).contentMaxWidth >= 440)
    }

    /// A zero anywhere in here draws as a collapsed list rather than as an error, which is the
    /// failure mode a metrics table invites.
    @Test func everyMeasurementIsPositive() {
        for layout in Self.layouts {
            let metrics = Self.metrics(layout)
            #expect(metrics.groupSpacing > 0, "\(layout)")
            #expect(metrics.contentMaxWidth > 0, "\(layout)")
            #expect(metrics.cardPadding >= 0, "\(layout)")
        }
    }

    /// One layout, one answer. The table is keyed on `CadenceTodayLayout` and reads nothing else, so
    /// the iPad's own narrow single-column fallback is drawn exactly like the phone's Today —
    /// because it *is* the phone's Today, on the same `Theme.bg` page.
    @Test func theSameLayoutAlwaysProducesTheSameMetrics() {
        for layout in Self.layouts {
            #expect(Self.metrics(layout) == Self.metrics(layout), "\(layout)")
        }
        #expect(Self.metrics(.compact) != Self.metrics(.twoPane))
    }
}
