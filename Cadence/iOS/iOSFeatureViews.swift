#if os(iOS)
import SwiftData
import SwiftUI

struct iOSPursuitsView: View {
    @Query(sort: \Pursuit.order) private var pursuits: [Pursuit]
    @State private var selectedID: UUID?

    private var activePursuits: [Pursuit] {
        pursuits.filter { $0.status != .done }
    }

    private var selected: Pursuit? {
        if let selectedID {
            return pursuits.first { $0.id == selectedID }
        }
        return activePursuits.first ?? pursuits.first
    }

    var body: some View {
        HStack(spacing: 0) {
            iOSFeatureListPane(
                eyebrow: "Pursuits",
                title: "Pursuits",
                count: activePursuits.count,
                emptyTitle: "No pursuits yet",
                emptySubtitle: "Pursuits from Mac will appear here.",
                emptyIcon: "sparkles"
            ) {
                ForEach(activePursuits) { pursuit in
                    Button {
                        selectedID = pursuit.id
                    } label: {
                        iOSFeatureSummaryRow(
                            title: pursuit.title.isEmpty ? "Untitled Pursuit" : pursuit.title,
                            subtitle: pursuit.context?.name ?? pursuit.kind.label,
                            detail: pursuitSummaryLabel(for: pursuit),
                            icon: pursuit.icon,
                            color: Color(hex: pursuit.colorHex),
                            isSelected: selected?.id == pursuit.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().background(Theme.borderSubtle)

            if let pursuit = selected {
                let summary = CadencePursuitSupport.summary(for: pursuit)
                iOSPursuitDetail(pursuit: pursuit, goals: summary.goals, habits: summary.habits)
            } else {
                iOSFeatureEmptyDetail(systemImage: "sparkles", title: "No pursuit selected")
            }
        }
        .onAppear {
            selectedID = selectedID ?? selected?.id
        }
    }

    private func pursuitSummaryLabel(for pursuit: Pursuit) -> String {
        let summary = CadencePursuitSupport.summary(for: pursuit)
        return "\(summary.activeGoalCount) milestones / \(summary.activeHabitCount) habits"
    }
}

struct iOSMilestonesView: View {
    @Query(sort: \Goal.order) private var goals: [Goal]
    @State private var selectedID: UUID?

    private var activeGoals: [Goal] {
        goals.filter { $0.status != .done }
    }

    private var selected: Goal? {
        if let selectedID {
            return goals.first { $0.id == selectedID }
        }
        return activeGoals.first ?? goals.first
    }

    var body: some View {
        HStack(spacing: 0) {
            iOSFeatureListPane(
                eyebrow: "Milestones",
                title: "Milestones",
                count: activeGoals.count,
                emptyTitle: "No milestones yet",
                emptySubtitle: "Milestones created on Mac will show here.",
                emptyIcon: "flag.fill"
            ) {
                ForEach(activeGoals) { goal in
                    Button {
                        selectedID = goal.id
                    } label: {
                        let summary = GoalContributionResolver.summary(for: goal)
                        iOSFeatureSummaryRow(
                            title: goal.title.isEmpty ? "Untitled Milestone" : goal.title,
                            subtitle: goal.pursuit?.title ?? goal.context?.name ?? goal.status.rawValue.capitalized,
                            detail: "\(Int((summary.progress * 100).rounded()))%",
                            icon: "flag.fill",
                            color: Color(hex: goal.colorHex),
                            isSelected: selected?.id == goal.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().background(Theme.borderSubtle)

            if let goal = selected {
                iOSMilestoneDetail(goal: goal)
            } else {
                iOSFeatureEmptyDetail(systemImage: "flag.fill", title: "No milestone selected")
            }
        }
        .onAppear {
            selectedID = selectedID ?? selected?.id
        }
    }
}

struct iOSHabitsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Habit.order) private var habits: [Habit]
    @State private var selectedID: UUID?

    private var todayKey: String { DateFormatters.todayKey() }

    private var selected: Habit? {
        if let selectedID {
            return habits.first { $0.id == selectedID }
        }
        return dueToday.first ?? habits.first
    }

    private var dueToday: [Habit] {
        habits.filter(\.isDueToday)
    }

    var body: some View {
        HStack(spacing: 0) {
            iOSFeatureListPane(
                eyebrow: "Habits",
                title: "Habits",
                count: habits.count,
                emptyTitle: "No habits yet",
                emptySubtitle: "Habits created on Mac will show here.",
                emptyIcon: "flame.fill"
            ) {
                ForEach(habits) { habit in
                    Button {
                        selectedID = habit.id
                    } label: {
                        iOSHabitSummaryRow(
                            habit: habit,
                            todayKey: todayKey,
                            isSelected: selected?.id == habit.id,
                            toggle: { toggle(habit) }
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().background(Theme.borderSubtle)

            if let habit = selected {
                iOSHabitDetail(habit: habit, todayKey: todayKey, toggle: { toggle(habit) })
            } else {
                iOSFeatureEmptyDetail(systemImage: "flame.fill", title: "No habit selected")
            }
        }
        .onAppear {
            selectedID = selectedID ?? selected?.id
        }
    }

    private func toggle(_ habit: Habit) {
        CadenceHabitSupport.toggle(habit, on: todayKey, modelContext: modelContext)
    }
}
#endif
