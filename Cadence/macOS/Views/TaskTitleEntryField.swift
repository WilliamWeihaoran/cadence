#if os(macOS)
import AppKit
import SwiftUI

struct TaskTitleEntryField: View {
    @Binding var title: String
    let priority: Binding<TaskPriority>?
    /// Whether a trailing or leading `!`/`!!`/`!!!` is drawn as the coloured marker. Always true
    /// with a `priority` binding; a host without one (the board's inline composer, whose priority
    /// is read back off the title by `TaskCreationDraft.resolvedPriority`) asks for it explicitly.
    let previewsPriorityShortcut: Bool
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
    let onCreateTag: ((String) -> Tag?)?
    /// [[T-16583]]: un-archives and commits a tag, answering whether the store took it. With it the
    /// `#` panel offers `Unarchive "<name>"` for an archived tag's name, as every other tag picker
    /// does; without it the panel offers nothing for that name.
    let onUnarchiveTag: ((Tag) -> Bool)?

    @State private var tildeMode: TaskTitleTildeMode = .none
    @State private var tildeSearchQuery = ""
    @State private var isTagMode = false
    @State private var tagSearchQuery = ""
    @State private var tagHighlightIdx = 0
    /// [[T-13961]]: where the `~`/`#` token the user last restored as literal text begins.
    @State private var declinedShortcutAnchor: String?
    @State private var shouldSuppressInitialTitleSelection = false
    @FocusState private var isTitleFocused: Bool

    /// **T-8106.** The preview used to be gated on the binding alone, so the inline composer —
    /// which has none, and keeps the marks in the title — showed the raw `!!` where the sheet
    /// showed the marker.
    static func previewsPriorityShortcut(hasPriorityBinding: Bool, requested: Bool) -> Bool {
        hasPriorityBinding || requested
    }

    private var priorityShortcutSegments: TaskTitlePriorityShortcutSegments? {
        guard previewsPriorityShortcut else { return nil }
        return TaskTitleSupport.priorityShortcutSegments(in: title)
    }

    private var isShowingPriorityShortcutPreview: Bool {
        priorityShortcutSegments != nil && !isEditingInlineShortcut
    }

    init(
        title: Binding<String>,
        priority: Binding<TaskPriority>? = nil,
        previewsPriorityShortcut: Bool = false,
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
        onCreateTag: ((String) -> Tag?)? = nil,
        onUnarchiveTag: ((Tag) -> Bool)? = nil,
        onDateNudge: ((Int) -> Void)? = nil,
        onSubmit: (() -> Void)? = nil
    ) {
        self._title = title
        self.priority = priority
        self.previewsPriorityShortcut = Self.previewsPriorityShortcut(
            hasPriorityBinding: priority != nil,
            requested: previewsPriorityShortcut
        )
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
        self.onUnarchiveTag = onUnarchiveTag
        self.onDateNudge = onDateNudge
        self.onSubmit = onSubmit
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // **T-5160.** Only where the host has a date to nudge. The inline composer and the
            // schedule panel's title pass no `onDateNudge`, and the buttons used to be installed
            // there anyway: they caught the chord and did nothing.
            if onDateNudge != nil {
                hiddenShortcutButtons
            }

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
                    // [[T-13961]]: a token the user just sent back to the title stays text.
                    if TaskTitleSupport.isDeclinedInlineShortcut(in: newValue, anchor: declinedShortcutAnchor) {
                        syncPriorityShortcut(from: newValue)
                        return
                    }
                    declinedShortcutAnchor = nil
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

    /// [[T-16583]]: the `#` panel's rows, Create row and Unarchive row, read from the one decision
    /// the inspector's `TagPickerPopover` and iOS's pickers ask ([[T-12744]]). This field spelled
    /// its own filter and Create rule and had no archived match, so an archived tag's name drew
    /// `No matching tags` here alone. `creationDecision` compares `stableSlug` ([[T-14772]]).
    private var tagQuery: TagPickerQuery {
        TagSupport.pickerQuery(tagSearchQuery, in: allTags)
    }

    private var filteredTags: [Tag] { tagQuery.matches }

    private var canCreateInlineTag: Bool { tagQuery.canCreate }

    private var archivedInlineTagMatch: Tag? {
        onUnarchiveTag == nil ? nil : tagQuery.archivedMatch
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
                .foregroundStyle(Theme.onColor(for: Theme.blue))
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
                projects: projects,
                selection: containerSelection?.wrappedValue
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
                .foregroundStyle(Theme.onColor(for: Theme.purple))
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
            archivedMatch: archivedInlineTagMatch,
            onSelect: selectInlineTagItem,
            onCreate: createInlineTag,
            onUnarchive: unarchiveInlineTag,
            onSubmit: selectInlineTag,
            onMoveHighlight: moveTagHighlight,
            onRestoreLiteral: { restoreLiteralShortcut(marker: "#", query: tagSearchQuery) }
        )
    }

    private var priorityShortcutPreview: some View {
        HStack(spacing: 4) {
            if let segments = priorityShortcutSegments {
                if !segments.leadingMarker.isEmpty {
                    priorityShortcutMarker(segments.leadingMarker, priority: segments.priority)
                }
                if !segments.title.isEmpty {
                    Text(segments.title)
                        .font(previewFont)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .fixedSize()
                }
                if !segments.trailingMarker.isEmpty {
                    priorityShortcutMarker(segments.trailingMarker, priority: segments.priority)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func priorityShortcutMarker(_ marker: String, priority: TaskPriority) -> some View {
        Text(marker)
            .font(previewFont)
            .foregroundStyle(Theme.priorityColor(priority))
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
        switch TaskTitleInlineTagSubmit.action(
            highlightIndex: tagHighlightIdx,
            matches: filteredTags,
            canCreate: canCreateInlineTag,
            archivedMatch: archivedInlineTagMatch
        ) {
        case .select(let tag): selectInlineTagItem(tag)
        case .unarchive: unarchiveInlineTag()
        case .create: createInlineTag()
        case .nothing: break
        }
    }

    private var tagPickerOptionCount: Int {
        TaskTitleInlineTagSubmit.optionCount(
            matchCount: filteredTags.count,
            canCreate: canCreateInlineTag,
            offersUnarchive: archivedInlineTagMatch != nil
        )
    }

    private func movedHighlightIndex(_ current: Int, by offset: Int, count: Int) -> Int {
        TaskPickerHighlightSupport.wrappedMovedIndex(current, by: offset, count: count)
    }

    private func clampedHighlightIndex(_ index: Int, count: Int) -> Int {
        TaskPickerHighlightSupport.clampedIndex(index, count: count)
    }

    /// **T-631.** A `nil` from `onCreateTag` means the store refused the tag and it has been taken
    /// back out, so nothing is selected and the `#` panel stays open over the name still in its
    /// field. Selecting a chip for a row the store does not hold is the report this used to make.
    private func createInlineTag() {
        guard let onCreateTag, let tag = onCreateTag(tagSearchQuery) else { return }
        selectInlineTagItem(tag)
    }

    /// [[T-16583]]: the T-631 rule `createInlineTag` follows -- a `false` from the host means the
    /// store refused, so nothing is selected and the panel stays open over the name. A tag the
    /// draft already carries is kept rather than toggled off by the row that brought it back.
    private func unarchiveInlineTag() {
        guard let onUnarchiveTag, let tag = archivedInlineTagMatch, onUnarchiveTag(tag) else { return }
        if selectedTags?.wrappedValue.contains(where: { $0.id == tag.id }) == true {
            tagSearchQuery = ""
            tagHighlightIdx = 0
            isTagMode = false
            DispatchQueue.main.async { isTitleFocused = true }
        } else {
            selectInlineTagItem(tag)
        }
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
        declinedShortcutAnchor = TaskTitleSupport.declinedInlineShortcutAnchor(prefix: title, marker: marker)
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
