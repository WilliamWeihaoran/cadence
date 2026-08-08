#if os(iOS)
import SwiftData
import SwiftUI

enum iOSPursuitEditorMode: Identifiable {
    case new
    case edit(Pursuit)

    var id: String {
        switch self {
        case .new: return "new-pursuit"
        case .edit(let pursuit): return "edit-pursuit-\(pursuit.id.uuidString)"
        }
    }
}

enum iOSGoalEditorMode: Identifiable {
    case new(Pursuit?)
    case edit(Goal)

    var id: String {
        switch self {
        case .new(let pursuit): return "new-goal-\(pursuit?.id.uuidString ?? "none")"
        case .edit(let goal): return "edit-goal-\(goal.id.uuidString)"
        }
    }
}

enum iOSHabitEditorMode: Identifiable {
    case new(Pursuit?)
    case edit(Habit)

    var id: String {
        switch self {
        case .new(let pursuit): return "new-habit-\(pursuit?.id.uuidString ?? "none")"
        case .edit(let habit): return "edit-habit-\(habit.id.uuidString)"
        }
    }
}

struct iOSPursuitEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Pursuit.order) private var allPursuits: [Pursuit]
    @Query(sort: \Context.order) private var contexts: [Context]

    let mode: iOSPursuitEditorMode
    let onSave: (Pursuit) -> Void

    @State private var title: String
    @State private var desc: String
    @State private var icon: String
    @State private var colorHex: String
    @State private var kind: PursuitKind
    @State private var status: PursuitStatus
    @State private var contextID: UUID?
    @State private var showContextPicker = false

    init(mode: iOSPursuitEditorMode, onSave: @escaping (Pursuit) -> Void = { _ in }) {
        self.mode = mode
        self.onSave = onSave

        if case .edit(let pursuit) = mode {
            _title = State(initialValue: pursuit.title)
            _desc = State(initialValue: pursuit.desc)
            _icon = State(initialValue: pursuit.icon)
            _colorHex = State(initialValue: pursuit.colorHex)
            _kind = State(initialValue: pursuit.kind)
            _status = State(initialValue: pursuit.status)
            _contextID = State(initialValue: pursuit.context?.id)
        } else {
            _title = State(initialValue: "")
            _desc = State(initialValue: "")
            _icon = State(initialValue: "sparkles")
            _colorHex = State(initialValue: "#a78bfa")
            _kind = State(initialValue: .ongoing)
            _status = State(initialValue: .active)
            _contextID = State(initialValue: nil)
        }
    }

    private var editingPursuit: Pursuit? {
        if case .edit(let pursuit) = mode { return pursuit }
        return nil
    }

    private var selectedContext: Context? {
        contextID.flatMap { id in contexts.first { $0.id == id } }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        iOSTrackingEditorShell(
            title: editingPursuit == nil ? "New Pursuit" : "Edit Pursuit",
            canSave: canSave,
            tint: Color(hex: colorHex),
            save: save
        ) {
            iOSTrackingTextField(title: "Title", placeholder: "e.g. Become more knowledgeable", text: $title)
            iOSTrackingTextField(title: "Direction", placeholder: "What are you trying to cultivate?", text: $desc, axis: .vertical)

            iOSTrackingPickerSection(title: "Context") {
                iOSChoiceValueButton(title: selectedContext?.name.isEmpty == false ? selectedContext!.name : "None", color: Theme.text) {
                    showContextPicker = true
                }
                .popover(isPresented: $showContextPicker) {
                    iOSChoicePopoverList(
                        rows: [iOSChoiceRow<UUID?>(value: nil, title: "None", color: Theme.dim)]
                            + contexts.map { context in
                                iOSChoiceRow(value: Optional(context.id), title: context.name, systemImage: context.icon, color: Color(hex: context.colorHex))
                            },
                        selection: $contextID,
                        isPresented: $showContextPicker
                    )
                }
            }

            iOSTrackingPickerSection(title: "Kind") {
                iOSSegmentedChoice(
                    options: PursuitKind.allCases.map { ($0, $0.label) },
                    selection: $kind
                )
            }

            iOSTrackingPickerSection(title: "Status") {
                iOSSegmentedChoice(
                    options: PursuitStatus.allCases.map { ($0, $0.label) },
                    selection: $status
                )
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
        guard let pursuit = CadenceTrackingMutationSupport.savePursuit(
            editingPursuit,
            title: title,
            desc: desc,
            icon: icon,
            colorHex: colorHex,
            kind: kind,
            status: status,
            context: selectedContext,
            allPursuits: allPursuits,
            modelContext: modelContext
        ) else { return }
        onSave(pursuit)
        dismiss()
    }
}

struct iOSGoalEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Goal.order) private var allGoals: [Goal]
    @Query(sort: \Pursuit.order) private var allPursuits: [Pursuit]
    @Query(sort: \Context.order) private var contexts: [Context]

    let mode: iOSGoalEditorMode
    let onSave: (Goal) -> Void

    @State private var title: String
    @State private var desc: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var progressType: GoalProgressType
    @State private var targetHours: Double
    @State private var colorHex: String
    @State private var status: GoalStatus
    @State private var contextID: UUID?
    @State private var pursuitID: UUID?
    @State private var showPursuitPicker = false
    @State private var showContextPicker = false

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
            _colorHex = State(initialValue: goal.colorHex)
            _status = State(initialValue: goal.status)
            _contextID = State(initialValue: goal.context?.id)
            _pursuitID = State(initialValue: goal.pursuit?.id)
        case .new(let pursuit):
            let start = Date()
            let end = Calendar.current.date(byAdding: .month, value: 1, to: start) ?? start
            _title = State(initialValue: "")
            _desc = State(initialValue: "")
            _startDate = State(initialValue: start)
            _endDate = State(initialValue: end)
            _progressType = State(initialValue: .subtasks)
            _targetHours = State(initialValue: 0)
            _colorHex = State(initialValue: pursuit?.colorHex ?? "#4a9eff")
            _status = State(initialValue: .active)
            _contextID = State(initialValue: pursuit?.context?.id)
            _pursuitID = State(initialValue: pursuit?.id)
        }
    }

    private var editingGoal: Goal? {
        if case .edit(let goal) = mode { return goal }
        return nil
    }

    private var pursuitChoices: [Pursuit] {
        var choices = allPursuits.filter { $0.status == .active }
        if let current = editingGoal?.pursuit,
           !choices.contains(where: { $0.id == current.id }) {
            choices.insert(current, at: 0)
        }
        return choices
    }

    private var selectedContext: Context? {
        contextID.flatMap { id in contexts.first { $0.id == id } }
    }

    private var selectedPursuit: Pursuit? {
        pursuitID.flatMap { id in allPursuits.first { $0.id == id } }
    }

    private var canSave: Bool {
        PursuitAssignmentRules.canSaveMilestone(title: title, pursuitID: pursuitID)
    }

    var body: some View {
        iOSTrackingEditorShell(
            title: editingGoal == nil ? "New Milestone" : "Edit Milestone",
            canSave: canSave,
            tint: Color(hex: colorHex),
            save: save
        ) {
            iOSTrackingTextField(title: "Title", placeholder: "e.g. Pass Exam P", text: $title)
            iOSTrackingTextField(title: "Definition of Done", placeholder: "What does done look like?", text: $desc, axis: .vertical)

            iOSTrackingPickerSection(title: "Pursuit") {
                iOSChoiceValueButton(
                    title: selectedPursuit.map { $0.title.isEmpty ? "Untitled Pursuit" : $0.title } ?? "Choose Pursuit",
                    color: Theme.text
                ) {
                    showPursuitPicker = true
                }
                .popover(isPresented: $showPursuitPicker) {
                    iOSChoicePopoverList(
                        rows: [iOSChoiceRow<UUID?>(value: nil, title: "Choose Pursuit", color: Theme.dim)]
                            + pursuitChoices.map { pursuit in
                                iOSChoiceRow(value: Optional(pursuit.id), title: pursuit.title.isEmpty ? "Untitled Pursuit" : pursuit.title, systemImage: pursuit.icon, color: Color(hex: pursuit.colorHex))
                            },
                        selection: $pursuitID,
                        isPresented: $showPursuitPicker
                    )
                }
            }

            iOSTrackingPickerSection(title: "Context") {
                iOSChoiceValueButton(title: selectedContext?.name.isEmpty == false ? selectedContext!.name : "Use Pursuit Context", color: Theme.text) {
                    showContextPicker = true
                }
                .popover(isPresented: $showContextPicker) {
                    iOSChoicePopoverList(
                        rows: [iOSChoiceRow<UUID?>(value: nil, title: "Use Pursuit Context", color: Theme.dim)]
                            + contexts.map { context in
                                iOSChoiceRow(value: Optional(context.id), title: context.name, systemImage: context.icon, color: Color(hex: context.colorHex))
                            },
                        selection: $contextID,
                        isPresented: $showContextPicker
                    )
                }
            }

            iOSTrackingDateRangeSection(startDate: $startDate, endDate: $endDate)

            iOSTrackingPickerSection(title: "Progress") {
                iOSSegmentedChoice(
                    options: GoalProgressType.allCases.map { ($0, $0.label) },
                    selection: $progressType
                )

                if progressType == .hours {
                    HStack {
                        Text("Target Hours")
                        Spacer()
                        TextField("Hours", value: $targetHours, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(width: 80)
                            .background(Theme.surface.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .padding(.top, 8)
                }
            }

            iOSTrackingPickerSection(title: "Status") {
                iOSSegmentedChoice(
                    options: GoalStatus.allCases.map { ($0, $0.trackingLabel) },
                    selection: $status
                )
            }

            iOSTrackingPickerSection(title: "Color") {
                iOSTrackingColorGrid(selection: $colorHex)
            }
        }
    }

    private func save() {
        guard let selectedPursuit else { return }
        guard let goal = CadenceTrackingMutationSupport.saveGoal(
            editingGoal,
            title: title,
            desc: desc,
            startDate: DateFormatters.dateKey(from: startDate),
            endDate: DateFormatters.dateKey(from: max(startDate, endDate)),
            progressType: progressType,
            targetHours: targetHours,
            colorHex: colorHex,
            status: status,
            context: selectedContext,
            pursuit: selectedPursuit,
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
    @Query(sort: \Pursuit.order) private var allPursuits: [Pursuit]
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
    @State private var pursuitID: UUID?
    @State private var goalID: UUID?
    @State private var hasReminder: Bool
    @State private var reminderMinuteOfDay: Int
    @State private var showPursuitPicker = false
    @State private var showGoalPicker = false
    @State private var showContextPicker = false
    @State private var showReminderTimePicker = false

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
            _pursuitID = State(initialValue: habit.pursuit?.id)
            _goalID = State(initialValue: habit.goal?.id)
            _hasReminder = State(initialValue: habit.reminderMinuteOfDay != nil)
            _reminderMinuteOfDay = State(initialValue: habit.reminderMinuteOfDay ?? 9 * 60)
        case .new(let pursuit):
            _title = State(initialValue: "")
            _icon = State(initialValue: "star.fill")
            _colorHex = State(initialValue: pursuit?.colorHex ?? "#4a9eff")
            _frequencyType = State(initialValue: .daily)
            _selectedDays = State(initialValue: [])
            _timesPerWeek = State(initialValue: 3)
            _monthlyDay = State(initialValue: 1)
            _contextID = State(initialValue: pursuit?.context?.id)
            _pursuitID = State(initialValue: pursuit?.id)
            _goalID = State(initialValue: nil)
            _hasReminder = State(initialValue: false)
            _reminderMinuteOfDay = State(initialValue: 9 * 60)
        }
    }

    private var editingHabit: Habit? {
        if case .edit(let habit) = mode { return habit }
        return nil
    }

    private var pursuitChoices: [Pursuit] {
        var choices = allPursuits.filter { $0.status == .active }
        if let current = editingHabit?.pursuit,
           !choices.contains(where: { $0.id == current.id }) {
            choices.insert(current, at: 0)
        }
        return choices
    }

    private var goalChoices: [Goal] {
        allGoals.filter { goal in
            goal.status == .active && (pursuitID == nil || goal.pursuit?.id == pursuitID)
        }
    }

    private var selectedContext: Context? {
        contextID.flatMap { id in contexts.first { $0.id == id } }
    }

    private var selectedPursuit: Pursuit? {
        pursuitID.flatMap { id in allPursuits.first { $0.id == id } }
    }

    private var selectedGoal: Goal? {
        goalID.flatMap { id in allGoals.first { $0.id == id } }
    }

    private var canSave: Bool {
        PursuitAssignmentRules.canSaveHabit(title: title, pursuitID: pursuitID)
    }

    var body: some View {
        iOSTrackingEditorShell(
            title: editingHabit == nil ? "New Habit" : "Edit Habit",
            canSave: canSave,
            tint: Color(hex: colorHex),
            save: save
        ) {
            iOSTrackingTextField(title: "Title", placeholder: "e.g. Read for 20 minutes", text: $title)

            iOSTrackingPickerSection(title: "Pursuit") {
                iOSChoiceValueButton(
                    title: selectedPursuit.map { $0.title.isEmpty ? "Untitled Pursuit" : $0.title } ?? "Choose Pursuit",
                    color: Theme.text
                ) {
                    showPursuitPicker = true
                }
                .popover(isPresented: $showPursuitPicker) {
                    iOSChoicePopoverList(
                        rows: [iOSChoiceRow<UUID?>(value: nil, title: "Choose Pursuit", color: Theme.dim)]
                            + pursuitChoices.map { pursuit in
                                iOSChoiceRow(value: Optional(pursuit.id), title: pursuit.title.isEmpty ? "Untitled Pursuit" : pursuit.title, systemImage: pursuit.icon, color: Color(hex: pursuit.colorHex))
                            },
                        selection: $pursuitID,
                        isPresented: $showPursuitPicker
                    )
                }
                .onChange(of: pursuitID) { _, _ in
                    if let goalID, !goalChoices.contains(where: { $0.id == goalID }) {
                        self.goalID = nil
                    }
                }
            }

            iOSTrackingPickerSection(title: "Goal") {
                iOSChoiceValueButton(
                    title: selectedGoal.map { $0.title.isEmpty ? "Untitled Milestone" : $0.title } ?? "None",
                    color: Theme.text
                ) {
                    showGoalPicker = true
                }
                .popover(isPresented: $showGoalPicker) {
                    iOSChoicePopoverList(
                        rows: [iOSChoiceRow<UUID?>(value: nil, title: "None", color: Theme.dim)]
                            + goalChoices.map { goal in
                                iOSChoiceRow(value: Optional(goal.id), title: goal.title.isEmpty ? "Untitled Milestone" : goal.title, systemImage: "flag.fill", color: Color(hex: goal.colorHex))
                            },
                        selection: $goalID,
                        isPresented: $showGoalPicker
                    )
                }
            }

            iOSTrackingPickerSection(title: "Context") {
                iOSChoiceValueButton(title: selectedContext?.name.isEmpty == false ? selectedContext!.name : "Use Pursuit Context", color: Theme.text) {
                    showContextPicker = true
                }
                .popover(isPresented: $showContextPicker) {
                    iOSChoicePopoverList(
                        rows: [iOSChoiceRow<UUID?>(value: nil, title: "Use Pursuit Context", color: Theme.dim)]
                            + contexts.map { context in
                                iOSChoiceRow(value: Optional(context.id), title: context.name, systemImage: context.icon, color: Color(hex: context.colorHex))
                            },
                        selection: $contextID,
                        isPresented: $showContextPicker
                    )
                }
            }

            iOSTrackingPickerSection(title: "Frequency") {
                iOSSegmentedChoice(
                    options: HabitFrequency.allCases.map { ($0, $0.label) },
                    selection: $frequencyType
                )

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
                    HStack {
                        Text("Reminder time")
                        Spacer()
                        iOSChoiceValueButton(title: TimeFormatters.timeString(from: reminderMinuteOfDay), color: Theme.text) {
                            showReminderTimePicker = true
                        }
                        .popover(isPresented: $showReminderTimePicker) {
                            iOSChoicePopoverList(
                                rows: stride(from: 0, to: 1440, by: 15).map { minute in
                                    iOSChoiceRow(value: minute, title: TimeFormatters.timeString(from: minute), color: Theme.blue)
                                },
                                selection: $reminderMinuteOfDay,
                                isPresented: $showReminderTimePicker
                            )
                        }
                    }
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

    private func save() {
        guard let selectedPursuit else { return }
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
            pursuit: selectedPursuit,
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
