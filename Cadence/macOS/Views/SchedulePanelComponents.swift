#if os(macOS)
import SwiftUI
import SwiftData
import EventKit

struct ScheduleTimeRailRow: View {
    let hour: Int
    let hourHeight: CGFloat

    var body: some View {
        Text(hourLabel)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.dim)
            .frame(width: timeLabelWidth, height: hourHeight, alignment: .topTrailing)
            .padding(.trailing, timeLabelPad)
            .offset(y: -6)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var hourLabel: String { "\(hour)" }
}

struct TaskInspectorDateControl: View {
    let label: String
    let icon: String
    var activeColor: Color = Theme.blue
    @Binding var isOn: Bool
    @Binding var date: Date

    @State private var showPicker = false
    @State private var viewMonth: Date = Calendar.current.startOfDay(for: Date())
    @State private var isHovered = false

    private let cal = Calendar.current

    private var isDoDate: Bool { icon == "calendar" }

    private var effectiveIcon: String {
        guard isOn, isDoDate else { return icon }
        return cal.isDateInToday(date) ? "star.fill" : icon
    }

    private var effectiveIconColor: Color {
        guard isOn else { return Theme.dim }
        if isDoDate && cal.isDateInToday(date) { return .yellow }
        return activeColor
    }

    private var displayLabel: String {
        guard isOn else { return label }
        return DateFormatters.relativeDate(from: DateFormatters.dateKey(from: date))
    }

    var body: some View {
        HStack(spacing: 0) {
            Button { showPicker.toggle() } label: {
                HStack(spacing: 5) {
                    Image(systemName: effectiveIcon)
                        .font(.system(size: 12))
                        .foregroundStyle(isOn ? effectiveIconColor : Theme.dim)

                    Group {
                        if isOn {
                            Text(displayLabel)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(isDoDate && cal.isDateInToday(date) ? .yellow : activeColor)
                        } else {
                            Text(label)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.dim)
                        }
                    }
                    .fixedSize()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(minHeight: 30)
                .contentShape(Rectangle())
                .background(isHovered ? activeColor.opacity(0.08) : Theme.surface.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.cadencePlain)
            .onHover { isHovered = $0 }
            .popover(isPresented: $showPicker, arrowEdge: .bottom) {
                pickerPopover
            }

            if isOn {
                Button {
                    isOn = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim.opacity(0.6))
                }
                .buttonStyle(.cadencePlain)
                .padding(.leading, 6)
            }
        }
        .onAppear {
            var comps = cal.dateComponents([.year, .month], from: isOn ? date : Date())
            comps.day = 1
            viewMonth = cal.date(from: comps) ?? Date()
        }
    }

    @ViewBuilder
    private var pickerPopover: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                quickPill("Today", offset: 0)
                quickPill("Tomorrow", offset: 1)
                quickPill("Next Week", weekOffset: true)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider().background(Theme.borderSubtle)

            MonthCalendarPanel(
                selection: Binding(
                    get: { date },
                    set: {
                        date = $0
                        isOn = true
                        showPicker = false
                    }
                ),
                viewMonth: $viewMonth,
                isOpen: $showPicker
            )

            if isOn {
                Button("Clear date") {
                    isOn = false
                    showPicker = false
                }
                .buttonStyle(.cadencePlain)
                .font(.system(size: 11))
                .foregroundStyle(Theme.red)
                .padding(.bottom, 10)
            }
        }
        .background(Theme.surfaceElevated)
    }

    @ViewBuilder
    private func quickPill(_ label: String, offset: Int = 0, weekOffset: Bool = false) -> some View {
        let target: Date = {
            let today = cal.startOfDay(for: Date())
            if weekOffset { return cal.date(byAdding: .weekOfYear, value: 1, to: today) ?? today }
            return cal.date(byAdding: .day, value: offset, to: today) ?? today
        }()
        let isSelected = isOn && cal.isDate(date, inSameDayAs: target)

        Button {
            date = target
            isOn = true
            showPicker = false
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? .white : Theme.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? activeColor : Theme.surface)
                .clipShape(Capsule())
        }
        .buttonStyle(.cadencePlain)
        .modifier(InspectorPickerHover(cornerRadius: 999))
    }
}

struct QuickCreateChoicePopover: View {
    let startMin: Int
    let endMin: Int
    let onCreateTask: (String) -> Void
    let onCreateEvent: ((String, String) -> Void)?
    let onCancel: () -> Void

    enum Mode { case timeBlock, calendarEvent }

    @Environment(CalendarManager.self) private var calendarManager
    @State private var mode: Mode = .timeBlock
    @State private var title = ""
    @State private var selectedCalendarID = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(TimeFormatters.timeRange(startMin: startMin, endMin: endMin))
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)

            if onCreateEvent != nil {
                HStack(spacing: 4) {
                    modeButton("Time Block", for: .timeBlock)
                    modeButton("Calendar Event", for: .calendarEvent)
                }
                .padding(3)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            TextField(mode == .timeBlock ? "Task title" : "Event title", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
                .focused($focused)
                .onSubmit { create() }

            if mode == .calendarEvent {
                let calendars = calendarManager.writableCalendars
                if !calendars.isEmpty {
                    CadenceCalendarPickerButton(
                        calendars: calendars,
                        selectedID: $selectedCalendarID,
                        allowNone: false,
                        style: .compact
                    )
                }
            }

            HStack(spacing: 8) {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.cadencePlain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                Spacer()
                Button("Create") { create() }
                    .buttonStyle(.cadencePlain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                    .disabled(mode == .calendarEvent && selectedCalendarID.isEmpty)
            }
        }
        .padding(14)
        .frame(width: 240)
        .background(Theme.surface)
        .onAppear {
            focused = true
            if let first = calendarManager.writableCalendars.first {
                selectedCalendarID = first.calendarIdentifier
            }
        }
    }

    private func create() {
        if mode == .timeBlock {
            onCreateTask(title)
        } else {
            onCreateEvent?(title, selectedCalendarID)
        }
    }

    @ViewBuilder
    private func modeButton(_ label: String, for target: Mode) -> some View {
        Button(label) { mode = target }
            .buttonStyle(.cadencePlain)
            .font(.system(size: 11, weight: mode == target ? .semibold : .regular))
            .foregroundStyle(mode == target ? Theme.text : Theme.dim)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(mode == target ? Theme.surface : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct TaskDetailPopover: View {
    @Bindable var task: AppTask
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query(sort: \Area.order)    private var areas:    [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Environment(\.modelContext) private var modelContext
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager

    @State private var showDatePicker = false
    @State private var showDoDatePicker = false
    @State private var showPriorityPicker = false
    @State private var dueDatePickerDate: Date = Date()
    @State private var doDatePickerDate: Date = Date()
    @State private var notesDraft = ""
    @State private var newSubtaskTitle = ""
    @FocusState private var subtaskFieldFocused: Bool

    private var taskContainerBinding: Binding<TaskContainerSelection> {
        Binding(
            get: {
                if let a = task.area    { return .area(a.id) }
                if let p = task.project { return .project(p.id) }
                return .inbox
            },
            set: { newSelection in
                switch newSelection {
                case .inbox:
                    task.area = nil; task.project = nil; task.context = nil; task.sectionName = TaskSectionDefaults.defaultName
                case .area(let id):
                    if let area = areas.first(where: { $0.id == id }) {
                        task.area = area; task.project = nil; task.context = area.context; task.sectionName = area.sectionNames.first ?? TaskSectionDefaults.defaultName
                    }
                case .project(let id):
                    if let project = projects.first(where: { $0.id == id }) {
                        task.project = project; task.area = nil; task.context = project.context; task.sectionName = project.sectionNames.first ?? TaskSectionDefaults.defaultName
                    }
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: task.containerColor).opacity(0.22))
                        .frame(width: 34, height: 34)
                        .overlay {
                            Image(systemName: task.scheduledStartMin >= 0 ? "calendar.badge.clock" : "checklist")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(hex: task.containerColor))
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Task title", text: $task.title, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1...8)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .layoutPriority(1)

                        Text(scheduleDescriptor)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.dim)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button { showPriorityPicker.toggle() } label: {
                        priorityPill(task.priority, selected: task.priority != .none)
                    }
                    .buttonStyle(.cadencePlain)
                    .fixedSize()
                    .popover(isPresented: $showPriorityPicker, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(TaskPriority.allCases, id: \.self) { priority in
                                Button {
                                    task.priority = priority
                                    showPriorityPicker = false
                                } label: {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(Theme.priorityColor(priority))
                                            .frame(width: 7, height: 7)
                                        Text(priority.label)
                                            .font(.system(size: 13))
                                            .foregroundStyle(task.priority == priority ? Theme.text : Theme.muted)
                                        Spacer()
                                        if task.priority == priority {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(Theme.blue)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(task.priority == priority ? Theme.blue.opacity(0.08) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.cadencePlain)
                                .modifier(InspectorPickerHover())
                            }
                        }
                        .padding(6)
                        .frame(width: 160)
                    }
                }

                infoCard {
                    detailRow("Time", icon: "clock") {
                        Text(task.scheduledStartMin >= 0 ? timeRange : "Not time-blocked")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(task.scheduledStartMin >= 0 ? Theme.text : Theme.dim)
                    }

                    detailRow("Do Date", icon: "calendar") {
                        TaskInspectorDateControl(
                            label: "Set do date",
                            icon: "calendar",
                            activeColor: Theme.blue,
                            isOn: Binding(
                                get: { !task.scheduledDate.isEmpty },
                                set: { isOn in
                                    if !isOn { task.scheduledDate = "" }
                                }
                            ),
                            date: Binding(
                                get: { DateFormatters.date(from: task.scheduledDate) ?? Date() },
                                set: { task.scheduledDate = DateFormatters.dateKey(from: $0) }
                            )
                        )
                    }

                    detailRow("Due", icon: "calendar.badge.exclamationmark") {
                        TaskInspectorDateControl(
                            label: "Set due date",
                            icon: "calendar.badge.exclamationmark",
                            activeColor: Theme.red,
                            isOn: Binding(
                                get: { !task.dueDate.isEmpty },
                                set: { isOn in
                                    if !isOn { task.dueDate = "" }
                                }
                            ),
                            date: Binding(
                                get: { DateFormatters.date(from: task.dueDate) ?? Date() },
                                set: { task.dueDate = DateFormatters.dateKey(from: $0) }
                            )
                        )
                    }

                    detailRow("List", icon: "tray.full") {
                        ContainerPickerBadge(selection: taskContainerBinding, contexts: contexts, areas: areas, projects: projects)
                    }

                    detailRow("Estimated", icon: "clock") {
                        EstimatePickerControl(value: $task.estimatedMinutes)
                    }

                    detailRow("Actual", icon: "clock.badge.checkmark") {
                        MinutesField(value: $task.actualMinutes)
                    }
                }

                infoCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Notes")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.dim)

                        TextEditor(text: Binding(
                            get: { task.notes },
                            set: { task.notes = $0 }
                        ))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 44)
                        .padding(8)
                        .background(Theme.surfaceElevated.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                infoCard {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Subtasks")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.dim)

                        let sortedSubtasks = (task.subtasks ?? []).sorted { $0.order < $1.order }
                        ForEach(sortedSubtasks) { subtask in
                            SubtaskRow(subtask: subtask, showDelete: true) {
                                deleteConfirmationManager.present(
                                    title: "Delete Subtask?",
                                    message: "This will permanently delete \"\(subtask.title.isEmpty ? "Untitled" : subtask.title)\"."
                                ) {
                                    modelContext.delete(subtask)
                                }
                            }
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.dim.opacity(0.6))
                            TextField("Add subtask…", text: $newSubtaskTitle)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.text)
                                .focused($subtaskFieldFocused)
                                .onSubmit { addSubtask() }
                        }
                        .padding(.vertical, 2)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        task.status = task.isDone ? .todo : .done
                    } label: {
                        Label(task.isDone ? "Unmark Done" : "Mark Done",
                              systemImage: task.isDone ? "circle" : "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(task.isDone ? Theme.dim : Theme.green)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Theme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.cadencePlain)

                    if task.scheduledStartMin >= 0 {
                        Button {
                            SchedulingActions.removeFromCalendar(task)
                            task.scheduledStartMin = -1
                            task.scheduledDate = ""
                        } label: {
                            Label("Unschedule", systemImage: "calendar.badge.minus")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.dim)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Theme.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.cadencePlain)
                    }
                }
            }
            .padding(18)
        }
        .frame(width: 380)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
        .onAppear {
            dueDatePickerDate = task.dueDate.isEmpty ? Date() : (DateFormatters.date(from: task.dueDate) ?? Date())
            doDatePickerDate  = task.scheduledDate.isEmpty ? Date() : (DateFormatters.date(from: task.scheduledDate) ?? Date())
            notesDraft = task.notes
        }
    }

    private func addSubtask() {
        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let existing = (task.subtasks ?? []).count
        let subtask = Subtask(title: trimmed)
        subtask.parentTask = task
        subtask.order = existing
        modelContext.insert(subtask)
        newSubtaskTitle = ""
    }

    private var timeRange: String {
        TimeFormatters.timeRange(startMin: task.scheduledStartMin, endMin: task.scheduledStartMin + max(task.estimatedMinutes, 5))
    }

    private var scheduleDescriptor: String {
        if task.scheduledStartMin >= 0 {
            return "Scheduled • \(timeRange)"
        }
        if !task.dueDate.isEmpty {
            return "Due \(DateFormatters.relativeDate(from: task.dueDate))"
        }
        return "Inbox task"
    }

    @ViewBuilder
    private func infoCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(14)
        .background(Theme.surface.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.borderSubtle, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func detailRow<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .frame(width: 88, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func priorityPill(_ priority: TaskPriority, selected: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Theme.priorityColor(priority))
                .frame(width: 7, height: 7)
            Text(priority.label)
                .font(.system(size: 11, weight: selected ? .semibold : .medium))
        }
        .foregroundStyle(selected ? Theme.text : Theme.muted)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(minHeight: 30)
        .contentShape(Rectangle())
        .background(selected ? Theme.surfaceElevated : Theme.surface.opacity(0.6))
        .clipShape(Capsule())
    }
}

struct InspectorPickerHover: ViewModifier {
    var cornerRadius: CGFloat = 6
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isHovered ? Theme.blue.opacity(0.06) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onHover { isHovered = $0 }
    }
}

struct MinutesField: View {
    @Binding var value: Int
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField("—", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(value > 0 ? Theme.text : Theme.dim)
                .frame(width: 52)
                .focused($focused)
                .onSubmit { commit() }
                .onChange(of: focused) { if !focused { commit() } }
            if value > 0 {
                Text("min")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }
        }
        .onAppear { text = value > 0 ? "\(value)" : "" }
        .onChange(of: value) { text = value > 0 ? "\(value)" : "" }
    }

    private func commit() {
        if let parsed = Int(text.trimmingCharacters(in: .whitespaces)), parsed >= 0 {
            value = parsed
        } else if text.trimmingCharacters(in: .whitespaces).isEmpty {
            value = 0
        }
        text = value > 0 ? "\(value)" : ""
    }
}
#endif
