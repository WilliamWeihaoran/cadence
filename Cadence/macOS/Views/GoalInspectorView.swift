#if os(macOS)
import SwiftUI

struct GoalInspectorView: View {
    let goal: Goal
    let onEdit: () -> Void
    let onAttachWork: () -> Void
    let onDetachList: (GoalListLink) -> Void

    private var summary: GoalContributionSummary {
        GoalContributionResolver.summary(for: goal)
    }

    private var habitMomentum: GoalHabitMomentumSummary {
        GoalHabitMomentumResolver.summary(for: goal)
    }

    /// The shared rule, not a second copy of it: title alone is a partial order over a SwiftData
    /// to-many with no defined order, so two lists of the same name swapped places between renders.
    /// `GoalLinkPresentation.links` is what iOS's goal detail reads too.
    private var linkedLists: [GoalListLink] {
        GoalLinkPresentation.links(of: goal)
    }

    private var contributingTasks: [AppTask] {
        GoalContributionResolver.contributingTasks(for: goal)
    }

    var body: some View {
        // Both resolvers recurse the goal's sub-goals and re-sort/re-parse every contributing
        // task; run each once per pass instead of once per read site.
        let summary = self.summary
        let habitMomentum = self.habitMomentum
        let contributingTasks = self.contributingTasks

        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                inspectorHeader(summary: summary)
                signalGrid(summary: summary, habitMomentum: habitMomentum)
                contributorLists
                allWorkSection(contributingTasks: contributingTasks)
            }
            .padding(20)
        }
        .background(Theme.surface)
    }

    private func inspectorHeader(summary: GoalContributionSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(goal.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                GoalStatusBadge(status: goal.status)
                Spacer(minLength: 0)
            }

            Text(goal.desc.isEmpty ? "No definition of done yet" : goal.desc)
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(summary.percentLabel)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .monospacedDigit()
                    Text("complete")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.dim)
                    Spacer()
                    Text(goal.daysSummary)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(goal.isOverdue ? Theme.red : Theme.dim)
                }
                GoalProgressBar(progress: summary.progress, color: Color(hex: goal.colorHex), height: 5)
            }

            HStack(spacing: 8) {
                CadenceActionButton(
                    title: "Edit",
                    systemImage: "pencil",
                    role: .secondary,
                    size: .compact,
                    action: onEdit
                )
                CadenceActionButton(
                    title: "Attach List",
                    systemImage: "plus",
                    role: .secondary,
                    size: .compact,
                    action: onAttachWork
                )
                Spacer()
            }
        }
    }

    /// Focus, momentum, habit momentum and overdue, as tiles.
    ///
    /// This was written complete and never referenced from `body` — Swift emits no warning for an
    /// unused private computed property, so it sat dead from the day the file was written. The
    /// effect was that macOS's goal inspector showed none of these signals while iOS showed some
    /// of them, and `GoalHabitMomentumResolver` was resolved on every inspector render purely to
    /// be discarded. Both resolvers are now passed in, matching the once-per-pass rule above.
    ///
    /// The original also carried a "Deadline" tile repeating `goal.daysSummary`, which the header
    /// prints two lines above it; a tile that restates its own header is the pattern this codebase
    /// already removed from page subtitles.
    private func signalGrid(
        summary: GoalContributionSummary,
        habitMomentum: GoalHabitMomentumSummary
    ) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            GoalSignalTile(title: "Focus", value: summary.focusLabel, icon: "clock.fill", color: Theme.blue)
            GoalSignalTile(title: "Momentum", value: "\(summary.recentCompletedCount) done", icon: "sparkline", color: Theme.green)
            GoalSignalTile(
                title: "Habit Momentum",
                value: habitMomentum.linkedHabitCount == 0 ? "No habits" : habitMomentum.dueTodayLabel,
                icon: "flame.fill",
                color: habitMomentum.dueTodayCount > 0 && habitMomentum.doneTodayCount >= habitMomentum.dueTodayCount
                    ? Theme.green
                    : Theme.amber
            )
            GoalSignalTile(title: "Overdue", value: "\(summary.overdueTaskCount)", icon: "exclamationmark.triangle.fill", color: summary.overdueTaskCount > 0 ? Theme.red : Theme.dim)
        }
    }

    private var contributorLists: some View {
        VStack(alignment: .leading, spacing: 10) {
            GoalSectionHeading(title: "Linked Lists", count: linkedLists.count)
            if linkedLists.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No lists attached")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(GoalLinkPresentation.emptyExplanation)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.surfaceElevated.opacity(0.38))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                VStack(spacing: 8) {
                    ForEach(linkedLists) { link in
                        GoalLinkedListRow(link: link, onDetach: { onDetachList(link) })
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func allWorkSection(contributingTasks: [AppTask]) -> some View {
        if !contributingTasks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                GoalSectionHeading(title: "Contributing Work", count: contributingTasks.count)
                VStack(spacing: 8) {
                    ForEach(contributingTasks.prefix(8)) { task in
                        GoalTaskContributorRow(task: task, onDetach: nil)
                    }
                }
            }
        }
    }
}

/// The same inspector, presented modally, at the widths where it has no column.
///
/// **The pane decision from T-250 stands; what was wrong is that two commands lived inside a pane.**
/// Below `CadenceDesktopSplitLayout.goalsSplitMinimumWidth` the inspector column is not merely tight
/// but invisible — nine points of 340 at the app's own minimum window with the sidebar out — so
/// dropping it was right. Dropping *Edit* and *Attach List* with it was not: the mission layout has
/// no other route to either, and `GoalLinkedListRow`'s detach has no other route at all. A pane may
/// be a luxury; the only way to change a goal is not.
///
/// **This is `iOSFeatureRowLink`'s shape, spelled for a page with no navigation stack.** That type
/// already states the rule this follows — "at regular width the row **selects** and the detail pane
/// beside it changes, and on the phone the row **pushes** the detail onto the tab's stack" — and
/// warns that Goals and Habits each once carried that difference as a byte-for-byte second copy of
/// their whole list pane. So the difference parameterised here is one control: what a card's
/// `onSelect` does. The list, the cards, the grouping and `GoalInspectorView` itself are shared
/// verbatim between the two widths, and macOS's Goals page has no `NavigationStack`, which is the
/// whole of why a push spells as a sheet.
///
/// **Edit and Attach List are presented from here rather than from `GoalsView`.** Setting one of
/// that view's flags would mean dismissing this sheet and raising another in the same update, and
/// the sequencing hacks that needs are already a documented smell in this repo (the quick-capture
/// panel's 250ms delay). Presenting them from inside the sheet is also the better reading: you edit
/// a goal, come back to its details, and attach a list — the modal you came from is where you were.
///
/// The width is **borrowed, not chosen**: `goalInspectorPaneMinWidth` is exactly what the inspector
/// column is handed at the threshold, so this is the column restored rather than a second opinion
/// about how wide an inspector should be. A typed `340` would satisfy every assertion here on the
/// day it was written and stop following its part the next day.
struct GoalInspectorSheet: View {
    let goal: Goal
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    let onDetachList: (GoalListLink) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showEditGoal = false
    @State private var showAttachWork = false

    var body: some View {
        VStack(spacing: 0) {
            // No title bar. `GoalInspectorView` opens with the goal's own name at 22pt, and a header
            // repeating it is the page-subtitle mistake one row up.
            HStack {
                Spacer()
                CadenceActionButton(title: "Done", role: .secondary, size: .compact) {
                    dismiss()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            GoalInspectorView(
                goal: goal,
                onEdit: { showEditGoal = true },
                onAttachWork: { showAttachWork = true },
                onDetachList: onDetachList
            )
        }
        .frame(width: CadenceDesktopSplitLayout.goalInspectorPaneMinWidth, height: 660)
        .background(Theme.surface)
        .sheet(isPresented: $showEditGoal) {
            CreateGoalSheet(goal: goal)
        }
        .sheet(isPresented: $showAttachWork) {
            AttachWorkSheet(
                goal: goal,
                contexts: contexts,
                areas: areas,
                projects: projects
            )
        }
    }
}
#endif
