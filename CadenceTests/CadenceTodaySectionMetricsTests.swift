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

    /// **The width cap is the only thing that varies now (T-587).** These two tests used to pin a
    /// `drawsCard` flag and a `cardPadding` beside it — and they pinned them *to each other*, so
    /// the pair stayed green after `85809ff` deleted the `.cadenceCard()` they described. What was
    /// left was an inset with no fill behind it, which is exactly the "12pt indent that reads as a
    /// broken gutter" the second of the two tests was written to forbid: it could not see it,
    /// because it only ever compared one field of this type against another.
    ///
    /// So this replaces both, and it is deliberately spelled with the **memberwise initialiser**.
    /// A new stored property does not fail this test — it fails to *compile* here, which is the
    /// point: the next per-layout knob has to be argued for in this file rather than added quietly
    /// and then guarded by a tautology.
    ///
    /// **T-596 added three fields and this is where they had to be argued for.** The two hosts were
    /// still typing their own scroll gutters — 14 / top 12 / bottom 20 in the two-pane column
    /// against 14 / top 10 / bottom 16 on the phone — *after* the cap was hoisted here so they
    /// could not drift apart again. They are stored properties now, and every one of them is taken
    /// from `compact` below: the assertion is that swapping the phone's three gutters into the
    /// two-pane value changes nothing, i.e. that the cap is still the only thing that varies.
    @Test func theWidthCapIsTheOnlyFigureThatVariesByLayout() {
        let compact = Self.metrics(.compact)
        let twoPane = Self.metrics(.twoPane)

        #expect(
            CadenceTodaySectionMetrics(
                groupSpacing: compact.groupSpacing,
                contentMaxWidth: twoPane.contentMaxWidth,
                horizontalPadding: compact.horizontalPadding,
                topPadding: compact.topPadding,
                bottomPadding: compact.bottomPadding
            ) == twoPane
        )
    }

    // MARK: - The hosts' own gutters (T-596)

    /// The three figures the hosts were still typing out, and what each of them settled on.
    ///
    /// The gutter was the one they had **not** drifted on, so it moves unchanged. The top inset had
    /// no reason on either side, and 12 is the tie-break the ticket calls for rather than a third
    /// number: nine sites across `Cadence/iOS/` spell `.padding(.top, 12)` against five for `10`.
    /// The end-of-content inset is the one decided on evidence — see below.
    @Test func todaysTwoHostsShareOneSetOfGutters() {
        for layout in Self.layouts {
            let metrics = Self.metrics(layout)
            #expect(metrics.horizontalPadding == 14, "\(layout)")
            #expect(metrics.topPadding == 12, "\(layout)")
            #expect(metrics.bottomPadding == 16, "\(layout)")
        }
    }

    /// **16 wins on evidence, not on counting.** It is the value with the rationale written beside
    /// it — breathing room at the end of the content, *not* clearance for the tab bar, which is a
    /// `VStack` sibling of the content rather than an overlay — and it is the same number the
    /// sibling segments of this tab already give All Tasks and Inbox, under that same sentence, at
    /// **both** widths. So the app had already decided this figure does not ramp, and the two-pane
    /// column's 20 was the outlier rather than the wide end of a ramp.
    @Test func theEndOfContentInsetIsTheOneTheOtherTabSegmentsUse() {
        for isRegular in [true, false] {
            #expect(
                Self.metrics(.compact).bottomPadding
                    == iOSTaskCollectionMetrics.metrics(isRegularWidth: isRegular).bottomPadding,
                "against All Tasks / Inbox at isRegular=\(isRegular)"
            )
        }
    }

    /// And the hosts read them. `Cadence/iOS/` is invisible to this macOS-built target, so this is
    /// the source text — the same half of the pin `theGroupStackTakesNoInsetOfItsOwn` above exists
    /// for, and for the same reason: every value assertion in this file stayed green while the two
    /// hosts drifted, because none of them could see a call site.
    @Test func neitherTodayHostTypesAGutterOfItsOwn() throws {
        for (path, layout) in [
            ("Cadence/iOS/iOSTodayView.swift", ".twoPane"),
            ("Cadence/iOS/iOSTodayCompactViews.swift", ".compact")
        ] {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))

            // Non-vacuity: the right file, past the comment stripper, still holding the cap read
            // that the gutters now sit beside.
            #expect(
                source.contains("iOSTodayTaskSections.contentMaxWidth(layout: \(layout))"),
                "non-vacuity: \(path)"
            )
            #expect(
                CadenceSourceScan.matchCount(
                    "iOSTodayTaskSections\\.contentPadding\\(layout: \\\(layout)\\)",
                    in: source
                ) == 1,
                "\(path) does not take its scroll insets from the metrics"
            )
            #expect(!source.contains(".padding(.horizontal, 14)"), "\(path) still types the gutter")
            #expect(!source.contains(".padding(.top, 10)"))
            #expect(!source.contains(".padding(.top, 12)"))
            #expect(!source.contains(".padding(.bottom, 16)"))
            #expect(!source.contains(".padding(.bottom, 20)"))
        }
    }

    /// The other half of T-587, and the half a value test cannot reach: **the view must not inset
    /// the group stack either.**
    ///
    /// The removed pair failed in exactly this gap. `85809ff` deleted the `.cadenceCard()` the
    /// `drawsCard` flag described, and `.padding(metrics.cardPadding)` stayed behind it — a 12pt
    /// inset with no fill, on top of the 14pt gutter both hosts already apply, so the phone's
    /// group headers sat inside the page header and options bar directly above them. Every
    /// assertion in this file stayed green through all of it, because none of them could see the
    /// call site.
    ///
    /// `Cadence/iOS/` is inside `#if os(iOS)` and invisible to this macOS-built target, so this
    /// reads the source text. Comments are blanked first, and the read is narrowed to `groupStack`
    /// by brace matching rather than run over the whole file — `iOSTodayOverdueListSheet` and the
    /// empty-state branch further down both pad legitimately, and a file-wide needle would be
    /// answering a different question.
    @Test func theGroupStackTakesNoInsetOfItsOwn() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTodayTaskSections.swift")
        )
        let declaration = try #require(source.range(of: "private var groupStack: some View"))
        let body = try #require(
            CadenceSourceScan.matchedBody(
                after: declaration.upperBound,
                in: source,
                open: "{",
                close: "}"
            )
        )

        // Non-vacuity: the matched span is the group stack and not an empty or runaway read.
        #expect(body.contains("iOSTaskGroupSection("))
        #expect(body.contains("spacing: metrics.groupSpacing"))

        #expect(!body.contains(".padding("))
        #expect(!body.contains("cardPadding"))
        #expect(!body.contains("drawsCard"))
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
    @Test func everyMeasurementIsPositiveInTodaySectionMetrics() {
        for layout in Self.layouts {
            let metrics = Self.metrics(layout)
            #expect(metrics.groupSpacing > 0, "\(layout)")
            #expect(metrics.contentMaxWidth > 0, "\(layout)")
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
