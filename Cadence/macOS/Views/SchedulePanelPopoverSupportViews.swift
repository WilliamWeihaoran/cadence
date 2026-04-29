#if os(macOS)
import SwiftUI
import SwiftData
import EventKit

enum TaskDetailPresentationMode {
    case full
    case subtasksOnly
}

struct TaskDetailHeaderSection: View {
    @Bindable var task: AppTask
    @Binding var showPriorityPicker: Bool
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    let taskContainerBinding: Binding<TaskContainerSelection>

    enum TildeMode {
        case none
        case list
        case section
    }

    private struct TildeContainerItem: Identifiable {
        let tag: TaskContainerSelection
        let icon: String
        let name: String
        let color: Color
        var id: TaskContainerSelection { tag }
    }

    @State private var tildeMode: TildeMode = .none
    @State private var tildeSearchQuery = ""
    @State private var tildeHighlightIdx = 0
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isTildeSearchFocused: Bool

    var body: some View {
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
                ZStack(alignment: .leading) {
                    TextField("Task title", text: $task.title, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1...8)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)
                        .focused($isTitleFocused)
                        .onChange(of: task.title) { _, newVal in
                            if newVal.hasSuffix("~") {
                                let prefix = String(newVal.dropLast())
                                if prefix.isEmpty || prefix.hasSuffix(" ") {
                                    task.title = prefix
                                    tildeSearchQuery = ""
                                    tildeHighlightIdx = 0
                                    tildeMode = .list
                                }
                            }
                        }
                        .opacity(tildeMode == .none ? 1 : 0)
                        .allowsHitTesting(tildeMode == .none)

                    if tildeMode != .none {
                        HStack(spacing: 4) {
                            if !task.title.isEmpty {
                                Text(task.title)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(1)
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
                                    isPresented: Binding(
                                        get: { tildeMode != .none },
                                        set: { if !$0 { tildeMode = .none } }
                                    ),
                                    arrowEdge: .bottom
                                ) {
                                    if tildeMode == .list {
                                        tildeListSearchView
                                    } else {
                                        tildeSectionSearchView
                                    }
                                }
                        }
                    }
                }

                Text(scheduleDescriptor)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Theme.surfaceElevated.opacity(0.7))
                    .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { showPriorityPicker.toggle() } label: {
                TaskPriorityPill(priority: task.priority, selected: task.priority != .none)
            }
            .buttonStyle(.cadencePlain)
            .fixedSize()
            .popover(isPresented: $showPriorityPicker, arrowEdge: .bottom) {
                TaskPriorityPickerPopover(priority: $task.priority, isPresented: $showPriorityPicker)
            }
        }
    }

    private var timeRange: String {
        TimeFormatters.timeRange(startMin: task.scheduledStartMin, endMin: task.scheduledStartMin + max(task.estimatedMinutes, 5))
    }

    private var availableSections: [String] {
        switch taskContainerBinding.wrappedValue {
        case .inbox:
            return [TaskSectionDefaults.defaultName]
        case .area(let areaID):
            return areas.first(where: { $0.id == areaID })?.sectionNames ?? [TaskSectionDefaults.defaultName]
        case .project(let projectID):
            return projects.first(where: { $0.id == projectID })?.sectionNames ?? [TaskSectionDefaults.defaultName]
        }
    }

    private var tildeFlatContainers: [TildeContainerItem] {
        let q = tildeSearchQuery.lowercased()
        func matches(_ name: String) -> Bool { q.isEmpty || name.lowercased().hasPrefix(q) }

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
        if !validSections.contains(where: { $0.caseInsensitiveCompare(task.sectionName) == .orderedSame }) {
            task.sectionName = validSections.first ?? TaskSectionDefaults.defaultName
        }
    }

    private func selectTildeContainer() {
        let items = tildeFlatContainers
        guard !items.isEmpty else { return }
        selectTildeContainerItem(items[min(tildeHighlightIdx, items.count - 1)].tag)
    }

    private func selectTildeContainerItem(_ tag: TaskContainerSelection) {
        taskContainerBinding.wrappedValue = tag
        normalizeSelectedSection()
        tildeSearchQuery = ""
        tildeHighlightIdx = 0
        tildeMode = .section
    }

    private var tildeListSearchView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Button("") {
                    let n = tildeFlatContainers.count
                    if n > 0 { tildeHighlightIdx = min(tildeHighlightIdx + 1, n - 1) }
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
                        let n = tildeFlatContainers.count
                        if n > 0 { tildeHighlightIdx = min(tildeHighlightIdx + 1, n - 1) }
                        return .handled
                    }
                    .onKeyPress(.tab) {
                        task.title += "~"
                        tildeMode = .none
                        DispatchQueue.main.async { isTitleFocused = true }
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
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        TildeContainerPickerRow(
                            icon: item.icon,
                            name: item.name,
                            color: item.color,
                            isHighlighted: i == tildeHighlightIdx,
                            isSelected: taskContainerBinding.wrappedValue == item.tag,
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
            selectedSectionName: task.sectionName,
            onSelect: { section in
                task.sectionName = section
                tildeMode = .none
                DispatchQueue.main.async { isTitleFocused = true }
            },
            onDismiss: {
                tildeMode = .none
                DispatchQueue.main.async { isTitleFocused = true }
            }
        )
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
}

struct TaskPriorityPickerPopover: View {
    @Binding var priority: TaskPriority
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(TaskPriority.allCases, id: \.self) { value in
                Button {
                    priority = value
                    isPresented = false
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Theme.priorityColor(value))
                            .frame(width: 7, height: 7)
                        Text(value.label)
                            .font(.system(size: 13))
                            .foregroundStyle(priority == value ? Theme.text : Theme.muted)
                        Spacer()
                        if priority == value {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.blue)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(priority == value ? Theme.blue.opacity(0.08) : Color.clear)
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

struct TaskDetailCompactOverviewSection: View {
    @Bindable var task: AppTask
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    let taskContainerBinding: Binding<TaskContainerSelection>
    let availableSections: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TaskInspectorInfoCard {
                inspectorBandTitle("When")

                HStack(alignment: .top, spacing: 8) {
                    compactField("Do", icon: "calendar") {
                        TaskInspectorDateControl(
                            label: "Set do",
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

                    compactField("Due", icon: "calendar.badge.exclamationmark") {
                        TaskInspectorDateControl(
                            label: "Set due",
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
                }

                HStack(alignment: .top, spacing: 8) {
                    compactField("Estimate", icon: "clock") {
                        EstimatePickerControl(value: $task.estimatedMinutes)
                    }

                    compactField("Repeats", icon: "arrow.clockwise") {
                        TaskInspectorRecurrenceControl(task: task)
                    }

                    if task.actualMinutes > 0 {
                        compactField("Actual", icon: "clock.badge.checkmark") {
                            MinutesField(value: $task.actualMinutes)
                        }
                    }
                }
            }

            TaskInspectorInfoCard {
                inspectorBandTitle("Place")

                HStack(alignment: .top, spacing: 8) {
                    compactField("List", icon: "tray.full") {
                        ContainerPickerBadge(selection: taskContainerBinding, contexts: contexts, areas: areas, projects: projects)
                    }

                    compactField("Section", icon: "square.split.2x1") {
                        TaskSectionPickerBadge(selection: $task.sectionName, sections: availableSections)
                    }
                }
            }

            TaskInspectorInfoCard {
                inspectorBandTitle("Event")

                compactWideField("Event", icon: "link") {
                    TaskInspectorEventAttachmentControl(task: task)
                }
            }
        }
    }

    @ViewBuilder
    private func compactField<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            } icon: {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }
            .labelStyle(.titleAndIcon)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func compactWideField<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Label {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            } icon: {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }
            .labelStyle(.titleAndIcon)
            .frame(width: 78, alignment: .leading)
            .padding(.top, 5)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func inspectorBandTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Theme.dim.opacity(0.82))
    }
}

#endif
