#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

struct TasksPanelHeader: View {
    let mode: TasksPanelMode

    @Environment(TaskCreationManager.self) private var taskCreationManager

    private var title: String {
        switch mode {
        case .todayOverview: return "Today"
        case .byDoDate:      return "By Do Date"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                PanelHeader(eyebrow: "Tasks", title: title)
                Spacer()
                Button {
                    switch mode {
                    case .todayOverview: taskCreationManager.present(doDateKey: DateFormatters.todayKey())
                    case .byDoDate:      taskCreationManager.present()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                        Text("New Task").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.cadencePlain)
                .padding(.top, 15)
                .padding(.trailing, 16)
            }
        }
    }
}

struct TodayOverdueListCard: View {
    let summary: TodayOverdueListSummary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(summary.color.opacity(0.16))
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: summary.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(summary.color)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text("\(DateFormatters.relativeDate(from: summary.dueDateKey)) • \(summary.activeTaskCount) active tasks")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.red)
                        .lineLimit(1)
                }

                Spacer()

                Text("List")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.red)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Theme.red.opacity(0.12))
                    .clipShape(Capsule())
            }
            .padding(12)
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.red.opacity(0.24), lineWidth: 1)
            }
        }
        .buttonStyle(.cadencePlain)
    }
}

struct TodayOverdueSectionCard: View {
    let summary: TodayOverdueSectionSummary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(summary.parentColor.opacity(0.16))
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: summary.parentIcon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(summary.parentColor)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.sectionName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text("\(summary.parentName) • \(DateFormatters.relativeDate(from: summary.dueDateKey))")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.red)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(summary.openTaskCount) open")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    if summary.completedTaskCount > 0 {
                        Text("\(summary.completedTaskCount) done")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.dim)
                    }
                }
            }
            .padding(12)
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.red.opacity(0.24), lineWidth: 1)
            }
        }
        .buttonStyle(.cadencePlain)
    }
}

struct SubtaskRow: View {
    @Bindable var subtask: Subtask
    var showDelete: Bool = false
    var onDelete: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Button { subtask.isDone.toggle() } label: {
                Image(systemName: subtask.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(subtask.isDone ? Theme.green : Theme.dim.opacity(0.6))
            }
            .buttonStyle(.cadencePlain)

            Text(subtask.title.isEmpty ? "Untitled" : subtask.title)
                .font(.system(size: 13))
                .foregroundStyle(subtask.isDone ? Theme.dim : Theme.muted)
                .strikethrough(subtask.isDone, color: Theme.dim)
                .lineLimit(1)

            Spacer(minLength: 0)

            if showDelete, let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.dim.opacity(0.5))
                }
                .buttonStyle(.cadencePlain)
            }
        }
        .padding(.vertical, 3)
    }
}

struct ContainerPickerBadge: View {
    @Binding var selection: TaskContainerSelection
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    var compact: Bool = false

    @State private var showPicker = false
    @State private var searchQuery = ""
    @State private var highlightIdx = 0
    @FocusState private var isSearchFocused: Bool

    private var label: String {
        switch selection {
        case .inbox:           return "Inbox"
        case .area(let id):    return areas.first(where: { $0.id == id })?.name ?? "Area"
        case .project(let id): return projects.first(where: { $0.id == id })?.name ?? "Project"
        }
    }

    private var labelIcon: String {
        switch selection {
        case .inbox:           return "tray"
        case .area(let id):    return areas.first(where: { $0.id == id })?.icon ?? "tray"
        case .project(let id): return projects.first(where: { $0.id == id })?.icon ?? "tray"
        }
    }

    private var labelColor: Color {
        switch selection {
        case .inbox:           return Theme.dim
        case .area(let id):    return areas.first(where: { $0.id == id }).map { Color(hex: $0.colorHex) } ?? Theme.dim
        case .project(let id): return projects.first(where: { $0.id == id }).map { Color(hex: $0.colorHex) } ?? Theme.dim
        }
    }

    private var groupedContainers: [(context: Context, areas: [Area], projects: [Project])] {
        contexts.compactMap { context in
            let matchingAreas = areas
                .filter { $0.context?.id == context.id }
                .sorted { $0.order < $1.order }
            let matchingProjects = projects
                .filter { $0.context?.id == context.id }
                .sorted { $0.order < $1.order }
            guard !matchingAreas.isEmpty || !matchingProjects.isEmpty else { return nil }
            return (context, matchingAreas, matchingProjects)
        }
    }

    private func matches(_ name: String) -> Bool {
        searchQuery.isEmpty || name.lowercased().hasPrefix(searchQuery.lowercased())
    }

    private var filteredGroupedContainers: [(context: Context, areas: [Area], projects: [Project])] {
        groupedContainers.compactMap { group in
            let filteredAreas = group.areas.filter { matches($0.name) }
            let filteredProjects = group.projects.filter { matches($0.name) }
            guard !filteredAreas.isEmpty || !filteredProjects.isEmpty else { return nil }
            return (group.context, filteredAreas, filteredProjects)
        }
    }

    private var flatFiltered: [TaskContainerSelection] {
        var result: [TaskContainerSelection] = []
        if matches("Inbox") { result.append(.inbox) }
        for group in filteredGroupedContainers {
            for area in group.areas { result.append(.area(area.id)) }
            for project in group.projects { result.append(.project(project.id)) }
        }
        return result
    }

    private var highlightedTag: TaskContainerSelection? {
        guard !flatFiltered.isEmpty else { return nil }
        return flatFiltered[min(highlightIdx, flatFiltered.count - 1)]
    }

    private func selectHighlighted() {
        guard let tag = highlightedTag else { return }
        selection = tag
        showPicker = false
    }

    var body: some View {
        Button { showPicker.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: labelIcon).font(.system(size: compact ? 9 : 10)).foregroundStyle(labelColor)
                Text(label)
                    .font(.system(size: compact ? 10 : 11))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: compact ? 60 : 80, alignment: .leading)
                Image(systemName: "chevron.down").font(.system(size: compact ? 7 : 8, weight: .semibold)).foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 3 : 6)
            .frame(minHeight: compact ? 21 : 28)
            .contentShape(Rectangle())
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: compact ? 6 : 7))
        }
        .buttonStyle(.cadencePlain)
        .popover(isPresented: $showPicker) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                    TextField("Search…", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                        .focused($isSearchFocused)
                        .onSubmit { selectHighlighted() }
                        .onKeyPress(.upArrow) {
                            highlightIdx = max(highlightIdx - 1, 0)
                            return .handled
                        }
                        .onKeyPress(.downArrow) {
                            let count = flatFiltered.count
                            if count > 0 { highlightIdx = min(highlightIdx + 1, count - 1) }
                            return .handled
                        }
                    if !searchQuery.isEmpty {
                        Button { searchQuery = "" } label: {
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

                VStack(alignment: .leading, spacing: 2) {
                    if matches("Inbox") {
                        ContainerPickerRow(
                            icon: "tray",
                            name: "Inbox",
                            color: Theme.dim,
                            isHighlighted: highlightedTag == .inbox,
                            isSelected: selection == .inbox,
                            action: {
                                selection = .inbox
                                showPicker = false
                            }
                        )
                    }

                    if !filteredGroupedContainers.isEmpty {
                        Divider().background(Theme.borderSubtle).padding(.vertical, 2)

                        ForEach(filteredGroupedContainers, id: \.context.id) { group in
                            Text(group.context.name.uppercased())
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color(hex: group.context.colorHex))
                                .kerning(0.6)
                                .padding(.horizontal, 12)
                                .padding(.top, 6)
                                .padding(.bottom, 2)

                            ForEach(group.areas) { area in
                                ContainerPickerRow(
                                    icon: area.icon,
                                    name: area.name,
                                    color: Color(hex: area.colorHex),
                                    isHighlighted: highlightedTag == .area(area.id),
                                    isSelected: selection == .area(area.id),
                                    action: {
                                        selection = .area(area.id)
                                        showPicker = false
                                    }
                                )
                            }

                            ForEach(group.projects) { project in
                                ContainerPickerRow(
                                    icon: project.icon,
                                    name: project.name,
                                    color: Color(hex: project.colorHex),
                                    isHighlighted: highlightedTag == .project(project.id),
                                    isSelected: selection == .project(project.id),
                                    action: {
                                        selection = .project(project.id)
                                        showPicker = false
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(minWidth: 190)
            .background(Theme.surfaceElevated)
            .onAppear {
                highlightIdx = 0
                DispatchQueue.main.async { isSearchFocused = true }
            }
            .onChange(of: showPicker) { _, isShown in
                if !isShown {
                    searchQuery = ""
                    highlightIdx = 0
                }
            }
            .onChange(of: searchQuery) { _, _ in
                highlightIdx = 0
            }
        }
    }
}

struct TaskSectionPickerBadge: View {
    @Binding var selection: String
    let sections: [String]

    @State private var showPicker = false
    @State private var searchQuery = ""
    @State private var highlightIdx = 0
    @FocusState private var isSearchFocused: Bool

    private var resolvedSections: [String] {
        let cleaned = sections
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return cleaned.isEmpty ? [TaskSectionDefaults.defaultName] : cleaned
    }

    private var filteredSections: [String] {
        guard !searchQuery.isEmpty else { return resolvedSections }
        return resolvedSections.filter { $0.lowercased().hasPrefix(searchQuery.lowercased()) }
    }

    private var highlightedSection: String? {
        guard !filteredSections.isEmpty else { return nil }
        return filteredSections[min(highlightIdx, filteredSections.count - 1)]
    }

    private var label: String {
        resolvedSections.first(where: { $0.caseInsensitiveCompare(selection) == .orderedSame }) ?? TaskSectionDefaults.defaultName
    }

    var body: some View {
        Button { showPicker.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: "square.split.2x1")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.dim)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 70, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.cadencePlain)
        .popover(isPresented: $showPicker) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                    TextField("Search…", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                        .focused($isSearchFocused)
                        .onSubmit {
                            if let section = highlightedSection {
                                selection = section
                                showPicker = false
                            }
                        }
                        .onKeyPress(.upArrow) {
                            highlightIdx = max(highlightIdx - 1, 0)
                            return .handled
                        }
                        .onKeyPress(.downArrow) {
                            let count = filteredSections.count
                            if count > 0 { highlightIdx = min(highlightIdx + 1, count - 1) }
                            return .handled
                        }
                    if !searchQuery.isEmpty {
                        Button { searchQuery = "" } label: {
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

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredSections, id: \.self) { section in
                        SectionPickerRow(
                            section: section,
                            isHighlighted: section == highlightedSection,
                            isSelected: section.caseInsensitiveCompare(selection) == .orderedSame,
                            action: {
                                selection = section
                                showPicker = false
                            }
                        )
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(minWidth: 170)
            .background(Theme.surfaceElevated)
            .onAppear {
                highlightIdx = 0
                DispatchQueue.main.async { isSearchFocused = true }
            }
            .onChange(of: showPicker) { _, isShown in
                if !isShown {
                    searchQuery = ""
                    highlightIdx = 0
                }
            }
            .onChange(of: searchQuery) { _, _ in
                highlightIdx = 0
            }
        }
    }
}

private struct ContainerPickerRow: View {
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
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
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

private struct SectionPickerRow: View {
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
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 16)
                Text(section).font(.system(size: 13)).foregroundStyle(Theme.text)
                Spacer()
                if isHighlighted {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.blue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
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

struct TaskPickerRowHover: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Theme.blue.opacity(0.06) : Color.clear)
            )
            .onHover { isHovered = $0 }
    }
}

struct CollapsibleTaskGroupHeader: View {
    let title: String
    let isCollapsed: Bool
    let overdueCount: Int?
    let regularCount: Int
    var accent: Color = Theme.dim
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                if let overdueCount, overdueCount > 0 {
                    Text("\(overdueCount)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.red)
                    Text("/")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.dim.opacity(0.8))
                }
                Text("\(regularCount)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(accent.opacity(0.12))
                    .clipShape(Capsule())
            }
            .foregroundStyle(Theme.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.surface.opacity(0.35))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.borderSubtle.opacity(0.55))
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.cadencePlain)
        .onTapGesture(count: 2, perform: onToggle)
    }
}

struct CompletedSectionHeader: View {
    let count: Int
    var isCollapsed: Bool = false
    var onToggle: (() -> Void)? = nil

    var body: some View {
        CollapsibleTaskGroupHeader(
            title: "Completed",
            isCollapsed: isCollapsed,
            overdueCount: nil,
            regularCount: count,
            accent: Theme.green,
            onToggle: { onToggle?() }
        )
        .allowsHitTesting(onToggle != nil)
        .overlay {
            if onToggle == nil {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.clear)
                    .allowsHitTesting(false)
            }
        }
    }
}

struct StaticTaskGroupHeader: View {
    let title: String
    let overdueCount: Int?
    let regularCount: Int

    var body: some View {
        CollapsibleTaskGroupHeader(
            title: title,
            isCollapsed: false,
            overdueCount: overdueCount,
            regularCount: regularCount,
            onToggle: {}
        )
        .allowsHitTesting(false)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.clear)
                .allowsHitTesting(false)
        }
    }
}

struct CadenceEnumPickerBadge<T: CaseIterable & RawRepresentable & Identifiable>: View where T.RawValue == String {
    let title: String
    @Binding var selection: T
    var excluded: [T] = []
    @State private var showPicker = false

    private var availableCases: [T] {
        Array(T.allCases).filter { item in !excluded.contains(where: { $0.id == item.id }) }
    }

    var body: some View {
        Button { showPicker.toggle() } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                Text(selection.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.text)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.cadencePlain)
        .popover(isPresented: $showPicker) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(availableCases, id: \.id) { value in
                    Button {
                        selection = value
                        showPicker = false
                    } label: {
                        HStack(spacing: 8) {
                            Text(value.rawValue).font(.system(size: 13)).foregroundStyle(Theme.text)
                            Spacer()
                            if selection.id == value.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.blue)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .background(selection.id == value.id ? Theme.blue.opacity(0.08) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.cadencePlain)
                }
            }
            .padding(.vertical, 6)
            .frame(minWidth: 170)
            .background(Theme.surfaceElevated)
        }
    }
}
#endif
