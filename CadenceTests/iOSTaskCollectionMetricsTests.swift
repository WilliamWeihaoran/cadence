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
        #expect(regular.cardPadding == compact.cardPadding)
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

    /// The whole card is drawn on a `Theme.bg` page at both widths, so it is drawn at both widths —
    /// a zero inset would be a card with its rows against its own edge.
    @Test func theGroupCardHasAnInsetAtBothWidths() {
        for isRegular in Self.widths {
            #expect(Self.metrics(isRegular).cardPadding > 0, "regular=\(isRegular)")
        }
    }

    // MARK: - What varies, and where it comes from

    /// The first thing in this scroll view is an `iOSPageHeader` drawn `padded: false`, so the page
    /// supplies the header's own gutter and top inset. They had better be the header's own numbers:
    /// a page that types 16 beside a ramp that says 20 is how a pushed All Tasks ends up starting at
    /// a different x than a pushed Goals.
    @Test func thePageGutterAndTopInsetAreTheHeadersOwn() {
        for isRegular in Self.widths {
            let page = Self.metrics(isRegular)
            let header = iOSPageHeaderMetrics.metrics(role: .page, isRegularWidth: isRegular)

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

    /// Every string the header and the empty state need, present and distinct. The empty state's
    /// *words* are not here — they are `CadenceEmptyStateCopy`'s, read in a `#if os(iOS)` extension
    /// because that enum is main-actor isolated and this one deliberately is not.
    @Test func eachCollectionNamesItselfCompletelyAndDistinctly() {
        for collection in CadenceTaskCollection.allCases {
            #expect(!collection.eyebrow.isEmpty, "\(collection)")
            #expect(!collection.title.isEmpty, "\(collection)")
            #expect(!collection.systemImage.isEmpty, "\(collection)")
            #expect(!collection.emptyIcon.isEmpty, "\(collection)")
        }

        #expect(CadenceTaskCollection.allTasks.title != CadenceTaskCollection.inbox.title)
        #expect(CadenceTaskCollection.allTasks.eyebrow != CadenceTaskCollection.inbox.eyebrow)
        #expect(CadenceTaskCollection.allTasks.systemImage != CadenceTaskCollection.inbox.systemImage)
    }
}
