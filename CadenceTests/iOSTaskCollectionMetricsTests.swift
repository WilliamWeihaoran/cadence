import CoreGraphics
import Foundation
import Testing
@testable import Cadence

/// All Tasks and Inbox were one screen rendered two ways: `ScrollView` + `LazyVStack` +
/// `iOSTaskGroupSection` at compact width, `List` + `Section` + `iOSTaskGroupHeader` +
/// `iOSTaskListRow` at regular. Two scroll containers, two separator treatments and two sets of row
/// insets — and four copies that had drifted in the group card, the empty state's height, the
/// options bar's padding and the page's own stack spacing.
///
/// It is one view now (`iOSTaskCollectionPage`). `Cadence/iOS/` sits inside `#if os(iOS)` and is
/// invisible to this macOS-built target, so what these pin is the part worth pinning and the reason
/// `iOSTaskCollectionMetrics` lives outside the platform guard: the figures, and the one behavioural
/// difference between the two collections.
///
/// **Deliberately not `@MainActor`** — both types are `nonisolated`, and every comparison below runs
/// in the nonisolated closure swift-testing expands to, so losing that marking re-emits the isolated
/// conformance error rather than passing quietly. Same reasoning as `CadenceTodaySectionMetricsTests`.
struct iOSTaskCollectionMetricsTests {
    private static let widths = [true, false]

    private static func metrics(_ isRegularWidth: Bool) -> iOSTaskCollectionMetrics {
        iOSTaskCollectionMetrics.metrics(isRegularWidth: isRegularWidth)
    }

    // MARK: - What must not vary

    /// The drift this type closes. The gap between a page header and the sort bar under it, and
    /// between one counted group and the next, is not something a wider pane needs more of — All
    /// Tasks stacked its chrome 12pt apart and Inbox 11, and neither number was chosen by anyone.
    @Test func bothWidthsStackThePageAndItsGroupsIdentically() {
        let regular = Self.metrics(true)
        let compact = Self.metrics(false)

        #expect(regular.stackSpacing == compact.stackSpacing)
        #expect(regular.groupSpacing == compact.groupSpacing)
        #expect(regular.bottomPadding == compact.bottomPadding)
        #expect(regular.emptyStateMinHeight == compact.emptyStateMinHeight)
    }

    /// Today, All Tasks and Inbox are the three segments of one tab, and a group gap that differs
    /// between them is visible the moment you flip between two of them. `CadenceTodaySectionMetrics`
    /// says the same thing from the other side; this is what stops one of the two moving alone.
    @Test func theTasksTabAgreesWithTodayOnGroupSpacing() {
        for layout in [CadenceTodayLayout.compact, .twoPane] {
            #expect(
                iOSTaskCollectionMetrics.groupSpacing
                    == CadenceTodaySectionMetrics.metrics(layout: layout).groupSpacing,
                "layout=\(layout)"
            )
        }
    }

    /// **The header's two figures are the only ones that vary, and there is no card inset at all
    /// now (T-613).** This test used to read `cardPadding > 0` at both widths, justified as "the
    /// whole card is drawn on a `Theme.bg` page at both widths" — and the card had been deleted by
    /// `85809ff` a fortnight before the assertion was written. It could not see that, because it
    /// only ever compared one field of this type against a constant.
    ///
    /// So it is replaced, and deliberately spelled with the **memberwise initialiser**: swapping
    /// the compact value's gutter and top inset into the regular one has to produce the regular one
    /// exactly. A new per-width knob does not fail this test, it fails to *compile* here — the same
    /// forcing function `CadenceTodaySectionMetricsTests.theWidthCapIsTheOnlyFigureThatVariesByLayout`
    /// took for the sibling type, after the same defect.
    @Test func theHeadersGutterAndTopInsetAreTheOnlyFiguresThatVaryByWidth() {
        let regular = Self.metrics(true)
        let compact = Self.metrics(false)

        #expect(
            iOSTaskCollectionMetrics(
                horizontalPadding: regular.horizontalPadding,
                topPadding: regular.topPadding,
                bottomPadding: compact.bottomPadding,
                stackSpacing: compact.stackSpacing,
                groupSpacing: compact.groupSpacing,
                emptyStateMinHeight: compact.emptyStateMinHeight
            ) == regular
        )
        // And they really do vary, or the assertion above is a comparison of a value with itself.
        #expect(regular.horizontalPadding != compact.horizontalPadding)
        #expect(regular.topPadding != compact.topPadding)
    }

    /// The other half of T-613, and the half a value test cannot reach: **no surface may inset its
    /// groups for a card it does not draw.**
    ///
    /// `85809ff` deleted five bare `.cadenceCard()` calls on purpose, because macOS never drew one.
    /// Three of the five insets outlived their fill: All Tasks / Inbox added 12 on top of the page
    /// gutter this type reads off `CadencePageHeaderMetrics`, so their group headers and rows sat at
    /// 28 against a page header at 16, and the list detail Tasks tab added 12 on top of its own 12
    /// for the same reason. T-587 removed the fourth, on Today.
    ///
    /// `Cadence/iOS/` is inside `#if os(iOS)` and invisible to this macOS-built target, so this
    /// reads the source text, narrowed by brace matching rather than run file-wide: each of these
    /// files pads legitimately elsewhere, and a file-wide needle would be answering a different
    /// question.
    @Test func noTaskCollectionSurfaceInsetsItsGroupsForACardItDoesNotDraw() throws {
        let page = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskCollectionPage.swift")
        )
        let groupStack = try Self.body(after: "private var groupStack: some View", in: page)
        // Non-vacuity: the matched span is the group stack, not an empty or runaway read.
        #expect(groupStack.contains("iOSTaskGroupSection("))
        #expect(groupStack.contains("spacing: metrics.groupSpacing"))
        #expect(!groupStack.contains(".padding("), "the group stack insets itself again")
        #expect(!page.contains("cardPadding"))

        // The Reminders strip is the group stack's sibling in the same `LazyVStack`, so it took the
        // same inset — and `iOSTaskCollectionMetrics` was the only thing it wanted the page's
        // metrics for. The parameter went with the padding.
        let reminders = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSInboxRemindersSection.swift")
        )
        #expect(reminders.contains("struct iOSInboxRemindersSection: View"), "non-vacuity: wrong file")
        #expect(!reminders.contains("iOSTaskCollectionMetrics"))
        #expect(page.contains("iOSInboxRemindersSection(remindersManager: remindersManager)"))

        // The list detail Tasks tab: one horizontal inset, and it is the one the options bar
        // directly above the rows already uses.
        let detail = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSListDetailView.swift")
        )
        let sectionStack = try Self.body(after: "private var sectionStack: some View", in: detail)
        #expect(sectionStack.contains("iOSTaskGroupSection("))
        #expect(!sectionStack.contains("cardPadding"))
        #expect(sectionStack.contains(".padding(.horizontal, iOSListDetailTaskMetrics.horizontalPadding)"))
        #expect(
            CadenceSourceScan.matchCount(#"\.padding\("#, in: sectionStack) == 2,
            "the section stack takes an inset besides its gutter and its end-of-content pad"
        )
        #expect(!detail.contains("static let cardPadding"))
        #expect(detail.contains("static let horizontalPadding: CGFloat = 16"))
        #expect(
            detail.contains(".padding(.horizontal, 16)"),
            "non-vacuity: the options bar above the rows no longer sits at 16"
        )
    }

    /// Brace-matched declaration body, so a needle counted over a whole file cannot stand in for
    /// one counted over the declaration that has to hold it.
    private static func body(after declaration: String, in source: String) throws -> String {
        let range = try #require(source.range(of: declaration), "declaration not found: \(declaration)")
        return try #require(
            CadenceSourceScan.matchedBody(after: range.upperBound, in: source, open: "{", close: "}")
        )
    }

    // MARK: - What varies, and where it comes from

    /// The first thing in this scroll view is an `iOSPageHeader` drawn `padded: false`, so the page
    /// supplies the header's own gutter and top inset. They had better be the header's own numbers:
    /// a page that types 16 beside a ramp that says 20 is how a pushed All Tasks ends up starting at
    /// a different x than a pushed Goals.
    @Test func thePageGutterAndTopInsetAreTheHeadersOwn() {
        for isRegular in Self.widths {
            let page = Self.metrics(isRegular)
            let header = CadencePageHeaderMetrics.metrics(role: .page, isRegularWidth: isRegular)

            #expect(page.horizontalPadding == header.horizontalPadding, "regular=\(isRegular)")
            #expect(page.topPadding == header.topPadding, "regular=\(isRegular)")
        }
    }

    // MARK: - What tells the two collections apart

    @Test func thereAreExactlyTwoFlatTaskCollections() {
        #expect(CadenceTaskCollection.allCases.count == 2)
    }

    /// Both pages head their live rows "Active", and the two headings mean different things. On
    /// Inbox every row under it is in the Inbox by construction, so the header is a placement a
    /// dropped `+` can inherit; on All Tasks the rows span every list, so it is completion status
    /// and there is nothing to inherit. This is the only difference between the two pages that is
    /// not a word, and flattening it would light a header up that then seeds nothing.
    @Test func onlyInboxsActiveHeadingIsAPlacement() {
        #expect(
            CadenceTaskDropSupport.dropKey(forGroup: CadenceTaskCollection.inbox.activeGroupIdentity)
                == "list:inbox"
        )
        #expect(
            CadenceTaskDropSupport.dropKey(forGroup: CadenceTaskCollection.allTasks.activeGroupIdentity)
                == nil
        )
    }

    /// The consequence of the above, and the reason the shared section can drop the hand-spelled
    /// `if !tasks.isEmpty` the two `List` hosts each wrote differently: a group you can still add to
    /// does not vanish when it empties, and a group you cannot does.
    @Test func inboxsActiveHeadingSurvivesEmptyingAndAllTasksDoesNot() {
        #expect(CadenceTaskDropSupport.showsWhenEmpty(CadenceTaskCollection.inbox.activeGroupIdentity))
        #expect(!CadenceTaskDropSupport.showsWhenEmpty(CadenceTaskCollection.allTasks.activeGroupIdentity))
    }

    /// Each collection is one `CadenceTaskSurface`, which is where "does a row name its list" and
    /// "which chrome controls does this offer" are answered — once, for both widths. The Inbox page
    /// is the surface where naming the list on every row names the page you are standing on.
    @Test func eachCollectionIsOneSurfaceAndTheSurfaceDecidesTheContainerChip() {
        #expect(CadenceTaskCollection.allTasks.surface == .allTasks)
        #expect(CadenceTaskCollection.inbox.surface == .inbox)

        #expect(CadenceTaskSurfaceOptions.showsContainerChip(on: CadenceTaskCollection.allTasks.surface))
        #expect(!CadenceTaskSurfaceOptions.showsContainerChip(on: CadenceTaskCollection.inbox.surface))
    }

    /// Both offer the sort chip and the completed toggle. The two `List` panels drew the bar
    /// unconditionally while the two compact views gated it here — a one-sided gate is how a surface
    /// ends up reading a `showCompleted` that nothing on screen can write.
    @Test func bothCollectionsOfferTheSameChromeControls() {
        for collection in CadenceTaskCollection.allCases {
            let options = CadenceTaskSurfaceOptions.options(for: collection.surface)
            #expect(options.showsSort, "\(collection)")
            #expect(options.showsCompletedToggle, "\(collection)")
        }
    }

    /// Every string the header and the empty state need, present and distinct — the empty state's
    /// *words* included. They spent a while in a private `#if os(iOS)` extension, because
    /// `CadenceEmptyStateCopy` had been missed by the `nonisolated` pass and could not be read from
    /// this deliberately-`nonisolated` file; that enum is `nonisolated` now, so the words sit on the
    /// collection with the rest of what tells the two pages apart, and the test target can see them.
    @Test func eachCollectionNamesItselfCompletelyAndDistinctly() {
        for collection in CadenceTaskCollection.allCases {
            #expect(!collection.eyebrow.isEmpty, "\(collection)")
            #expect(!collection.title.isEmpty, "\(collection)")
            #expect(!collection.systemImage.isEmpty, "\(collection)")
            #expect(!collection.emptyIcon.isEmpty, "\(collection)")
            #expect(!collection.emptyTitle.isEmpty, "\(collection)")
            #expect(!collection.emptySubtitle.isEmpty, "\(collection)")
        }

        #expect(CadenceTaskCollection.allTasks.title != CadenceTaskCollection.inbox.title)
        #expect(CadenceTaskCollection.allTasks.eyebrow != CadenceTaskCollection.inbox.eyebrow)
        #expect(CadenceTaskCollection.allTasks.systemImage != CadenceTaskCollection.inbox.systemImage)
        #expect(CadenceTaskCollection.allTasks.emptyTitle != CadenceTaskCollection.inbox.emptyTitle)
        #expect(
            CadenceTaskCollection.allTasks.emptySubtitle != CadenceTaskCollection.inbox.emptySubtitle
        )
    }

    /// The collection reads the shared constants rather than restating them, which is the whole
    /// point of `CadenceEmptyStateCopy` — All Tasks and Inbox each used to spell their own.
    @Test func theEmptyStateWordsAreTheSharedConstantsAndNotACopyOfThem() {
        #expect(CadenceTaskCollection.allTasks.emptyTitle == CadenceEmptyStateCopy.allTasksTitle)
        #expect(CadenceTaskCollection.allTasks.emptySubtitle == CadenceEmptyStateCopy.allTasksSubtitle)
        #expect(CadenceTaskCollection.inbox.emptyTitle == CadenceEmptyStateCopy.inboxTitle)
        #expect(CadenceTaskCollection.inbox.emptySubtitle == CadenceEmptyStateCopy.inboxSubtitle)
    }
}
