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
#endif
