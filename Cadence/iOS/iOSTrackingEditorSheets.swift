#if os(iOS)
import SwiftData
import SwiftUI

enum iOSGoalEditorMode: Identifiable {
    /// `.new(nil)` creates a top-level goal (a direction); passing a parent nests the new
    /// goal underneath it as one of that goal's milestones.
    case new(Goal?)
    case edit(Goal)

    var id: String {
        switch self {
        case .new(let parent): return "new-goal-\(parent?.id.uuidString ?? "root")"
        case .edit(let goal): return "edit-goal-\(goal.id.uuidString)"
        }
    }
}

enum iOSHabitEditorMode: Identifiable {
    /// `.new(goal)` pre-links the habit to `goal`; `nil` leaves it unlinked.
    case new(Goal?)
    case edit(Habit)

    var id: String {
        switch self {
        case .new(let goal): return "new-habit-\(goal?.id.uuidString ?? "none")"
        case .edit(let habit): return "edit-habit-\(habit.id.uuidString)"
        }
    }
}

struct iOSGoalEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Goal.order) private var allGoals: [Goal]
    @Query(sort: \Context.order) private var contexts: [Context]

    let mode: iOSGoalEditorMode
    let onSave: (Goal) -> Void

    @State private var title: String
    @State private var desc: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var progressType: GoalProgressType
    @State private var targetHours: Double
    @State private var icon: String
    @State private var colorHex: String
    @State private var kind: GoalKind
    @State private var status: GoalStatus
    @State private var contextID: UUID?
    @State private var parentGoalID: UUID?

    init(mode: iOSGoalEditorMode, onSave: @escaping (Goal) -> Void = { _ in }) {
        self.mode = mode
        self.onSave = onSave

        switch mode {
        case .edit(let goal):
            _title = State(initialValue: goal.title)
            _desc = State(initialValue: goal.desc)
            _startDate = State(initialValue: DateFormatters.date(from: goal.startDate) ?? Date())
            _endDate = State(initialValue: DateFormatters.date(from: goal.endDate) ?? Date())
            _progressType = State(initialValue: goal.progressType)
            _targetHours = State(initialValue: goal.targetHours)
            _icon = State(initialValue: goal.icon)
            _colorHex = State(initialValue: goal.colorHex)
            _kind = State(initialValue: goal.kind)
            _status = State(initialValue: goal.status)
            _contextID = State(initialValue: goal.context?.id)
            _parentGoalID = State(initialValue: goal.parentGoal?.id)
        case .new(let parent):
            let start = Date()
            let end = Calendar.current.date(byAdding: .month, value: 1, to: start) ?? start
            _title = State(initialValue: "")
            _desc = State(initialValue: "")
            _startDate = State(initialValue: start)
            _endDate = State(initialValue: end)
            _progressType = State(initialValue: .subtasks)
            _targetHours = State(initialValue: 0)
            // A goal created underneath another one reads as a milestone with a finish line;
            // a fresh top-level goal reads as a long-running direction.
            _icon = State(initialValue: parent == nil ? "sparkles" : "flag.fill")
            _colorHex = State(initialValue: parent?.colorHex ?? "#4a9eff")
            _kind = State(initialValue: parent == nil ? .ongoing : .completable)
            _status = State(initialValue: .active)
            _contextID = State(initialValue: parent?.context?.id)
            _parentGoalID = State(initialValue: parent?.id)
        }
    }

    private var editingGoal: Goal? {
        if case .edit(let goal) = mode { return goal }
        return nil
    }

    /// A top-level goal that already owns milestones stays top-level — nesting it would push
    /// its own milestones to a third level the Goals list does not render. Goals that are
    /// already nested keep their picker so an existing parent can still be changed or cleared.
    private var mustStayTopLevel: Bool {
        guard let editingGoal else { return false }
        return editingGoal.parentGoal == nil && !(editingGoal.subGoals ?? []).isEmpty
    }

    private var parentChoices: [Goal] {
        guard !mustStayTopLevel else { return [] }
        var choices = GoalAssignmentRules
            .topLevelGoals(from: allGoals)
            .filter { $0.status == .active && $0.id != editingGoal?.id }
        if let current = editingGoal?.parentGoal,
           !choices.contains(where: { $0.id == current.id }) {
            choices.insert(current, at: 0)
        }
        return choices
    }

    private var selectedContext: Context? {
        contextID.flatMap { id in contexts.first { $0.id == id } }
    }

    private var selectedParentGoal: Goal? {
        parentGoalID.flatMap { id in allGoals.first { $0.id == id } }
    }

    private var canSave: Bool {
        GoalAssignmentRules.canSaveGoal(title: title)
    }

    var body: some View {
        iOSTrackingEditorShell(
            title: editingGoal == nil ? "New Goal" : "Edit Goal",
            canSave: canSave,
            tint: Color(hex: colorHex),
            save: save
        ) {
            iOSTrackingTextField(title: "Title", placeholder: "e.g. Become more knowledgeable", text: $title)
            iOSTrackingTextField(title: "Definition of Done", placeholder: "What does done look like?", text: $desc, axis: .vertical)

            iOSTrackingPickerSection(title: "Parent Goal") {
                if mustStayTopLevel {
                    Text("This goal has milestones of its own, so it stays top-level.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Picker("Parent Goal", selection: $parentGoalID) {
                        Text("None — top-level goal").tag(Optional<UUID>.none)
                        ForEach(parentChoices) { goal in
                            Label(goal.title.isEmpty ? "Untitled Goal" : goal.title, systemImage: goal.icon)
                                .tag(Optional(goal.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            iOSTrackingPickerSection(title: "Context") {
                Picker("Context", selection: $contextID) {
                    Text("Use Parent Context").tag(Optional<UUID>.none)
                    ForEach(contexts) { context in
                        Label(context.name, systemImage: context.icon).tag(Optional(context.id))
                    }
                }
                .pickerStyle(.menu)
            }

            iOSTrackingPickerSection(title: "Kind") {
                Picker("Kind", selection: $kind) {
                    ForEach(GoalKind.allCases, id: \.self) { kind in
                        Label(kind.label, systemImage: kind.systemImage).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                Text(kind.detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .padding(.top, 8)
            }

            iOSTrackingDateRangeSection(startDate: $startDate, endDate: $endDate)

            iOSTrackingPickerSection(title: "Progress") {
                Picker("Progress", selection: $progressType) {
                    ForEach(GoalProgressType.allCases, id: \.self) { type in
                        Text(type.label).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                if progressType == .hours {
                    Stepper(value: $targetHours, in: 0...10_000, step: 1) {
                        HStack {
                            Text("Target Hours")
                            Spacer()
                            Text("\(Int(targetHours))h")
                                .foregroundStyle(Theme.dim)
                        }
                    }
                    .padding(.top, 8)
                }
            }

            iOSTrackingPickerSection(title: "Status") {
                Picker("Status", selection: $status) {
                    ForEach(GoalStatus.allCases, id: \.self) { status in
                        Text(status.label).tag(status)
                    }
                }
                .pickerStyle(.segmented)
            }

            iOSTrackingPickerSection(title: "Icon") {
                iOSTrackingIconGrid(selection: $icon)
            }

            iOSTrackingPickerSection(title: "Color") {
                iOSTrackingColorGrid(selection: $colorHex)
            }
        }
    }

    private func save() {
        guard let goal = CadenceTrackingMutationSupport.saveGoal(
            editingGoal,
            title: title,
            desc: desc,
            startDate: DateFormatters.dateKey(from: startDate),
            endDate: DateFormatters.dateKey(from: max(startDate, endDate)),
            progressType: progressType,
            targetHours: targetHours,
            icon: icon,
            colorHex: colorHex,
            kind: kind,
            status: status,
            context: selectedContext,
            parentGoal: selectedParentGoal,
            allGoals: allGoals,
            modelContext: modelContext
        ) else { return }
        onSave(goal)
        dismiss()
    }
}

struct iOSHabitEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Habit.order) private var allHabits: [Habit]
    @Query(sort: \Goal.order) private var allGoals: [Goal]
    @Query(sort: \Context.order) private var contexts: [Context]

    let mode: iOSHabitEditorMode
    let onSave: (Habit) -> Void

    @State private var title: String
    @State private var icon: String
    @State private var colorHex: String
    @State private var frequencyType: HabitFrequency
    @State private var selectedDays: Set<Int>
    @State private var timesPerWeek: Int
    @State private var monthlyDay: Int
    @State private var contextID: UUID?
    @State private var goalID: UUID?
    @State private var hasReminder: Bool
    @State private var reminderMinuteOfDay: Int

    init(mode: iOSHabitEditorMode, onSave: @escaping (Habit) -> Void = { _ in }) {
        self.mode = mode
        self.onSave = onSave

        switch mode {
        case .edit(let habit):
            let storedDays = habit.frequencyDays
            _title = State(initialValue: habit.title)
            _icon = State(initialValue: habit.icon)
            _colorHex = State(initialValue: habit.colorHex)
            _frequencyType = State(initialValue: habit.frequencyType)
            _selectedDays = State(initialValue: habit.frequencyType == .daysOfWeek ? Set(storedDays) : [])
            _timesPerWeek = State(initialValue: habit.frequencyType == .timesPerWeek ? max(1, habit.targetCount) : 3)
            _monthlyDay = State(initialValue: habit.frequencyType == .monthly ? min(max(storedDays.first ?? 1, 1), 31) : 1)
            _contextID = State(initialValue: habit.context?.id)
            _goalID = State(initialValue: habit.goal?.id)
            _hasReminder = State(initialValue: habit.reminderMinuteOfDay != nil)
            _reminderMinuteOfDay = State(initialValue: habit.reminderMinuteOfDay ?? 9 * 60)
        case .new(let goal):
            _title = State(initialValue: "")
            _icon = State(initialValue: "star.fill")
            _colorHex = State(initialValue: goal?.colorHex ?? "#4a9eff")
            _frequencyType = State(initialValue: .daily)
            _selectedDays = State(initialValue: [])
            _timesPerWeek = State(initialValue: 3)
            _monthlyDay = State(initialValue: 1)
            _contextID = State(initialValue: goal?.context?.id)
            _goalID = State(initialValue: goal?.id)
            _hasReminder = State(initialValue: false)
            _reminderMinuteOfDay = State(initialValue: 9 * 60)
        }
    }

    private var editingHabit: Habit? {
        if case .edit(let habit) = mode { return habit }
        return nil
    }

    /// Top-level goals first, each immediately followed by its own milestones, so the menu
    /// reads as the same outline the Goals screen shows.
    private var goalChoices: [Goal] {
        var choices: [Goal] = []
        for goal in GoalAssignmentRules.topLevelGoals(from: allGoals) where goal.status == .active {
            choices.append(goal)
            choices.append(contentsOf: GoalAssignmentRules.milestones(of: goal).filter { $0.status == .active })
        }
        if let current = editingHabit?.goal,
           !choices.contains(where: { $0.id == current.id }) {
            choices.insert(current, at: 0)
        }
        return choices
    }

    private var selectedContext: Context? {
        contextID.flatMap { id in contexts.first { $0.id == id } }
    }

    private var selectedGoal: Goal? {
        goalID.flatMap { id in allGoals.first { $0.id == id } }
    }

    private var canSave: Bool {
        GoalAssignmentRules.canSaveHabit(title: title)
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: reminderMinuteOfDay / 60,
                    minute: reminderMinuteOfDay % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                reminderMinuteOfDay = ((comps.hour ?? 9) * 60) + (comps.minute ?? 0)
            }
        )
    }

    var body: some View {
        iOSTrackingEditorShell(
            title: editingHabit == nil ? "New Habit" : "Edit Habit",
            canSave: canSave,
            tint: Color(hex: colorHex),
            save: save
        ) {
            iOSTrackingTextField(title: "Title", placeholder: "e.g. Read for 20 minutes", text: $title)

            iOSTrackingPickerSection(title: "Goal") {
                Picker("Goal", selection: $goalID) {
                    Text("None").tag(Optional<UUID>.none)
                    ForEach(goalChoices) { goal in
                        Label(goalMenuTitle(for: goal), systemImage: goal.icon)
                            .tag(Optional(goal.id))
                    }
                }
                .pickerStyle(.menu)
            }

            iOSTrackingPickerSection(title: "Context") {
                Picker("Context", selection: $contextID) {
                    Text("Use Goal Context").tag(Optional<UUID>.none)
                    ForEach(contexts) { context in
                        Label(context.name, systemImage: context.icon).tag(Optional(context.id))
                    }
                }
                .pickerStyle(.menu)
            }

            iOSTrackingPickerSection(title: "Frequency") {
                Picker("Frequency", selection: $frequencyType) {
                    ForEach(HabitFrequency.allCases, id: \.self) { frequency in
                        Text(frequency.label).tag(frequency)
                    }
                }
                .pickerStyle(.segmented)

                iOSHabitFrequencyEditor(
                    frequencyType: frequencyType,
                    selectedDays: $selectedDays,
                    timesPerWeek: $timesPerWeek,
                    monthlyDay: $monthlyDay
                )
                .padding(.top, 10)
            }

            iOSTrackingPickerSection(title: "Reminder") {
                Toggle("Remind me daily", isOn: $hasReminder)
                if hasReminder {
                    DatePicker(
                        "Reminder time",
                        selection: reminderTimeBinding,
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .padding(.top, 8)
                }
            }

            iOSTrackingPickerSection(title: "Icon") {
                iOSTrackingIconGrid(selection: $icon)
            }

            iOSTrackingPickerSection(title: "Color") {
                iOSTrackingColorGrid(selection: $colorHex)
            }
        }
    }

    private func goalMenuTitle(for goal: Goal) -> String {
        let name = goal.title.isEmpty ? "Untitled Goal" : goal.title
        guard let parent = goal.parentGoal else { return name }
        let parentName = parent.title.isEmpty ? "Untitled Goal" : parent.title
        return "\(parentName) › \(name)"
    }

    private func save() {
        let frequency = resolvedFrequency()
        guard let habit = CadenceTrackingMutationSupport.saveHabit(
            editingHabit,
            title: title,
            icon: icon,
            colorHex: colorHex,
            frequencyType: frequencyType,
            frequencyDays: frequency.days,
            targetCount: frequency.targetCount,
            context: selectedContext,
            goal: selectedGoal,
            allHabits: allHabits,
            modelContext: modelContext
        ) else { return }
        habit.reminderMinuteOfDay = hasReminder ? reminderMinuteOfDay : nil
        try? modelContext.save()
        HabitNotificationReconcileSupport.scheduleReconcile(in: modelContext)
        onSave(habit)
        dismiss()
    }

    private func resolvedFrequency() -> (days: [Int], targetCount: Int) {
        switch frequencyType {
        case .daily:
            return ([], 1)
        case .daysOfWeek:
            let days = selectedDays.isEmpty ? [Habit.weekdayIndex(for: Date())] : selectedDays.sorted()
            return (days, days.count)
        case .timesPerWeek:
            return ([timesPerWeek], timesPerWeek)
        case .monthly:
            return ([monthlyDay], 1)
        }
    }
}

#endif
