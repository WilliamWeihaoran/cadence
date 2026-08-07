#if os(macOS)
import SwiftUI
import SwiftData

struct CreateHabitSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Habit.order) private var habits: [Habit]
    @Query(sort: \Context.order) private var allContexts: [Context]
    @Query(sort: \Goal.order) private var allGoals: [Goal]

    @State private var title = ""
    @State private var selectedIcon = "star.fill"
    @State private var selectedColor = "#4a9eff"
    @State private var frequencyType: HabitFrequency = .daily
    @State private var selectedDays: Set<Int> = []
    @State private var timesPerWeek = 3
    @State private var monthlyDay = 1
    @State private var selectedContextID: UUID? = nil
    @State private var selectedGoalID: UUID? = nil
    @State private var hasReminder = false
    @State private var reminderMinuteOfDay = 9 * 60

    private let initialGoal: Goal?

    /// A habit no longer needs a parent to be saved — `goal` is only a seed for the picker.
    init(goal: Goal? = nil) {
        initialGoal = goal
        _selectedContextID = State(initialValue: goal?.context?.id)
        _selectedGoalID = State(initialValue: goal?.id)
    }

    private var goalChoices: [Goal] {
        var choices = allGoals.filter { $0.status != .done }
        if let initialGoal,
           !choices.contains(where: { $0.id == initialGoal.id }) {
            choices.insert(initialGoal, at: 0)
        }
        return choices
    }

    private var selectedGoal: Goal? {
        selectedGoalID.flatMap { id in allGoals.first { $0.id == id } }
    }

    private var canSave: Bool {
        GoalAssignmentRules.canSaveHabit(title: title)
    }

    var body: some View {
        HabitFormSheetShell(
            title: "New Habit",
            actionTitle: "Create",
            canSave: canSave,
            actionTint: nil,
            onCancel: { dismiss() },
            onSave: create
        ) {
            HabitFormFields(
                title: $title,
                selectedIcon: $selectedIcon,
                selectedColor: $selectedColor,
                frequencyType: $frequencyType,
                selectedDays: $selectedDays,
                timesPerWeek: $timesPerWeek,
                monthlyDay: $monthlyDay,
                selectedContextID: $selectedContextID,
                selectedGoalID: $selectedGoalID,
                hasReminder: $hasReminder,
                reminderMinuteOfDay: $reminderMinuteOfDay,
                contexts: allContexts,
                goals: goalChoices
            )
        }
    }

    private func create() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let habit = Habit(title: trimmed)
        habit.icon = selectedIcon
        habit.colorHex = selectedColor
        habit.frequencyType = frequencyType
        habit.order = habits.count
        habit.applyFrequency(
            frequencyType,
            selectedDays: selectedDays,
            timesPerWeek: timesPerWeek,
            monthlyDay: monthlyDay
        )
        habit.assignContext(selectedContextID: selectedContextID, contexts: allContexts, fallbackGoal: selectedGoal)
        habit.goal = selectedGoal
        habit.reminderMinuteOfDay = hasReminder ? reminderMinuteOfDay : nil

        modelContext.insert(habit)
        HabitNotificationReconcileSupport.scheduleReconcile(in: modelContext)
        dismiss()
    }
}

struct EditHabitSheet: View {
    let habit: Habit

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Context.order) private var allContexts: [Context]
    @Query(sort: \Goal.order) private var allGoals: [Goal]

    @State private var title: String
    @State private var selectedIcon: String
    @State private var selectedColor: String
    @State private var frequencyType: HabitFrequency
    @State private var selectedDays: Set<Int>
    @State private var timesPerWeek: Int
    @State private var monthlyDay: Int
    @State private var selectedContextID: UUID?
    @State private var selectedGoalID: UUID?
    @State private var hasReminder: Bool
    @State private var reminderMinuteOfDay: Int

    init(habit: Habit) {
        self.habit = habit
        let frequency = habit.frequencyType
        let storedDays = habit.frequencyDays

        _title = State(initialValue: habit.title)
        _selectedIcon = State(initialValue: habit.icon)
        _selectedColor = State(initialValue: habit.colorHex)
        _frequencyType = State(initialValue: frequency)
        _selectedDays = State(initialValue: frequency == .daysOfWeek ? Set(storedDays) : [])
        _timesPerWeek = State(initialValue: frequency == .timesPerWeek ? max(1, habit.targetCount) : 3)
        _monthlyDay = State(initialValue: frequency == .monthly ? min(max(storedDays.first ?? 1, 1), 31) : 1)
        _selectedContextID = State(initialValue: habit.context?.id)
        _selectedGoalID = State(initialValue: habit.goal?.id)
        _hasReminder = State(initialValue: habit.reminderMinuteOfDay != nil)
        _reminderMinuteOfDay = State(initialValue: habit.reminderMinuteOfDay ?? 9 * 60)
    }

    private var goalChoices: [Goal] {
        var choices = allGoals.filter { $0.status != .done }
        if let current = habit.goal,
           !choices.contains(where: { $0.id == current.id }) {
            choices.insert(current, at: 0)
        }
        return choices
    }

    private var selectedGoal: Goal? {
        selectedGoalID.flatMap { id in allGoals.first { $0.id == id } }
    }

    private var canSave: Bool {
        GoalAssignmentRules.canSaveHabit(title: title)
    }

    var body: some View {
        HabitFormSheetShell(
            title: "Edit Habit",
            actionTitle: "Save",
            canSave: canSave,
            actionTint: Color(hex: selectedColor),
            onCancel: { dismiss() },
            onSave: save
        ) {
            HabitFormFields(
                title: $title,
                selectedIcon: $selectedIcon,
                selectedColor: $selectedColor,
                frequencyType: $frequencyType,
                selectedDays: $selectedDays,
                timesPerWeek: $timesPerWeek,
                monthlyDay: $monthlyDay,
                selectedContextID: $selectedContextID,
                selectedGoalID: $selectedGoalID,
                hasReminder: $hasReminder,
                reminderMinuteOfDay: $reminderMinuteOfDay,
                contexts: allContexts,
                goals: goalChoices
            )
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        habit.title = trimmed
        habit.icon = selectedIcon
        habit.colorHex = selectedColor
        habit.frequencyType = frequencyType
        habit.applyFrequency(
            frequencyType,
            selectedDays: selectedDays,
            timesPerWeek: timesPerWeek,
            monthlyDay: monthlyDay
        )
        habit.assignContext(selectedContextID: selectedContextID, contexts: allContexts, fallbackGoal: selectedGoal)
        habit.goal = selectedGoal
        habit.reminderMinuteOfDay = hasReminder ? reminderMinuteOfDay : nil
        if let context = habit.modelContext {
            HabitNotificationReconcileSupport.scheduleReconcile(in: context)
        }
        dismiss()
    }
}

private struct HabitFormSheetShell<Content: View>: View {
    let title: String
    let actionTitle: String
    let canSave: Bool
    let actionTint: Color?
    let onCancel: () -> Void
    let onSave: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

            Divider().background(Theme.borderSubtle)

            ScrollView {
                content()
                    .padding(24)
            }

            Divider().background(Theme.borderSubtle)

            HStack {
                Spacer()
                CadenceActionButton(
                    title: "Cancel",
                    role: .ghost,
                    size: .compact,
                    action: onCancel
                )
                CadenceActionButton(
                    title: actionTitle,
                    role: .primary,
                    size: .compact,
                    tint: actionTint,
                    isDisabled: !canSave,
                    action: onSave
                )
            }
            .padding(16)
        }
        .frame(width: 460, height: 640)
        .background(Theme.surface)
    }
}

private extension Habit {
    func applyFrequency(
        _ frequencyType: HabitFrequency,
        selectedDays: Set<Int>,
        timesPerWeek: Int,
        monthlyDay: Int
    ) {
        switch frequencyType {
        case .daily:
            frequencyDays = []
            targetCount = 1
        case .daysOfWeek:
            let resolvedDays = selectedDays.isEmpty ? [Habit.weekdayIndex(for: Date())] : selectedDays.sorted()
            frequencyDays = resolvedDays
            targetCount = resolvedDays.count
        case .timesPerWeek:
            frequencyDays = [timesPerWeek]
            targetCount = timesPerWeek
        case .monthly:
            frequencyDays = [monthlyDay]
            targetCount = 1
        }
    }

    /// Falls back to the linked goal's context when no context was picked explicitly. The goal is
    /// optional now, so an unlinked habit simply ends up with no context.
    func assignContext(selectedContextID: UUID?, contexts: [Context], fallbackGoal: Goal?) {
        if let selectedContextID,
           let context = contexts.first(where: { $0.id == selectedContextID }) {
            self.context = context
        } else {
            context = fallbackGoal?.context
        }
    }
}
#endif
