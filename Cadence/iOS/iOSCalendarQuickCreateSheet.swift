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
    @State private var kind: iOSCalendarQuickCreateKind
    @State private var title = ""
    @State private var priority: TaskPriority = .none
    @State private var estimatedMinutes = 30
    @State private var notes = ""
    @State private var notesEditorFocused = false
    @State private var selectedReferenceNote: Note?
    @State private var selectedReferenceTask: AppTask?
    @State private var hasTime: Bool
    @State private var eventIsAllDay = false
    @State private var startTime: Date
    @State private var containerSelection = "inbox"
    @State private var sectionName = TaskSectionDefaults.defaultName
    @State private var selectedCalendarID = ""
    @State private var showCalendarPicker = false
    @State private var showContainerPicker = false
    @State private var showSectionPicker = false
    @State private var showStartTimePicker = false

    /// `initialKind` is what the capture palette's **Event** segment needs: the segmented control
    /// is still there and still switches, but a palette that says "Event" and opens on Task would
    /// be the choice being taken twice. Defaults to `.task`, which is what every existing caller —
    /// a tapped empty slot on the calendar — means.
    init(dateKey: String, initialStartMinute: Int? = nil, initialKind: iOSCalendarQuickCreateKind = .task) {
        self.dateKey = dateKey
        self.initialStartMinute = initialStartMinute
        _kind = State(initialValue: initialKind)
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

    private var selectedCalendarTitle: String {
        selectedWritableCalendar?.title ?? "Choose Calendar"
    }

    private var startTimeMinutesBinding: Binding<Int> {
        Binding(
            get: {
                let comps = Calendar.current.dateComponents([.hour, .minute], from: startTime)
                return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
            },
            set: { minutes in
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: startTime)
                comps.hour = minutes / 60
                comps.minute = minutes % 60
                startTime = Calendar.current.date(from: comps) ?? startTime
            }
        )
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

    /// Read for two things only: the sheet's gutter, and whether the form splits into two columns.
    /// Both are facts about the host. Nothing the sheet *draws* consults it — those figures are
    /// `iOSEditorSheetMetrics`, which takes no width.
    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                formLayout
                    .padding(iOSEditorSheetMetrics.cardPadding)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusPanel, style: .continuous))
                    .padding(iOSEditorSheetMetrics.gutter(isRegularWidth: isRegularWidth))
            }
            .background(Theme.bg)
            .toolbar(.hidden, for: .navigationBar)
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
        VStack(alignment: .leading, spacing: iOSEditorSheetMetrics.groupSpacing) {
            header
            kindPicker
            titleSection
            formDetails
            timeSection
            formNotes
        }
    }

    private var regularFormLayout: some View {
        HStack(alignment: .top, spacing: iOSEditorSheetMetrics.groupSpacing) {
            VStack(alignment: .leading, spacing: iOSEditorSheetMetrics.groupSpacing) {
                header
                kindPicker
                titleSection
                timeSection
            }
            .frame(
                minWidth: iOSEditorSheetMetrics.primaryColumnMinWidth,
                maxWidth: iOSEditorSheetMetrics.primaryColumnMaxWidth,
                alignment: .topLeading
            )

            VStack(alignment: .leading, spacing: iOSEditorSheetMetrics.groupSpacing) {
                formDetails
                formNotes
            }
            .frame(
                minWidth: iOSEditorSheetMetrics.secondaryColumnMinWidth,
                maxWidth: iOSEditorSheetMetrics.secondaryColumnMaxWidth,
                alignment: .topLeading
            )
        }
        .frame(maxWidth: iOSEditorSheetMetrics.twoColumnMaxWidth, alignment: .top)
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
            iOSIconTile(systemImage: "calendar.badge.plus", color: Theme.blue, size: 42, iconSize: 19)

            VStack(alignment: .leading, spacing: 3) {
                Text(DateFormatters.relativeDate(from: dateKey))
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Theme.text)
                if let headerSubtitle {
                    Text(headerSubtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.subdued)
                }
            }

            Spacer(minLength: 8)

            if kind == .task {
                priorityFlagButton
            }

            cancelButton
            createButton
        }
    }

    private var priorityFlagButton: some View {
        Button(action: cyclePriority) {
            Image(systemName: "flag.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.priorityColor(priority))
                .frame(width: 40, height: 40)
                .background(Theme.priorityColor(priority).opacity(0.13))
                .clipShape(Circle())
                .iOSExpandedHitArea(2)
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel("Priority: \(priority.label)")
        .accessibilityHint("Tap to cycle priority")
    }

    private var cancelButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.dim)
                .frame(width: 40, height: 40)
                .background(Theme.surface)
                .clipShape(Circle())
                .iOSExpandedHitArea(2)
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel("Cancel")
    }

    private var createButton: some View {
        Button(action: create) {
            Image(systemName: "arrow.up")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.onColor)
                .frame(width: 40, height: 40)
                .background(canCreate ? Theme.blue : Theme.blue.opacity(0.4))
                .clipShape(Circle())
                .iOSExpandedHitArea(2)
        }
        .buttonStyle(.iosPressable)
        .disabled(!canCreate)
        .accessibilityLabel("Create")
    }

    private func cyclePriority() {
        switch priority {
        case .none: priority = .low
        case .low: priority = .medium
        case .medium: priority = .high
        case .high: priority = .none
        }
    }

    private var kindPicker: some View {
        iOSSegmentedChoice(
            options: iOSCalendarQuickCreateKind.allCases.map { ($0, $0.title) },
            selection: $kind
        )
    }

    /// No eyebrow. It read "TASK" / "BLOCK" / "EVENT" — the word the segmented control directly
    /// above it already has lit up, and the word the field's own placeholder repeats a line below.
    private var titleSection: some View {
        iOSEditorSection(title: nil, style: .ruled) {
            TextField(kind.placeholder, text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: iOSEditorSheetMetrics.titleSize, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(1...iOSEditorSheetMetrics.titleLineLimit)
                .submitLabel(.done)
                .onSubmit {
                    if canCreate { create() }
                }
        }
    }

    private var calendarSection: some View {
        iOSEditorSection(title: "Apple Calendar", style: .ruled) {
            if !calendarManager.isAuthorized {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Calendar access is needed to create events.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.dim)
                    iOSActionButton(
                        title: "Allow Calendar Access",
                        systemImage: "calendar.badge.plus",
                        role: .primary,
                        size: .compact
                    ) {
                        Task {
                            _ = await calendarManager.requestAccess()
                            normalizeCalendarSelection()
                        }
                    }
                }
            } else if calendarManager.writableCalendars.isEmpty {
                Text("No writable calendars are available.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.dim)
            } else {
                iOSEditorFieldRow(label: "Calendar", systemImage: "calendar", color: Theme.green) {
                    iOSChoiceValueButton(title: selectedCalendarTitle, color: Theme.text) {
                        showCalendarPicker = true
                    }
                    .popover(isPresented: $showCalendarPicker) {
                        iOSChoicePopoverList(
                            rows: calendarManager.writableCalendars.map { calendar in
                                iOSChoiceRow(value: calendar.calendarIdentifier, title: calendar.title, systemImage: "calendar", color: Theme.green)
                            },
                            selection: $selectedCalendarID,
                            isPresented: $showCalendarPicker
                        )
                    }
                }
            }
        }
    }

    private var taskOptions: some View {
        iOSEditorSection(title: "Details", style: .ruled) {
            iOSEditorFieldRow(label: "Estimate", systemImage: "clock.fill", color: Theme.blue) {
                EstimatePickerControl(value: $estimatedMinutes)
            }

            iOSEditorDivider()

            iOSEditorFieldRow(label: "List", systemImage: "tray.full.fill", color: Theme.blue) {
                iOSChoiceValueButton(title: containerTitle, color: Theme.text) {
                    showContainerPicker = true
                }
                .popover(isPresented: $showContainerPicker) {
                    iOSContainerChoicePopover(
                        activeAreas: activeAreas,
                        activeProjects: activeProjects,
                        selection: $containerSelection,
                        isPresented: $showContainerPicker
                    )
                }
            }

            iOSEditorDivider()

            iOSEditorFieldRow(label: "Section", systemImage: "rectangle.split.3x1.fill", color: Theme.purple) {
                iOSChoiceValueButton(title: sectionName, color: Theme.text) {
                    showSectionPicker = true
                }
                .popover(isPresented: $showSectionPicker) {
                    iOSChoicePopoverList(
                        rows: availableSectionNames.map { name in
                            iOSChoiceRow(value: name, title: name, color: Theme.purple)
                        },
                        selection: $sectionName,
                        isPresented: $showSectionPicker
                    )
                }
                .disabled(containerSelection == "inbox")
                .opacity(containerSelection == "inbox" ? 0.45 : 1)
            }
        }
    }

    private var containerTitle: String {
        if containerSelection == "inbox" { return "Inbox" }
        if let selectedArea { return selectedArea.name.isEmpty ? "Untitled Area" : selectedArea.name }
        if let selectedProject { return selectedProject.name.isEmpty ? "Untitled Project" : selectedProject.name }
        return "Inbox"
    }

    private var timeSection: some View {
        iOSEditorSection(title: "Schedule", style: .ruled) {
            if kind == .task {
                Toggle(isOn: $hasTime) {
                    iOSEditorInlineLabel(
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
                    iOSEditorInlineLabel(
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
                    iOSEditorDivider()
                }

                iOSEditorFieldRow(label: "Starts", systemImage: "clock.fill", color: Theme.blue) {
                    iOSChoiceValueButton(title: TimeFormatters.timeString(from: startTimeMinutesBinding.wrappedValue), color: Theme.text) {
                        showStartTimePicker = true
                    }
                    .popover(isPresented: $showStartTimePicker) {
                        iOSChoicePopoverList(
                            rows: stride(from: 0, to: 1440, by: 15).map { minute in
                                iOSChoiceRow(value: minute, title: TimeFormatters.timeString(from: minute), color: Theme.blue)
                            },
                            selection: startTimeMinutesBinding,
                            isPresented: $showStartTimePicker
                        )
                    }
                }

                // No Duration row for a task. A task's length is `estimatedMinutes`, and the
                // Estimate row in DETAILS above already edits it — two rows, one field, showing the
                // same "30m" and moving together. Blocks and events have no Details section, so for
                // them this is the only place the length can be set.
                if kind != .task {
                    iOSEditorDivider()

                    iOSEditorFieldRow(label: "Duration", systemImage: "timer", color: Theme.green) {
                        EstimatePickerControl(value: $estimatedMinutes)
                    }
                }
            }
        }
    }

    private var notesSection: some View {
        iOSEditorSection(title: "Notes", style: .ruled) {
            VStack(alignment: .leading, spacing: 8) {
                Text(kind == .event ? "Apple Calendar note" : "Task note")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.subdued)

                iOSMarkdownEditingSurface(
                    text: $notes,
                    isFocused: $notesEditorFocused,
                    placeholder: "Add markdown notes...",
                    referenceNotes: allNotes,
                    referenceTasks: allTasks,
                    onOpenReference: openMarkdownReference,
                    allowsEmbeddedTaskCreation: false
                )
                .iOSMarkdownWell()
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

    /// Only the slot the sheet was opened on. The other branch used to read "Create a planned task,
    /// block, or Apple Calendar event." — a subtitle listing the three options the segmented control
    /// two rows below already lists, on a sheet whose one purpose is creating one of them.
    private var headerSubtitle: String? {
        guard let initialStartMinute else { return nil }
        return "Create around \(CadenceScheduleSupport.timeRangeLabel(startMinute: initialStartMinute, endMinute: initialStartMinute + estimatedMinutes))."
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

enum iOSCalendarQuickCreateKind: String, CaseIterable, Identifiable {
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

#endif
