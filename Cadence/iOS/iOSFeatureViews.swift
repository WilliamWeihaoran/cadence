#if os(iOS)
import SwiftData
import SwiftUI

/// Goals screen. Top-level goals are the long-running directions that used to live in their
/// own model; each is listed with its milestones (`subGoals`) nested directly underneath it.
struct iOSGoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Goal.order) private var goals: [Goal]
    @State private var selectedID: UUID?
    @State private var editorMode: iOSGoalEditorMode?
    @State private var habitEditorMode: iOSHabitEditorMode?
    @State private var pendingDeleteID: UUID?

    private var pendingDelete: Goal? {
        guard let pendingDeleteID else { return nil }
        return goals.first { $0.id == pendingDeleteID }
    }

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

    /// A selected id that no longer resolves falls through to the default rather than resolving to
    /// nothing: the goal can disappear from under the selection at any time — deleted on the Mac
    /// and arriving over CloudKit, or deleted from the compact list — and returning `nil` there
    /// left the iPad detail pane reading "No goal selected" for as long as the view stayed alive,
    /// with no way to pick anything again.
    private var selected: Goal? {
        if let selectedID, let match = goals.first(where: { $0.id == selectedID }) {
            return match
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
        .iOSHidesCompactNavigationBar()
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
        .alert(
            "Delete \(pendingDelete?.isTopLevel == true ? "Goal" : "Milestone")?",
            isPresented: Binding(get: { pendingDeleteID != nil }, set: { if !$0 { pendingDeleteID = nil } })
        ) {
            Button("Delete", role: .destructive, action: deletePendingGoal)
            Button("Cancel", role: .cancel) { pendingDeleteID = nil }
        } message: {
            Text(deleteMessage)
        }
    }

    /// Names what actually goes, because the cascade is asymmetric: milestones die with their
    /// parent, but the tasks, habits and lists the goal organised are the user's real work and
    /// survive with their link severed.
    private var deleteMessage: String {
        guard let goal = pendingDelete else { return "" }
        // The whole nested subtree, which is what `deleteGoal` removes — counting direct children
        // alone said "1 milestone" for a goal → milestone → sub-milestone tree and deleted two.
        let milestoneCount = GoalAssignmentRules.nestedGoalCount(under: goal)
        let nested = milestoneCount == 1 ? "its 1 milestone" : "its \(milestoneCount) milestones"
        let scope = milestoneCount == 0 ? "This deletes the goal." : "This deletes the goal and \(nested)."
        return "\(scope) Linked tasks, habits and lists are kept."
    }

    private func deletePendingGoal() {
        guard let goal = pendingDelete else { return }
        if selectedID == goal.id || goal.subGoals?.contains(where: { $0.id == selectedID }) == true {
            selectedID = nil
        }
        pendingDeleteID = nil
        modelContext.deleteGoal(goal)
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

    /// The eyebrow says what the title cannot. "PROGRESS / Goals" was a label over a label; this
    /// is the shape of the tree underneath it.
    private var shapeEyebrow: String {
        let milestoneCount = topLevelGoals.reduce(0) { $0 + milestones(of: $1).count }
        guard !topLevelGoals.isEmpty else { return "Nothing in flight" }
        let directions = topLevelGoals.count == 1 ? "1 direction" : "\(topLevelGoals.count) directions"
        let nested = milestoneCount == 1 ? "1 milestone" : "\(milestoneCount) milestones"
        return "\(directions) · \(nested)"
    }

    private var listPane: some View {
        iOSFeatureListPane(
            eyebrow: shapeEyebrow,
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
                .buttonStyle(.iosPressable)
                .contextMenu { deleteMenuItem(for: goal) }

                ForEach(milestones(of: goal)) { milestone in
                    Button {
                        selectedID = milestone.id
                    } label: {
                        goalRow(milestone, isSelected: selected?.id == milestone.id)
                    }
                    .buttonStyle(.iosPressable)
                    .contextMenu { deleteMenuItem(for: milestone) }
                    .padding(.leading, 16)
                }
            }
        }
    }

    private var compactListPane: some View {
        iOSFeatureListPane(
            eyebrow: shapeEyebrow,
            title: "Goals",
            count: activeGoals.count,
            emptyTitle: "No goals yet",
            emptySubtitle: "Create a direction, then nest milestones and habits underneath it.",
            emptyIcon: "sparkles",
            actionTitle: "New Goal",
            actionSystemImage: "plus",
            action: { editorMode = .new(nil) },
            onBack: { dismiss() }
        ) {
            ForEach(topLevelGoals) { goal in
                NavigationLink {
                    pushedDetailView(for: goal)
                } label: {
                    goalRow(goal, isSelected: false)
                }
                .buttonStyle(.iosPressable)
                .contextMenu { deleteMenuItem(for: goal) }

                ForEach(milestones(of: goal)) { milestone in
                    NavigationLink {
                        pushedDetailView(for: milestone)
                    } label: {
                        goalRow(milestone, isSelected: false)
                    }
                    .buttonStyle(.iosPressable)
                    .contextMenu { deleteMenuItem(for: milestone) }
                    .padding(.leading, 16)
                }
            }
        }
    }

    /// Long-press on the row rather than a button on the detail: in the compact push stack the
    /// detail is the pushed view, so deleting from inside it would leave a screen bound to a row
    /// that no longer exists.
    private func deleteMenuItem(for goal: Goal) -> some View {
        Button(role: .destructive) {
            pendingDeleteID = goal.id
        } label: {
            Label(goal.isTopLevel ? "Delete Goal" : "Delete Milestone", systemImage: "trash")
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

    private func detailView(for goal: Goal, showsBackControl: Bool = false) -> some View {
        iOSGoalDetail(
            goal: goal,
            milestones: CadenceGoalGroupSupport.milestones(for: goal),
            habits: CadenceGoalGroupSupport.habits(for: goal),
            onEdit: { editorMode = .edit(goal) },
            onNewMilestone: { editorMode = .new(goal) },
            onNewHabit: { habitEditorMode = .new(goal) },
            showsBackControl: showsBackControl
        )
    }

    /// The compact push stack's copy, which draws its own back chevron because the navigation bar
    /// it would otherwise sit in is hidden.
    private func pushedDetailView(for goal: Goal) -> some View {
        detailView(for: goal, showsBackControl: true)
    }

    @ViewBuilder
    private var detailPane: some View {
        if let goal = selected {
            detailView(for: goal)
        } else {
            iOSFeatureEmptyDetail(systemImage: "sparkles", title: "No goal selected")
        }
    }
}

struct iOSHabitsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Habit.order) private var habits: [Habit]
    @State private var selectedID: UUID?
    @State private var editorMode: iOSHabitEditorMode?
    @State private var pendingDeleteID: UUID?

    private var pendingDelete: Habit? {
        guard let pendingDeleteID else { return nil }
        return habits.first { $0.id == pendingDeleteID }
    }

    private var todayKey: String { DateFormatters.todayKey() }

    /// As on the goals screen: a selected id that no longer resolves falls through to the default
    /// rather than leaving the detail pane permanently empty.
    private var selected: Habit? {
        if let selectedID, let match = habits.first(where: { $0.id == selectedID }) {
            return match
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
        .iOSHidesCompactNavigationBar()
        .onAppear {
            selectedID = selectedID ?? selected?.id
        }
        .sheet(item: $editorMode) { mode in
            iOSHabitEditorSheet(mode: mode) { habit in
                selectedID = habit.id
            }
        }
        .alert(
            "Delete Habit?",
            isPresented: Binding(get: { pendingDeleteID != nil }, set: { if !$0 { pendingDeleteID = nil } })
        ) {
            Button("Delete", role: .destructive, action: deletePendingHabit)
            Button("Cancel", role: .cancel) { pendingDeleteID = nil }
        } message: {
            Text(deleteMessage)
        }
    }

    /// A habit's completion history has nowhere else to live, so it goes with the habit — unlike a
    /// goal's tasks and lists, which survive. The reminder is cancelled by `deleteHabit`; habit
    /// reminders repeat on time-of-day, so a surviving request would fire the deleted habit's
    /// title every day until the next `scenePhase` reconcile.
    private var deleteMessage: String {
        guard let habit = pendingDelete else { return "" }
        let count = (habit.completions ?? []).count
        let history = count == 1 ? "1 recorded completion" : "\(count) recorded completions"
        return "This deletes the habit and \(history)."
    }

    private func deletePendingHabit() {
        guard let habit = pendingDelete else { return }
        if selectedID == habit.id {
            selectedID = nil
        }
        pendingDeleteID = nil
        modelContext.deleteHabit(habit)
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

    /// The header eyebrow says what the title cannot — how today is actually going. "HABITS /
    /// Habits" told the reader the name of the screen they were already looking at, twice.
    private var todayEyebrow: String {
        guard !dueToday.isEmpty else { return "Nothing due today" }
        let done = dueToday.filter { $0.isDone(on: todayKey) }.count
        return "\(done) of \(dueToday.count) done today"
    }

    private var listPane: some View {
        iOSFeatureListPane(
            eyebrow: todayEyebrow,
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
                habitRow(habit, isSelected: selected?.id == habit.id) {
                    Button {
                        selectedID = habit.id
                    } label: {
                        iOSHabitSummaryRow(habit: habit, todayKey: todayKey, isSelected: selected?.id == habit.id)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var compactListPane: some View {
        iOSFeatureListPane(
            eyebrow: todayEyebrow,
            title: "Habits",
            count: habits.count,
            emptyTitle: "No habits yet",
            emptySubtitle: "Create repeating commitments and track today.",
            emptyIcon: "flame.fill",
            actionTitle: "New Habit",
            actionSystemImage: "plus",
            action: { editorMode = .new(nil) },
            onBack: { dismiss() }
        ) {
            ForEach(habits) { habit in
                habitRow(habit, isSelected: false) {
                    NavigationLink {
                        detailView(for: habit, showsBackControl: true)
                    } label: {
                        iOSHabitSummaryRow(habit: habit, todayKey: todayKey, isSelected: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// The check-in control is layered *over* the row's select/navigate control rather than
    /// nested inside its label — a nested button never sees the tap on iOS, so checking a habit
    /// off from the list used to do nothing but open the detail. The row reserves exactly
    /// `iOSHabitCheckInSize` at its trailing edge for it.
    private func habitRow<Row: View>(
        _ habit: Habit,
        isSelected: Bool,
        @ViewBuilder row: () -> Row
    ) -> some View {
        ZStack(alignment: .trailing) {
            row()

            iOSHabitCheckInButton(habit: habit, todayKey: todayKey) {
                toggle(habit)
            }
            .padding(.trailing, 4)
        }
        .contextMenu { deleteMenuItem(for: habit) }
    }

    private func detailView(for habit: Habit, showsBackControl: Bool = false) -> some View {
        iOSHabitDetail(
            habit: habit,
            todayKey: todayKey,
            toggle: { toggle(habit) },
            onEdit: { editorMode = .edit(habit) },
            showsBackControl: showsBackControl
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

    /// Long-press on the row, for the same reason goals use one: in the compact push stack the
    /// detail *is* the pushed view.
    private func deleteMenuItem(for habit: Habit) -> some View {
        Button(role: .destructive) {
            pendingDeleteID = habit.id
        } label: {
            Label("Delete Habit", systemImage: "trash")
        }
    }

    private func toggle(_ habit: Habit) {
        CadenceHabitSupport.toggle(habit, on: todayKey, modelContext: modelContext)
    }
}
#endif
