#if os(macOS)
import SwiftUI

/// Pure filtering and ordering behind the container picker. Split out from the view so the
/// prefix match, the context grouping, and the flat order the arrow keys walk can be exercised
/// without SwiftUI.
enum ContainerPickerFilterSupport {
    typealias Group = (context: Context, areas: [Area], projects: [Project])

    /// Forwards to the shared rule so the `~` suggestions in the iOS composer and this picker
    /// cannot disagree about what `des` matches.
    static func matches(_ name: String, query: String) -> Bool {
        CadenceTaskComposerSupport.matchesQuery(name, query: query)
    }

    static func matchesInbox(query: String) -> Bool {
        matches("Inbox", query: query)
    }

    static func groups(
        contexts: [Context],
        areas: [Area],
        projects: [Project],
        query: String
    ) -> [Group] {
        contexts.compactMap { context in
            let matchingAreas = areas
                .filter { $0.isActive && $0.context?.id == context.id && matches($0.name, query: query) }
                .sorted { $0.order < $1.order }
            let matchingProjects = projects
                .filter { $0.isActive && $0.context?.id == context.id && matches($0.name, query: query) }
                .sorted { $0.order < $1.order }
            guard !matchingAreas.isEmpty || !matchingProjects.isEmpty else { return nil }
            return (context, matchingAreas, matchingProjects)
        }
    }

    /// The flat order the arrow-key highlight walks. Must stay in the order the rows render.
    static func flatSelections(inGroups groups: [Group], includingInbox: Bool) -> [TaskContainerSelection] {
        var result: [TaskContainerSelection] = []
        if includingInbox { result.append(.inbox) }
        for group in groups {
            result.append(contentsOf: group.areas.map { .area($0.id) })
            result.append(contentsOf: group.projects.map { .project($0.id) })
        }
        return result
    }

    /// The row `highlightIdx` currently names, or `nil` when the query matches nothing.
    static func highlighted(at index: Int, in selections: [TaskContainerSelection]) -> TaskContainerSelection? {
        guard !selections.isEmpty else { return nil }
        return selections[TaskPickerHighlightSupport.clampedIndex(index, count: selections.count)]
    }
}

/// The searchable, context-grouped list picker. Every container control presents this same body;
/// only the *trigger* and what a selection writes to differ — `ContainerPickerBadge` writes
/// through its own binding, the kanban card's list chip goes through
/// `CadenceTaskMutationSupport.moveToContainer` — so the picker itself lives here once.
struct ContainerPickerPopoverContent: View {
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    /// Selecting a row does not dismiss on its own: the presenting surface owns its
    /// `isPresented` state and closes as part of writing the selection.
    let onSelect: (TaskContainerSelection) -> Void

    @State private var searchQuery = ""
    @State private var highlightIdx = 0
    @FocusState private var isSearchFocused: Bool

    private var groups: [ContainerPickerFilterSupport.Group] {
        ContainerPickerFilterSupport.groups(
            contexts: contexts,
            areas: areas,
            projects: projects,
            query: searchQuery
        )
    }

    private var showsInbox: Bool {
        ContainerPickerFilterSupport.matchesInbox(query: searchQuery)
    }

    private var flatFiltered: [TaskContainerSelection] {
        ContainerPickerFilterSupport.flatSelections(inGroups: groups, includingInbox: showsInbox)
    }

    private var highlighted: TaskContainerSelection? {
        ContainerPickerFilterSupport.highlighted(at: highlightIdx, in: flatFiltered)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchBar

            Divider().background(Theme.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if showsInbox {
                        ContainerPickerRow(
                            icon: "tray",
                            name: "Inbox",
                            color: Theme.dim,
                            isHighlighted: highlighted == .inbox,
                            action: { onSelect(.inbox) }
                        )
                    }

                    if !groups.isEmpty {
                        Divider().background(Theme.borderSubtle).padding(.vertical, 2)

                        ForEach(groups, id: \.context.id) { group in
                            SectionEyebrowLabel(
                                text: group.context.name,
                                size: .compact,
                                tint: Color(hex: group.context.colorHex)
                            )
                                .padding(.horizontal, 12)
                                .padding(.top, 6)
                                .padding(.bottom, 2)

                            ForEach(group.areas) { area in
                                ContainerPickerRow(
                                    icon: area.icon,
                                    name: area.name,
                                    color: Color(hex: area.colorHex),
                                    isHighlighted: highlighted == .area(area.id),
                                    action: { onSelect(.area(area.id)) }
                                )
                            }

                            ForEach(group.projects) { project in
                                ContainerPickerRow(
                                    icon: project.icon,
                                    name: project.name,
                                    color: Color(hex: project.colorHex),
                                    isHighlighted: highlighted == .project(project.id),
                                    action: { onSelect(.project(project.id)) }
                                )
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 320)
        }
        .frame(minWidth: 190)
        .background(Theme.surfaceElevated)
        .onAppear {
            // This is also the reset-on-close: popover content is rebuilt per presentation, so
            // clearing here guarantees every open starts on the first row with an empty query
            // regardless of what the previous session left behind.
            searchQuery = ""
            highlightIdx = 0
            DispatchQueue.main.async { isSearchFocused = true }
        }
        .onChange(of: searchQuery) { _, _ in
            highlightIdx = 0
        }
    }

    private var searchBar: some View {
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
                    if let highlighted { onSelect(highlighted) }
                }
                .onKeyPress(.upArrow) {
                    highlightIdx = TaskPickerHighlightSupport.clampedMovedIndex(highlightIdx, by: -1, count: flatFiltered.count)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    highlightIdx = TaskPickerHighlightSupport.clampedMovedIndex(highlightIdx, by: 1, count: flatFiltered.count)
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
    }
}

/// A dedicated struct rather than a `@ViewBuilder` function so a highlight change updates the
/// affected rows in place. The checkmark tracks `isHighlighted` — the keyboard cursor — which is
/// why there is deliberately no `isSelected` here.
private struct ContainerPickerRow: View {
    let icon: String
    let name: String
    let color: Color
    let isHighlighted: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(color).frame(width: 16)
                Text(name).font(.system(size: 13)).foregroundStyle(Theme.text).lineLimit(1)
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

    /// One background layer for both states; stacking a hover fill under a highlight fill made
    /// the highlighted row read as a different colour when the pointer happened to rest on it.
    private var rowBackground: Color {
        if isHighlighted { return Theme.blue.opacity(0.08) }
        if isHovered { return Theme.blue.opacity(0.06) }
        return .clear
    }
}
#endif
