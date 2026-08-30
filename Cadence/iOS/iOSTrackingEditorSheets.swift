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
    @State private var showParentGoalPicker = false
    @State private var showContextPicker = false
    /// T-322, and the same slot `iOSCalendarQuickCreateSheet` keeps for the same reason: what went
    /// wrong stays on the sheet the user is looking at, rather than travelling out with a
    /// `dismiss()` that should not have happened.
    @State private var actionError: String?

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
            _colorHex = State(initialValue: parent?.colorHex ?? Theme.blueHex)
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
            actionErrorNotice
            iOSTrackingTextField(title: "Title", placeholder: "e.g. Become more knowledgeable", text: $title)
            iOSTrackingTextField(title: "Definition of Done", placeholder: "What does done look like?", text: $desc, axis: .vertical)

            iOSTrackingPickerSection(title: "Parent Goal") {
                if mustStayTopLevel {
                    Text("This goal has milestones of its own, so it stays top-level.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    iOSChoiceValueButton(
                        title: selectedParentGoal.map { $0.title.isEmpty ? CadenceTitleNormalization.defaultGoalTitle : $0.title } ?? "None \u{2014} top-level goal",
                        color: Theme.text
                    ) {
                        showParentGoalPicker = true
                    }
                    .popover(isPresented: $showParentGoalPicker) {
                        iOSChoicePopoverList(
                            rows: [iOSChoiceRow<UUID?>(value: nil, title: "None \u{2014} top-level goal", color: Theme.dim)]
                                + parentChoices.map { goal in
                                    iOSChoiceRow(value: Optional(goal.id), title: goal.title.isEmpty ? CadenceTitleNormalization.defaultGoalTitle : goal.title, systemImage: goal.icon, color: Color(hex: goal.colorHex))
                                },
                            selection: $parentGoalID,
                            isPresented: $showParentGoalPicker
                        )
                    }
                }
            }

            iOSTrackingPickerSection(title: "Context") {
                iOSChoiceValueButton(
                    title: CadenceContextPickerSupport.selectionTitle(
                        from: contexts,
                        selectedID: contextID,
                        noneTitle: "Use Parent Context"
                    ),
                    color: Theme.text
                ) {
                    showContextPicker = true
                }
                .popover(isPresented: $showContextPicker) {
                    iOSChoicePopoverList(
                        rows: CadenceContextPickerSupport.items(
                            from: contexts,
                            selectedID: contextID,
                            noneTitle: "Use Parent Context"
                        ).map { item in
                            iOSChoiceRow<UUID?>(
                                value: item.id,
                                title: item.title,
                                systemImage: item.icon,
                                color: item.tint
                            )
                        },
                        selection: $contextID,
                        isPresented: $showContextPicker
                    )
                }
            }

            iOSTrackingPickerSection(title: "Kind") {
                iOSSegmentedChoice(
                    options: GoalKind.allCases.map { ($0, $0.label) },
                    selection: $kind
                )

                Text(kind.detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.subdued)
                    .padding(.top, 8)
            }

            iOSTrackingDateRangeSection(startDate: $startDate, endDate: $endDate)

            iOSTrackingPickerSection(title: "Progress") {
                iOSSegmentedChoice(
                    options: GoalProgressType.allCases.map { ($0, $0.label) },
                    selection: $progressType
                )

                if progressType == .hours {
                    HStack {
                        iOSTrackingFieldLabel("Target Hours")
                        Spacer()
                        TextField("Hours", value: $targetHours, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 12)
                            .frame(width: 90, height: 44)
                            .background(Theme.surface.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                    }
                    .padding(.top, 8)
                }
            }

            iOSTrackingPickerSection(title: "Status") {
                iOSSegmentedChoice(
                    options: GoalStatus.allCases.map { ($0, $0.label) },
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

    /// The same notice the calendar sheets show, in the same component, reading a string held
    /// beside the mutation that throws it (T-322).
    @ViewBuilder
    private var actionErrorNotice: some View {
        if let actionError {
            iOSEditorSection(title: nil, style: .ruled) {
                Text(actionError)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// T-322. `onSave` and `dismiss()` are reachable only through the `try` succeeding. The `nil`
    /// answer — an empty title, which `canSave` already prevents — stays a silent return and does
    /// not dismiss, the same separation `iOSCalendarQuickCreateSheet.createTask()` draws.
    private func save() {
        let goal: Goal?
        do {
            goal = try CadenceTrackingMutationSupport.saveGoal(
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
            )
        } catch {
            actionError = CadenceTrackingMutationSupport.goalSaveFailureNotice
            return
        }
        guard let goal else { return }
        actionError = nil
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
    @State private var showGoalPicker = false
    @State private var showContextPicker = false
    @State private var showReminderTimePicker = false
    /// See `iOSGoalEditorSheet.actionError` (T-322).
    @State private var actionError: String?

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
            // Clamped, not just floored: a habit written by the old `1...14` picker would other-
            // wise open on a value the picker no longer lists, and save it straight back.
            _timesPerWeek = State(
                initialValue: habit.frequencyType == .timesPerWeek
                    ? HabitFrequency.clampedWeeklyTarget(habit.targetCount)
                    : 3
            )
            _monthlyDay = State(initialValue: habit.frequencyType == .monthly ? min(max(storedDays.first ?? 1, 1), 31) : 1)
            _contextID = State(initialValue: habit.context?.id)
            _goalID = State(initialValue: habit.goal?.id)
            // An out-of-range stored minute opens unset rather than as a fabricated time, and
            // macOS's editor reads the same decision. See `CadenceHabitReminderEditing` (T-410).
            let reminder = CadenceHabitReminderEditing.editorState(for: habit.reminderMinuteOfDay)
            _hasReminder = State(initialValue: reminder.isOn)
            _reminderMinuteOfDay = State(initialValue: reminder.minuteOfDay)
        case .new(let goal):
            _title = State(initialValue: "")
            _icon = State(initialValue: "star.fill")
            _colorHex = State(initialValue: goal?.colorHex ?? Theme.blueHex)
            _frequencyType = State(initialValue: .daily)
            _selectedDays = State(initialValue: [])
            _timesPerWeek = State(initialValue: 3)
            _monthlyDay = State(initialValue: 1)
            _contextID = State(initialValue: goal?.context?.id)
            _goalID = State(initialValue: goal?.id)
            _hasReminder = State(initialValue: false)
            _reminderMinuteOfDay = State(initialValue: CadenceHabitReminderEditing.defaultMinuteOfDay)
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

    var body: some View {
        iOSTrackingEditorShell(
            title: editingHabit == nil ? "New Habit" : "Edit Habit",
            canSave: canSave,
            tint: Color(hex: colorHex),
            save: save
        ) {
            actionErrorNotice
            iOSTrackingTextField(title: "Title", placeholder: "e.g. Read for 20 minutes", text: $title)

            iOSTrackingPickerSection(title: "Goal") {
                iOSChoiceValueButton(
                    title: selectedGoal.map { goalMenuTitle(for: $0) } ?? "None",
                    color: Theme.text
                ) {
                    showGoalPicker = true
                }
                .popover(isPresented: $showGoalPicker) {
                    iOSChoicePopoverList(
                        rows: [iOSChoiceRow<UUID?>(value: nil, title: "None", color: Theme.dim)]
                            + goalChoices.map { goal in
                                iOSChoiceRow(value: Optional(goal.id), title: goalMenuTitle(for: goal), systemImage: goal.icon, color: Color(hex: goal.colorHex))
                            },
                        selection: $goalID,
                        isPresented: $showGoalPicker
                    )
                }
            }

            iOSTrackingPickerSection(title: "Context") {
                iOSChoiceValueButton(
                    title: CadenceContextPickerSupport.selectionTitle(
                        from: contexts,
                        selectedID: contextID,
                        noneTitle: "Use Goal Context"
                    ),
                    color: Theme.text
                ) {
                    showContextPicker = true
                }
                .popover(isPresented: $showContextPicker) {
                    iOSChoicePopoverList(
                        rows: CadenceContextPickerSupport.items(
                            from: contexts,
                            selectedID: contextID,
                            noneTitle: "Use Goal Context"
                        ).map { item in
                            iOSChoiceRow<UUID?>(
                                value: item.id,
                                title: item.title,
                                systemImage: item.icon,
                                color: item.tint
                            )
                        },
                        selection: $contextID,
                        isPresented: $showContextPicker
                    )
                }
            }

            iOSTrackingPickerSection(title: "Frequency") {
                // Full labels. This call site used to pass a shortened `compactLabel` set because
                // `iOSSegmentedChoice` truncated anything longer without saying so; the control now
                // wraps and scales instead, so the workaround — and the second spelling of every
                // frequency it required — is gone.
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
                Toggle(isOn: $hasReminder) {
                    iOSTrackingFieldLabel("Remind me daily")
                }
                .tint(Theme.blue)
                if hasReminder {
                    HStack {
                        iOSTrackingFieldLabel("Reminder time")
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

    private func goalMenuTitle(for goal: Goal) -> String {
        let name = goal.title.isEmpty ? CadenceTitleNormalization.defaultGoalTitle : goal.title
        guard let parent = goal.parentGoal else { return name }
        let parentName = parent.title.isEmpty ? CadenceTitleNormalization.defaultGoalTitle : parent.title
        return "\(parentName) › \(name)"
    }

    /// See `iOSGoalEditorSheet.actionErrorNotice` (T-322).
    @ViewBuilder
    private var actionErrorNotice: some View {
        if let actionError {
            iOSEditorSection(title: nil, style: .ruled) {
                Text(actionError)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// T-322, and this one had a second swallowed save under the first: `reminderMinuteOfDay` is
    /// written *after* `saveHabit` returns and was committed by its own `try?`. Both go through the
    /// reminder edit now, so a refused write cannot leave the habit saved with a reminder the store
    /// never took — the notification reconcile below would then schedule against a value only this
    /// process believes in.
    private func save() {
        let frequency = resolvedFrequency()
        let habit: Habit?
        do {
            habit = try CadenceTrackingMutationSupport.saveHabit(
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
            )
        } catch {
            actionError = CadenceTrackingMutationSupport.habitSaveFailureNotice
            return
        }
        guard let habit else { return }

        let previousReminder = habit.reminderMinuteOfDay
        habit.reminderMinuteOfDay = hasReminder ? reminderMinuteOfDay : nil
        do {
            try CadencePendingChangePersistence.commitEdit(in: modelContext) {
                habit.reminderMinuteOfDay = previousReminder
            }
        } catch {
            actionError = CadenceTrackingMutationSupport.habitSaveFailureNotice
            return
        }

        actionError = nil
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
