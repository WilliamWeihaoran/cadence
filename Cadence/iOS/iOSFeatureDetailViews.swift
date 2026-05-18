#if os(iOS)
import SwiftData
import SwiftUI

struct iOSPursuitDetail: View {
    let pursuit: Pursuit
    let goals: [Goal]
    let habits: [Habit]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                iOSFeatureHero(
                    eyebrow: pursuit.kind.label,
                    title: pursuit.title.isEmpty ? "Untitled Pursuit" : pursuit.title,
                    subtitle: pursuit.desc.isEmpty ? pursuit.context?.name ?? "Pursuit" : pursuit.desc,
                    icon: pursuit.icon,
                    color: Color(hex: pursuit.colorHex)
                )

                HStack(spacing: 10) {
                    iOSMetricTile(title: "Milestones", value: "\(goals.count)", icon: "flag.fill", color: Theme.green)
                    iOSMetricTile(title: "Habits", value: "\(habits.count)", icon: "flame.fill", color: Theme.amber)
                    iOSMetricTile(title: "Status", value: pursuit.status.label, icon: "circle.fill", color: Color(hex: pursuit.colorHex))
                }

                iOSFeatureSection(title: "Milestones") {
                    ForEach(goals) { goal in
                        let summary = GoalContributionResolver.summary(for: goal)
                        iOSFeatureSummaryRow(
                            title: goal.title.isEmpty ? "Untitled Milestone" : goal.title,
                            subtitle: summary.nextActionTitle ?? goal.status.rawValue.capitalized,
                            detail: summary.percentLabel,
                            icon: "flag.fill",
                            color: Color(hex: goal.colorHex)
                        )
                    }
                }

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
            .padding(20)
        }
        .background(Theme.bg)
    }
}

struct iOSMilestoneDetail: View {
    let goal: Goal

    private var summary: GoalContributionSummary {
        GoalContributionResolver.summary(for: goal)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                iOSFeatureHero(
                    eyebrow: goal.status.rawValue.capitalized,
                    title: goal.title.isEmpty ? "Untitled Milestone" : goal.title,
                    subtitle: goal.desc.isEmpty ? goal.pursuit?.title ?? goal.context?.name ?? "Milestone" : goal.desc,
                    icon: "flag.fill",
                    color: Color(hex: goal.colorHex)
                )

                ProgressView(value: summary.progress)
                    .tint(Color(hex: goal.colorHex))

                HStack(spacing: 10) {
                    iOSMetricTile(title: "Progress", value: summary.percentLabel, icon: "chart.line.uptrend.xyaxis", color: Color(hex: goal.colorHex))
                    iOSMetricTile(title: "Tasks", value: summary.taskCountLabel, icon: "checklist", color: Theme.blue)
                    iOSMetricTile(title: "Focus", value: summary.focusLabel, icon: "timer", color: Theme.amber)
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
                Text(habit.pursuit?.title ?? habit.frequencySummary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(habit.currentStreak)d")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(hex: habit.colorHex))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(isSelected ? Color(hex: habit.colorHex).opacity(0.15) : Theme.surfaceElevated.opacity(0.38))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color(hex: habit.colorHex).opacity(0.32) : Theme.borderSubtle.opacity(0.45), lineWidth: 1)
        }
    }
}

struct iOSHabitDetail: View {
    let habit: Habit
    let todayKey: String
    let toggle: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                iOSFeatureHero(
                    eyebrow: habit.frequencyShortLabel,
                    title: habit.title.isEmpty ? "Untitled Habit" : habit.title,
                    subtitle: habit.pursuit?.title ?? habit.goal?.title ?? habit.context?.name ?? habit.frequencySummary,
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
