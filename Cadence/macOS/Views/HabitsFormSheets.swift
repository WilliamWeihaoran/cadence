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
    /// `Habit.colorHex`'s model default, read from the palette rather than re-typed (T-262).
    @State private var selectedColor = Theme.blueHex
    @State private var frequencyType: HabitFrequency = .daily
    @State private var selectedDays: Set<Int> = []
    @State private var timesPerWeek = 3
    @State private var monthlyDay = 1
    @State private var selectedContextID: UUID? = nil
    @State private var selectedGoalID: UUID? = nil
    @State private var hasReminder = false
    @State private var reminderMinuteOfDay = CadenceHabitReminderEditing.defaultMinuteOfDay

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
        let trimmed = CadenceTitleNormalization.normalized(title)
        guard !trimmed.isEmpty else { return }

        let habit = Habit(title: trimmed)
        habit.icon = selectedIcon
        habit.colorHex = selectedColor
        habit.frequencyType = frequencyType
        // `habits.count` collides after any deletion: delete the habit at order 1 of four and
        // the remaining orders are 0, 2, 3 while the count is 3, so the next habit created lands
        // on 3 twice. `@Query(sort: \.order)` then has an unstable tie and the two swap places
        // between renders and between devices. iOS's shared path already uses max + 1.
        habit.order = (habits.map(\.order).max() ?? -1) + 1
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
    @Environment(\.modelContext) private var modelContext
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
        // Clamped, not just floored: an unreachable target above 7 used to render with `+`
        // disabled and then save itself straight back unchanged.
        _timesPerWeek = State(
            initialValue: frequency == .timesPerWeek ? HabitFrequency.clampedWeeklyTarget(habit.targetCount) : 3
        )
        _monthlyDay = State(initialValue: frequency == .monthly ? min(max(storedDays.first ?? 1, 1), 31) : 1)
        _selectedContextID = State(initialValue: habit.context?.id)
        _selectedGoalID = State(initialValue: habit.goal?.id)
        // An out-of-range stored minute opens unset rather than as a fabricated time, and
        // iOS's editor reads the same decision. See `CadenceHabitReminderEditing` (T-410).
        let reminder = CadenceHabitReminderEditing.editorState(for: habit.reminderMinuteOfDay)
        _hasReminder = State(initialValue: reminder.isOn)
        _reminderMinuteOfDay = State(initialValue: reminder.minuteOfDay)
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
            onDelete: requestDelete,
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

    /// Dismisses first, then raises the app's confirmation overlay. The sheet is a separate
    /// window, so leaving it up behind the overlay would put two modal layers on screen at once.
    private func requestDelete() {
        let habit = habit
        let modelContext = modelContext
        let completionCount = (habit.completions ?? []).count
        let title = habit.title
        dismiss()
        DeleteConfirmationManager.shared.present(
            title: "Delete Habit",
            message: completionCount > 0
                ? "\"\(title)\" and its \(completionCount) recorded check-in\(completionCount == 1 ? "" : "s") will be deleted. This cannot be undone."
                : "\"\(title)\" will be deleted. This cannot be undone."
        ) {
            modelContext.deleteHabit(habit)
        }
    }

    private func save() {
        let trimmed = CadenceTitleNormalization.normalized(title)
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
    /// Present only when editing. Sits on the leading edge, away from Save, so the destructive
    /// action can never be the one a reflexive click lands on.
    var onDelete: (() -> Void)? = nil
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
                if let onDelete {
                    CadenceActionButton(
                        title: "Delete",
                        systemImage: "trash",
                        role: .ghost,
                        size: .compact,
                        tint: Theme.red,
                        action: onDelete
                    )
                }
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
