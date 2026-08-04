#if os(iOS)
import EventKit
import SwiftData
import SwiftUI

struct iOSCalendarQuickCreateSheet: View {
    let dateKey: String
    let initialStartMinute: Int?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(iOSCalendarManager.self) private var calendarManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @State private var kind: iOSCalendarQuickCreateKind = .task
    @State private var title = ""
    @State private var priority: TaskPriority = .none
    @State private var estimatedMinutes = 30
    @State private var notes = ""
    @AppStorage(iOSMarkdownEditorPreferences.modeKey) private var notesEditorModeRaw = iOSMarkdownEditorPreferences.defaultMode.rawValue
    @State private var notesEditorFocused = false
    @State private var selectedReferenceNote: Note?
    @State private var selectedReferenceTask: AppTask?
    @State private var hasTime: Bool
    @State private var eventIsAllDay = false
    @State private var startTime: Date
    @State private var containerSelection = "inbox"
    @State private var sectionName = TaskSectionDefaults.defaultName
    @State private var selectedCalendarID = ""

    init(dateKey: String, initialStartMinute: Int? = nil) {
        self.dateKey = dateKey
        self.initialStartMinute = initialStartMinute
        _hasTime = State(initialValue: initialStartMinute != nil)
        _startTime = State(initialValue: iOSCalendarQuickCreateSheet.defaultStartTime(dateKey: dateKey, startMinute: initialStartMinute))
    }

    private var activeAreas: [Area] {
        areas.filter(\.isActive)
    }

    private var activeProjects: [Project] {
        projects.filter(\.isActive)
    }

    private var availableSectionNames: [String] {
        CadenceTaskMutationSupport.sectionNames(forArea: selectedArea, project: selectedProject)
    }

    private var selectedArea: Area? {
        guard containerSelection.hasPrefix("area:"),
              let id = UUID(uuidString: String(containerSelection.dropFirst(5)))
        else { return nil }
        return areas.first { $0.id == id }
    }

    private var selectedProject: Project? {
        guard containerSelection.hasPrefix("project:"),
              let id = UUID(uuidString: String(containerSelection.dropFirst(8)))
        else { return nil }
        return projects.first { $0.id == id }
    }

    private var canCreate: Bool {
        switch kind {
        case .task:
            return !TaskTitleSupport.isEmpty(title)
        case .bundle:
            return true
        case .event:
            return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedWritableCalendar != nil
        }
    }

    private var selectedWritableCalendar: EKCalendar? {
        calendarManager.writableCalendars.first { $0.calendarIdentifier == selectedCalendarID }
    }

    private var showsTimedControls: Bool {
        switch kind {
        case .task:
            return hasTime
        case .bundle:
            return true
        case .event:
            return !eventIsAllDay
        }
    }

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var notesEditorModeBinding: Binding<iOSMarkdownEditorMode> {
        iOSMarkdownEditorPreferences.binding(for: $notesEditorModeRaw)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                formLayout
                    .padding(isRegularWidth ? 20 : 18)
            }
            .background(Theme.bg)
            .navigationTitle("Add to Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: create)
                        .disabled(!canCreate)
                }
            }
            .onChange(of: containerSelection) { _, _ in normalizeSection() }
            .onChange(of: kind) { _, _ in normalizeCalendarSelection() }
            .onAppear {
                normalizeCalendarSelection()
            }
        }
        .iOSMarkdownReferenceSheets(
            selectedNote: $selectedReferenceNote,
            selectedTask: $selectedReferenceTask,
            referenceNotes: allNotes,
            referenceTasks: allTasks
        )
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var formLayout: some View {
        if isRegularWidth {
            regularFormLayout
        } else {
            compactFormLayout
        }
    }

    private var compactFormLayout: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            kindPicker
            titleSection
            formDetails
            timeSection
            formNotes
        }
    }

    private var regularFormLayout: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                header
                kindPicker
                titleSection
                timeSection
            }
            .frame(minWidth: 340, maxWidth: 440, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 16) {
                formDetails
                formNotes
            }
            .frame(minWidth: 360, maxWidth: 520, alignment: .topLeading)
        }
        .frame(maxWidth: 980, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var formDetails: some View {
        if kind == .task {
            taskOptions
        }
        if kind == .event {
            calendarSection
        }
    }

    @ViewBuilder
    private var formNotes: some View {
        if kind == .task || kind == .event {
            notesSection
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Theme.blue)
                .frame(width: 42, height: 42)
                .background(Theme.blue.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(DateFormatters.relativeDate(from: dateKey))
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(headerSubtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.dim)
            }

            Spacer()
        }
        .padding(16)
        .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusCard, shadowRadius: 12, shadowY: 5)
    }

    private var kindPicker: some View {
        Picker("Kind", selection: $kind) {
            ForEach(iOSCalendarQuickCreateKind.allCases) { item in
                Label(item.title, systemImage: item.systemImage).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .tint(Theme.blue)
    }

    private var titleSection: some View {
        iOSCalendarQuickCreateSection(title: kind.title) {
            TextField(kind.placeholder, text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(1...3)
                .submitLabel(.done)
                .onSubmit {
                    if canCreate { create() }
                }
        }
    }

    private var calendarSection: some View {
        iOSCalendarQuickCreateSection(title: "Apple Calendar") {
            if !calendarManager.isAuthorized {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Calendar access is needed to create events.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.dim)
                    Button {
                        Task {
                            _ = await calendarManager.requestAccess()
                            normalizeCalendarSelection()
                        }
                    } label: {
                        Label("Allow Calendar Access", systemImage: "calendar.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.blue)
                }
            } else if calendarManager.writableCalendars.isEmpty {
                Text("No writable calendars are available.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.dim)
            } else {
                iOSCalendarQuickCreateRow(label: "Calendar", systemImage: "calendar", color: Theme.green) {
                    Picker("Calendar", selection: $selectedCalendarID) {
                        ForEach(calendarManager.writableCalendars, id: \.calendarIdentifier) { calendar in
                            Text(calendar.title).tag(calendar.calendarIdentifier)
                        }
                    }
                    .labelsHidden()
                }
            }
        }
    }

    private var taskOptions: some View {
        iOSCalendarQuickCreateSection(title: "Details") {
            iOSCalendarQuickCreateRow(label: "Priority", systemImage: "flag.fill", color: Theme.priorityColor(priority)) {
                Picker("Priority", selection: $priority) {
                    ForEach(TaskPriority.allCases, id: \.self) { priority in
                        Text(priority.label).tag(priority)
                    }
                }
                .labelsHidden()
            }

            iOSCalendarQuickCreateDivider()

            iOSCalendarQuickCreateRow(label: "Estimate", systemImage: "clock.fill", color: Theme.blue) {
                Stepper(value: $estimatedMinutes, in: 5...480, step: 5) {
                    Text(durationLabel(estimatedMinutes))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }
            }

            iOSCalendarQuickCreateDivider()

            iOSCalendarQuickCreateRow(label: "List", systemImage: "tray.full.fill", color: Theme.blue) {
                Picker("List", selection: $containerSelection) {
                    Text("Inbox").tag("inbox")
                    if !activeAreas.isEmpty {
                        Section("Areas") {
                            ForEach(activeAreas) { area in
                                Text(area.name.isEmpty ? "Untitled Area" : area.name)
                                    .tag("area:\(area.id.uuidString)")
                            }
                        }
                    }
                    if !activeProjects.isEmpty {
                        Section("Projects") {
                            ForEach(activeProjects) { project in
                                Text(project.name.isEmpty ? "Untitled Project" : project.name)
                                    .tag("project:\(project.id.uuidString)")
                            }
                        }
                    }
                }
                .labelsHidden()
            }

            iOSCalendarQuickCreateDivider()

            iOSCalendarQuickCreateRow(label: "Section", systemImage: "rectangle.split.3x1.fill", color: Theme.purple) {
                Picker("Section", selection: $sectionName) {
                    ForEach(availableSectionNames, id: \.self) { section in
                        Text(section).tag(section)
                    }
                }
                .labelsHidden()
                .disabled(containerSelection == "inbox")
                .opacity(containerSelection == "inbox" ? 0.45 : 1)
            }
        }
    }

    private var timeSection: some View {
        iOSCalendarQuickCreateSection(title: "Schedule") {
            if kind == .task {
                Toggle(isOn: $hasTime) {
                    iOSCalendarQuickCreateInlineLabel(
                        label: "Set time",
                        systemImage: "clock",
                        color: Theme.amber
                    )
                }
                .toggleStyle(.switch)
                .tint(Theme.blue)
            }

            if kind == .event {
                Toggle(isOn: $eventIsAllDay) {
                    iOSCalendarQuickCreateInlineLabel(
                        label: "All day",
                        systemImage: "sun.max",
                        color: Theme.amber
                    )
                }
                .toggleStyle(.switch)
                .tint(Theme.blue)
            }

            if showsTimedControls {
                if kind == .task || kind == .event {
                    iOSCalendarQuickCreateDivider()
                }

                DatePicker("Starts", selection: $startTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.compact)
                    .tint(Theme.blue)

                iOSCalendarQuickCreateDivider()

                iOSCalendarQuickCreateRow(label: "Duration", systemImage: "timer", color: Theme.green) {
                    Stepper(value: $estimatedMinutes, in: 5...480, step: 5) {
                        Text(durationLabel(estimatedMinutes))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                    }
                }
            }
        }
    }

    private var notesSection: some View {
        iOSCalendarQuickCreateSection(title: "Notes") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(kind == .event ? "Apple Calendar note" : "Task note")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.dim)

                    Spacer(minLength: 0)

                    iOSMarkdownModePicker(mode: notesEditorModeBinding, compact: true)
                }

                iOSMarkdownEditingSurface(
                    text: $notes,
                    isFocused: $notesEditorFocused,
                    mode: notesEditorModeBinding,
                    placeholder: "Add markdown notes...",
                    referenceNotes: allNotes,
                    referenceTasks: allTasks,
                    onOpenReference: openMarkdownReference,
                    allowsEmbeddedTaskCreation: false
                )
                .frame(minHeight: isRegularWidth ? 280 : 230)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.borderSubtle.opacity(0.68), lineWidth: 1)
                }
            }
        }
    }

    private func openMarkdownReference(_ target: MarkdownReferenceDisplayTarget) {
        switch target.kind {
        case .note:
            selectedReferenceNote = iOSMarkdownReferenceResolver.note(for: target, in: allNotes)
        case .task:
            selectedReferenceTask = iOSMarkdownReferenceResolver.task(for: target, in: allTasks)
        }
    }

    private func create() {
        switch kind {
        case .task:
            createTask()
        case .bundle:
            createBundle()
        case .event:
            createEvent()
        }
    }

    private func createTask() {
        let startMin = hasTime ? minuteOfDay(from: startTime) : -1
        guard (try? CadenceTaskMutationSupport.insertScheduledTask(
            title: title,
            allTasks: allTasks,
            modelContext: modelContext,
            scheduledDate: dateKey,
            scheduledStartMin: startMin,
            estimatedMinutes: estimatedMinutes,
            configure: configureTask
        )) != nil else { return }
        HabitNotificationReconcileSupport.scheduleReconcile(in: modelContext)
        dismiss()
    }

    private func createEvent() {
        guard let baseDate = DateFormatters.date(from: dateKey) else { return }
        let startDate: Date
        let endDate: Date
        if eventIsAllDay {
            startDate = Calendar.current.startOfDay(for: baseDate)
            endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        } else {
            let startMinute = minuteOfDay(from: startTime)
            startDate = Calendar.current.date(byAdding: .minute, value: startMinute, to: baseDate) ?? baseDate
            endDate = Calendar.current.date(byAdding: .minute, value: max(5, estimatedMinutes), to: startDate) ?? startDate
        }
        guard calendarManager.createEvent(
            title: title,
            startDate: startDate,
            endDate: endDate,
            calendarID: selectedCalendarID,
            notes: notes,
            isAllDay: eventIsAllDay
        ) else { return }
        dismiss()
    }

    private func createBundle() {
        let startMin = minuteOfDay(from: startTime)
        _ = try? CadenceTaskMutationSupport.insertBundle(
            title: title,
            dateKey: dateKey,
            startMin: startMin,
            durationMinutes: estimatedMinutes,
            modelContext: modelContext
        )
        dismiss()
    }

    private func configureTask(_ task: AppTask) {
        if priority != .none {
            task.priority = priority
        }
        task.notes = notes
        task.estimatedMinutes = estimatedMinutes
        CadenceTaskMutationSupport.assignContainer(
            task,
            area: selectedArea,
            project: selectedProject,
            sectionName: sectionName,
            allTasks: allTasks
        )
    }

    private func normalizeSection() {
        sectionName = CadenceTaskMutationSupport.normalizedSectionName(
            sectionName,
            area: selectedArea,
            project: selectedProject
        )
    }

    private func normalizeCalendarSelection() {
        guard kind == .event else { return }
        if !calendarManager.writableCalendars.contains(where: { $0.calendarIdentifier == selectedCalendarID }) {
            selectedCalendarID = calendarManager.writableCalendars.first?.calendarIdentifier ?? ""
        }
    }

    private func minuteOfDay(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return max(0, min(23 * 60 + 59, (components.hour ?? 9) * 60 + (components.minute ?? 0)))
    }

    private func durationLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return String(format: "%.1fh", Double(minutes) / 60.0)
    }

    private var headerSubtitle: String {
        if let initialStartMinute {
            return "Create around \(CadenceScheduleSupport.timeRangeLabel(startMinute: initialStartMinute, endMinute: initialStartMinute + estimatedMinutes))."
        }
        return "Create a planned task, block, or Apple Calendar event."
    }

    private static func defaultStartTime(dateKey: String, startMinute: Int?) -> Date {
        let baseDate = DateFormatters.date(from: dateKey) ?? Date()
        var components = Calendar.current.dateComponents([.year, .month, .day], from: baseDate)
        if let startMinute {
            components.hour = startMinute / 60
            components.minute = startMinute % 60
        } else {
            let hour = Calendar.current.component(.hour, from: Date())
            components.hour = min(max(hour + 1, CadenceScheduleSupport.calendarStartHour), CadenceScheduleSupport.calendarEndHour - 1)
            components.minute = 0
        }
        return Calendar.current.date(from: components) ?? baseDate
    }
}

private enum iOSCalendarQuickCreateKind: String, CaseIterable, Identifiable {
    case task
    case bundle
    case event

    var id: String { rawValue }

    var title: String {
        switch self {
        case .task: return "Task"
        case .bundle: return "Block"
        case .event: return "Event"
        }
    }

    var placeholder: String {
        switch self {
        case .task: return "Task title"
        case .bundle: return "Block title"
        case .event: return "Event title"
        }
    }

    var systemImage: String {
        switch self {
        case .task: return "checkmark.circle"
        case .bundle: return "tray.full.fill"
        case .event: return "calendar.badge.plus"
        }
    }
}

private struct iOSCalendarQuickCreateSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .textCase(.uppercase)
                .kerning(0.8)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusCard, shadowRadius: 12, shadowY: 5)
        }
    }
}

private struct iOSCalendarQuickCreateRow<Content: View>: View {
    let label: String
    let systemImage: String
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 10) {
            iOSCalendarQuickCreateInlineLabel(label: label, systemImage: systemImage, color: color)
            Spacer(minLength: 12)
            content()
        }
        .frame(minHeight: 34)
    }
}

private struct iOSCalendarQuickCreateInlineLabel: View {
    let label: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
        }
    }
}

private struct iOSCalendarQuickCreateDivider: View {
    var body: some View {
        Divider().background(Theme.borderSubtle.opacity(0.6))
    }
}
#endif
