#if os(iOS)
import SwiftData
import SwiftUI

struct iOSPursuitsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Pursuit.order) private var pursuits: [Pursuit]
    @State private var selectedID: UUID?
    @State private var editorMode: iOSPursuitEditorMode?
    @State private var goalEditorMode: iOSGoalEditorMode?
    @State private var habitEditorMode: iOSHabitEditorMode?

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
        Group {
            if horizontalSizeClass == .compact {
                compactLayout
            } else {
                horizontalLayout
            }
        }
        .background(Theme.bg)
        .onAppear {
            selectedID = selectedID ?? selected?.id
        }
        .sheet(item: $editorMode) { mode in
            iOSPursuitEditorSheet(mode: mode) { pursuit in
                selectedID = pursuit.id
            }
        }
        .sheet(item: $goalEditorMode) { mode in
            iOSGoalEditorSheet(mode: mode)
        }
        .sheet(item: $habitEditorMode) { mode in
            iOSHabitEditorSheet(mode: mode)
        }
    }

    private var horizontalLayout: some View {
        HStack(spacing: 0) {
            listPane

            Divider().background(Theme.borderSubtle)

            detailPane
        }
    }

    private var compactLayout: some View {
        VStack(spacing: 0) {
            listPane
                .frame(maxHeight: 360)

            Divider().background(Theme.borderSubtle)

            detailPane
        }
    }

    private var listPane: some View {
        iOSFeatureListPane(
            eyebrow: "Pursuits",
            title: "Pursuits",
            count: activePursuits.count,
            emptyTitle: "No pursuits yet",
            emptySubtitle: "Create a direction for related milestones and habits.",
            emptyIcon: "sparkles",
            actionTitle: "New Pursuit",
            actionSystemImage: "plus",
            action: { editorMode = .new }
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
    }

    @ViewBuilder
    private var detailPane: some View {
        if let pursuit = selected {
            let summary = CadencePursuitSupport.summary(for: pursuit)
            iOSPursuitDetail(
                pursuit: pursuit,
                goals: summary.goals,
                habits: summary.habits,
                onEdit: { editorMode = .edit(pursuit) },
                onNewGoal: { goalEditorMode = .new(pursuit) },
                onNewHabit: { habitEditorMode = .new(pursuit) }
            )
        } else {
            iOSFeatureEmptyDetail(systemImage: "sparkles", title: "No pursuit selected")
        }
    }

    private func pursuitSummaryLabel(for pursuit: Pursuit) -> String {
        let summary = CadencePursuitSupport.summary(for: pursuit)
        return "\(summary.activeGoalCount) milestones / \(summary.activeHabitCount) habits"
    }
}

struct iOSMilestonesView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Goal.order) private var goals: [Goal]
    @State private var selectedID: UUID?
    @State private var editorMode: iOSGoalEditorMode?

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
        Group {
            if horizontalSizeClass == .compact {
                compactLayout
            } else {
                horizontalLayout
            }
        }
        .background(Theme.bg)
        .onAppear {
            selectedID = selectedID ?? selected?.id
        }
        .sheet(item: $editorMode) { mode in
            iOSGoalEditorSheet(mode: mode) { goal in
                selectedID = goal.id
            }
        }
    }

    private var horizontalLayout: some View {
        HStack(spacing: 0) {
            listPane

            Divider().background(Theme.borderSubtle)

            detailPane
        }
    }

    private var compactLayout: some View {
        VStack(spacing: 0) {
            listPane
                .frame(maxHeight: 360)

            Divider().background(Theme.borderSubtle)

            detailPane
        }
    }

    private var listPane: some View {
        iOSFeatureListPane(
            eyebrow: "Milestones",
            title: "Milestones",
            count: activeGoals.count,
            emptyTitle: "No milestones yet",
            emptySubtitle: "Create milestones under a pursuit to track outcomes.",
            emptyIcon: "flag.fill",
            actionTitle: "New Milestone",
            actionSystemImage: "plus",
            action: { editorMode = .new(nil) }
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
    }

    @ViewBuilder
    private var detailPane: some View {
        if let goal = selected {
            iOSMilestoneDetail(goal: goal, onEdit: { editorMode = .edit(goal) })
        } else {
            iOSFeatureEmptyDetail(systemImage: "flag.fill", title: "No milestone selected")
        }
    }
}

struct iOSHabitsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Habit.order) private var habits: [Habit]
    @State private var selectedID: UUID?
    @State private var editorMode: iOSHabitEditorMode?

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
        Group {
            if horizontalSizeClass == .compact {
                compactLayout
            } else {
                horizontalLayout
            }
        }
        .background(Theme.bg)
        .onAppear {
            selectedID = selectedID ?? selected?.id
        }
        .sheet(item: $editorMode) { mode in
            iOSHabitEditorSheet(mode: mode) { habit in
                selectedID = habit.id
            }
        }
    }

    private var horizontalLayout: some View {
        HStack(spacing: 0) {
            listPane

            Divider().background(Theme.borderSubtle)

            detailPane
        }
    }

    private var compactLayout: some View {
        VStack(spacing: 0) {
            listPane
                .frame(maxHeight: 360)

            Divider().background(Theme.borderSubtle)

            detailPane
        }
    }

    private var listPane: some View {
        iOSFeatureListPane(
            eyebrow: "Habits",
            title: "Habits",
            count: habits.count,
            emptyTitle: "No habits yet",
            emptySubtitle: "Create repeating commitments and track today.",
            emptyIcon: "flame.fill",
            actionTitle: "New Habit",
            actionSystemImage: "plus",
            action: { editorMode = .new(nil) }
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
    }

    @ViewBuilder
    private var detailPane: some View {
        if let habit = selected {
            iOSHabitDetail(
                habit: habit,
                todayKey: todayKey,
                toggle: { toggle(habit) },
                onEdit: { editorMode = .edit(habit) }
            )
        } else {
            iOSFeatureEmptyDetail(systemImage: "flame.fill", title: "No habit selected")
        }
    }

    private func toggle(_ habit: Habit) {
        CadenceHabitSupport.toggle(habit, on: todayKey, modelContext: modelContext)
    }
}
#endif
