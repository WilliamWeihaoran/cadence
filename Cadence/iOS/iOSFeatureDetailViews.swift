#if os(iOS)
import SwiftData
import SwiftUI

/// One detail surface for every goal, top-level or nested. A top-level goal reads as a
/// direction that owns milestones and habits; a nested goal reads as a milestone of its parent.
struct iOSGoalDetail: View {
    let goal: Goal
    var milestones: [Goal] = []
    var habits: [Habit] = []
    var onEdit: () -> Void = {}
    var onNewMilestone: () -> Void = {}
    var onNewHabit: () -> Void = {}
    var onSelectMilestone: ((Goal) -> Void)? = nil

    private var summary: GoalContributionSummary {
        GoalContributionResolver.summary(for: goal)
    }

    private var tint: Color {
        Color(hex: goal.colorHex)
    }

    private var heroSubtitle: String {
        if !goal.desc.isEmpty { return goal.desc }
        if let parent = goal.parentGoal {
            return parent.title.isEmpty ? "Untitled Goal" : parent.title
        }
        return goal.context?.name ?? goal.kind.detail
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                iOSFeatureHero(
                    eyebrow: goal.isTopLevel ? goal.kind.label : "Milestone",
                    title: goal.title.isEmpty ? "Untitled Goal" : goal.title,
                    subtitle: heroSubtitle,
                    icon: goal.icon,
                    color: tint
                )

                HStack(spacing: 10) {
                    Button(action: onEdit) {
                        Label("Edit", systemImage: "square.and.pencil")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)

                    Button(action: onNewMilestone) {
                        Label("Milestone", systemImage: "flag.fill")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.green)

                    Button(action: onNewHabit) {
                        Label("Habit", systemImage: "flame.fill")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.amber)
                }

                ProgressView(value: summary.progress)
                    .tint(tint)

                HStack(spacing: 10) {
                    iOSMetricTile(title: "Progress", value: summary.percentLabel, icon: "chart.line.uptrend.xyaxis", color: tint)
                    iOSMetricTile(title: "Tasks", value: summary.taskCountLabel, icon: "checklist", color: Theme.blue)
                    iOSMetricTile(title: "Focus", value: summary.focusLabel, icon: "timer", color: Theme.amber)
                }

                HStack(spacing: 10) {
                    iOSMetricTile(title: "Milestones", value: "\(milestones.count)", icon: "flag.fill", color: Theme.green)
                    iOSMetricTile(title: "Habits", value: "\(habits.count)", icon: "flame.fill", color: Theme.amber)
                    iOSMetricTile(title: "Status", value: goal.status.label, icon: "circle.fill", color: tint)
                }

                if let nextActionTitle = summary.nextActionTitle {
                    iOSFeatureSection(title: "Next Action") {
                        iOSFeatureSummaryRow(
                            title: nextActionTitle,
                            subtitle: "Highest priority open task",
                            icon: "arrow.right.circle.fill",
                            color: Theme.blue
                        )
                    }
                }

                if !milestones.isEmpty {
                    iOSFeatureSection(title: "Milestones") {
                        ForEach(milestones) { milestone in
                            milestoneRow(milestone)
                        }
                    }
                }

                if !habits.isEmpty {
                    iOSFeatureSection(title: "Habits") {
                        ForEach(habits) { habit in
                            iOSFeatureSummaryRow(
                                title: habit.title.isEmpty ? "Untitled Habit" : habit.title,
                                subtitle: habit.frequencySummary,
                                detail: "\(habit.currentStreak)d",
                                icon: habit.icon,
                                color: Color(hex: habit.colorHex)
                            )
                        }
                    }
                }

                iOSFeatureSection(title: "Linked Work") {
                    iOSFeatureSummaryRow(
                        title: "\(summary.linkedListCount) linked lists",
                        subtitle: "\(summary.overdueTaskCount) overdue, \(summary.recentCompletedCount) recent completions",
                        icon: "folder.fill",
                        color: Theme.green
                    )
                }
            }
            .padding(20)
        }
        .background(Theme.bg)
    }

    @ViewBuilder
    private func milestoneRow(_ milestone: Goal) -> some View {
        let milestoneSummary = GoalContributionResolver.summary(for: milestone)
        let row = iOSFeatureSummaryRow(
            title: milestone.title.isEmpty ? "Untitled Goal" : milestone.title,
            subtitle: milestoneSummary.nextActionTitle ?? milestone.status.label,
            detail: milestoneSummary.percentLabel,
            icon: milestone.icon,
            color: Color(hex: milestone.colorHex)
        )

        if let onSelectMilestone {
            Button {
                onSelectMilestone(milestone)
            } label: {
                row
            }
            .buttonStyle(.plain)
        } else {
            row
        }
    }
}

struct iOSHabitSummaryRow: View {
    let habit: Habit
    let todayKey: String
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: toggle) {
                Image(systemName: habit.isDone(on: todayKey) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(habit.isDone(on: todayKey) ? Theme.green : Theme.dim)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(habit.title.isEmpty ? "Untitled Habit" : habit.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(habit.goal?.title ?? habit.frequencySummary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(habit.currentStreak)d")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(hex: habit.colorHex))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(isSelected ? Color(hex: habit.colorHex).opacity(0.16) : Theme.surfaceElevated.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .shadow(color: Theme.cardElevationShadow, radius: 6, x: 0, y: 2)
    }
}

struct iOSHabitDetail: View {
    let habit: Habit
    let todayKey: String
    let toggle: () -> Void
    var onEdit: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                iOSFeatureHero(
                    eyebrow: habit.frequencyShortLabel,
                    title: habit.title.isEmpty ? "Untitled Habit" : habit.title,
                    subtitle: habit.goal?.title ?? habit.context?.name ?? habit.frequencySummary,
                    icon: habit.icon,
                    color: Color(hex: habit.colorHex)
                )

                Button(action: toggle) {
                    Label(habit.isDone(on: todayKey) ? "Done Today" : "Mark Done Today",
                          systemImage: habit.isDone(on: todayKey) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(habit.isDone(on: todayKey) ? Theme.green : Theme.text)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(habit.isDone(on: todayKey) ? Theme.green.opacity(0.13) : Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onEdit) {
                    Label("Edit Habit", systemImage: "square.and.pencil")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: habit.colorHex))

                HStack(spacing: 10) {
                    iOSMetricTile(title: "Current", value: "\(habit.currentStreak)d", icon: "flame.fill", color: Theme.amber)
                    iOSMetricTile(title: "Best", value: "\(habit.bestStreak)d", icon: "trophy.fill", color: Theme.green)
                    iOSMetricTile(title: "30 days", value: "\(habit.last30DayCompletionRate)%", icon: "chart.bar.fill", color: Theme.blue)
                }

                iOSFeatureSection(title: "Recent") {
                    ForEach(habit.last7DayStates.indices, id: \.self) { index in
                        let done = habit.last7DayStates[index]
                        iOSFeatureSummaryRow(
                            title: recentDayLabel(offset: 6 - index),
                            subtitle: done ? "Completed" : "Open",
                            icon: done ? "checkmark.circle.fill" : "circle",
                            color: done ? Theme.green : Theme.dim
                        )
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.bg)
    }

    private func recentDayLabel(offset: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
        return DateFormatters.dayOfWeek.string(from: date)
    }
}
#endif
