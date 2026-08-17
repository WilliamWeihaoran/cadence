#if os(iOS)
import SwiftData
import SwiftUI

struct iOSCompactTodayView: View {
    var showsHeader = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let completedTodayTasks: [AppTask]
    let todayTaskGroups: [CadenceTodayTaskGroup]
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
            .padding(.horizontal, 14)
            .padding(.top, 10)
            // Breathing room at the end of the content, not bar clearance: the tab bar is a `VStack`
            // sibling of the tab content in `iOSCompactRootShell`, so this scroll view is handed a
            // height that already stops where the bar starts. This used to be 132 — hand-cut
            // clearance for a floating `+` — which is the shape of thing that goes wrong the moment
            // the bar's height changes.
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
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
    /// It carries the same `eyebrowDetail` the two-pane column's header does. The summary is a fact
    /// about the day — how much of it is timed, how much is already done — not a fact about how much
    /// room the screen has, and the phone had simply never been given it.
    private var header: some View {
        iOSCompactPageHeader(
            eyebrow: DateFormatters.longDate.string(from: Date()),
            eyebrowDetail: summary.line,
            title: "Today",
            systemImage: "sun.max.fill",
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
            showsCompleted: showCompleted,
            sampleDataStatus: sampleDataStatus,
            seedSampleData: seedSampleData
        )
        #else
        iOSTodayTaskSections(
            layout: .compact,
            taskGroups: todayTaskGroups,
            completedTasks: completedTodayTasks,
            showsCompleted: showCompleted
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
/// **It draws its own card.** The two callers each wrapped it in one of their own and disagreed
/// about the fill — `Theme.surface` on the phone, `Theme.surfaceElevated.opacity(0.36)` on the
/// iPad — so one component had two looks. `Theme.surfaceElevated` is the one value that reads as a
/// card against both hosts: the phone's page is `Theme.bg`, and the iPad's task column is itself
/// `Theme.surface`, which a `Theme.surface` card disappears into.
struct iOSCompactTodayEmptyState: View {
    var body: some View {
        emptyRow
            .cadenceCard(background: Theme.surfaceElevated, cornerRadius: Theme.radiusCard)
    }

    private var emptyRow: some View {
        HStack(alignment: .center, spacing: 13) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .frame(width: 42, height: 42)
                .background(Theme.surfaceElevated.opacity(0.54))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                        .strokeBorder(Theme.borderSubtle.opacity(0.42), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(CadenceTodayPresentationSupport.emptyCompactTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                Text(CadenceTodayPresentationSupport.emptySubtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

/// Debug-only, on both widths — the seeding affordance cannot ship. iPad had its own "Samples"
/// button welded into its empty-state card; it is this card now.
#if DEBUG
struct iOSCompactSampleDataCard: View {
    let status: String?
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            iOSIconTile(systemImage: "wand.and.stars", color: Theme.amber, bordered: false)

            VStack(alignment: .leading, spacing: 3) {
                Text(status ?? "Need realistic rows?")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)

                Text("Seed local simulator tasks for Today, Inbox, and Timeline.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(action: action) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.onColor)
                    .frame(width: 34, height: 34)
                    .background(Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            }
            .accessibilityLabel("Seed sample tasks")
        }
        .padding(12)
        // Same fill as the empty-state card it sits under, for the same reason: on iPad both are
        // drawn on a `Theme.surface` task column, where a `Theme.surface` card is invisible.
        .cadenceCard(background: Theme.surfaceElevated, cornerRadius: Theme.radiusCard)
    }
}
#endif

#endif
