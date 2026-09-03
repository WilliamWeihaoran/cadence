#if os(macOS)
import SwiftUI

// The `~` list-search panel. **One of them (T-287).**
//
// Typing `~` in a task title opens a list picker: search field, flat container list, arrow keys,
// Enter or Tab to commit. The [[T-123]] split extracted the sibling `#` panel into
// `TaskTitleInlineTagPicker` and left this one written out twice — once in `TaskTitleEntryField`
// and once in `QuickCreateChoicePopover`, under the same five names (`tildeFlatContainers`,
// `selectTildeContainer`, `selectTildeContainerItem`, `clampTildeHighlight`,
// `normalizeSelectedSection`), sharing only `TildeContainerPickerRow`.
//
// The two copies had drifted in exactly the place a duplicate drifts: the escape hatches. The
// title field restored the literal `~query` into the title on Escape and on backspace-at-empty;
// the popover copy had neither, so the only way out of its panel was to pick a list — Escape fell
// through to the enclosing popover and threw the whole draft away. That is a bug in one copy, not
// a deliberate distinction, and it is fixed here by there being one panel that handles the key.
//
// `TaskTitleInlineTagPicker` is the shape this follows deliberately: the panel owns its search
// field, its focus, its highlight index and its key handling, and the host owns only what the
// commit means. A host cannot hold a stale highlight, because it does not hold one.

/// One row of the `~` list: a container, and the icon, name and colour it draws with.
struct TildeContainerItem: Identifiable {
    let tag: TaskContainerSelection
    let icon: String
    let name: String
    let color: Color

    var id: TaskContainerSelection { tag }
}

/// The non-view half of the `~` panel: which containers it offers, and what committing one means.
enum TildeContainerPickerSupport {
    /// Inbox, then each context's active areas and active projects in `order`, then the lists that
    /// belong to none of the offered contexts — all filtered by a case-insensitive **prefix** match
    /// on the name.
    ///
    /// Prefix rather than `contains`, and unsorted within a context beyond `order`: this is the
    /// list the user is looking at while typing, and reordering it under a keystroke moves the
    /// highlighted row out from under Enter.
    ///
    /// **The trailing bucket is the whole of T-558, and it is the fifth time this shape has been
    /// filed.** The body was a `for context in contexts` whose only membership test was
    /// `$0.context?.id == context.id`, so a list with `context == nil` was reached by no iteration
    /// and appended nowhere. Not un-grouped — *absent*, from the only source of rows the `~` panel
    /// has on either macOS composer, which is a list no task can be filed into from the Mac at all.
    /// `Area.context` and `Project.context` both default to `nil` and iOS's list editor writes it
    /// from a "None" row in every mode, so this is a state a shipping surface makes.
    ///
    /// Keyed on the **offered** contexts (`CadenceSidebarLists.isOffered`) rather than on
    /// `context == nil`, so a list whose context exists but was not handed to this function lands
    /// in the same place — the rule T-534's picker and T-538's two sidebars already apply. There is
    /// no heading here because this panel has no headings; the bucket is a position, not a section.
    ///
    /// **`selection` is T-534's *first* defect, arriving here last (T-685's sibling, T-684).**
    /// "Which lists may I offer" is a rule about *fresh* choices, and the list the draft is already
    /// in is not a fresh choice. Filtering on `isActive` alone meant a draft sitting in an archived
    /// or completed list got a panel with no row for where it is — and `TildeContainerPicker` is
    /// handed the same selection for its checkmark, so the panel could highlight a row it would not
    /// draw. Narrowed through `pickableAreas` / `pickableProjects`, the pair
    /// `ContainerPickerFilterSupport.groups` already uses, so the two macOS list pickers cannot
    /// drift on the rule.
    static func flatContainers(
        query: String,
        contexts: [Context],
        areas: [Area],
        projects: [Project],
        selection: TaskContainerSelection?
    ) -> [TildeContainerItem] {
        let needle = query.lowercased()
        func matches(_ name: String) -> Bool {
            needle.isEmpty || name.lowercased().hasPrefix(needle)
        }
        func areaItem(_ area: Area) -> TildeContainerItem {
            TildeContainerItem(
                tag: .area(area.id),
                icon: area.icon,
                name: area.name,
                color: Color(hex: area.colorHex)
            )
        }
        func projectItem(_ project: Project) -> TildeContainerItem {
            TildeContainerItem(
                tag: .project(project.id),
                icon: project.icon,
                name: project.name,
                color: Color(hex: project.colorHex)
            )
        }

        // Applied inside the closure rather than handed over as `flatMap(…selectedAreaID)`: an
        // unapplied reference to a main-actor-isolated method is a value in a nonisolated context,
        // which is a warning, and the warning baseline here is zero.
        let offerableAreas = CadenceTaskComposerSupport
            .pickableAreas(
                areas,
                selectedID: selection.flatMap { CadenceTaskComposerSupport.selectedAreaID($0) }
            )
            .filter { matches($0.name) }
        let offerableProjects = CadenceTaskComposerSupport
            .pickableProjects(
                projects,
                selectedID: selection.flatMap { CadenceTaskComposerSupport.selectedProjectID($0) }
            )
            .filter { matches($0.name) }
        let offered = Set(contexts.map(\.id))

        var result: [TildeContainerItem] = []
        if matches("Inbox") {
            result.append(TildeContainerItem(tag: .inbox, icon: "tray", name: "Inbox", color: Theme.dim))
        }
        for context in contexts {
            result += offerableAreas
                .filter { $0.context?.id == context.id }
                .sorted { $0.order < $1.order }
                .map(areaItem)
            result += offerableProjects
                .filter { $0.context?.id == context.id }
                .sorted { $0.order < $1.order }
                .map(projectItem)
        }
        result += offerableAreas
            .filter { !CadenceSidebarLists.isOffered($0.context?.id, among: offered) }
            .sorted { $0.order < $1.order }
            .map(areaItem)
        result += offerableProjects
            .filter { !CadenceSidebarLists.isOffered($0.context?.id, among: offered) }
            .sorted { $0.order < $1.order }
            .map(projectItem)
        return result
    }

    /// Commits a `~` choice: the container, **and** the section name that choice may have
    /// invalidated.
    ///
    /// The second half is the reason this is one function rather than a note in two files. Section
    /// names belong to the container — "Build" exists on one project and nowhere else — so moving
    /// a draft to another list can leave `sectionName` pointing at a column that does not exist
    /// there, and every composer that showed a section picker would then show an empty one. Both
    /// copies of the panel did remember to renormalise, silently, in a private method of their own;
    /// the next one would not have. `TaskContainerResolver.normalizedSectionName` is the repo's
    /// answer to "what is this name, in this container", and it also canonicalises the *spelling*
    /// of a case-insensitive match, which the two open-coded copies did not.
    static func applySelection(
        _ tag: TaskContainerSelection,
        container: Binding<TaskContainerSelection>,
        sectionName: Binding<String>?,
        areas: [Area],
        projects: [Project]
    ) {
        container.wrappedValue = tag
        guard let sectionName else { return }
        sectionName.wrappedValue = TaskContainerResolver(areas: areas, projects: projects)
            .normalizedSectionName(sectionName.wrappedValue, for: tag)
    }
}

/// The panel itself.
///
/// `highlightIndex` is `@State`, not a binding: a host that keeps its own copy is a host that can
/// disagree with the rows on screen, which is how both former copies needed a `clampTildeHighlight`
/// wired to two separate `onChange`s. Wrapping arrow navigation and the Enter/Tab commit read the
/// same index because there is only one.
struct TildeContainerPicker: View {
    @Binding var query: String
    let items: [TildeContainerItem]
    let selection: TaskContainerSelection?
    let onSelect: (TaskContainerSelection) -> Void
    /// Puts the `~` and whatever was typed after it back in the title and closes the panel.
    let onRestoreLiteral: () -> Void

    @State private var highlightIndex = 0
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hiddenShortcutButtons

            searchRow

            Divider().background(Theme.borderSubtle)

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
                            isHighlighted: index == clampedHighlightIndex,
                            isSelected: selection == item.tag,
                            action: { onSelect(item.tag) }
                        )
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .frame(minWidth: 200)
        .background(Theme.surfaceElevated)
        .onAppear {
            clampHighlight()
            DispatchQueue.main.async { isSearchFocused = true }
        }
        .onChange(of: query) { _, _ in highlightIndex = 0 }
        .onChange(of: items.map(\.id)) { _, _ in clampHighlight() }
    }

    /// Cmd+Shift+= / Cmd+Shift+- move the highlight without leaving the search field. Zero-sized
    /// and inside the panel, because a `keyboardShortcut` in the host's hierarchy does not reach a
    /// popover.
    private var hiddenShortcutButtons: some View {
        ZStack {
            Button("") { moveHighlight(by: 1) }
                .keyboardShortcut("=", modifiers: [.command, .shift])
            Button("") { moveHighlight(by: -1) }
                .keyboardShortcut("-", modifiers: [.command, .shift])
        }
        .frame(width: 0, height: 0)
        .clipped()
    }

    private var searchRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
            TextField("Search lists…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .focused($isSearchFocused)
                .onSubmit(commitHighlighted)
                .onKeyPress(.upArrow) {
                    moveHighlight(by: -1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    moveHighlight(by: 1)
                    return .handled
                }
                .onKeyPress(.tab) {
                    commitHighlighted()
                    return .handled
                }
                .onKeyPress(.escape) {
                    onRestoreLiteral()
                    return .handled
                }
                .onKeyPress(.delete) {
                    guard query.isEmpty else { return .ignored }
                    onRestoreLiteral()
                    return .handled
                }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim.opacity(0.5))
                }
                .buttonStyle(.cadencePlain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var clampedHighlightIndex: Int {
        TaskPickerHighlightSupport.clampedIndex(highlightIndex, count: items.count)
    }

    private func commitHighlighted() {
        guard !items.isEmpty else { return }
        onSelect(items[clampedHighlightIndex].tag)
    }

    private func moveHighlight(by offset: Int) {
        highlightIndex = TaskPickerHighlightSupport.wrappedMovedIndex(
            highlightIndex,
            by: offset,
            count: items.count
        )
    }

    private func clampHighlight() {
        highlightIndex = clampedHighlightIndex
    }
}
#endif
