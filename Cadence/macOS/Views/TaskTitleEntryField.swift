#if os(macOS)
import SwiftUI

struct TaskTitleEntryField: View {
    @Binding var title: String
    let priority: Binding<TaskPriority>?
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
    let allTags: [Tag]
    let containerSelection: Binding<TaskContainerSelection>?
    let sectionName: Binding<String>?
    let selectedTags: Binding<[Tag]>?
    let onCreateTag: ((String) -> Tag)?

    @State private var tildeMode: TaskTitleTildeMode = .none
    @State private var tildeSearchQuery = ""
    @State private var tildeHighlightIdx = 0
    @State private var isTagMode = false
    @State private var tagSearchQuery = ""
    @State private var tagHighlightIdx = 0
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isTildeSearchFocused: Bool

    private var priorityShortcutSegments: TaskTitlePriorityShortcutSegments? {
        guard priority != nil else { return nil }
        return TaskTitleSupport.priorityShortcutSegments(in: title)
    }

    private var isShowingPriorityShortcutPreview: Bool {
        priorityShortcutSegments != nil && !isEditingInlineShortcut
    }

    init(
        title: Binding<String>,
        priority: Binding<TaskPriority>? = nil,
        placeholder: String,
        font: Font,
        previewFont: Font? = nil,
        lineLimit: ClosedRange<Int> = 1...1,
        autofocus: Bool = false,
        contexts: [Context] = [],
        areas: [Area] = [],
        projects: [Project] = [],
        allTags: [Tag] = [],
        containerSelection: Binding<TaskContainerSelection>? = nil,
        sectionName: Binding<String>? = nil,
        selectedTags: Binding<[Tag]>? = nil,
        onCreateTag: ((String) -> Tag)? = nil,
        onDateNudge: ((Int) -> Void)? = nil,
        onSubmit: (() -> Void)? = nil
    ) {
        self._title = title
        self.priority = priority
        self.placeholder = placeholder
        self.font = font
        self.previewFont = previewFont ?? font
        self.lineLimit = lineLimit
        self.autofocus = autofocus
        self.contexts = contexts
        self.areas = areas
        self.projects = projects
        self.allTags = allTags
        self.containerSelection = containerSelection
        self.sectionName = sectionName
        self.selectedTags = selectedTags
        self.onCreateTag = onCreateTag
        self.onDateNudge = onDateNudge
        self.onSubmit = onSubmit
    }

    var body: some View {
        ZStack(alignment: .leading) {
            hiddenShortcutButtons

            TextField(placeholder, text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(font)
                .foregroundStyle(isShowingPriorityShortcutPreview ? Color.clear : Theme.text)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                .focused($isTitleFocused)
                .onSubmit {
                    applyTitleShortcuts()
                    onSubmit?()
                }
                .onChange(of: title) { _, newValue in
                    guard tildeMode == .none, !isTagMode else { return }
                    if canUseTildeRouting,
                       let shortcut = TaskTitleSupport.containerShortcut(in: newValue) {
                        title = shortcut.prefix
                        tildeSearchQuery = shortcut.query
                        tildeHighlightIdx = 0
                        tildeMode = .list
                        return
                    }
                    if canUseTagRouting,
                       let shortcut = TaskTitleSupport.tagShortcut(in: newValue) {
                        title = shortcut.prefix
                        tagSearchQuery = shortcut.query
                        tagHighlightIdx = 0
                        isTagMode = true
                        return
                    }
                    syncPriorityShortcut(from: newValue)
                }
                .opacity(isEditingInlineShortcut ? 0 : 1)
                .allowsHitTesting(!isEditingInlineShortcut)

            if isShowingPriorityShortcutPreview {
                priorityShortcutPreview
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            if tildeMode != .none {
                tildePreview
            } else if isTagMode {
                tagPreview
            }
        }
        .onAppear {
            guard autofocus else { return }
            DispatchQueue.main.async { isTitleFocused = true }
        }
        .onChange(of: isTitleFocused) { _, focused in
            guard !focused, !isEditingInlineShortcut else { return }
            applyTitleShortcuts()
        }
    }

    private var isEditingInlineShortcut: Bool {
        tildeMode != .none || isTagMode
    }

    private var canUseTildeRouting: Bool {
        containerSelection != nil
    }

    private var canUseTagRouting: Bool {
        selectedTags != nil && onCreateTag != nil
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

    private var activeTags: [Tag] {
        TagSupport.uniqueBySlug(allTags.filter { !$0.isArchived })
    }

    private var filteredTags: [Tag] {
        let trimmed = tagSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return activeTags }
        let slug = TagSupport.slug(for: trimmed)
        return activeTags.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) ||
                $0.slug.localizedCaseInsensitiveContains(slug)
        }
    }

    private var canCreateInlineTag: Bool {
        let name = TagSupport.displayName(for: tagSearchQuery)
        guard !name.isEmpty,
              name.rangeOfCharacter(from: .alphanumerics) != nil else { return false }
        let slug = TagSupport.slug(for: name)
        return !allTags.contains { $0.slug == slug }
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
                    tildeListSearchView
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
                        selectTildeContainer()
                        return .handled
                    }
                    .onKeyPress(.delete) {
                        guard tildeSearchQuery.isEmpty else { return .ignored }
                        restoreLiteralShortcut(marker: "~", query: tildeSearchQuery)
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
                            isHighlighted: index == clampedTildeHighlightIndex,
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
        .onAppear {
            clampTildeHighlight()
            DispatchQueue.main.async { isTildeSearchFocused = true }
        }
        .onChange(of: tildeSearchQuery) { _, _ in tildeHighlightIdx = 0 }
        .onChange(of: tildeFlatContainers.map(\.id)) { _, _ in clampTildeHighlight() }
    }

    private var tagPreview: some View {
        HStack(spacing: 4) {
            if !title.isEmpty {
                Text(title)
                    .font(previewFont)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .fixedSize()
            }
            Text("#")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Theme.purple)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .popover(
                    isPresented: Binding(
                        get: { isTagMode },
                        set: { if !$0 { isTagMode = false } }
                    ),
                    arrowEdge: .bottom
                ) {
                    tagSearchView
                }
            Spacer(minLength: 0)
        }
    }

    private var tagSearchView: some View {
        TaskTitleInlineTagPicker(
            query: $tagSearchQuery,
            highlightIndex: $tagHighlightIdx,
            filteredTags: filteredTags,
            selectedTags: selectedTags?.wrappedValue ?? [],
            canCreate: canCreateInlineTag,
            onSelect: selectInlineTagItem,
            onCreate: createInlineTag,
            onSubmit: selectInlineTag,
            onMoveHighlight: moveTagHighlight,
            onRestoreLiteral: { restoreLiteralShortcut(marker: "#", query: tagSearchQuery) }
        )
    }

    private var priorityShortcutPreview: some View {
        HStack(spacing: 4) {
            if let segments = priorityShortcutSegments {
                switch segments.placement {
                case .leading:
                    priorityShortcutMarker(segments)
                    if !segments.title.isEmpty {
                        Text(segments.title)
                            .font(previewFont)
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .fixedSize()
                    }
                case .trailing:
                    if !segments.title.isEmpty {
                        Text(segments.title)
                            .font(previewFont)
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    priorityShortcutMarker(segments)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func priorityShortcutMarker(_ segments: TaskTitlePriorityShortcutSegments) -> some View {
        Text(segments.marker)
            .font(previewFont)
            .foregroundStyle(Theme.priorityColor(segments.priority))
            .lineLimit(1)
            .fixedSize()
    }

    private func moveTildeHighlight(by offset: Int) {
        tildeHighlightIdx = movedHighlightIndex(tildeHighlightIdx, by: offset, count: tildeFlatContainers.count)
    }

    private func moveTagHighlight(by offset: Int) {
        tagHighlightIdx = movedHighlightIndex(tagHighlightIdx, by: offset, count: tagPickerOptionCount)
    }

    private func selectTildeContainer() {
        let items = tildeFlatContainers
        guard !items.isEmpty else { return }
        selectTildeContainerItem(items[clampedTildeHighlightIndex].tag)
    }

    private func selectTildeContainerItem(_ tag: TaskContainerSelection) {
        containerSelection?.wrappedValue = tag
        normalizeSelectedSection()
        tildeSearchQuery = ""
        tildeHighlightIdx = 0
        tildeMode = .none
        DispatchQueue.main.async { isTitleFocused = true }
    }

    private func selectInlineTag() {
        let tags = filteredTags
        let index = clampedHighlightIndex(tagHighlightIdx, count: tagPickerOptionCount)
        if index < tags.count {
            selectInlineTagItem(tags[index])
        } else if canCreateInlineTag {
            createInlineTag()
        }
    }

    private var tagPickerOptionCount: Int {
        filteredTags.count + (canCreateInlineTag ? 1 : 0)
    }

    private var clampedTildeHighlightIndex: Int {
        clampedHighlightIndex(tildeHighlightIdx, count: tildeFlatContainers.count)
    }

    private func clampTildeHighlight() {
        tildeHighlightIdx = clampedTildeHighlightIndex
    }

    private func movedHighlightIndex(_ current: Int, by offset: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (clampedHighlightIndex(current, count: count) + offset + count) % count
    }

    private func clampedHighlightIndex(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index, 0), count - 1)
    }

    private func createInlineTag() {
        guard let onCreateTag else { return }
        selectInlineTagItem(onCreateTag(tagSearchQuery))
    }

    private func selectInlineTagItem(_ tag: Tag) {
        guard let selectedTags else { return }
        var tags = selectedTags.wrappedValue
        if !tags.contains(where: { $0.id == tag.id }) {
            tags.append(tag)
            selectedTags.wrappedValue = TagSupport.sorted(tags)
        }
        tagSearchQuery = ""
        tagHighlightIdx = 0
        isTagMode = false
        DispatchQueue.main.async { isTitleFocused = true }
    }

    private func restoreLiteralShortcut(marker: Character, query: String) {
        title += "\(marker)\(query)"
        tildeMode = .none
        tildeSearchQuery = ""
        tildeHighlightIdx = 0
        isTagMode = false
        tagSearchQuery = ""
        tagHighlightIdx = 0
        DispatchQueue.main.async { isTitleFocused = true }
    }

    private func normalizeSelectedSection() {
        guard let sectionName else { return }
        let validSections = availableSections
        if !validSections.contains(where: { $0.caseInsensitiveCompare(sectionName.wrappedValue) == .orderedSame }) {
            sectionName.wrappedValue = validSections.first ?? TaskSectionDefaults.defaultName
        }
    }

    private func applyTitleShortcuts() {
        if let priority {
            var currentPriority = priority.wrappedValue
            title = TaskTitleSupport.titleApplyingPriorityShortcut(title, priority: &currentPriority)
            priority.wrappedValue = currentPriority
        } else {
            title = TaskTitleSupport.normalized(title)
        }
    }

    private func syncPriorityShortcut(from value: String) {
        guard let priority,
              let shortcut = TaskTitleSupport.priorityShortcut(in: value) else { return }
        priority.wrappedValue = shortcut.priority
    }
}

private enum TaskTitleTildeMode {
    case none
    case list
}

private struct TaskTitleTildeContainerItem: Identifiable {
    let tag: TaskContainerSelection
    let icon: String
    let name: String
    let color: Color

    var id: TaskContainerSelection { tag }
}

#endif
