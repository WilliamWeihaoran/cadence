#if os(macOS)
import SwiftData
import SwiftUI

struct KanbanContainerPickerPopover: View {
    @Bindable var task: AppTask
    @Binding var isPresented: Bool

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query private var allTasks: [AppTask]

    /// Set when the move's commit was refused. The popover stays open over it — see `select(_:)`.
    @State private var moveFailureNotice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ContainerPickerPopoverContent(
                contexts: contexts,
                areas: areas,
                projects: projects,
                // The card has the task itself rather than a binding, so the placement is read off
                // it through the shared accessor `select(_:)` below writes back through. Without it
                // a card sitting in an archived list opened a picker with no row for that list.
                selection: CadenceTaskComposerSupport.container(of: task)
            ) { picked in
                select(picked)
            }

            if let moveFailureNotice {
                CadenceInlineFailureNotice(text: moveFailureNotice)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }
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

        // T-497: this closed the popover unconditionally over a swallowed `save()`, so a refused
        // move looked exactly like one that landed — the picker shut and the card kept the list it
        // had never left. The popover holds no draft, so the move undoes cleanly and the honest
        // answer is to stay open and say so.
        guard CadenceTaskMutationSupport.moveToContainer(
            task,
            area: area,
            project: project,
            allTasks: allTasks,
            modelContext: modelContext
        ) else {
            moveFailureNotice = CadenceTaskFieldEditCommit.saveFailureNotice
            return
        }
        moveFailureNotice = nil
        isPresented = false
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
                TagSupport.committedTag(named: name, in: modelContext)
            }
        )
    }
}
#endif
