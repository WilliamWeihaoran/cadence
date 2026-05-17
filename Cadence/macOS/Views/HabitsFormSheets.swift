#if os(macOS)
import SwiftUI
import SwiftData

struct CreateHabitSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Habit.order) private var habits: [Habit]
    @Query(sort: \Context.order) private var allContexts: [Context]
    @Query(sort: \Pursuit.order) private var allPursuits: [Pursuit]

    @State private var title = ""
    @State private var selectedIcon = "star.fill"
    @State private var selectedColor = "#4a9eff"
    @State private var frequencyType: HabitFrequency = .daily
    @State private var selectedDays: Set<Int> = []
    @State private var timesPerWeek = 3
    @State private var monthlyDay = 1
    @State private var selectedContextID: UUID? = nil
    @State private var selectedPursuitID: UUID? = nil
    @State private var showCreatePursuit = false

    private let initialPursuit: Pursuit?

    init(pursuit: Pursuit? = nil) {
        initialPursuit = pursuit
        _selectedContextID = State(initialValue: pursuit?.context?.id)
        _selectedPursuitID = State(initialValue: pursuit?.id)
    }

    private var pursuitChoices: [Pursuit] {
        var choices = allPursuits.filter { $0.status == .active }
        if let initialPursuit,
           !choices.contains(where: { $0.id == initialPursuit.id }) {
            choices.insert(initialPursuit, at: 0)
        }
        return choices
    }

    private var selectedContext: Context? {
        selectedContextID.flatMap { id in allContexts.first { $0.id == id } }
    }

    private var canSave: Bool {
        PursuitAssignmentRules.canSaveHabit(title: title, pursuitID: selectedPursuitID)
    }

    var body: some View {
        HabitFormSheetShell(
            title: "New Habit",
            actionTitle: "Create",
            canSave: canSave,
            actionTint: nil,
            showCreatePursuit: $showCreatePursuit,
            selectedContextID: $selectedContextID,
            selectedPursuitID: $selectedPursuitID,
            selectedContext: selectedContext,
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
                selectedPursuitID: $selectedPursuitID,
                contexts: allContexts,
                pursuits: pursuitChoices,
                onCreatePursuit: { showCreatePursuit = true }
            )
        }
    }

    private func create() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard let selectedPursuit = selectedPursuitID.flatMap({ id in allPursuits.first { $0.id == id } }) else { return }

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
        habit.assignContext(selectedContextID: selectedContextID, contexts: allContexts, fallbackPursuit: selectedPursuit)
        habit.pursuit = selectedPursuit

        modelContext.insert(habit)
        dismiss()
    }
}

struct EditHabitSheet: View {
    let habit: Habit

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Context.order) private var allContexts: [Context]
    @Query(sort: \Pursuit.order) private var allPursuits: [Pursuit]

    @State private var title: String
    @State private var selectedIcon: String
    @State private var selectedColor: String
    @State private var frequencyType: HabitFrequency
    @State private var selectedDays: Set<Int>
    @State private var timesPerWeek: Int
    @State private var monthlyDay: Int
    @State private var selectedContextID: UUID?
    @State private var selectedPursuitID: UUID?
    @State private var showCreatePursuit = false

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
        _selectedPursuitID = State(initialValue: habit.pursuit?.id)
    }

    private var pursuitChoices: [Pursuit] {
        var choices = allPursuits.filter { $0.status == .active }
        if let current = habit.pursuit,
           !choices.contains(where: { $0.id == current.id }) {
            choices.insert(current, at: 0)
        }
        return choices
    }

    private var selectedContext: Context? {
        selectedContextID.flatMap { id in allContexts.first { $0.id == id } }
    }

    private var canSave: Bool {
        PursuitAssignmentRules.canSaveHabit(title: title, pursuitID: selectedPursuitID)
    }

    var body: some View {
        HabitFormSheetShell(
            title: "Edit Habit",
            actionTitle: "Save",
            canSave: canSave,
            actionTint: Color(hex: selectedColor),
            showCreatePursuit: $showCreatePursuit,
            selectedContextID: $selectedContextID,
            selectedPursuitID: $selectedPursuitID,
            selectedContext: selectedContext,
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
                selectedPursuitID: $selectedPursuitID,
                contexts: allContexts,
                pursuits: pursuitChoices,
                onCreatePursuit: { showCreatePursuit = true }
            )
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let selectedPursuit = selectedPursuitID.flatMap({ id in allPursuits.first { $0.id == id } }) else { return }

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
        habit.assignContext(selectedContextID: selectedContextID, contexts: allContexts, fallbackPursuit: selectedPursuit)
        habit.pursuit = selectedPursuit
        dismiss()
    }
}

private struct HabitFormSheetShell<Content: View>: View {
    let title: String
    let actionTitle: String
    let canSave: Bool
    let actionTint: Color?
    @Binding var showCreatePursuit: Bool
    @Binding var selectedContextID: UUID?
    @Binding var selectedPursuitID: UUID?
    let selectedContext: Context?
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
        .sheet(isPresented: $showCreatePursuit) {
            CreatePursuitSheet(context: selectedContext) { pursuit in
                selectedPursuitID = pursuit.id
                if selectedContextID == nil {
                    selectedContextID = pursuit.context?.id
                }
            }
        }
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

    func assignContext(selectedContextID: UUID?, contexts: [Context], fallbackPursuit: Pursuit) {
        if let selectedContextID,
           let context = contexts.first(where: { $0.id == selectedContextID }) {
            self.context = context
        } else {
            context = fallbackPursuit.context
        }
    }
}
#endif
