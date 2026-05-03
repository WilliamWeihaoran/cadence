#if os(macOS)
import SwiftUI
import EventKit
import SwiftData

struct QuickCreateChoicePopover: View {
    enum TildeMode { case none, list, section }
    enum Mode { case timeBlock, calendarEvent, bundle }

    let startMin: Int
    let endMin: Int
    let dateKey: String
    let onCreateTask: (String, TaskContainerSelection, String, String, [String]) -> Void
    let onCreateBundle: ((String, [AppTask]) -> Void)?
    let onCreateEvent: ((String, String, String) -> Void)?
    let onCancel: () -> Void

    @Environment(CalendarManager.self) private var calendarManager
    @Query(sort: \AppTask.createdAt, order: .reverse) private var allTasks: [AppTask]
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @State private var mode: Mode
    @State private var title = ""
    @State private var selectedCalendarID = ""
    @State private var notes = ""
    @State private var subtaskDraft = ""
    @State private var subtaskTitles: [String] = []
    @State private var selectedContainer: TaskContainerSelection = .inbox
    @State private var selectedSectionName: String = TaskSectionDefaults.defaultName
    @State private var tildeMode: TildeMode = .none
    @State private var tildeSearchQuery = ""
    @State private var tildeHighlightIdx = 0
    @State private var bundleTaskSearch = ""
    @State private var selectedBundleTaskIDs: [UUID] = []
    @FocusState private var focused: Bool
    @FocusState private var isTildeSearchFocused: Bool
    private let modeFormMinHeight: CGFloat = 280

    init(
        startMin: Int,
        endMin: Int,
        dateKey: String,
        onCreateTask: @escaping (String, TaskContainerSelection, String, String, [String]) -> Void,
        onCreateBundle: ((String, [AppTask]) -> Void)? = nil,
        onCreateEvent: ((String, String, String) -> Void)?,
        onCancel: @escaping () -> Void,
        defaultsToCalendarEvent: Bool = false
    ) {
        self.startMin = startMin
        self.endMin = endMin
        self.dateKey = dateKey
        self.onCreateTask = onCreateTask
        self.onCreateBundle = onCreateBundle
        self.onCreateEvent = onCreateEvent
        self.onCancel = onCancel
        let initialMode: Mode = defaultsToCalendarEvent && onCreateEvent != nil ? .calendarEvent : .timeBlock
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(TimeFormatters.timeRange(startMin: startMin, endMin: endMin))
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)

            modeSelector

            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .leading) {
                    TextField(titlePlaceholder, text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .focused($focused)
                        .onSubmit { create() }
                        .onChange(of: title) { _, newValue in
                            guard mode == .timeBlock, newValue.hasSuffix("~") else { return }
                            let prefix = String(newValue.dropLast())
                            if prefix.isEmpty || prefix.hasSuffix(" ") {
                                title = prefix
                                tildeSearchQuery = ""
                                tildeHighlightIdx = 0
                                tildeMode = .list
                            }
                        }
                        .opacity(tildeMode == .none ? 1 : 0)
                        .allowsHitTesting(tildeMode == .none)

                    if tildeMode != .none {
                        HStack(spacing: 4) {
                            if !title.isEmpty {
                                Text(title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                    .fixedSize()
                            }
                            Text("~")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Theme.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            Spacer(minLength: 0)
                        }
                    }
                }

                if tildeMode != .none {
                    tildeInlineSearchView
                }

                if mode == .timeBlock {
                    taskDetailsView
                } else if mode == .calendarEvent {
                    let _ = calendarManager.storeVersion
                    let calendars = calendarManager.writableCalendars
                    if !calendars.isEmpty {
                        CadenceCalendarPickerButton(
                            calendars: calendars,
                            selectedID: $selectedCalendarID,
                            allowNone: false,
                            style: .compact
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.dim)

                        TextEditor(text: $notes)
                            .scrollContentBackground(.hidden)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.text)
                            .frame(minHeight: 84)
                            .padding(8)
                            .background(Theme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                } else if mode == .bundle {
                    bundleTaskSelectionView
                }
            }
            .frame(minHeight: modeFormMinHeight, alignment: .topLeading)

            HStack(spacing: 8) {
                CadenceActionButton(
                    title: "Cancel",
                    role: .ghost,
                    size: .compact
                ) {
                    onCancel()
                }
                Spacer()
                CadenceActionButton(
                    title: "Create",
                    role: .secondary,
                    size: .compact,
                    tint: mode == .bundle ? Theme.amber : Theme.blue,
                    isDisabled: mode == .calendarEvent && selectedCalendar == nil
                ) {
                    create()
                }
            }
        }
        .padding(14)
        .frame(width: mode == .bundle ? 326 : 316)
        .background(Theme.surface)
        .onAppear {
            focused = true
            normalizeSelectedSection()
            if selectedCalendar == nil,
               let calendar = calendarManager.defaultWritableCalendar {
                selectedCalendarID = calendar.calendarIdentifier
            }
        }
    }

    private func create() {
        if mode == .timeBlock {
            let pendingSubtask = subtaskDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedSubtasks = pendingSubtask.isEmpty ? subtaskTitles : subtaskTitles + [pendingSubtask]
            onCreateTask(title, selectedContainer, selectedSectionName, notes, resolvedSubtasks)
        } else if mode == .bundle {
            onCreateBundle?(
                title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Task Bundle" : title,
                selectedBundleTasks
            )
        } else {
            onCreateEvent?(title, selectedCalendar?.calendarIdentifier ?? selectedCalendarID, notes)
        }
    }

    private var titlePlaceholder: String {
        switch mode {
        case .timeBlock: return "Task title"
        case .bundle: return "Bundle title"
        case .calendarEvent: return "Event title"
        }
    }

    private var selectedCalendar: EKCalendar? {
        calendarManager.writableCalendars.first { $0.calendarIdentifier == selectedCalendarID }
            ?? calendarManager.defaultWritableCalendar
    }

    private var selectedBundleTaskSet: Set<UUID> {
        Set(selectedBundleTaskIDs)
    }

    private var selectedBundleTasks: [AppTask] {
        selectedBundleTaskIDs.compactMap { id in
            allTasks.first { $0.id == id }
        }
    }

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

    private struct TildeContainerItem: Identifiable {
        let tag: TaskContainerSelection
        let icon: String
        let name: String
        let color: Color
        var id: TaskContainerSelection { tag }
    }

    private var tildeFlatContainers: [TildeContainerItem] {
        let query = tildeSearchQuery.lowercased()
        func matches(_ name: String) -> Bool { query.isEmpty || name.lowercased().hasPrefix(query) }

        var result: [TildeContainerItem] = []
        if matches("Inbox") {
            result.append(.init(tag: .inbox, icon: "tray", name: "Inbox", color: Theme.dim))
        }
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

    private func normalizeSelectedSection() {
        let validSections = availableSections
        if !validSections.contains(where: { $0.caseInsensitiveCompare(selectedSectionName) == .orderedSame }) {
            selectedSectionName = validSections.first ?? TaskSectionDefaults.defaultName
        }
    }

    private func selectTildeContainer() {
        let items = tildeFlatContainers
        guard !items.isEmpty else { return }
        selectTildeContainerItem(items[min(tildeHighlightIdx, items.count - 1)].tag)
    }

    private func selectTildeContainerItem(_ tag: TaskContainerSelection) {
        selectedContainer = tag
        normalizeSelectedSection()
        tildeSearchQuery = ""
        tildeHighlightIdx = 0
        tildeMode = .section
    }

    private var tildeListSearchView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Button("") {
                    let count = tildeFlatContainers.count
                    if count > 0 { tildeHighlightIdx = min(tildeHighlightIdx + 1, count - 1) }
                }
                .keyboardShortcut("=", modifiers: [.command, .shift])
                Button("") { tildeHighlightIdx = max(tildeHighlightIdx - 1, 0) }
                    .keyboardShortcut("-", modifiers: [.command, .shift])
            }
            .frame(width: 0, height: 0)
            .clipped()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
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
                        let count = tildeFlatContainers.count
                        if count > 0 { tildeHighlightIdx = min(tildeHighlightIdx + 1, count - 1) }
                        return .handled
                    }
                    .onKeyPress(.tab) {
                        title += "~"
                        tildeMode = .none
                        DispatchQueue.main.async { focused = true }
                        return .handled
                    }
                if !tildeSearchQuery.isEmpty {
                    Button { tildeSearchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.dim.opacity(0.5))
                    }
                    .buttonStyle(.cadencePlain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().background(Theme.borderSubtle)

            let items = tildeFlatContainers
            if items.isEmpty {
                Text("No results")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        TildeContainerPickerRow(
                            icon: item.icon,
                            name: item.name,
                            color: item.color,
                            isHighlighted: index == tildeHighlightIdx,
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

    @ViewBuilder
    private var tildeInlineSearchView: some View {
        Group {
            if tildeMode == .list {
                tildeListSearchView
            } else {
                tildeSectionSearchView
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.borderSubtle.opacity(0.8), lineWidth: 1)
        )
    }

    private var tildeSectionSearchView: some View {
        TildeSectionSearchPanel(
            sections: availableSections,
            selectedSectionName: selectedSectionName,
            onSelect: { section in
                selectedSectionName = section
                tildeMode = .none
                DispatchQueue.main.async { focused = true }
            },
            onDismiss: {
                tildeMode = .none
                DispatchQueue.main.async { focused = true }
            }
        )
    }

    private var bundleTaskSelectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(selectedBundleTaskIDs.isEmpty ? "Add tasks now" : "\(selectedBundleTaskIDs.count) selected")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                Spacer()
                if !selectedBundleTaskIDs.isEmpty {
                    Button("Clear") {
                        selectedBundleTaskIDs.removeAll()
                    }
                    .buttonStyle(.cadencePlain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                }
            }

            if !selectedBundleTasks.isEmpty {
                VStack(spacing: 5) {
                    ForEach(selectedBundleTasks) { task in
                        selectedBundleTaskRow(task)
                    }
                }
            }

            TaskBundleTaskPickerPanel(
                bundleDateKey: dateKey,
                allTasks: allTasks,
                areas: areas,
                projects: projects,
                excludedTaskIDs: selectedBundleTaskSet,
                searchText: $bundleTaskSearch,
                maxHeight: 188,
                onAdd: addSelectedBundleTask
            )
        }
    }

    private func selectedBundleTaskRow(_ task: AppTask) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.amber)
            Text(task.title.isEmpty ? "Untitled" : task.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(max(task.estimatedMinutes, 5))m")
                .font(.system(size: 10))
                .foregroundStyle(Theme.dim)
            Button {
                selectedBundleTaskIDs.removeAll { $0 == task.id }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.cadencePlain)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Theme.surfaceElevated.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func addSelectedBundleTask(_ task: AppTask) {
        guard !selectedBundleTaskIDs.contains(task.id) else { return }
        selectedBundleTaskIDs.append(task.id)
        bundleTaskSearch = ""
    }

    private var taskDetailsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                ContainerPickerBadge(
                    selection: $selectedContainer,
                    contexts: contexts,
                    areas: areas,
                    projects: projects
                )
                .onChange(of: selectedContainer) { normalizeSelectedSection() }

                sectionPicker
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Notes")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)

                TextEditor(text: $notes)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text)
                    .frame(minHeight: 72)
                    .padding(8)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Subtasks")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)

                if !subtaskTitles.isEmpty {
                    VStack(spacing: 5) {
                        ForEach(Array(subtaskTitles.enumerated()), id: \.offset) { index, title in
                            subtaskRow(title: title, index: index)
                        }
                    }
                }

                HStack(spacing: 7) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                    TextField("Add subtask...", text: $subtaskDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text)
                        .onSubmit { commitSubtaskDraft() }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .background(Theme.surfaceElevated.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var sectionPicker: some View {
        Menu {
            ForEach(availableSections, id: \.self) { section in
                Button(section) {
                    selectedSectionName = section
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                Text(selectedSectionName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .frame(maxWidth: 92, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(minHeight: 28)
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.cadencePlain)
    }

    private func subtaskRow(title: String, index: Int) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dim)
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button {
                subtaskTitles.remove(at: index)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.cadencePlain)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Theme.surfaceElevated.opacity(0.52))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func commitSubtaskDraft() {
        let trimmed = subtaskDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        subtaskTitles.append(trimmed)
        subtaskDraft = ""
    }

    @ViewBuilder
    private var modeSelector: some View {
        if onCreateEvent != nil || onCreateBundle != nil {
            HStack(spacing: 6) {
                modeButton("Task", for: .timeBlock, tint: Theme.blue)
                if onCreateEvent != nil {
                    modeButton("Event", for: .calendarEvent, tint: Theme.purple)
                }
                if onCreateBundle != nil {
                    modeButton("Bundle", for: .bundle, tint: Theme.amber)
                }
            }
        }
    }

    @ViewBuilder
    private func modeButton(_ label: String, for target: Mode, tint: Color) -> some View {
        Button {
            selectMode(target)
        } label: {
            let isSelected = mode == target
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? tint : Theme.dim)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 28)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? tint.opacity(0.12) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? tint.opacity(0.24) : Theme.borderSubtle.opacity(0.38), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.cadencePlain)
    }

    private func selectMode(_ target: Mode) {
        mode = target
        tildeMode = .none
        if target == .bundle,
           title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            title = "Task Bundle"
        } else if target != .bundle,
                  title.trimmingCharacters(in: .whitespacesAndNewlines) == "Task Bundle" {
            title = ""
        }
        if target == .calendarEvent,
           selectedCalendar == nil,
           let calendar = calendarManager.defaultWritableCalendar {
            selectedCalendarID = calendar.calendarIdentifier
        }
    }
}
#endif
