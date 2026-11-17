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

/// **[[T-18292]], the fourth `TagPickerPopover` host, brought to [[T-18288]]'s shape.** It kept the
/// field in its own `@State`, so a name the dismiss commit could not land closed with it, and both
/// its writes swallowed a refusal: the selection setter was `try?` over a raw `save()`, and a
/// refused create drew nothing. Now the field and the failure line are the card's state, every
/// write answers what the store said, and `refusalRoute` decides where that is said.
struct KanbanTagPickerPopover: View {
    @Bindable var task: AppTask
    /// The field's text, held by the card so a refused name is back on the next open, as
    /// `TagPickerControl` holds it for the other three hosts.
    @Binding var query: String
    /// The card's sentence for a refusal made while this popover is open, drawn under the picker
    /// as `KanbanContainerPickerPopover` draws its `moveFailureNotice`.
    let failureNotice: String?
    /// Every write's answer -- a refusal's sentence, `nil` for a write the store took -- handed to
    /// the card, which knows whether this popover is still open to say it in.
    let report: (String?) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tag.order) private var allTags: [Tag]

    /// Where a write's answer goes. While the popover is open it is drawn inside it; once it has
    /// closed -- the field's dismiss commit -- nothing inside it is on screen, so the card raises
    /// its refusal alert instead, the one a closed menu's refused write raises.
    enum RefusalRoute: Equatable {
        case cleared
        case inline(String)
        case alert(String)
    }

    static func refusalRoute(_ refusal: String?, pickerOpen: Bool) -> RefusalRoute {
        guard let refusal else { return .cleared }
        return pickerOpen ? .inline(refusal) : .alert(refusal)
    }

    /// The selection setter's write, committed through the inspector's own tag write
    /// (`TaskInspectorScheduleCommit.setTags`, a `commitEdit` with a field snapshot for its undo)
    /// rather than `try?` over a raw `save()`. Answers the refusal's sentence, `nil` on success.
    static func setTags(
        _ tags: [Tag], on task: AppTask, in context: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> String? {
        TaskInspectorScheduleCommit.setTags(tags, on: task, in: context, commit: commit)
            ? nil : CadenceTaskFieldEditCommit.saveFailureNotice
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TagPickerPopover(
                selectedTags: Binding(
                    get: { task.sortedTags },
                    set: { report(Self.setTags($0, on: task, in: modelContext)) }
                ),
                allTags: allTags,
                onCreateTag: createTag,
                query: $query,
                onDismissRefusal: { report($0) }
            )

            if let failureNotice {
                CadenceInlineFailureNotice(text: failureNotice)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }
        }
    }

    /// The Create row's mint, committed by `TagSupport.committedTag` ([[T-651]]); a refusal is now
    /// said rather than only answered `nil`, as `TaskDetailPopover.createTag` says it.
    private func createTag(_ name: String) -> Tag? {
        let tag = TagSupport.committedTag(named: name, in: modelContext)
        report(tag == nil ? CadencePendingChangePersistence.editFailureNotice : nil)
        return tag
    }
}
#endif
