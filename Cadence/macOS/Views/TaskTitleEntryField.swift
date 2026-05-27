#if os(macOS)
import SwiftUI

struct TaskTitleEntryField: View {
    @Binding var title: String
    let placeholder: String
    let font: Font
    let previewFont: Font
    let lineLimit: ClosedRange<Int>
    let autofocus: Bool
    let onSubmit: (() -> Void)?
    let onDateNudge: ((Int) -> Void)?
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    let containerSelection: Binding<TaskContainerSelection>?
    let sectionName: Binding<String>?

    @State private var tildeMode: TaskTitleTildeMode = .none
    @State private var tildeSearchQuery = ""
    @State private var tildeHighlightIdx = 0
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isTildeSearchFocused: Bool

    init(
        title: Binding<String>,
        placeholder: String,
        font: Font,
        previewFont: Font? = nil,
        lineLimit: ClosedRange<Int> = 1...1,
        autofocus: Bool = false,
        contexts: [Context] = [],
        areas: [Area] = [],
        projects: [Project] = [],
        containerSelection: Binding<TaskContainerSelection>? = nil,
        sectionName: Binding<String>? = nil,
        onDateNudge: ((Int) -> Void)? = nil,
        onSubmit: (() -> Void)? = nil
    ) {
        self._title = title
        self.placeholder = placeholder
        self.font = font
        self.previewFont = previewFont ?? font
        self.lineLimit = lineLimit
        self.autofocus = autofocus
        self.contexts = contexts
        self.areas = areas
        self.projects = projects
        self.containerSelection = containerSelection
        self.sectionName = sectionName
        self.onDateNudge = onDateNudge
        self.onSubmit = onSubmit
    }

    var body: some View {
        ZStack(alignment: .leading) {
            hiddenShortcutButtons

            TextField(placeholder, text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(font)
                .foregroundStyle(Theme.text)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                .focused($isTitleFocused)
                .onSubmit {
                    title = TaskTitleSupport.normalized(title)
                    onSubmit?()
                }
                .onChange(of: title) { _, newValue in
                    guard canUseTildeRouting,
                          let prefix = TaskTitleSupport.titleBeforeContainerShortcut(in: newValue) else {
                        return
                    }
                    title = prefix
                    tildeSearchQuery = ""
                    tildeHighlightIdx = 0
                    tildeMode = .list
                }
                .opacity(tildeMode == .none ? 1 : 0)
                .allowsHitTesting(tildeMode == .none)

            if tildeMode != .none {
                tildePreview
            }
        }
        .onAppear {
            guard autofocus else { return }
            DispatchQueue.main.async { isTitleFocused = true }
        }
    }

    private var canUseTildeRouting: Bool {
        containerSelection != nil && sectionName != nil
    }

    private var availableSections: [String] {
        guard let containerSelection else { return [TaskSectionDefaults.defaultName] }
        return TaskContainerResolver(areas: areas, projects: projects)
            .availableSections(for: containerSelection.wrappedValue)
    }

    private var tildeFlatContainers: [TaskTitleTildeContainerItem] {
        let query = tildeSearchQuery.lowercased()
        func matches(_ name: String) -> Bool {
            query.isEmpty || name.lowercased().hasPrefix(query)
        }

        var result: [TaskTitleTildeContainerItem] = []
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

    private var hiddenShortcutButtons: some View {
        ZStack {
            Button("") {
                if tildeMode == .list {
                    moveTildeHighlight(by: 1)
                } else if tildeMode == .none {
                    onDateNudge?(1)
                }
            }
            .keyboardShortcut("=", modifiers: [.command, .shift])

            Button("") {
                if tildeMode == .list {
                    moveTildeHighlight(by: -1)
                } else if tildeMode == .none {
                    onDateNudge?(-1)
                }
            }
            .keyboardShortcut("-", modifiers: [.command, .shift])
        }
        .frame(width: 0, height: 0)
        .clipped()
    }

    private var tildePreview: some View {
        HStack(spacing: 4) {
            if !title.isEmpty {
                Text(title)
                    .font(previewFont)
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
            Spacer(minLength: 0)
        }
    }

    private var tildeListSearchView: some View {
        VStack(alignment: .leading, spacing: 0) {
            hiddenShortcutButtons

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                TextField("Search lists...", text: $tildeSearchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .focused($isTildeSearchFocused)
                    .onSubmit { selectTildeContainer() }
                    .onKeyPress(.upArrow) {
                        moveTildeHighlight(by: -1)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        moveTildeHighlight(by: 1)
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
                            isSelected: containerSelection.map { $0.wrappedValue == item.tag } ?? false,
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
            selectedSectionName: sectionName?.wrappedValue ?? TaskSectionDefaults.defaultName,
            onSelect: { section in
                sectionName?.wrappedValue = section
                tildeMode = .none
                DispatchQueue.main.async { isTitleFocused = true }
            },
            onDismiss: {
                tildeMode = .none
                DispatchQueue.main.async { isTitleFocused = true }
            }
        )
    }

    private func moveTildeHighlight(by offset: Int) {
        let count = tildeFlatContainers.count
        guard count > 0 else { return }
        tildeHighlightIdx = min(max(tildeHighlightIdx + offset, 0), count - 1)
    }

    private func selectTildeContainer() {
        let items = tildeFlatContainers
        guard !items.isEmpty else { return }
        selectTildeContainerItem(items[min(tildeHighlightIdx, items.count - 1)].tag)
    }

    private func selectTildeContainerItem(_ tag: TaskContainerSelection) {
        containerSelection?.wrappedValue = tag
        normalizeSelectedSection()
        tildeSearchQuery = ""
        tildeHighlightIdx = 0
        tildeMode = .section
    }

    private func normalizeSelectedSection() {
        guard let sectionName else { return }
        let validSections = availableSections
        if !validSections.contains(where: { $0.caseInsensitiveCompare(sectionName.wrappedValue) == .orderedSame }) {
            sectionName.wrappedValue = validSections.first ?? TaskSectionDefaults.defaultName
        }
    }
}

private enum TaskTitleTildeMode {
    case none
    case list
    case section
}

private struct TaskTitleTildeContainerItem: Identifiable {
    let tag: TaskContainerSelection
    let icon: String
    let name: String
    let color: Color

    var id: TaskContainerSelection { tag }
}
#endif
