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
    @State private var tildeMode: TildeMode = .none
    @State private var tildeSearchQuery   = ""
    @State private var tildeHighlightIdx  = 0
    // showLocalSuccessToast removed — global toast used instead
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

                TagPickerControl(
                    selectedTags: $selectedTags,
                    allTags: tags,
                    onCreateTag: createTag
                )

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
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                CadenceActionButton(
                    title: "Cancel",
                    role: .ghost,
                    size: .regular
                ) {
                    dismiss()
                }
                CadenceActionButton(
                    title: "Create Task",
                    role: .primary,
                    size: .regular,
                    isDisabled: trimmedTitle.isEmpty,
                    shortcut: KeyboardShortcut(.return, modifiers: [.command])
                ) {
                    createTask()
                }
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
        let draft = TaskCreationDraft(
            title: title,
            notes: notes,
            priority: selectedPriority,
            container: selectedContainer,
            sectionName: selectedSectionName,
            dueDateKey: hasDueDate ? DateFormatters.dateKey(from: dueDate) : "",
            scheduledDateKey: hasDoDate ? DateFormatters.dateKey(from: doDate) : "",
            subtaskTitles: subtaskTitles,
            tags: selectedTags
        )
        guard TaskCreationService(areas: areas, projects: projects).insertTask(from: draft, into: modelContext) != nil else {
            return
        }

        if dismissAction != nil {
            // Quick panel: close immediately, then show global toast after panel has dismissed
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                taskCreationManager.presentSuccessToast()
            }
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

#endif
