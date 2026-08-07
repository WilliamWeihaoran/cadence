#if os(macOS)
import SwiftUI
import SwiftData

struct CreateTaskSheet: View {
    let seed: TaskCreationSeed
    let dismissAction: (() -> Void)?
    let successAction: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(TaskCreationManager.self) private var taskCreationManager
    @Query(sort: \Context.order)  private var contexts:  [Context]
    @Query(sort: \Area.order)     private var areas:     [Area]
    @Query(sort: \Project.order)  private var projects:  [Project]
    @Query(sort: \Tag.order)      private var tags:      [Tag]

    @State private var title:             String
    @State private var notes:             String
    @State private var selectedPriority:  TaskPriority
    @State private var selectedContainer: TaskContainerSelection
    @State private var selectedSectionName: String
    @State private var hasDueDate:        Bool
    @State private var dueDate:           Date
    @State private var hasDoDate:         Bool
    @State private var doDate:            Date
    @State private var selectedTags:      [Tag] = []

    @State private var showPriorityPicker = false
    @State private var showDoPicker  = false
    @State private var showDuePicker = false
    // showLocalSuccessToast removed — global toast used instead
    @FocusState private var focusedSubtask: Int?
    @State private var subtaskTitles: [String] = []

    init(
        seed: TaskCreationSeed,
        dismissAction: (() -> Void)? = nil,
        successAction: (() -> Void)? = nil
    ) {
        self.seed = seed
        self.dismissAction = dismissAction
        self.successAction = successAction
        let resolvedDueDate = DateFormatters.date(from: seed.dueDateKey) ?? Date()
        let resolvedDoDate  = DateFormatters.date(from: seed.doDateKey)  ?? Date()
        _title             = State(initialValue: seed.title)
        _notes             = State(initialValue: seed.notes)
        _selectedPriority  = State(initialValue: seed.priority)
        _selectedContainer = State(initialValue: seed.container)
        _selectedSectionName = State(initialValue: seed.sectionName)
        _hasDueDate        = State(initialValue: !seed.dueDateKey.isEmpty)
        _dueDate           = State(initialValue: resolvedDueDate)
        _hasDoDate         = State(initialValue: !seed.doDateKey.isEmpty)
        _doDate            = State(initialValue: resolvedDoDate)
        _subtaskTitles     = State(initialValue: seed.subtaskTitles)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            keyboardShortcuts
            titleSection
            notesSection
            subtasksSection
            addSubtaskButton

            Divider().background(Theme.borderSubtle)

            toolbarRow
        }
        .frame(width: 600)
        .background(Theme.surface)
        .onAppear {
            normalizeSelectedSection()
        }
        .onChange(of: selectedContainer) { _, _ in normalizeSelectedSection() }
    }

    private var keyboardShortcuts: some View {
        ZStack {
            Button("") { setDoToday() }
                .keyboardShortcut("t", modifiers: .command)
            Button("") { showDoPicker = true }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Button("") { setDueToday() }
                .keyboardShortcut("d", modifiers: .command)
            Button("") { showDuePicker = true }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Button("") { cyclePriority() }
                .keyboardShortcut("p", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .clipped()
    }

    private var titleSection: some View {
        HStack(alignment: .center, spacing: 8) {
            priorityMarkButton

            TaskTitleEntryField(
                title: $title,
                priority: $selectedPriority,
                placeholder: "What needs doing?",
                font: .system(size: 17, weight: .semibold),
                autofocus: true,
                contexts: contexts,
                areas: areas,
                projects: projects,
                allTags: tags,
                containerSelection: $selectedContainer,
                sectionName: $selectedSectionName,
                selectedTags: $selectedTags,
                onCreateTag: createTag,
                onDateNudge: nudgeDoDate
            ) {
                if !TaskTitleSupport.isEmpty(title) { createTask() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private var notesSection: some View {
        ZStack(alignment: .topLeading) {
            if notes.isEmpty {
                Text("Notes")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.dim.opacity(0.45))
                    .padding(.top, 1)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $notes)
                .font(.system(size: 14))
                .foregroundStyle(Theme.text)
                .scrollContentBackground(.hidden)
                .frame(height: 40)
        }
        .padding(.leading, 52)
        .padding(.trailing, 16)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var subtasksSection: some View {
        if !subtaskTitles.isEmpty {
            VStack(spacing: 0) {
                ForEach(subtaskTitles.indices, id: \.self) { index in
                    subtaskRow(at: index)
                }
            }
        }
    }

    private func subtaskRow(at index: Int) -> some View {
        HStack(spacing: 8) {
            Circle()
                .strokeBorder(Theme.dim.opacity(0.3), lineWidth: 1)
                .frame(width: 12, height: 12)
            TextField("Subtask", text: $subtaskTitles[index])
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Theme.text)
                .focused($focusedSubtask, equals: index)
                .onSubmit(addNextSubtask)
            Button {
                subtaskTitles.remove(at: index)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.dim.opacity(0.5))
            }
            .buttonStyle(.cadencePlain)
        }
        .padding(.leading, 52)
        .padding(.trailing, 16)
        .padding(.vertical, 4)
    }

    private var addSubtaskButton: some View {
        Button(action: addNextSubtask) {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                Text("Add Subtask")
                    .font(.system(size: 12))
            }
            .foregroundStyle(Theme.dim.opacity(0.65))
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.cadencePlain)
        .padding(.leading, 52)
        .padding(.bottom, 4)
    }

    private var toolbarRow: some View {
        HStack(spacing: 8) {
            ContainerPickerBadge(
                selection: $selectedContainer,
                contexts: contexts,
                areas: areas,
                projects: projects,
                outlined: true
            )

            if showsSectionPicker {
                TaskSectionPickerBadge(
                    selection: $selectedSectionName,
                    sections: availableSections
                )
            }

            TaskDateChip(label: "Do Date",
                         icon: "calendar",
                         activeColor: Theme.blue,
                         isOn: $hasDoDate, date: $doDate,
                         showPicker: $showDoPicker)

            TaskDateChip(label: "Due Date",
                         icon: "flag.fill",
                         activeColor: Theme.red,
                         isOn: $hasDueDate, date: $dueDate,
                         showPicker: $showDuePicker)

            TagPickerControl(
                selectedTags: $selectedTags,
                allTags: tags,
                onCreateTag: createTag,
                showsLabel: true
            )

            Spacer(minLength: 0)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.cadencePlain)
            .accessibilityLabel("Cancel")

            Button(action: createTask) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.cadencePlain)
            .disabled(trimmedTitle.isEmpty)
            .opacity(trimmedTitle.isEmpty ? 0.5 : 1)
            .keyboardShortcut(.return, modifiers: [.command])
            .accessibilityLabel("Create Task")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.surfaceElevated)
    }

    private func addNextSubtask() {
        subtaskTitles.append("")
        focusedSubtask = subtaskTitles.count - 1
    }

    // MARK: - Priority chip

    private var priorityMarkButton: some View {
        Button { showPriorityPicker.toggle() } label: {
            Image(systemName: "flag.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(selectedPriority == .none ? Theme.dim : Theme.priorityColor(selectedPriority))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
                .accessibilityLabel("Priority")
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
                            Text(TaskTitleSupport.priorityMark(for: p))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(p == .none ? Theme.dim : Theme.priorityColor(p))
                                .frame(width: 24, alignment: .leading)
                            Text(p.label).font(.system(size: 13)).foregroundStyle(Theme.text)
                            Spacer()
                            if selectedPriority == p {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.blue)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
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

    // MARK: - Logic

    private var containerResolver: TaskContainerResolver {
        TaskContainerResolver(areas: areas, projects: projects)
    }

    private var availableSections: [String] {
        containerResolver.availableSections(for: selectedContainer)
    }

    private var showsSectionPicker: Bool {
        switch selectedContainer {
        case .inbox: return false
        case .area, .project: return true
        }
    }

    private var trimmedTitle: String {
        TaskTitleSupport.priorityShortcut(in: title)?.title ?? TaskTitleSupport.normalized(title)
    }

    private func createTask() {
        guard !trimmedTitle.isEmpty else { return }
        let draft = TaskCreationDraft(
            title: title,
            notes: notes,
            priority: selectedPriority,
            container: selectedContainer,
            sectionName: selectedSectionName,
            dueDateKey: hasDueDate ? DateFormatters.dateKey(from: dueDate) : "",
            scheduledDateKey: hasDoDate ? DateFormatters.dateKey(from: doDate) : "",
            subtaskTitles: subtaskTitles,
            tags: selectedTags,
            scheduledStartMin: seed.scheduledStartMin,
            estimatedMinutes: seed.estimatedMinutes
        )
        guard TaskCreationService(areas: areas, projects: projects).insertTask(from: draft, into: modelContext) != nil else {
            return
        }
        // Fast-path reconcile so a newly-created scheduled/due task's notification is picked up
        // immediately, instead of waiting for the next scenePhase checkpoint.
        HabitNotificationReconcileSupport.scheduleReconcile(in: modelContext)

        if let successAction {
            successAction()
        } else {
            dismiss()
            taskCreationManager.presentSuccessToast()
        }
    }

    private func setDoToday() {
        let today = Calendar.current.startOfDay(for: Date())
        if hasDoDate && Calendar.current.isDateInToday(doDate) {
            hasDoDate = false
        } else {
            hasDoDate = true
            doDate = today
        }
    }

    private func setDueToday() {
        let today = Calendar.current.startOfDay(for: Date())
        if hasDueDate && Calendar.current.isDateInToday(dueDate) {
            hasDueDate = false
        } else {
            hasDueDate = true
            dueDate = today
        }
    }

    private func nudgeDoDate(by days: Int) {
        let cal = Calendar.current
        if !hasDoDate {
            hasDoDate = true
            doDate = cal.startOfDay(for: Date())
        }
        doDate = cal.date(byAdding: .day, value: days, to: doDate) ?? doDate
    }

    private func cyclePriority() {
        let all = TaskPriority.allCases
        let idx = all.firstIndex(of: selectedPriority) ?? 0
        selectedPriority = all[(idx + 1) % all.count]
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

    private func createTag(_ name: String) -> Tag {
        TagSupport.resolveTags(named: [name], in: modelContext).first ?? Tag(name: name)
    }

}

#endif
