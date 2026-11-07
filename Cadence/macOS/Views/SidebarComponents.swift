#if os(macOS)
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// Non-SwiftUI storage for the currently-dragged sidebar row ID.
// Using a plain class instead of @State/@Binding so it's never nil'd by
// SwiftUI view updates between onDrag and performDrop.
//
// **SwiftUI never says when a drag ENDS** ([[T-7701]]). `.onDrag` sets the item, but a list
// released over empty sidebar gets no callback at all, so the item can outlive its drag. It is
// therefore only ever a hint: a drop counts as a list reorder only when the drag's own payload
// names the same list (`SidebarListDropPlacement.confirmedListDrag`), every drop on a list row
// ends the drag whatever it carried (`endDrag(onto:)`), and a row that sees a payload which is
// not that list clears it. Before that a task dragged onto a list row after an abandoned list
// drag drew the insertion line and reordered the old list.
final class SidebarDragContext {
    static let shared = SidebarDragContext()
    var draggedListItem: SidebarListDragItem?
    init() {}

    /// The synchronous half of a drop on a list row: ends the drag in flight on EVERY path —
    /// dropped on its own row, on a row of another section, or with nothing in flight — and
    /// returns the list to move onto `target`, or `nil` when the drop moves nothing.
    func endDrag(onto target: SidebarListDragItem) -> SidebarListDragItem? {
        let dragged = draggedListItem
        draggedListItem = nil
        guard let dragged, dragged != target else { return nil }
        return dragged
    }

    /// A row saw a drag whose payload is not the list this context thinks is in flight, so that
    /// list's drag ended without a drop on any row. Forget it, unless a newer list drag has
    /// already replaced it.
    func forgetStale(_ stale: SidebarListDragItem) {
        if draggedListItem == stale { draggedListItem = nil }
    }
}

nonisolated enum SidebarListKind: String {
    case area
    case project
}

nonisolated struct SidebarListDragItem: Equatable {
    let kind: SidebarListKind
    let id: UUID

    var providerText: NSString {
        "\(kind.rawValue):\(id.uuidString)" as NSString
    }
}

/// The Mac's drag half of `SidebarListEntry`, which itself moved to
/// `Cadence/Shared/CadenceSidebarListReorder.swift` when iOS gained list reorder ([[T-7260]](a)).
extension SidebarListEntry {
    var dragItem: SidebarListDragItem {
        switch self {
        case .area(let area): return SidebarListDragItem(kind: .area, id: area.id)
        case .project(let project): return SidebarListDragItem(kind: .project, id: project.id)
        }
    }

    fileprivate func matches(_ item: SidebarListDragItem) -> Bool {
        dragItem == item
    }

    /// The row a list drag names, looked up in the store rather than in one section's `entries`:
    /// a list dropped onto another context's section is, by definition, not among that section's
    /// rows ([[T-7260]](b)).
    static func resolve(_ item: SidebarListDragItem, in modelContext: ModelContext) -> SidebarListEntry? {
        switch item.kind {
        case .area: return resolve(kind: .area, id: item.id, in: modelContext)
        case .project: return resolve(kind: .project, id: item.id, in: modelContext)
        }
    }
}

/// A list dropped onto a row of a DIFFERENT context's section moves into that context
/// ([[T-7260]](b)).
///
/// The drop used to reach `reorderList`, find the dragged row absent from the section's `entries`
/// and return, while `SidebarListDropDelegate.performDrop` answered `true` -- a drag the column
/// accepted and then did nothing with. It is a context change now, the one the edit sheet's
/// Context row makes (`EditAreaSheet` / `EditProjectSheet.applyEdits()`): the list's own `context`
/// is written, its tasks' denormalized `context` is re-pointed by the same
/// `CadenceTaskMutationSupport.reassignInheritedContext` ([[T-559]], [[T-293]]), and it commits with
/// no confirmation, as the sheet's Save does. A project's parent area is left alone, as the sheet's
/// Context row leaves it.
///
/// The row lands directly above the row it was dropped on (`SidebarListDropPlacement.inserted`),
/// and the target section is renumbered whole so that position holds under
/// `CadenceSidebarLists.sorted`. One commit carries the move and the renumber, and a refusal puts
/// back every field and task the snapshot holds and every order it wrote, never `rollback()` --
/// `CadenceOrderCommit`'s reason.
enum SidebarListContextMove {
    static func commit(
        _ moved: SidebarListEntry,
        into context: Context?,
        onto targetIndex: Int,
        among entries: [SidebarListEntry],
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Bool {
        let arranged = SidebarListDropPlacement.inserted(moved, into: entries, at: targetIndex)
        let previousOrders = arranged.map(\.order)
        let snapshot: CadenceListEditSnapshot
        switch moved {
        case .area(let area):
            snapshot = CadenceListEditSnapshot(
                area,
                tasks: CadenceTaskMutationSupport.inheritedContextTargets(area: area)
            )
            area.context = context
            CadenceTaskMutationSupport.reassignInheritedContext(area: area)
        case .project(let project):
            snapshot = CadenceListEditSnapshot(
                project,
                tasks: CadenceTaskMutationSupport.inheritedContextTargets(project: project)
            )
            project.context = context
            CadenceTaskMutationSupport.reassignInheritedContext(project: project)
        }
        for (index, entry) in arranged.enumerated() {
            entry.setOrder(index)
        }
        do {
            try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit) {
                snapshot.restore()
                for (entry, order) in zip(arranged, previousOrders) {
                    entry.setOrder(order)
                }
            }
        } catch {
            return false
        }
        return true
    }
}

/// One section of the sidebar's lists region: a header, and the rows filed under it.
///
/// **It no longer derives its own rows (T-538).** It used to take a `Context` and read
/// `(context.areas ?? []).filter(\.isActive)`, which meant the region was drawn by *iterating
/// contexts* — and a list whose `context` is `nil`, or whose context has been archived, is reached
/// by no iteration. Not merely un-grouped: **absent**. iOS creates that state from the "None" row
/// of its list editor, in new and edit mode alike, and it arrives here by sync.
/// `SidebarView.listSections` buckets through `CadenceSidebarLists.sections` now — the rule the
/// iPad column already used — so the leftovers get the same "Other" section instead of falling out
/// of the loop.
///
/// **T-333 is why it does not sort either.** The private copy of `CadenceSidebarLists.sorted` that
/// used to live here stopped at name, so two same-kind rows sharing an `order` and a name could
/// reshuffle between renders on the Mac while the iPad held still. The rows arrive ordered.
struct ContextSection: View {
    let title: String
    /// The context this section files lists under, `nil` on the catch-all. A list dropped here
    /// from another section moves into it ([[T-7260]](b)).
    let context: Context?
    /// Already bucketed and already sorted, by `CadenceSidebarLists.sections`.
    let entries: [SidebarListEntry]
    @Binding var selection: SidebarItem?
    /// Every header has one, the catch-all included since T-559 made `CreateListSheet`'s context
    /// optional — before that it was `(() -> Void)?` and `nil` there, because the sheet could not
    /// be opened without a context to open it in. On macOS this button is the only way to make a
    /// list in a given context, which is also why an empty context still gets a section here and
    /// gets none on iPad.
    let onAddList: () -> Void
    @Environment(\.modelContext) private var modelContext
    @State private var areaForEdit: Area? = nil
    @State private var projectForEdit: Project? = nil
    @State private var dragOverListItem: SidebarListDragItem? = nil
    /// Set when the store refused a list drag (T-868). The rows are already back in their old
    /// order by then, so the column and this sentence agree.
    @State private var reorderFailureNotice: String? = nil
    /// Set when the store refused a project due date picked from the row's flag ([[T-4970]]). The
    /// project already holds its old date again by then, so the badge and this sentence agree.
    @State private var dueDateFailureNotice: String? = nil
    /// The row menu's Complete / Archive waiting on its confirmation ([[T-12621]]); set only when
    /// the wind-down would settle open work.
    @State private var pendingWindDown: SidebarListWindDown? = nil
    /// Set when the store refused a row-menu wind-down. The list and its tasks are back as they
    /// were by then (the commit's undo), so the row and this sentence agree.
    @State private var windDownFailureNotice: String? = nil

    private var hasLists: Bool { !entries.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: SidebarMetrics.contextHeaderBottomSpacing) {
            // Label plus "+", nothing else: the glyph and the hairline rule this header
            // used to carry drew more attention than the list names underneath it.
            HStack(spacing: SidebarMetrics.listIconLabelSpacing) {
                Text(title.uppercased())
                    .font(.system(size: SidebarMetrics.contextHeaderFontSize, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .kerning(SidebarMetrics.contextHeaderKerning)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: SidebarMetrics.listTrailingGap)

                Button(action: onAddList) {
                    Image(systemName: "plus")
                        .font(.system(size: SidebarMetrics.contextAddIconSize, weight: .semibold))
                        .foregroundStyle(Theme.dim.opacity(0.8))
                        .frame(
                            width: SidebarMetrics.contextAddButtonSize,
                            height: SidebarMetrics.contextAddButtonSize
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.cadencePlain)
                .cadenceControlLabel("Add list to \(title)")
            }
            .padding(.horizontal, SidebarMetrics.listRowHorizontalPadding)
            .padding(.top, SidebarMetrics.contextHeaderTopPadding)

            if let reorderFailureNotice {
                CadenceInlineFailureNotice(text: reorderFailureNotice)
                    .padding(.horizontal, SidebarMetrics.listRowHorizontalPadding)
            }

            if let dueDateFailureNotice {
                CadenceInlineFailureNotice(text: dueDateFailureNotice)
                    .padding(.horizontal, SidebarMetrics.listRowHorizontalPadding)
            }

            if let windDownFailureNotice {
                CadenceInlineFailureNotice(text: windDownFailureNotice)
                    .padding(.horizontal, SidebarMetrics.listRowHorizontalPadding)
            }

            if hasLists {
                VStack(alignment: .leading, spacing: SidebarMetrics.listRowSpacing) {
                    // Top drop zone — lets the user drag any item to the first position. It is
                    // transparent, so its height is also 4pt of whitespace under the header;
                    // `SidebarContextHeaderRhythm.gapBelowHeader` counts it as such.
                    if let firstItem = entries.first?.dragItem {
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .frame(height: SidebarMetrics.contextLeadingDropZoneHeight)
                            .onDrop(of: [UTType.text], delegate: SidebarListDropDelegate(
                                target: firstItem,
                                dragOverItem: $dragOverListItem,
                                onDrop: reorderList
                            ))
                    }

                    ForEach(entries) { entry in
                        switch entry {
                        case .area(let area):
                            areaRow(area, target: entry.dragItem)
                        case .project(let project):
                            projectRow(project, target: entry.dragItem)
                        }
                    }
                }
            } else {
                SidebarAddFirstListButton(action: onAddList)
            }
        }
        .padding(.bottom, SidebarMetrics.contextSectionBottomSpacing)
        .sheet(item: $areaForEdit) { area in
            EditAreaSheet(area: area)
        }
        .sheet(item: $projectForEdit) { project in
            EditProjectSheet(project: project)
        }
        .confirmationDialog(
            pendingWindDown?.confirmationTitle ?? "",
            isPresented: Binding(
                get: { pendingWindDown != nil },
                set: { if !$0 { pendingWindDown = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingWindDown
        ) { target in
            Button(target.actionTitle) { commitWindDown(target) }
            Button("Cancel", role: .cancel) { pendingWindDown = nil }
        } message: { target in
            Text(target.summary.settledLine ?? "")
        }
    }

    /// The row menu's Complete / Archive ([[T-12621]]). Asks first only when something would be
    /// settled -- `CadenceContainerWindDownSummary.requiresConfirmation`, the rule the iPad's same
    /// menu follows -- and otherwise winds the list down at once.
    private func requestWindDown(_ target: SidebarListWindDown?) {
        guard let target else { return }
        if target.summary.requiresConfirmation {
            pendingWindDown = target
        } else {
            commitWindDown(target)
        }
    }

    private func commitWindDown(_ target: SidebarListWindDown) {
        pendingWindDown = nil
        do {
            try SidebarListWindDown.windDown(target, in: modelContext)
        } catch {
            windDownFailureNotice = CadencePendingChangePersistence.editFailureNotice
            return
        }
        windDownFailureNotice = nil
    }

    /// Drag a list to a new place in the sidebar.
    ///
    /// **It ended in `try? modelContext.save()` until T-868.** A rearrangement the user can see is a
    /// success report (T-614): the row sits where it was dropped, and a refused save meant it came
    /// back in its old place at next launch with nothing on screen having said so. It commits
    /// through the shared unit now and names the refusal under the section header.
    ///
    /// The insert index is deliberately **not** `CadenceOrderReassignment.moved`'s: this column
    /// treats the row you drop on as the destination itself, rather than as "the row I go before",
    /// which is what stops a drag onto the next row down from feeling like a no-op. That is a
    /// different gesture from the contexts pane's, so it keeps its own arithmetic; what it shares
    /// is the commit.
    ///
    /// A list dragged in from ANOTHER section is not among `entries`; it moves into this section's
    /// context instead ([[T-7260]](b), `SidebarListContextMove`).
    private func reorderList(dropped: SidebarListDragItem, target: SidebarListDragItem) {
        guard let toIndex = entries.firstIndex(where: { $0.matches(target) }) else { return }
        guard let fromIndex = entries.firstIndex(where: { $0.matches(dropped) }) else {
            moveListIntoContext(dropped, onto: toIndex)
            return
        }
        // Treat the row we drop on as the destination row itself. This avoids the
        // "no-op" feeling when dragging onto the next item down in the list.
        // The same call iOS's Move Up / Move Down makes ([[T-7260]](a)): one arrangement, one
        // renumber, one commit with its full restore, `CadenceOrderCommit` underneath.
        let reordered = withAnimation(.spring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.08)) {
            CadenceSidebarListReorder.commit(entries, moving: fromIndex, onto: toIndex, in: modelContext)
        }
        reorderFailureNotice = reordered ? nil : CadenceOrderCommit.failureNotice
    }

    /// The cross-section drop ([[T-7260]](b)). A refusal reads the reorder's own sentence, under
    /// this header: the row is back in its old section by then, so "Nothing was moved" is true.
    private func moveListIntoContext(_ dropped: SidebarListDragItem, onto toIndex: Int) {
        guard let moved = SidebarListEntry.resolve(dropped, in: modelContext) else { return }
        let landed = withAnimation(.spring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.08)) {
            SidebarListContextMove.commit(
                moved,
                into: context,
                onto: toIndex,
                among: entries,
                in: modelContext
            )
        }
        reorderFailureNotice = landed ? nil : CadenceOrderCommit.failureNotice
    }

    /// The row's due-date flag picks or clears the project's date ([[T-4970]]).
    ///
    /// It used to be `project.dueDate = newKey` and nothing else, so the date sat pending in the
    /// app's single `ModelContext` until an unrelated save committed it or an unrelated
    /// `rollback()` discarded it — the [[T-4911]] / [[T-503]] shape. A refusal puts the old date
    /// back and says so under the section header, beside the reorder notice.
    private func setDueDate(_ newKey: String, on project: Project) {
        do {
            try Self.commitDueDate(newKey, on: project, in: modelContext)
        } catch {
            dueDateFailureNotice = CadencePendingChangePersistence.editFailureNotice
            return
        }
        dueDateFailureNotice = nil
    }

    static func commitDueDate(
        _ dueDateKey: String,
        on project: Project,
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        let previousDueDate = project.dueDate
        project.dueDate = dueDateKey
        try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit) {
            project.dueDate = previousDueDate
        }
    }

    /// The 2pt insertion line over the row a list is being dragged onto, on the edge the drop
    /// will actually land at.
    ///
    /// It used to be pinned to the row's TOP for every drag, while `reorderList` puts the row
    /// where the target was — so a downward drag landed one row BELOW the line, and a drag onto
    /// the next row down drew the line exactly where the row already sat and then moved it. A row
    /// dragged in from another section draws the line on the target's top edge, where the
    /// context move puts it ([[T-7260]](b)); until then it drew none, because that drop did nothing.
    @ViewBuilder
    private func dropIndicator(for target: SidebarListDragItem) -> some View {
        if dragOverListItem == target,
           let dragged = SidebarDragContext.shared.draggedListItem,
           let toIndex = entries.firstIndex(where: { $0.matches(target) }),
           let edge = SidebarListDropPlacement.indicatorEdge(
               draggedIndex: entries.firstIndex(where: { $0.matches(dragged) }),
               targetIndex: toIndex
           ) {
            VStack(spacing: 0) {
                if edge == .bottom { Spacer(minLength: 0) }
                Rectangle().fill(Theme.blue).frame(height: 2)
                if edge == .top { Spacer(minLength: 0) }
            }
            .transition(.opacity)
        }
    }

    private func areaRow(_ area: Area, target: SidebarListDragItem) -> some View {
        SidebarListRow(
            item: .area(area.id),
            label: area.name,
            kind: .area,
            count: CadenceSidebarLayout.listCount(
                openTaskCount: CadenceTaskQuerySupport.openTaskCount(for: area)
            ),
            dueDateKey: nil,
            onSetDueDate: nil,
            selection: $selection,
            onEdit: { areaForEdit = area },
            onWindDown: { requestWindDown(SidebarListWindDown(.area(area), choice: $0)) }
        )
        .overlay { dropIndicator(for: target) }
        .animation(.easeInOut(duration: 0.15), value: dragOverListItem)
        .onDrag {
            SidebarDragContext.shared.draggedListItem = target
            return NSItemProvider(object: target.providerText)
        }
        .onDrop(of: [UTType.text], delegate: SidebarListDropDelegate(
            target: target,
            dragOverItem: $dragOverListItem,
            onDrop: reorderList
        ))
    }

    private func projectRow(_ project: Project, target: SidebarListDragItem) -> some View {
        SidebarListRow(
            item: .project(project.id),
            label: project.name,
            kind: .project,
            count: CadenceSidebarLayout.listCount(
                openTaskCount: CadenceTaskQuerySupport.openTaskCount(for: project)
            ),
            dueDateKey: project.dueDate,
            onSetDueDate: { newKey in
                setDueDate(newKey, on: project)
            },
            selection: $selection,
            onEdit: { projectForEdit = project },
            onWindDown: { requestWindDown(SidebarListWindDown(.project(project), choice: $0)) }
        )
        .overlay { dropIndicator(for: target) }
        .animation(.easeInOut(duration: 0.15), value: dragOverListItem)
        .onDrag {
            SidebarDragContext.shared.draggedListItem = target
            return NSItemProvider(object: target.providerText)
        }
        .onDrop(of: [UTType.text], delegate: SidebarListDropDelegate(
            target: target,
            dragOverItem: $dragOverListItem,
            onDrop: reorderList
        ))
    }
}

// MARK: - Row menu wind-down

/// One list the sidebar row's menu is completing or archiving ([[T-12621]]).
///
/// The same writes the Edit sheet's `apply(_:)` makes for that choice -- the list's `status`, then
/// `TaskContainerLifecycleService.settleRemainingActiveTasks` in the direction
/// `ListEditorLifecycleChoice.windDownOutcome` names -- under one snapshot and one commit, without
/// the sheet's pending field edits, because the row has none. The sheet keeps its own copy for the
/// reason `iOSListWindDownSupport`'s editor does: its settle rides its field edits' commit.
struct SidebarListWindDown: Identifiable {
    enum Subject {
        case area(Area)
        case project(Project)
    }

    let subject: Subject
    let choice: ListEditorLifecycleChoice
    let outcome: CadenceWindDownOutcome

    /// `nil` for `.active`: reopening a list settles nothing, so it is no wind-down.
    init?(_ subject: Subject, choice: ListEditorLifecycleChoice) {
        guard let outcome = choice.windDownOutcome else { return nil }
        self.subject = subject
        self.choice = choice
        self.outcome = outcome
    }

    var id: String {
        switch subject {
        case .area(let area): return "area-\(area.id)"
        case .project(let project): return "project-\(project.id)"
        }
    }

    private var noun: String {
        switch subject {
        case .area: return "Area"
        case .project: return "Project"
        }
    }

    /// The menu item's own words, so the confirmation's button says what was clicked.
    var actionTitle: String {
        "\(outcome == .done ? "Complete" : "Archive") \(noun)"
    }

    var confirmationTitle: String { "\(actionTitle)?" }

    /// The settle's own array, counted before the fact -- the iPad's confirmation counts the same.
    var summary: CadenceContainerWindDownSummary {
        switch subject {
        case .area(let area): return .forArea(area, outcome: outcome)
        case .project(let project): return .forProject(project, outcome: outcome)
        }
    }

    /// Writes the wind-down and commits it; a refusal puts the list and every settled task back.
    static func windDown(
        _ target: SidebarListWindDown,
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        let undo: CadenceListEditSnapshot
        switch target.subject {
        case .area(let area):
            undo = CadenceListEditSnapshot(
                area,
                tasks: TaskContainerLifecycleService.remainingActiveTasks(in: area, includingChildProjects: true)
            )
            area.status = target.choice == .completed ? .done : .archived
            TaskContainerLifecycleService.settleRemainingActiveTasks(
                in: area,
                includingChildProjects: true,
                outcome: target.outcome,
                in: modelContext
            )
        case .project(let project):
            undo = CadenceListEditSnapshot(
                project,
                tasks: TaskContainerLifecycleService.remainingActiveTasks(in: project)
            )
            project.status = target.choice == .completed ? .done : .archived
            TaskContainerLifecycleService.settleRemainingActiveTasks(
                in: project,
                outcome: target.outcome,
                in: modelContext
            )
        }
        try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit, undo: undo.restore)
    }
}

// MARK: - Drop placement

/// Where a list dragged within one sidebar section lands, and which edge of the target row the
/// insertion line is drawn on. One declaration for both, so the line cannot say one place while
/// the drop writes another.
nonisolated enum SidebarListDropPlacement {
    enum Edge: Equatable {
        case top
        case bottom
    }

    /// `items` with the row at `from` moved to `onto`'s position: the dropped-on row is the
    /// destination itself, so a downward drag lands after it and an upward drag before it.
    ///
    /// The arithmetic is `CadenceSidebarListReorder.reordered`'s, the one iOS's one-step move uses.
    static func reordered<Element>(_ items: [Element], moving from: Int, onto to: Int) -> [Element] {
        CadenceSidebarListReorder.reordered(items, moving: from, onto: to)
    }

    /// `items` with a row from ANOTHER section inserted directly above `at` ([[T-7260]](b)) -- the
    /// position the line drawn for it promises. An index past the end appends.
    static func inserted<Element>(_ element: Element, into items: [Element], at index: Int) -> [Element] {
        var result = items
        result.insert(element, at: max(0, min(index, result.count)))
        return result
    }

    /// The edge of the target row the dragged row will sit against once dropped, or `nil` when
    /// the drop moves nothing (the row itself). A row from another section (`nil` index) is
    /// inserted above the target, so its line is the top edge ([[T-7260]](b)).
    static func indicatorEdge(draggedIndex: Int?, targetIndex: Int) -> Edge? {
        guard let draggedIndex else { return .top }
        guard draggedIndex != targetIndex else { return nil }
        return draggedIndex < targetIndex ? .bottom : .top
    }

    /// The list a drag over a list row moves, or `nil` when it is not a list reorder.
    ///
    /// A payload that LOADED decides it: only that list's own `providerText` confirms `dragged`;
    /// a task (`TaskDragPayload`) or foreign text is not a list drag, whatever
    /// `SidebarDragContext` still holds from an earlier one ([[T-7701]]). A payload that did NOT
    /// load (no provider, or `loadObject` failed) is no evidence either way, so the in-flight
    /// `dragged` stands: treating it as a refusal made every reorder hang on an async load that
    /// AppKit need not serve mid-drag, and a failed load then forgot the list ([[T-7892]]).
    static func confirmedListDrag(payload: String?, dragged: SidebarListDragItem?) -> SidebarListDragItem? {
        guard let dragged else { return nil }
        guard let payload else { return dragged }
        return payload == dragged.providerText as String ? dragged : nil
    }
}

// MARK: - First list

/// "Add first list", the only row the lists region draws when it has no list rows to draw.
///
/// **Two callers, and the second one is the whole of T-1113.** `ContextSection` draws it under the
/// header of a context that holds nothing, and `SidebarView.listsSection` draws it when the region
/// produced *no sections at all* — which is what a genuinely fresh install produces, because
/// `CadenceSidebarLists.sections` derives every header from an existing context or an existing
/// list. Before that second caller the column's only route to `CreateListSheet` was a context
/// header's "+", and on a blank store there was no header, so the first list on a new Mac had to be
/// preceded by a trip to Settings → Contexts. An App Store reviewer opens a blank store.
///
/// It is one view rather than two spellings of one button because the two cases differ only in what
/// context the sheet opens on, and that is the caller's `action`. The empty-store caller passes
/// `nil`, so the sheet opens on "No context" — the state `CreateListSheet` has accepted since
/// T-559 and the state the resulting list is filed under ("Other") if it is saved that way.
struct SidebarAddFirstListButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Starts on the same x as a list name would, so an empty context and a
            // populated one share a left edge.
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(.system(size: SidebarMetrics.listIconSize, weight: .semibold))
                Text(CadenceEmptyStateCopy.addFirstListAction)
                    .font(.system(size: SidebarMetrics.listLabelFontSize, weight: .medium))
                Spacer(minLength: SidebarMetrics.listTrailingGap)
            }
            .foregroundStyle(Theme.dim)
            .padding(.horizontal, SidebarMetrics.listRowHorizontalPadding)
            .padding(.vertical, SidebarMetrics.listRowVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: SidebarMetrics.listRowCornerRadius, style: .continuous)
                    .fill(Theme.surfaceElevated.opacity(0.55))
            )
        }
        .buttonStyle(.cadencePlain(cornerRadius: SidebarMetrics.listRowCornerRadius))
    }
}

// MARK: - Drop Delegates

private struct SidebarListDropDelegate: DropDelegate {
    let target: SidebarListDragItem
    @Binding var dragOverItem: SidebarListDragItem?
    let onDrop: (SidebarListDragItem, SidebarListDragItem) -> Void

    /// Refused outright when no list drag is in flight, so a task hovering a list row draws no
    /// line and its drop is not taken for a reorder ([[T-7701]]).
    func validateDrop(info: DropInfo) -> Bool {
        SidebarDragContext.shared.draggedListItem != nil && info.hasItemsConforming(to: [UTType.text])
    }

    /// Draws the line at once, then checks the payload: one that loads and is not the in-flight
    /// list means that list's drag was abandoned, so the line comes down and the stale item is
    /// forgotten. One that does not load keeps the list ([[T-7892]]). The late answer can only
    /// take the line away, never put it up after the drag has left.
    func dropEntered(info: DropInfo) {
        guard let inFlight = SidebarDragContext.shared.draggedListItem else { return }
        dragOverItem = target
        let target = target
        let dragOverItem = $dragOverItem
        loadPayload(from: info) { payload in
            guard SidebarListDropPlacement.confirmedListDrag(payload: payload, dragged: inFlight) == nil else { return }
            SidebarDragContext.shared.forgetStale(inFlight)
            if dragOverItem.wrappedValue == target { dragOverItem.wrappedValue = nil }
        }
    }

    func dropExited(info: DropInfo) {
        if dragOverItem == target { dragOverItem = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        if dragOverItem == target { dragOverItem = nil }
        // Ends the drag before anything can return early: a list dropped back on its own row
        // used to keep it in flight ([[T-7701]]).
        guard let dropped = SidebarDragContext.shared.endDrag(onto: target) else { return false }
        let target = target
        let onDrop = onDrop
        loadPayload(from: info) { payload in
            guard let confirmed = SidebarListDropPlacement.confirmedListDrag(payload: payload, dragged: dropped) else { return }
            onDrop(confirmed, target)
        }
        return true
    }

    /// The drag's plain-text payload, delivered on the main actor (`nil` when there is no text
    /// provider or it failed to load, which `confirmedListDrag` treats as no evidence).
    private func loadPayload(from info: DropInfo, then deliver: @escaping @MainActor (String?) -> Void) {
        guard let provider = info.itemProviders(for: [UTType.text]).first else {
            deliver(nil)
            return
        }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            let payload = (object as? NSString).map { $0 as String }
            Task { @MainActor in deliver(payload) }
        }
    }
}
#endif
