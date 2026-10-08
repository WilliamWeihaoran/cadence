#if os(iOS)
import SwiftData
import SwiftUI

struct iOSCompactTodayView: View {
    var showsHeader = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let completedTodayTasks: [AppTask]
    let todayTaskGroups: [CadenceTodayTaskGroup]
    /// Today's rollover banner, or `nil` when there is nothing to roll. Forwarded straight to
    /// `iOSTodayTaskSections`, which is where both widths draw it — this host does not decide
    /// anything about it.
    var rolloverNotice: iOSTodayRolloverNotice?
    /// The day's counts, as the two-pane column reads them. It used to take a `todayTasks` array
    /// purely to call `.count` on it for the header badge, which is the same number
    /// `CadenceTodaySummary.activeCount` already holds — and the rest of the summary was simply not
    /// drawn here, so the tablet said "· 3 timed · 1 done" beside its date and the phone said
    /// nothing beside the same date.
    let summary: CadenceTodaySummary
    @Binding var sortMode: CadenceTaskSortMode
    @Binding var showCompleted: Bool
    #if DEBUG
    let sampleDataStatus: String?
    let seedSampleData: () -> Void
    #endif

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if showsHeader {
                    header
                }
                optionsBar
                // Tasks and nothing else. The day's note card and the schedule preview used to sit
                // under this list; both are one tab away and better there — the Notes tab opens the
                // same daily note, and Calendar shows the same schedule at full height. Today's job
                // in the Tasks tab is the day's tasks.
                taskSections
            }
            // One cap for the header, the bar and the rows together. It is the layout's number,
            // read from `CadenceTodaySectionMetrics` rather than typed here, so the two hosts
            // cannot drift apart again the way 520-against-720 was only half a decision.
            .frame(maxWidth: iOSTodayTaskSections.contentMaxWidth(layout: .compact), alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
            // The gutter, the top inset and the end-of-content inset, from the same place the cap
            // above comes from. The bottom of the three keeps its reasoning on the constant:
            // breathing room at the end of the content, *not* bar clearance — the tab bar is a
            // `VStack` sibling of the tab content in `iOSCompactRootShell`, so this scroll view is
            // handed a height that already stops where the bar starts. It used to be 132, hand-cut
            // clearance for a floating `+`.
            .padding(iOSTodayTaskSections.contentPadding(layout: .compact))
        }
        .scrollIndicators(.hidden)
        // The same region the iPad column registers, on the scroll view for the same reason. See
        // `iOSTodayTaskRegionDropTarget`.
        .iOSTodayTaskRegionDropTarget()
        .background(Theme.bg.ignoresSafeArea())
    }

    /// Drawn only when this is a *pushed* screen, where it is the page's only title and — with the
    /// navigation bar hidden on iPhone — the only row the back control has to live on. Inside the
    /// Tasks tab the tab's header does both jobs; see `showsHeader`.
    ///
    /// `onBack` is passed **only** on compact width. This view is now also the iPad's Today at pane
    /// widths below the two-pane floor, where `iPadMacStyleRootShell` hosts it with no
    /// `NavigationStack` around it — so `dismiss()` has nothing to dismiss and the chevron would be
    /// a control that looks wired and does nothing, which is the defect this whole sweep has been
    /// removing. The header draws no button when `onBack` is nil.
    ///
    /// **It no longer carries `eyebrowDetail`, and that is where the phone and the tablet now
    /// differ.** It used to pass `summary.line` — "1 timed · 2 done" — on the grounds that the
    /// summary is a fact about the day rather than about how much room the screen has, and that the
    /// phone had simply never been given it. The owner has asked for that line off the iPhone:
    /// *"also remove the line '1 timed · 2 done'"*. The two-pane column's `iPadTodayTaskHeader`
    /// keeps it, which is the split this doc comment has always described — one header per layout,
    /// not per size class — so nothing about the tablet's Today moves.
    ///
    /// `summary` is still read, twice: the header's count badge is `activeCount`, and the options
    /// bar below reads `completedCount`. What is gone is the sentence beside the date, not the day's
    /// arithmetic.
    private var header: some View {
        iOSCompactPageHeader(
            eyebrow: DateFormatters.longDate.string(from: Date()),
            title: "Today",
            color: Theme.amber,
            count: summary.activeCount,
            onBack: horizontalSizeClass == .compact ? { dismiss() } : nil
        )
        .padding(.top, 2)
        .padding(.bottom, 1)
    }

    /// The same shared bar Inbox and All Tasks draw, and the same one iPad Today carries on its
    /// header row. Today had neither control on the phone — while still reading `showCompleted`,
    /// which nothing could then write — so completed work was unreachable here by construction.
    /// See `CadenceTaskSurfaceOptions`, where "which controls a surface offers" is stated once
    /// with no size class in sight.
    @ViewBuilder
    private var optionsBar: some View {
        let options = CadenceTaskSurfaceOptions.options(for: .today)
        if options.showsSort || options.showsCompletedToggle {
            iOSTaskViewOptionsBar(
                sortMode: $sortMode,
                showCompleted: $showCompleted,
                completedCount: summary.completedCount
            )
            .padding(.vertical, 2)
        }
    }

    /// `iOSTodayTaskSections`, which is also what the two-pane task column draws. This used to be a
    /// second copy of it, 1pt apart on the group spacing and with its own answer to whether a row
    /// names its list.
    private var taskSections: some View {
        #if DEBUG
        iOSTodayTaskSections(
            layout: .compact,
            taskGroups: todayTaskGroups,
            completedTasks: completedTodayTasks,
            showsCompleted: $showCompleted,
            rolloverNotice: rolloverNotice,
            sampleDataStatus: sampleDataStatus,
            seedSampleData: seedSampleData
        )
        #else
        iOSTodayTaskSections(
            layout: .compact,
            taskGroups: todayTaskGroups,
            completedTasks: completedTodayTasks,
            showsCompleted: $showCompleted,
            rolloverNotice: rolloverNotice
        )
        #endif
    }

}

/// The one Today empty state, on both widths.
///
/// iPad used to run its own: a card, then a row of three tinted "Write notes" / "Check timeline" /
/// "Completed" tiles, then two more "Capture" / "Plan" hint cards — five instructional cards
/// standing in for content, one of which ("Plan — Use the inspector to switch notes and timeline")
/// described the page it was drawn on. That is the mistake the deleted `iOSCompactHomeView` grid
/// made. An empty day looks empty and says so once, in `Theme.dim`.
///
/// **It draws no card.** It used to: the two callers each wrapped it in one of their own and
/// disagreed about the fill, so the component was pulled inward to draw one `Theme.surfaceElevated`
/// card for both hosts. The user has since had the cards taken off task groups everywhere, and an
/// empty state boxed on a page whose populated state is not boxed reads as a different kind of
/// thing rather than the same list with nothing in it. So it is bare text on the page now, on both
/// hosts. The fill reasoning is kept here only because it explains why a `Theme.surface` card would
/// have been invisible on iPad if anyone reaches for one again.
struct iOSCompactTodayEmptyState: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling
    var body: some View {
        emptyRow
    }

    private var emptyRow: some View {
        let wraps = iOSTaskPageTypographyMetrics.stacksControls(at: dynamicTypeSize, scaling: scaling)
        let side = iOSTaskPageTypographyMetrics.glyphFrame(42, glyph: 20, at: dynamicTypeSize, scaling: scaling)
        let layout = wraps ? AnyLayout(VStackLayout(alignment: .leading, spacing: 13)) : AnyLayout(HStackLayout(spacing: 13))
        return layout {
            Image(systemName: "checkmark.circle")
                .cadenceFont(.controlLabel, base: 20)
                .foregroundStyle(Theme.dim)
                .frame(width: side, height: side)
                .background(Theme.surfaceElevated.opacity(0.54))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                        .strokeBorder(Theme.borderSubtle.opacity(0.42), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(CadenceTodayPresentationSupport.emptyTitle)
                    .cadenceFont(.bodyText, weight: .semibold)
                    .foregroundStyle(Theme.text)
                    .lineLimit(wraps ? nil : 1)
                    .fixedSize(horizontal: false, vertical: wraps)

                Text(CadenceTodayPresentationSupport.emptySubtitle)
                    .cadenceFont(.metadata)
                    .foregroundStyle(Theme.dim)
                    .lineLimit(wraps ? nil : 2)
                    .fixedSize(horizontal: false, vertical: wraps)
            }

            if !wraps { Spacer(minLength: 0) }
        }
        .padding(14)
    }
}

/// Debug-only, on both widths — the seeding affordance cannot ship. iPad had its own "Samples"
/// button welded into its empty-state card; it is this card now.
#if DEBUG
struct iOSCompactSampleDataCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling
    let status: String?
    let action: () -> Void

    var body: some View {
        let wraps = iOSTaskPageTypographyMetrics.stacksControls(at: dynamicTypeSize, scaling: scaling)
        let side = iOSTaskPageTypographyMetrics.glyphFrame(34, glyph: 14, at: dynamicTypeSize, scaling: scaling)
        let layout = wraps ? AnyLayout(VStackLayout(alignment: .leading, spacing: 11)) : AnyLayout(HStackLayout(spacing: 11))
        layout {
            iOSIconTile(systemImage: "wand.and.stars", color: Theme.amber, bordered: false)

            VStack(alignment: .leading, spacing: 3) {
                Text(status ?? "Need realistic rows?")
                    .cadenceFont(.controlLabel)
                    .foregroundStyle(Theme.text)
                    .lineLimit(wraps ? nil : 2)
                    .fixedSize(horizontal: false, vertical: wraps)

                Text("Seed local simulator tasks for Today, Inbox, and Timeline.")
                    .cadenceFont(.metadata, base: 11)
                    .foregroundStyle(Theme.dim)
                    .lineLimit(wraps ? nil : 2)
                    .fixedSize(horizontal: false, vertical: wraps)
            }

            if !wraps { Spacer(minLength: 8) }

            Button(action: action) {
                Image(systemName: "plus")
                    .cadenceFont(.controlLabel, base: 14, weight: .bold)
                    .foregroundStyle(Theme.onColor(for: Theme.blue))
                    .frame(width: side, height: side)
                    .background(Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            }
            .accessibilityLabel("Seed sample tasks")
        }
        .padding(12)
    }
}
#endif

#endif
