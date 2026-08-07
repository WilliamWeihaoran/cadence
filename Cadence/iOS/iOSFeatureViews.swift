#if os(iOS)
import SwiftData
import SwiftUI

/// Goals screen. Top-level goals are the long-running directions that used to live in their
/// own model; each is listed with its milestones (`subGoals`) nested directly underneath it.
struct iOSGoalsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Goal.order) private var goals: [Goal]
    @State private var selectedID: UUID?
    @State private var editorMode: iOSGoalEditorMode?
    @State private var habitEditorMode: iOSHabitEditorMode?

    private var activeGoals: [Goal] {
        goals.filter { $0.status != .done }
    }

    /// Genuine directions, plus any nested goal whose parent is completed — without the second
    /// half those milestones would have no row to appear under and drop off the screen.
    private var topLevelGoals: [Goal] {
        let activeIDs = Set(activeGoals.map(\.id))
        return activeGoals.filter { goal in
            guard let parent = goal.parentGoal else { return true }
            return !activeIDs.contains(parent.id)
        }
    }

    private func milestones(of goal: Goal) -> [Goal] {
        GoalAssignmentRules.milestones(of: goal).filter { $0.status != .done }
    }

    private var selected: Goal? {
        if let selectedID {
            return goals.first { $0.id == selectedID }
        }
        return topLevelGoals.first ?? activeGoals.first ?? goals.first
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
        compactListPane
    }

    private var listPane: some View {
        iOSFeatureListPane(
            eyebrow: "Progress",
            title: "Goals",
            count: activeGoals.count,
            emptyTitle: "No goals yet",
            emptySubtitle: "Create a direction, then nest milestones and habits underneath it.",
            emptyIcon: "sparkles",
            actionTitle: "New Goal",
            actionSystemImage: "plus",
            action: { editorMode = .new(nil) }
        ) {
            ForEach(topLevelGoals) { goal in
                Button {
                    selectedID = goal.id
                } label: {
                    goalRow(goal, isSelected: selected?.id == goal.id)
                }
                .buttonStyle(.plain)

                ForEach(milestones(of: goal)) { milestone in
                    Button {
                        selectedID = milestone.id
                    } label: {
                        goalRow(milestone, isSelected: selected?.id == milestone.id)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 16)
                }
            }
        }
    }

    private var compactListPane: some View {
        iOSFeatureListPane(
            eyebrow: "Progress",
            title: "Goals",
            count: activeGoals.count,
            emptyTitle: "No goals yet",
            emptySubtitle: "Create a direction, then nest milestones and habits underneath it.",
            emptyIcon: "sparkles",
            actionTitle: "New Goal",
            actionSystemImage: "plus",
            action: { editorMode = .new(nil) }
        ) {
            ForEach(topLevelGoals) { goal in
                NavigationLink {
                    detailView(for: goal)
                } label: {
                    goalRow(goal, isSelected: false)
                }
                .buttonStyle(.plain)

                ForEach(milestones(of: goal)) { milestone in
                    NavigationLink {
                        detailView(for: milestone)
                    } label: {
                        goalRow(milestone, isSelected: false)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 16)
                }
            }
        }
    }

    private func goalRow(_ goal: Goal, isSelected: Bool) -> some View {
        iOSFeatureSummaryRow(
            title: goal.title.isEmpty ? "Untitled Goal" : goal.title,
            subtitle: rowSubtitle(for: goal),
            detail: GoalContributionResolver.summary(for: goal).percentLabel,
            icon: goal.icon,
            color: Color(hex: goal.colorHex),
            isSelected: isSelected
        )
    }

    private func rowSubtitle(for goal: Goal) -> String {
        if let parent = goal.parentGoal {
            return parent.title.isEmpty ? "Untitled Goal" : parent.title
        }
        let summary = CadenceGoalGroupSupport.summary(for: goal)
        return "\(summary.activeGoalCount) milestones / \(summary.activeHabitCount) habits"
    }

    /// `onSelectMilestone` is only wired up in the split layout, where re-pointing `selectedID`
    /// swaps the detail pane. In the compact push stack the list rows already navigate, so the
    /// detail's milestone rows stay non-interactive there.
    private func detailView(for goal: Goal, onSelectMilestone: ((Goal) -> Void)? = nil) -> some View {
        iOSGoalDetail(
            goal: goal,
            milestones: CadenceGoalGroupSupport.milestones(for: goal),
            habits: CadenceGoalGroupSupport.habits(for: goal),
            onEdit: { editorMode = .edit(goal) },
            onNewMilestone: { editorMode = .new(goal) },
            onNewHabit: { habitEditorMode = .new(goal) },
            onSelectMilestone: onSelectMilestone
        )
    }

    @ViewBuilder
    private var detailPane: some View {
        if let goal = selected {
            detailView(for: goal) { milestone in
                selectedID = milestone.id
            }
        } else {
            iOSFeatureEmptyDetail(systemImage: "sparkles", title: "No goal selected")
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
        compactListPane
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

    private var compactListPane: some View {
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
                NavigationLink {
                    detailView(for: habit)
                } label: {
                    iOSHabitSummaryRow(
                        habit: habit,
                        todayKey: todayKey,
                        isSelected: false,
                        toggle: { toggle(habit) }
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func detailView(for habit: Habit) -> some View {
        iOSHabitDetail(
            habit: habit,
            todayKey: todayKey,
            toggle: { toggle(habit) },
            onEdit: { editorMode = .edit(habit) }
        )
    }

    @ViewBuilder
    private var detailPane: some View {
        if let habit = selected {
            detailView(for: habit)
        } else {
            iOSFeatureEmptyDetail(systemImage: "flame.fill", title: "No habit selected")
        }
    }

    private func toggle(_ habit: Habit) {
        CadenceHabitSupport.toggle(habit, on: todayKey, modelContext: modelContext)
    }
}
#endif
