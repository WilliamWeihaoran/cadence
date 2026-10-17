#if os(iOS)
import SwiftData
import SwiftUI

struct iOSCompactTodayView: View {
    var showsHeader = true
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
        iOSCompactBackActionReader { onBack in
            iOSCompactPageHeader(
                eyebrow: DateFormatters.longDate.string(from: Date()),
                title: "Today",
                color: Theme.amber,
                count: summary.activeCount,
                onBack: onBack
            )
        }
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
                completedCount: summary.completedCount,
                showsCompletedControl: false
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

// [[T-3197]] removed iOSCompactTodayEmptyState — Today's "Nothing planned" / "Add a task with +,
// or schedule one from Inbox." empty state, a checkmark tile beside two lines of text, drawn on
// iPhone and iPad by iOSTodayTaskSections when the day had no groups, no completed work and no
// rollover notice. The owner asked for it off: *"remove the box that says 'nothing planned add a
// task with + ......'"*. A Today with nothing scheduled is now a blank area under the sort
// control, which is the owner's call and was made knowing it.
//
// What is NOT gone, and was checked rather than assumed:
//   - The debug seed card below. The owner asked whether it was dev-only; it is `#if DEBUG`, so it
//     never compiles into a release build, and it stays exactly as it is.
//   - CadenceTodayPresentationSupport.emptyTitle / .emptySubtitle. macOS's TasksPanel still draws
//     them, so the constants keep a live reader and are not deleted out from under it. That leaves
//     the two hosts saying different things about an empty Today for the first time — the owner's
//     instruction named the phone's box and `for all devices` is what they said about the estimate
//     chip, not about this. Raised on [[T-3197]] rather than decided here.

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
