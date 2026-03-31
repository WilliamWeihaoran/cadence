#if os(macOS)
import SwiftUI
import SwiftData

struct CreateTaskSheet: View {
    let seed: TaskCreationSeed
    let dismissAction: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(TaskCreationManager.self) private var taskCreationManager
    @Query(sort: \Context.order)  private var contexts:  [Context]
    @Query(sort: \Area.order)     private var areas:     [Area]
    @Query(sort: \Project.order)  private var projects:  [Project]

    @State private var title:             String
    @State private var notes:             String
    @State private var selectedPriority:  TaskPriority
    @State private var selectedContainer: TaskContainerSelection
    @State private var selectedSectionName: String
    @State private var hasDueDate:        Bool
    @State private var dueDate:           Date
    @State private var hasDoDate:         Bool
    @State private var doDate:            Date
    @State private var estimatedMinutes:  Int
    @State private var subtaskTitles:     [String] = []

    @State private var showPriorityPicker  = false
    @State private var showEstimatePicker  = false
    @State private var showSuccess         = false
    @FocusState private var focusedSubtask: Int?

    init(seed: TaskCreationSeed, dismissAction: (() -> Void)? = nil) {
        self.seed = seed
        self.dismissAction = dismissAction
        let resolvedDueDate = DateFormatters.date(from: seed.dueDateKey) ?? Date()
        let resolvedDoDate  = DateFormatters.date(from: seed.doDateKey)  ?? Date()
        _title             = State(initialValue: seed.title)
        _notes             = State(initialValue: seed.notes)
        _selectedPriority  = State(initialValue: seed.priority)
        _selectedContainer = State(initialValue: seed.container)
        _selectedSectionName = State(initialValue: seed.sectionName)
        _hasDueDate        = State(initialValue: !seed.dueDateKey.isEmpty)
        _dueDate           = State(initialValue: resolvedDueDate)
        _hasDoDate         = State(initialValue: true)
        _doDate            = State(initialValue: resolvedDoDate)
        _estimatedMinutes  = State(initialValue: 30)
    }

    var body: some View {
        ZStack {
        VStack(alignment: .leading, spacing: 0) {

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    // ── Title row: circle + field ─────────────────────────────
                    HStack(alignment: .center, spacing: 10) {
                        Circle()
                            .strokeBorder(Theme.dim.opacity(0.4), lineWidth: 1.5)
                            .frame(width: 16, height: 16)

                        TextField("What needs doing?", text: $title)
                            .textFieldStyle(.plain)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .onSubmit { if !trimmedTitle.isEmpty { createTask() } }
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 8)

                    // ── Notes (borderless, placeholder via overlay) ──────────
                    ZStack(alignment: .topLeading) {
                        if notes.isEmpty {
                            Text("Notes")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.dim.opacity(0.45))
                                .padding(.top, 4)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $notes)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.text)
                            .scrollContentBackground(.hidden)
                            .frame(height: 60)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 8) {
                    ContainerPickerBadge(selection: $selectedContainer, contexts: contexts, areas: areas, projects: projects)

                    if showsSectionPicker {
                        TaskSectionPickerBadge(
                            selection: $selectedSectionName,
                            sections: availableSections
                        )
                    }
                }
                .frame(width: 188, alignment: .topTrailing)
                .padding(.top, 6)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)

            // ── Subtasks ──────────────────────────────────────────────────────
            if !subtaskTitles.isEmpty {
                VStack(spacing: 0) {
                    ForEach(subtaskTitles.indices, id: \.self) { i in
                        HStack(spacing: 8) {
                            Circle()
                                .strokeBorder(Theme.dim.opacity(0.3), lineWidth: 1)
                                .frame(width: 12, height: 12)
                            TextField("Subtask", text: $subtaskTitles[i])
                                .textFieldStyle(.plain)
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.text)
                                .focused($focusedSubtask, equals: i)
                                .onSubmit {
                                    subtaskTitles.append("")
                                    focusedSubtask = subtaskTitles.count - 1
                                }
                            Button {
                                subtaskTitles.remove(at: i)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Theme.dim.opacity(0.5))
                            }
                            .buttonStyle(.cadencePlain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 5)
                    }
                }
            }

            // Add subtask button
            Button {
                subtaskTitles.append("")
                focusedSubtask = subtaskTitles.count - 1
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Add Subtask")
                        .font(.system(size: 12))
                }
                .foregroundStyle(Theme.dim.opacity(0.7))
            }
            .buttonStyle(.cadencePlain)
            .padding(.leading, 16)
            .padding(.bottom, 10)

            Divider().background(Theme.borderSubtle)

            // ── Metadata toolbar: do date | estimate ··· due date ───────────
            HStack(spacing: 0) {
                TaskDateControl(label: "Do Date",
                                icon: "calendar",
                                activeColor: Theme.blue,
                                isOn: $hasDoDate, date: $doDate)

                toolbarDivider

                estimateButton

                Spacer(minLength: 0)

                toolbarDivider

                TaskDateControl(label: "Due Date",
                                icon: "flag.fill",
                                activeColor: Theme.red,
                                isOn: $hasDueDate, date: $dueDate)
            }
            .frame(height: 56)
            .background(Theme.surfaceElevated)

            Divider().background(Theme.borderSubtle)

            // ── Footer: priority left, actions right ─────────────────────────
            HStack(spacing: 0) {
                priorityButton
                Spacer(minLength: 0)
                Button("Cancel") { dismiss() }
                    .buttonStyle(.cadencePlain)
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                Button("Create Task") { createTask() }
                    .buttonStyle(.cadencePlain)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .disabled(trimmedTitle.isEmpty)
                    .opacity(trimmedTitle.isEmpty ? 0.5 : 1)
                    .padding(.trailing, 12)
            }
            .padding(.vertical, 8)
            .background(Theme.surfaceElevated)
        }
        .frame(width: 680)
        .background(Theme.surface)
        .onAppear { normalizeSelectedSection() }
        .onChange(of: selectedContainer) { _, _ in
            normalizeSelectedSection()
        }

        // Success overlay
        if showSuccess {
            ZStack {
                Theme.surface.opacity(0.96)
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.green)
                    Text("Task Created")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }
            }
            .frame(width: 680)
            .transition(.opacity.animation(.easeInOut(duration: 0.15)))
        }
        } // ZStack
    }

    // MARK: - Toolbar items

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Theme.borderSubtle)
            .frame(width: 1)
            .padding(.vertical, 6)
    }

    // Estimate: preset list via popover
    private var estimateButton: some View {
        Button { showEstimatePicker.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.system(size: 12))
                    .foregroundStyle(estimatedMinutes > 0 ? Theme.blue : Theme.dim)
                Text(estimateLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(estimatedMinutes > 0 ? Theme.text : Theme.dim)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 30)
            .contentShape(Rectangle())
            .background(Theme.surface.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.cadencePlain)
        .popover(isPresented: $showEstimatePicker, arrowEdge: .top) {
            estimatePickerContent
        }
    }

    @ViewBuilder
    private var estimatePickerContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(
                [(0, "No estimate"), (5, "5 min"), (15, "15 min"),
                 (30, "30 min"), (45, "45 min"), (60, "1 hour"), (90, "1.5 hrs")],
                id: \.0
            ) { mins, label in
                Button {
                    estimatedMinutes = mins
                    showEstimatePicker = false
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "timer")
                            .font(.system(size: 12))
                            .foregroundStyle(estimatedMinutes == mins ? Theme.blue : Theme.dim)
                            .frame(width: 16)
                        Text(label)
                            .font(.system(size: 13))
                            .foregroundStyle(estimatedMinutes == mins ? Theme.text : Theme.muted)
                        Spacer()
                        if estimatedMinutes == mins {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.blue)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(estimatedMinutes == mins ? Theme.blue.opacity(0.08) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.cadencePlain)
                .modifier(CreateTaskPickerHover())
            }
        }
        .padding(6)
        .frame(minWidth: 160)
        .background(Theme.surfaceElevated)
    }

    // Priority: compact dot+label, opens popover
    private var priorityButton: some View {
        Button { showPriorityPicker.toggle() } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(Theme.priorityColor(selectedPriority))
                    .frame(width: 8, height: 8)
                Text(selectedPriority.label)
                    .font(.system(size: 13))
                    .foregroundStyle(selectedPriority == .none ? Theme.dim : Theme.muted)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minHeight: 30)
            .contentShape(Rectangle())
            .background(Theme.surface.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.cadencePlain)
        .popover(isPresented: $showPriorityPicker, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(TaskPriority.allCases, id: \.self) { p in
                    Button {
                        selectedPriority = p
                        showPriorityPicker = false
                    } label: {
                        HStack(spacing: 8) {
                            Circle().fill(Theme.priorityColor(p)).frame(width: 7, height: 7)
                            Text(p.label).font(.system(size: 12)).foregroundStyle(Theme.text)
                            Spacer()
                            if selectedPriority == p {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Theme.blue)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        .background(selectedPriority == p ? Theme.blue.opacity(0.08) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.cadencePlain)
                    .modifier(CreateTaskPickerHover())
                }
            }
            .padding(.vertical, 6).frame(minWidth: 140).background(Theme.surfaceElevated)
        }
    }

    // MARK: - Helpers

    private var estimateLabel: String {
        switch estimatedMinutes {
        case 0:  return "—"
        case 5:  return "5m"
        case 15: return "15m"
        case 30: return "30m"
        case 45: return "45m"
        case 60: return "1h"
        case 90: return "1.5h"
        default: return "\(estimatedMinutes)m"
        }
    }

    // MARK: - Logic

    private var availableSections: [String] {
        switch selectedContainer {
        case .inbox:
            return [TaskSectionDefaults.defaultName]
        case .area(let areaID):
            return areas.first(where: { $0.id == areaID })?.sectionNames ?? [TaskSectionDefaults.defaultName]
        case .project(let projectID):
            return projects.first(where: { $0.id == projectID })?.sectionNames ?? [TaskSectionDefaults.defaultName]
        }
    }

    private var showsSectionPicker: Bool {
        switch selectedContainer {
        case .inbox:
            return false
        case .area, .project:
            return true
        }
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func createTask() {
        guard !trimmedTitle.isEmpty else { return }
        let task = AppTask(title: trimmedTitle)
        task.notes            = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        task.priority         = selectedPriority
        task.estimatedMinutes = estimatedMinutes
        task.sectionName      = selectedSectionName
        if hasDueDate { task.dueDate      = DateFormatters.dateKey(from: dueDate) }
        if hasDoDate  { task.scheduledDate = DateFormatters.dateKey(from: doDate)  }
        applyContainer(task)
        modelContext.insert(task)
        if task.scheduledStartMin >= 0 { SchedulingActions.syncToCalendarIfLinked(task) }

        // Create subtasks linked to the parent task
        for (i, subtaskTitle) in subtaskTitles.enumerated() {
            let trimmed = subtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let subtask = Subtask(title: trimmed)
            subtask.parentTask = task
            subtask.order = i
            modelContext.insert(subtask)
        }

        withAnimation { showSuccess = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { dismiss() }
    }

    private func applyContainer(_ task: AppTask) {
        switch selectedContainer {
        case .inbox:
            task.area = nil; task.project = nil; task.context = nil
        case .area(let areaID):
            if let area = areas.first(where: { $0.id == areaID }) {
                task.area = area; task.project = nil; task.context = area.context
            }
        case .project(let projectID):
            if let project = projects.first(where: { $0.id == projectID }) {
                task.project = project; task.area = nil; task.context = project.context
            }
        }
    }

    private func dismiss() {
        if let dismissAction { dismissAction() } else { taskCreationManager.dismiss() }
    }

    private func normalizeSelectedSection() {
        let validSections = availableSections
        if !validSections.contains(where: { $0.caseInsensitiveCompare(selectedSectionName) == .orderedSame }) {
            selectedSectionName = validSections.first ?? TaskSectionDefaults.defaultName
        }
    }
}

// MARK: - TaskDateControl (own View so it can hold @State)

private struct TaskDateControl: View {
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
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(isDoDate && cal.isDateInToday(date) ? .yellow : activeColor)
                        } else {
                            Text(label)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.dim)
                        }
                    }
                    .fixedSize()
                }
                .padding(.leading, 10)
                .padding(.trailing, isOn ? 4 : 10)
                .padding(.vertical, 6)
                .frame(minHeight: 30)
                .contentShape(Rectangle())
                .background(isHovered ? activeColor.opacity(0.08) : Theme.surface.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.cadencePlain)
            .onHover { isHovered = $0 }
            .popover(isPresented: $showPicker, arrowEdge: .top) {
                pickerPopover
            }

            if isOn {
                Button { isOn = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim.opacity(0.6))
                }
                .buttonStyle(.cadencePlain)
                .padding(.trailing, 8)
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
                quickPill("Today",     offset: 0)
                quickPill("Tomorrow",  offset: 1)
                quickPill("Next Week", weekOffset: true)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider().background(Theme.borderSubtle)

            MonthCalendarPanel(
                selection: Binding(get: { date }, set: { date = $0; isOn = true; showPicker = false }),
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
                .padding(.vertical, 5)
                .background(isSelected ? Theme.blue : Theme.surface)
                .clipShape(Capsule())
        }
        .buttonStyle(.cadencePlain)
        .modifier(CreateTaskPickerHover(cornerRadius: 999))
    }
}

private struct CreateTaskPickerHover: ViewModifier {
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
#endif
