#if os(iOS)
import SwiftData
import SwiftUI

/// Today's rollover notice, as a surface opts into it: the tasks the banner lists and the action
/// its button runs, together, because the two are useless apart — the same shape as
/// `iOSBundleFormingDrop`.
struct iOSTodayRolloverNotice {
    let tasks: [AppTask]
    let onRollOver: () -> Void
}

/// Today's past-due summaries, as a surface opts into them: the two arrays and the one thing that
/// can act on either, together — the same shape as `iOSTodayRolloverNotice` above.
///
/// **The action is a closure, and that is the whole platform-shaped half of T-195's second
/// piece.** macOS's cards hop `ListNavigationManager`, a shell-level router that exists because the
/// Mac's sidebar is always on screen: opening a list there is a change of pane, and Today is one
/// click back. iOS has no equivalent and does not grow one here. See `iOSTodayView`, which
/// presents rather than navigates, and says why.
struct iOSTodayOverdueSummaries {
    let listSummaries: [CadenceTodayOverdueListSummary]
    let sectionSummaries: [CadenceTodayOverdueSectionSummary]
    let onOpen: (CadenceListOpenRequest) -> Void

    var isEmpty: Bool {
        listSummaries.isEmpty && sectionSummaries.isEmpty
    }
}

/// Today's list of counted task groups — **the** one, for both hosts.
///
/// The phone's Today and the iPad task column each drew their own copy of this: the same
/// `CadenceTodayTaskGroup`s, the same "Completed Today" group under them, and the same empty state,
/// stacked 14pt apart on one and 15pt on the other, padded 14 on one and 18 on the other. Two
/// copies of one list is how the previous round of this sweep found the iPad heading its groups
/// with a bare eyebrow while the phone counted them — a difference in what the screen *said*, from
/// a split nobody had chosen.
///
/// Everything that legitimately varies is `CadenceTodaySectionMetrics`, keyed on the layout rather
/// than the size class, so the iPad's narrow single-column fallback is drawn like the phone's Today
/// because it *is* the phone's Today, on the same `Theme.bg` page.
struct iOSTodayTaskSections: View {
    /// Which Today this is the list of. The only parameter that decides anything about appearance,
    /// and it decides it by asking `CadenceTodaySectionMetrics`.
    let layout: CadenceTodayLayout
    let taskGroups: [CadenceTodayTaskGroup]
    let completedTasks: [AppTask]
    let showsCompleted: Bool
    /// `nil` when there is nothing to roll over, or the day's notice has already been dismissed.
    /// The host decides — `CadenceTodayRolloverSupport.isNoticeVisible` — because the host is what
    /// holds the `@AppStorage` day key.
    var rolloverNotice: iOSTodayRolloverNotice?
    /// `nil` when nothing is past due. Like the notice above, the host derives it and this view is
    /// the only thing that draws it, so "both widths show it" is true by construction.
    var overdueSummaries: iOSTodayOverdueSummaries?
    #if DEBUG
    /// Debug-only, and passed by both hosts. See `iOSCompactSampleDataCard`.
    let sampleDataStatus: String?
    let seedSampleData: () -> Void
    #endif

    private var metrics: CadenceTodaySectionMetrics {
        .metrics(layout: layout)
    }

    /// The readable-column cap belongs to the **host**, not to this view: it has to hold the page
    /// header and the options bar as well, or a narrow iPad pane would cap the rows at 520 and let
    /// the header above them run the full width of the pane. Both hosts read it from here so it is
    /// still one number per layout.
    static func contentMaxWidth(layout: CadenceTodayLayout) -> CGFloat {
        CadenceTodaySectionMetrics.metrics(layout: layout).contentMaxWidth
    }

    /// `CadenceTaskQuerySupport.todayGroups` drops its empty groups, so an empty list of groups is
    /// an empty day — the two hosts each re-derived this from their own `todayTasks` array instead,
    /// which is one more chance for them to disagree about when Today is empty.
    ///
    /// **The rollover notice counts as content.** While it is up the grouped list is deliberately
    /// *missing* the tasks it is offering, so a day whose only open work is yesterday's leftovers
    /// has no groups — and without the last clause this view would draw "nothing planned" directly
    /// under a banner listing four things to do. Since T-305 the withheld rows are missing from
    /// *their lists'* groups rather than from a "Past Do" section, so confirming the roll makes a
    /// list group appear rather than moving rows between two date buckets — which is the whole
    /// point of the roll being visible.
    ///
    /// **The past-due summaries count as content too**, for the same reason the notice does: a day
    /// with nothing planned but three columns whose deadlines have gone by would otherwise read
    /// "nothing planned" directly under three cards saying otherwise.
    private var isEmpty: Bool {
        taskGroups.isEmpty
            && (!showsCompleted || completedTasks.isEmpty)
            && rolloverNotice == nil
            && (overdueSummaries?.isEmpty ?? true)
    }

    @ViewBuilder
    var body: some View {
        // Above both branches: the notice and the past-due cards are the day's first things to
        // read whether or not anything is left in the groups under them.
        if rolloverNotice != nil || !(overdueSummaries?.isEmpty ?? true) {
            VStack(alignment: .leading, spacing: metrics.groupSpacing) {
                if let rolloverNotice {
                    CadenceTodayRolloverBanner(tasks: rolloverNotice.tasks, style: .card) {
                        rolloverNotice.onRollOver()
                    }
                }
                overdueSummarySections
                content
            }
        } else {
            content
        }
    }

    /// The two runs of past-due cards, each headed by the shared eyebrow. Lists first: a whole
    /// project past its date is a larger statement than one of its columns being past its own, and
    /// the columns underneath frequently belong to it.
    @ViewBuilder
    private var overdueSummarySections: some View {
        if let overdueSummaries, !overdueSummaries.isEmpty {
            if !overdueSummaries.listSummaries.isEmpty {
                overdueSummaryRun(
                    title: CadenceTodayOverdueSummarySupport.listsHeading,
                    count: overdueSummaries.listSummaries.count
                ) {
                    ForEach(overdueSummaries.listSummaries) { summary in
                        CadenceTodayOverdueListCard(summary: summary) {
                            guard let request = CadenceTodayOverdueSummarySupport.openRequest(for: summary) else { return }
                            overdueSummaries.onOpen(request)
                        }
                    }
                }
            }

            if !overdueSummaries.sectionSummaries.isEmpty {
                overdueSummaryRun(
                    title: CadenceTodayOverdueSummarySupport.sectionsHeading,
                    count: overdueSummaries.sectionSummaries.count
                ) {
                    ForEach(overdueSummaries.sectionSummaries) { summary in
                        CadenceTodayOverdueSectionCard(summary: summary) {
                            guard let request = CadenceTodayOverdueSummarySupport.openRequest(for: summary) else { return }
                            overdueSummaries.onOpen(request)
                        }
                    }
                }
            }
        }
    }

    private func overdueSummaryRun<Cards: View>(
        title: String,
        count: Int,
        @ViewBuilder cards: () -> Cards
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CadenceTodayOverdueSummaryHeading(title: title, count: count)
            VStack(spacing: 8) {
                cards()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isEmpty {
            // Not carded by `metrics`: `iOSCompactTodayEmptyState` draws its own card, at the one
            // fill that reads against both hosts. A second card around it would be the stacked
            // layers the standing rule rules out.
            VStack(alignment: .leading, spacing: 12) {
                iOSCompactTodayEmptyState()

                #if DEBUG
                iOSCompactSampleDataCard(
                    status: sampleDataStatus,
                    action: seedSampleData
                )
                #endif
            }
        } else {
            groupStack
        }
    }

    @ViewBuilder
    private var groupStack: some View {
        // Asked of the surface rather than decided here, so the phone's Today and the iPad's cannot
        // answer "does a row name its list" differently — the same reason Inbox asks.
        let showsContainer = CadenceTaskSurfaceOptions.showsContainerChip(on: .today)

        let stack = VStack(alignment: .leading, spacing: metrics.groupSpacing) {
            ForEach(taskGroups) { group in
                // A list group accepts a dropped `+` and inherits its list; Overdue is defined by a
                // day that has gone by, so it does not light up.
                // `CadenceTaskDropSupport.dropKey(forGroup:)` decides, once, for both layouts.
                //
                // `showsContainer` is `&&`-ed with the group's own answer rather than replaced by
                // it: the surface still decides whether Today names lists at all, and the group
                // then withholds the chip inside a header that already prints the list's name.
                iOSTaskGroupSection(
                    title: group.title,
                    color: group.accent,
                    tasks: group.tasks,
                    showsContainer: showsContainer && group.showsContainerChip,
                    dropIdentity: group.dropIdentity
                )
            }

            if showsCompleted {
                iOSTaskGroupSection(
                    title: CadenceTodayPresentationSupport.completedSectionTitle,
                    color: CadenceTodayPresentationSupport.completedSectionAccent,
                    tasks: CadenceTaskSurfaceOptions.completedRows(from: completedTasks, tier: .touch),
                    showsContainer: showsContainer,
                    opacity: 0.62,
                    dropIdentity: .completion,
                    hiddenCount: CadenceTaskSurfaceOptions.hiddenCompletedCount(from: completedTasks, tier: .touch)
                )
            }
        }

        if metrics.drawsCard {
            stack
                .padding(metrics.cardPadding)
        } else {
            stack
        }
    }
}

/// The list a past-due summary card opens, as Today presents it.
///
/// It is `iOSListDetailView` and nothing else — the same page the Lists tab pushes, at the page the
/// request names, with the named column scrolled into view. Wrapping it rather than writing a
/// reduced "here are the overdue cards" panel is the point: the reason to tap the card is to *work
/// on* the column, and a read-only excerpt would send you to the Lists tab to do anything about it.
///
/// **It carries its own task-inspector host.** The root's host is already presenting this sheet, and
/// a host that is presenting cannot present again — a task row inside here would be a dead tap
/// without a nearer owner. `iOSTaskInspectorHost` records that the environment resolves to the
/// innermost host for exactly this case.
struct iOSTodayOverdueListSheet: View {
    let request: CadenceListOpenRequest
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]

    var body: some View {
        content
            .iOSTaskInspectorHost()
    }

    /// A list can be deleted or archived on another device between the card being drawn and the
    /// card being tapped, so the miss is a real state and not a defensive `else` — the same one
    /// `iOSRootView` and `iOSSearchView` already answer with this view.
    @ViewBuilder
    private var content: some View {
        switch request.target {
        case .area(let id):
            if let area = areas.first(where: { $0.id == id }) {
                iOSListDetailView(
                    area: area,
                    initialPage: request.page,
                    highlightedSectionName: request.sectionName,
                    isPresentedModally: true
                )
            } else {
                iOSMissingListView()
            }
        case .project(let id):
            if let project = projects.first(where: { $0.id == id }) {
                iOSListDetailView(
                    project: project,
                    initialPage: request.page,
                    highlightedSectionName: request.sectionName,
                    isPresentedModally: true
                )
            } else {
                iOSMissingListView()
            }
        }
    }
}
#endif
