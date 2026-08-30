#if os(macOS)
import AppKit
import SwiftUI

struct TaskTitleEntryField: View {
    @Binding var title: String
    let priority: Binding<TaskPriority>?
    let placeholder: String
    let font: Font
    let previewFont: Font
    let lineLimit: ClosedRange<Int>
    let autofocus: Bool
    let suppressInitialSelection: Bool
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
    @State private var isTagMode = false
    @State private var tagSearchQuery = ""
    @State private var tagHighlightIdx = 0
    @State private var shouldSuppressInitialTitleSelection = false
    @FocusState private var isTitleFocused: Bool

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
        suppressInitialSelection: Bool = false,
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
        self.suppressInitialSelection = suppressInitialSelection
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
                .background {
                    if suppressInitialSelection {
                        TaskTitleInitialSelectionSuppressor(
                            expectedText: title,
                            shouldCollapseSelection: $shouldSuppressInitialTitleSelection
                        )
                        .frame(width: 0, height: 0)
                    }
                }
                .onSubmit {
                    applyTitleShortcuts()
                    onSubmit?()
                }
                .onChange(of: title) { _, newValue in
                    guard tildeMode == .none, !isTagMode else { return }
                    if canUseTildeRouting,
                       let shortcut = TaskTitleSupport.containerShortcut(in: newValue) {
                        enterTildeSearch(shortcut)
                        return
                    }
                    if canUseTagRouting,
                       let shortcut = TaskTitleSupport.tagShortcut(in: newValue) {
                        enterTagSearch(shortcut)
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
            if suppressInitialSelection {
                shouldSuppressInitialTitleSelection = true
            }
            guard autofocus else { return }
            DispatchQueue.main.async { isTitleFocused = true }
        }
        .onChange(of: isTitleFocused) { _, focused in
            guard !focused, !isEditingInlineShortcut else { return }
            applyTitleShortcuts()
        }
        .onChange(of: tildeMode) { _, mode in
            guard mode != .none else { return }
            focusTildeSearch()
        }
        .onChange(of: isTagMode) { _, active in
            guard active else { return }
            isTitleFocused = false
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

    /// Cmd+Shift+= / Cmd+Shift+- nudge the do-date **while the title field is the thing on
    /// screen**. When the `~` panel is open the same chord moves its highlight instead, and that
    /// pair of buttons lives inside `TildeContainerPicker` — a `keyboardShortcut` declared out here
    /// does not reach into a popover, which is why there were ever two.
    private var hiddenShortcutButtons: some View {
        ZStack {
            Button("") { nudgeDate(by: 1) }
                .keyboardShortcut("=", modifiers: [.command, .shift])

            Button("") { nudgeDate(by: -1) }
                .keyboardShortcut("-", modifiers: [.command, .shift])
        }
        .frame(width: 0, height: 0)
        .clipped()
    }

    private func nudgeDate(by offset: Int) {
        guard tildeMode == .none else { return }
        onDateNudge?(offset)
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
                .foregroundStyle(Theme.onColor)
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

    /// The `~` panel, from `TildeContainerPicker` (T-287) — the same one
    /// `QuickCreateChoicePopover` shows. The panel owns the search field, the focus, the highlight
    /// and every key; this field owns only what committing a list means here.
    private var tildeListSearchView: some View {
        TildeContainerPicker(
            query: $tildeSearchQuery,
            items: TildeContainerPickerSupport.flatContainers(
                query: tildeSearchQuery,
                contexts: contexts,
                areas: areas,
                projects: projects
            ),
            selection: containerSelection?.wrappedValue,
            onSelect: selectTildeContainerItem,
            onRestoreLiteral: { restoreLiteralShortcut(marker: "~", query: tildeSearchQuery) }
        )
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
                .foregroundStyle(Theme.onColor)
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
            hasActiveTags: !activeTags.isEmpty,
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

    private func moveTagHighlight(by offset: Int) {
        tagHighlightIdx = movedHighlightIndex(tagHighlightIdx, by: offset, count: tagPickerOptionCount)
    }

    private func selectTildeContainerItem(_ tag: TaskContainerSelection) {
        if let containerSelection {
            TildeContainerPickerSupport.applySelection(
                tag,
                container: containerSelection,
                sectionName: sectionName,
                areas: areas,
                projects: projects
            )
        }
        tildeSearchQuery = ""
        tildeMode = .none
        DispatchQueue.main.async { isTitleFocused = true }
    }

    private func enterTildeSearch(_ shortcut: TaskTitleInlineShortcut) {
        title = shortcut.prefix
        tildeSearchQuery = shortcut.query
        tildeMode = .list
        focusTildeSearch()
    }

    private func enterTagSearch(_ shortcut: TaskTitleInlineShortcut) {
        title = shortcut.prefix
        tagSearchQuery = shortcut.query
        tagHighlightIdx = 0
        isTagMode = true
        isTitleFocused = false
    }

    /// Only releases the title. `TildeContainerPicker` focuses its own search field when it
    /// appears, the way `TaskTitleInlineTagPicker` already did.
    private func focusTildeSearch() {
        isTitleFocused = false
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

    private func movedHighlightIndex(_ current: Int, by offset: Int, count: Int) -> Int {
        TaskPickerHighlightSupport.wrappedMovedIndex(current, by: offset, count: count)
    }

    private func clampedHighlightIndex(_ index: Int, count: Int) -> Int {
        TaskPickerHighlightSupport.clampedIndex(index, count: count)
    }

    private func createInlineTag() {
        guard let onCreateTag else { return }
        selectInlineTagItem(onCreateTag(tagSearchQuery))
    }

    /// Toggles, rather than only adding.
    ///
    /// `TaskTitleInlineTagPicker` draws a blue checkmark on the already-selected rows — the same
    /// affordance `TagPickerPopover.tagRow` uses, and that one removes on tap. Here the `else`
    /// branch simply did not exist, so tapping a checkmarked row closed the panel and did nothing.
    /// `#` is the documented way to add a tag to a task, which makes it the first thing a user
    /// reaches for to take one off again.
    private func selectInlineTagItem(_ tag: Tag) {
        guard let selectedTags else { return }
        var tags = selectedTags.wrappedValue
        if let existing = tags.firstIndex(where: { $0.id == tag.id }) {
            tags.remove(at: existing)
            selectedTags.wrappedValue = TagSupport.sorted(tags)
        } else {
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
        isTagMode = false
        tagSearchQuery = ""
        tagHighlightIdx = 0
        DispatchQueue.main.async { isTitleFocused = true }
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

#endif
