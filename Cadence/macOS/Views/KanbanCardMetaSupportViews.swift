#if os(macOS)
import SwiftData
import SwiftUI

struct KanbanDateMetaButton<PopoverContent: View>: View {
    let item: KanbanMetaItem
    @Binding var isPresented: Bool
    let onOpen: () -> Void
    let onHoverChanged: (Bool) -> Void
    @ViewBuilder let popoverContent: () -> PopoverContent

    var body: some View {
        Button {
            onOpen()
        } label: {
            KanbanMetaChip(item: item, isFocused: isPresented, onHoverChanged: onHoverChanged)
        }
        .buttonStyle(.cadencePlain)
        .popover(isPresented: $isPresented, content: popoverContent)
    }
}

/// The list chip. Clicking it opens the same searchable, context-grouped list picker that
/// `ContainerPickerBadge` presents on every other surface.
///
/// The picker's `@Query`s live in the popover *content*, not here: a board can have a hundred
/// cards alive at once, and a query per card would mean a hundred fetches and a hundred
/// observation registrations for a picker almost none of them will ever open. Popover content is
/// only instantiated when it is presented — the same trick `TaskDetailPopover` already uses.
struct KanbanContainerMetaButton: View {
    let item: KanbanMetaItem
    let task: AppTask
    @Binding var isPresented: Bool
    let onOpen: () -> Void
    let onHoverChanged: (Bool) -> Void

    var body: some View {
        Button {
            onOpen()
        } label: {
            KanbanMetaChip(item: item, isFocused: isPresented, onHoverChanged: onHoverChanged)
        }
        .buttonStyle(.cadencePlain)
        .help("Move to another list")
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            KanbanContainerPickerPopover(task: task, isPresented: $isPresented)
        }
    }
}

struct KanbanContainerPickerPopover: View {
    @Bindable var task: AppTask
    @Binding var isPresented: Bool

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query private var allTasks: [AppTask]

    @State private var searchQuery = ""
    @State private var highlightIdx = 0
    @FocusState private var isSearchFocused: Bool

    private var groupedContainers: [(context: Context, areas: [Area], projects: [Project])] {
        contexts.compactMap { context in
            let matchingAreas = areas
                .filter { $0.isActive && $0.context?.id == context.id && matches($0.name) }
                .sorted { $0.order < $1.order }
            let matchingProjects = projects
                .filter { $0.isActive && $0.context?.id == context.id && matches($0.name) }
                .sorted { $0.order < $1.order }
            guard !matchingAreas.isEmpty || !matchingProjects.isEmpty else { return nil }
            return (context, matchingAreas, matchingProjects)
        }
    }

    private func matches(_ name: String) -> Bool {
        searchQuery.isEmpty || name.lowercased().hasPrefix(searchQuery.lowercased())
    }

    private var showsInbox: Bool { matches("Inbox") }

    /// Flat ordering behind the arrow-key highlight — must stay in the same order the rows render.
    private var flatFiltered: [TaskContainerSelection] {
        var result: [TaskContainerSelection] = []
        if showsInbox { result.append(.inbox) }
        for group in groupedContainers {
            result.append(contentsOf: group.areas.map { .area($0.id) })
            result.append(contentsOf: group.projects.map { .project($0.id) })
        }
        return result
    }

    private var highlighted: TaskContainerSelection? {
        guard !flatFiltered.isEmpty else { return nil }
        return flatFiltered[TaskPickerHighlightSupport.clampedIndex(highlightIdx, count: flatFiltered.count)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchBar

            Divider().background(Theme.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if showsInbox {
                        KanbanContainerPickerRow(
                            icon: "tray",
                            name: "Inbox",
                            color: Theme.dim,
                            isHighlighted: highlighted == .inbox
                        ) {
                            select(.inbox)
                        }
                    }

                    ForEach(groupedContainers, id: \.context.id) { group in
                        Text(group.context.name.uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color(hex: group.context.colorHex))
                            .kerning(0.6)
                            .padding(.horizontal, 12)
                            .padding(.top, 6)
                            .padding(.bottom, 2)

                        ForEach(group.areas) { area in
                            KanbanContainerPickerRow(
                                icon: area.icon,
                                name: area.name,
                                color: Color(hex: area.colorHex),
                                isHighlighted: highlighted == .area(area.id)
                            ) {
                                select(.area(area.id))
                            }
                        }

                        ForEach(group.projects) { project in
                            KanbanContainerPickerRow(
                                icon: project.icon,
                                name: project.name,
                                color: Color(hex: project.colorHex),
                                isHighlighted: highlighted == .project(project.id)
                            ) {
                                select(.project(project.id))
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
            highlightIdx = 0
            DispatchQueue.main.async { isSearchFocused = true }
        }
        .onChange(of: searchQuery) { _, _ in highlightIdx = 0 }
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
                    if let highlighted { select(highlighted) }
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

    private func select(_ selection: TaskContainerSelection) {
        let area: Area?
        let project: Project?
        switch selection {
        case .inbox:
            area = nil
            project = nil
        case .area(let id):
            area = areas.first { $0.id == id }
            project = nil
        case .project(let id):
            area = nil
            project = projects.first { $0.id == id }
        }

        CadenceTaskMutationSupport.moveToContainer(
            task,
            area: area,
            project: project,
            allTasks: allTasks,
            modelContext: modelContext
        )
        isPresented = false
    }
}

private struct KanbanContainerPickerRow: View {
    let icon: String
    let name: String
    let color: Color
    let isHighlighted: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(color)
                    .frame(width: 16)
                Text(name)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer()
                if isHighlighted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.blue)
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

/// The card's tag chips. Clicking any of them opens the task's tag editor — the same
/// `TagPickerPopover` the task inspector and the create sheet use — so the strip is an
/// affordance rather than decoration. Renders nothing when the task has no tags.
///
/// As with the list chip, the `allTags` query is inside the popover content so an untouched
/// card costs no fetch.
struct KanbanCardTagStrip: View {
    let task: AppTask
    @Binding var isPresented: Bool
    let onOpen: () -> Void
    let onHoverChanged: (Bool) -> Void

    var body: some View {
        let tags = task.sortedTags
        if !tags.isEmpty {
            Button {
                onOpen()
            } label: {
                CompactTagStrip(tags: tags, limit: 3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.cadencePlain)
            .help("Edit tags")
            .onHover { onHoverChanged($0) }
            .popover(isPresented: $isPresented, arrowEdge: .trailing) {
                KanbanTagPickerPopover(task: task)
            }
        }
    }
}

struct KanbanTagPickerPopover: View {
    @Bindable var task: AppTask

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tag.order) private var allTags: [Tag]

    var body: some View {
        TagPickerPopover(
            selectedTags: Binding(
                get: { task.sortedTags },
                set: { newValue in
                    task.tags = newValue
                    try? modelContext.save()
                }
            ),
            allTags: allTags,
            onCreateTag: { name in
                TagSupport.resolveTags(named: [name], in: modelContext).first ?? Tag(name: name)
            }
        )
    }
}
#endif
