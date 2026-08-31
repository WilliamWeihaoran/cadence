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
        .accessibilityLabel(CadenceTaskControlAccessibility.list)
        .accessibilityValue(item.text)
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

    var body: some View {
        ContainerPickerPopoverContent(
            contexts: contexts,
            areas: areas,
            projects: projects,
            // The card has the task itself rather than a binding, so the placement is read off it
            // through the shared accessor `select(_:)` below writes back through. Without it a
            // card sitting in an archived list opened a picker with no row for that list.
            selection: CadenceTaskComposerSupport.container(of: task)
        ) { picked in
            select(picked)
        }
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
                // `CadenceTaskPresentationSupport.rowTagLimit`, not a local 3. Same figure, but the
                // iOS board card reads it too now, and a literal here is a literal that can drift.
                CompactTagStrip(tags: tags, limit: CadenceTaskPresentationSupport.rowTagLimit)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.cadencePlain)
            .accessibilityLabel("Edit tags")
            .accessibilityValue(tags.map { CadenceTagChipStyle.displayName(for: $0) }.joined(separator: ", "))
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
                TagSupport.resolveTags(named: [name], in: modelContext)?.first ?? Tag(name: name)
            }
        )
    }
}
#endif
