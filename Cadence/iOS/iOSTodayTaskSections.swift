#if os(iOS)
import SwiftUI

/// Today's rollover notice, as a surface opts into it: the tasks the banner lists and the action
/// its button runs, together, because the two are useless apart — the same shape as
/// `iOSBoardTaskCardBundleDrop`.
struct iOSTodayRolloverNotice {
    let tasks: [AppTask]
    let onRollOver: () -> Void
}

/// Today's list of counted task groups — **the** one, for both hosts.
///
/// The phone's Today and the iPad task column each drew their own copy of this: the same four
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
    /// under a banner listing four things to do.
    private var isEmpty: Bool {
        taskGroups.isEmpty && (!showsCompleted || completedTasks.isEmpty) && rolloverNotice == nil
    }

    @ViewBuilder
    var body: some View {
        // Above both branches: the notice is the day's first thing to read whether or not anything
        // is left in the groups under it.
        if let rolloverNotice {
            VStack(alignment: .leading, spacing: metrics.groupSpacing) {
                CadenceTodayRolloverBanner(tasks: rolloverNotice.tasks, style: .card) {
                    rolloverNotice.onRollOver()
                }
                content
            }
        } else {
            content
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
            ForEach(taskGroups, id: \.title) { group in
                // Due Today and Planned Today accept a dropped `+`; Overdue and Past Do are defined
                // by a day that has gone by, so they do not light up.
                // `CadenceTaskDropSupport.dropKey(forGroup:)` decides, once, for both layouts.
                iOSTaskGroupSection(
                    title: group.title,
                    color: CadenceTodayPresentationSupport.accent(for: group.kind),
                    tasks: group.tasks,
                    showsContainer: showsContainer,
                    dropIdentity: .todayDate(group.kind)
                )
            }

            if showsCompleted {
                iOSTaskGroupSection(
                    title: CadenceTodayPresentationSupport.completedSectionTitle,
                    color: CadenceTodayPresentationSupport.completedSectionAccent,
                    tasks: CadenceTaskSurfaceOptions.completedRows(from: completedTasks),
                    showsContainer: showsContainer,
                    opacity: 0.62,
                    dropIdentity: .completion
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
#endif
