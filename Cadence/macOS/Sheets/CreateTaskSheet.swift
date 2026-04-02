#if os(macOS)
import SwiftUI
import SwiftData

struct CreateTaskSheet: View {
    enum TildeMode { case none, list, section }

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

    @State private var showPriorityPicker = false
    @State private var showDoPicker  = false
    @State private var showDuePicker = false
    @State private var tildeMode: TildeMode = .none
    @State private var tildeSearchQuery   = ""
    @State private var tildeHighlightIdx  = 0
    @FocusState private var isTitleFocused: Bool
    @FocusState private var focusedSubtask: Int?
    @FocusState private var isTildeSearchFocused: Bool
    @State private var subtaskTitles: [String] = []

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
        _hasDoDate         = State(initialValue: !seed.doDateKey.isEmpty)
        _doDate            = State(initialValue: resolvedDoDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Sheet-local keyboard shortcuts ─────────────────────────────────
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
                Button("") {
                    if tildeMode == .list {
                        let n = tildeFlatContainers.count
                        if n > 0 { tildeHighlightIdx = min(tildeHighlightIdx + 1, n - 1) }
                    } else if tildeMode == .none {
                        nudgeDoDate(by: 1)
                    }
                }
                .keyboardShortcut("=", modifiers: [.command, .shift])
                Button("") {
                    if tildeMode == .list {
                        tildeHighlightIdx = max(tildeHighlightIdx - 1, 0)
                    } else if tildeMode == .none {
                        nudgeDoDate(by: -1)
                    }
                }
                .keyboardShortcut("-", modifiers: [.command, .shift])
            }
            .frame(width: 0, height: 0)
            .clipped()

            // ── Title ─────────────────────────────────────────────────────────
            HStack(alignment: .center, spacing: 10) {
                Circle()
                    .strokeBorder(Theme.dim.opacity(0.4), lineWidth: 1.5)
                    .frame(width: 16, height: 16)

                ZStack(alignment: .leading) {
                    // Always in the hierarchy so it never gets select-all on re-insertion
                    TextField("What needs doing?", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .focused($isTitleFocused)
                        .onSubmit { if !trimmedTitle.isEmpty { createTask() } }
                        .onChange(of: title) { _, newVal in
                            if newVal.hasSuffix("~") {
                                let prefix = String(newVal.dropLast())
                                if prefix.isEmpty || prefix.hasSuffix(" ") {
                                    title = prefix
                                    tildeSearchQuery = ""
                                    tildeHighlightIdx = 0
                                    tildeMode = .list
                                }
                            }
                        }
                        .opacity(tildeMode != .none ? 0 : 1)
                        .allowsHitTesting(tildeMode == .none)

                    if tildeMode != .none {
                        HStack(spacing: 4) {
                            if !title.isEmpty {
                                Text(title)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                    .fixedSize()
                            }
                            Text("~")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Theme.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .popover(
                                    isPresented: Binding(get: { tildeMode != .none }, set: { if !$0 { tildeMode = .none } }),
                                    arrowEdge: .bottom
                                ) {
                                    if tildeMode == .list {
                                        tildeListSearchView
                                    } else {
                                        tildeSectionSearchView
                                    }
                                }
                            Spacer()
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 6)

            // ── Notes ────────────────────────────────────────────────────────
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
            .padding(.leading, 42)
            .padding(.trailing, 16)
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
                        .padding(.leading, 42)
                        .padding(.trailing, 16)
                        .padding(.vertical, 4)
                    }
                }
            }

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
                .foregroundStyle(Theme.dim.opacity(0.65))
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.cadencePlain)
            .padding(.leading, 42)
            .padding(.bottom, 4)

            Divider().background(Theme.borderSubtle)

            // ── Chip strip: list/section left, dates + priority right ─────────
            HStack(spacing: 4) {
                ContainerPickerBadge(
                    selection: $selectedContainer,
                    contexts: contexts,
                    areas: areas,
                    projects: projects
                )

                if showsSectionPicker {
                    TaskSectionPickerBadge(
                        selection: $selectedSectionName,
                        sections: availableSections
                    )
                }

                Spacer(minLength: 0)

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

                priorityChip
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Theme.surfaceElevated)

            Divider().background(Theme.borderSubtle)

            // ── Footer ────────────────────────────────────────────────────────
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Text("Cancel")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.cadencePlain)
                Button("Create Task") { createTask() }
                    .buttonStyle(.cadencePlain)
                    .foregroundStyle(.white)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(trimmedTitle.isEmpty ? Theme.blue.opacity(0.45) : Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .disabled(trimmedTitle.isEmpty)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .padding(.trailing, 12)
            }
            .padding(.vertical, 2)
            .background(Theme.surfaceElevated)
        }
        .frame(width: 600)
        .background(Theme.surface)
        .onAppear {
            normalizeSelectedSection()
            DispatchQueue.main.async { isTitleFocused = true }
        }
        .onChange(of: selectedContainer) { _, _ in normalizeSelectedSection() }
    }

    // MARK: - Priority chip

    private var priorityChip: some View {
        Button { showPriorityPicker.toggle() } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(Theme.priorityColor(selectedPriority))
                    .frame(width: 7, height: 7)
                ZStack(alignment: .leading) {
                    Text("Priority").opacity(0) // width anchor — widest label
                    Text(selectedPriority == .none ? "Priority" : shortPriorityLabel(selectedPriority))
                        .foregroundStyle(selectedPriority == .none ? Theme.dim : Theme.muted)
                }
                .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .opacity(selectedPriority == .none ? 0 : 1) // always takes space
            }
            .fixedSize() // lock the whole chip to its max intrinsic size
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(selectedPriority == .none ? Color.clear : Theme.priorityColor(selectedPriority).opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Theme.borderSubtle, lineWidth: selectedPriority == .none ? 0 : 1)
            )
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
        case .inbox: return false
        case .area, .project: return true
        }
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: - Tilde search data

    private struct TildeContainerItem: Identifiable {
        let tag: TaskContainerSelection
        let icon: String
        let name: String
        let color: Color
        var id: TaskContainerSelection { tag }
    }

    private var tildeFlatContainers: [TildeContainerItem] {
        let q = tildeSearchQuery.lowercased()
        func matches(_ name: String) -> Bool { q.isEmpty || name.lowercased().hasPrefix(q) }
        var result: [TildeContainerItem] = []
        if matches("Inbox") { result.append(.init(tag: .inbox, icon: "tray", name: "Inbox", color: Theme.dim)) }
        for context in contexts {
            for area in areas.filter({ $0.context?.id == context.id }).sorted(by: { $0.order < $1.order }) {
                if matches(area.name) {
                    result.append(.init(tag: .area(area.id), icon: area.icon, name: area.name, color: Color(hex: area.colorHex)))
                }
            }
            for project in projects.filter({ $0.context?.id == context.id }).sorted(by: { $0.order < $1.order }) {
                if matches(project.name) {
                    result.append(.init(tag: .project(project.id), icon: project.icon, name: project.name, color: Color(hex: project.colorHex)))
                }
            }
        }
        return result
    }

    private func createTask() {
        guard !trimmedTitle.isEmpty else { return }
        let task = AppTask(title: trimmedTitle)
        task.notes       = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        task.priority    = selectedPriority
        task.sectionName = selectedSectionName
        if hasDueDate { task.dueDate       = DateFormatters.dateKey(from: dueDate) }
        if hasDoDate  { task.scheduledDate  = DateFormatters.dateKey(from: doDate)  }
        applyContainer(task)
        modelContext.insert(task)
        if task.scheduledStartMin >= 0 { SchedulingActions.syncToCalendarIfLinked(task) }

        for (i, subtaskTitle) in subtaskTitles.enumerated() {
            let trimmed = subtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let subtask = Subtask(title: trimmed)
            subtask.parentTask = task
            subtask.order = i
            modelContext.insert(subtask)
        }

        dismiss()
        taskCreationManager.presentSuccessToast()
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

    private func shortPriorityLabel(_ p: TaskPriority) -> String {
        switch p {
        case .none:   return "N/A"
        case .low:    return "L"
        case .medium: return "M"
        case .high:   return "H"
        }
    }

    private func cyclePriority() {
        let all = TaskPriority.allCases
        let idx = all.firstIndex(of: selectedPriority) ?? 0
        selectedPriority = all[(idx + 1) % all.count]
    }

    private func selectTildeContainer() {
        let items = tildeFlatContainers
        guard !items.isEmpty else { return }
        selectTildeContainerItem(items[min(tildeHighlightIdx, items.count - 1)].tag)
    }

    private func selectTildeContainerItem(_ tag: TaskContainerSelection) {
        selectedContainer = tag
        normalizeSelectedSection()
        tildeSearchQuery  = ""
        tildeHighlightIdx = 0
        tildeMode = .section
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

    // MARK: - Tilde popover views

    private var tildeListSearchView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Local shortcut buttons so Cmd+Shift+=/- work while the popover TextField is focused
            ZStack {
                Button("") { let n = tildeFlatContainers.count; if n > 0 { tildeHighlightIdx = min(tildeHighlightIdx + 1, n - 1) } }
                    .keyboardShortcut("=", modifiers: [.command, .shift])
                Button("") { tildeHighlightIdx = max(tildeHighlightIdx - 1, 0) }
                    .keyboardShortcut("-", modifiers: [.command, .shift])
            }
            .frame(width: 0, height: 0).clipped()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.dim)
                TextField("Search lists…", text: $tildeSearchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .focused($isTildeSearchFocused)
                    .onSubmit { selectTildeContainer() }
                    .onKeyPress(.upArrow) {
                        tildeHighlightIdx = max(tildeHighlightIdx - 1, 0)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        let n = tildeFlatContainers.count
                        if n > 0 { tildeHighlightIdx = min(tildeHighlightIdx + 1, n - 1) }
                        return .handled
                    }
                    .onKeyPress(.tab) {
                        title += "~"
                        tildeMode = .none
                        DispatchQueue.main.async { isTitleFocused = true }
                        return .handled
                    }
                if !tildeSearchQuery.isEmpty {
                    Button { tildeSearchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.dim.opacity(0.5))
                    }.buttonStyle(.cadencePlain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            Divider().background(Theme.borderSubtle)

            let items = tildeFlatContainers
            if items.isEmpty {
                Text("No results").font(.system(size: 13)).foregroundStyle(Theme.dim)
                    .padding(.horizontal, 12).padding(.vertical, 10)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        TildeContainerPickerRow(
                            icon: item.icon,
                            name: item.name,
                            color: item.color,
                            isHighlighted: i == tildeHighlightIdx,
                            isSelected: selectedContainer == item.tag,
                            action: { selectTildeContainerItem(item.tag) }
                        )
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .frame(minWidth: 200)
        .background(Theme.surfaceElevated)
        .onAppear { DispatchQueue.main.async { isTildeSearchFocused = true } }
        .onChange(of: tildeSearchQuery) { _, _ in tildeHighlightIdx = 0 }
    }

    private var tildeSectionSearchView: some View {
        TildeSectionSearchPanel(
            sections: availableSections,
            selectedSectionName: selectedSectionName,
            onSelect: { section in
                selectedSectionName = section
                tildeMode = .none
                DispatchQueue.main.async { isTitleFocused = true }
            },
            onDismiss: {
                tildeMode = .none
                DispatchQueue.main.async { isTitleFocused = true }
            }
        )
    }

}

// MARK: - Tilde picker row structs

private struct TildeContainerPickerRow: View {
    let icon: String
    let name: String
    let color: Color
    let isHighlighted: Bool
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(color).frame(width: 16)
                Text(name).font(.system(size: 13)).foregroundStyle(Theme.text)
                Spacer()
                if isHighlighted {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.blue)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.cadencePlain)
        .onHover { isHovered = $0 }
    }

    private var rowBackground: Color {
        if isHighlighted { return Theme.blue.opacity(0.08) }
        if isHovered { return Theme.blue.opacity(0.06) }
        return .clear
    }
}

private struct TildeSectionPickerRow: View {
    let section: String
    let isHighlighted: Bool
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: section.caseInsensitiveCompare(TaskSectionDefaults.defaultName) == .orderedSame
                      ? "square.grid.2x2" : "rectangle.split.3x1")
                    .font(.system(size: 11)).foregroundStyle(Theme.dim).frame(width: 16)
                Text(section).font(.system(size: 13)).foregroundStyle(Theme.text)
                Spacer()
                if isHighlighted {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.blue)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.cadencePlain)
        .onHover { isHovered = $0 }
    }

    private var rowBackground: Color {
        if isHighlighted { return Theme.blue.opacity(0.08) }
        if isHovered { return Theme.blue.opacity(0.06) }
        return .clear
    }
}

private struct TildeSectionSearchPanel: View {
    let sections: [String]
    let selectedSectionName: String
    let onSelect: (String) -> Void
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var highlightIdx = 0
    @FocusState private var isSearchFocused: Bool

    private var filtered: [String] {
        query.isEmpty ? sections : sections.filter { $0.lowercased().hasPrefix(query.lowercased()) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Button("") { if !filtered.isEmpty { highlightIdx = min(highlightIdx + 1, filtered.count - 1) } }
                    .keyboardShortcut("=", modifiers: [.command, .shift])
                Button("") { highlightIdx = max(highlightIdx - 1, 0) }
                    .keyboardShortcut("-", modifiers: [.command, .shift])
            }
            .frame(width: 0, height: 0).clipped()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.dim)
                TextField("Search sections…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .focused($isSearchFocused)
                    .onSubmit { selectHighlighted() }
                    .onKeyPress(.upArrow) { highlightIdx = max(highlightIdx - 1, 0); return .handled }
                    .onKeyPress(.downArrow) {
                        if !filtered.isEmpty { highlightIdx = min(highlightIdx + 1, filtered.count - 1) }
                        return .handled
                    }
                    .onKeyPress(.tab) { onDismiss(); return .handled }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.dim.opacity(0.5))
                    }.buttonStyle(.cadencePlain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            Divider().background(Theme.borderSubtle)

            VStack(spacing: 2) {
                ForEach(filtered, id: \.self) { section in
                    TildeSectionPickerRow(
                        section: section,
                        isHighlighted: filtered.firstIndex(of: section) == highlightIdx,
                        isSelected: selectedSectionName.caseInsensitiveCompare(section) == .orderedSame,
                        action: { onSelect(section) }
                    )
                }
            }
            .padding(.vertical, 6)
        }
        .frame(minWidth: 200)
        .background(Theme.surfaceElevated)
        .onAppear { DispatchQueue.main.async { isSearchFocused = true } }
        .onChange(of: query) { _, _ in highlightIdx = 0 }
    }

    private func selectHighlighted() {
        guard !filtered.isEmpty else { return }
        onSelect(filtered[min(highlightIdx, filtered.count - 1)])
    }
}

// MARK: - TaskDateChip

private struct TaskDateChip: View {
    let label: String
    let icon: String
    var activeColor: Color = Theme.blue
    @Binding var isOn: Bool
    @Binding var date: Date
    @Binding var showPicker: Bool

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
                        .font(.system(size: 11))
                        .foregroundStyle(isOn ? effectiveIconColor : Theme.dim)
                    ZStack(alignment: .leading) {
                        // Width anchor: reserves space for both the inactive label and "Tomorrow"
                        Text(label).font(.system(size: 12)).opacity(0)
                        Text("Tomorrow").font(.system(size: 12, weight: .semibold)).opacity(0)
                        if isOn {
                            Text(displayLabel)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(isDoDate && cal.isDateInToday(date) ? .yellow : activeColor)
                        } else {
                            Text(label)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.dim)
                        }
                    }
                    .fixedSize()
                }
                .padding(.leading, 8)
                .padding(.trailing, 8)
                .padding(.vertical, 5)
                .background(
                    isOn
                        ? activeColor.opacity(isDoDate && cal.isDateInToday(date) ? 0.0 : 0.1)
                        : (isHovered ? activeColor.opacity(0.06) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(isOn ? activeColor.opacity(0.25) : Theme.borderSubtle.opacity(isHovered ? 0.8 : 0), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.cadencePlain)
            .onHover { isHovered = $0 }
            .popover(isPresented: $showPicker, arrowEdge: .top) { pickerPopover }

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
                quickPill("This Weekend", weekend: true)
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
                Button("Clear date") { isOn = false; showPicker = false }
                    .buttonStyle(.cadencePlain)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.red)
                    .padding(.bottom, 10)
            }
        }
        .background(Theme.surfaceElevated)
    }

    @ViewBuilder
    private func quickPill(_ label: String, offset: Int = 0, weekend: Bool = false) -> some View {
        let target: Date = {
            let today = cal.startOfDay(for: Date())
            if weekend {
                let todayWeekday = cal.component(.weekday, from: today)
                if todayWeekday == 7 || todayWeekday == 1 { return today }
                let daysUntilSaturday = (7 - todayWeekday + 7) % 7
                return cal.date(byAdding: .day, value: daysUntilSaturday, to: today) ?? today
            }
            return cal.date(byAdding: .day, value: offset, to: today) ?? today
        }()
        let isSelected = isOn && cal.isDate(date, inSameDayAs: target)
        Button {
            date = target; isOn = true; showPicker = false
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
