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

/// One row of the lists region, still holding its model object: these rows drag, and the drop
/// delegate writes `order` straight back.
///
/// Internal rather than file-private because `SidebarView` builds the region's sections now — see
/// `SidebarView.listSections`. `ContextSection` is handed a section's rows already bucketed and
/// already sorted.
enum SidebarListEntry: Identifiable {
    case area(Area)
    case project(Project)

    var id: String {
        switch self {
        case .area(let area): return "area-\(area.id.uuidString)"
        case .project(let project): return "project-\(project.id.uuidString)"
        }
    }

    /// This row, flattened to what `CadenceSidebarLists` groups and orders by. `kindRank` used to
    /// live here as a hand-rolled twin of `CadenceSidebarLists.Kind.rank`; the shared type owns it
    /// now, and since T-538 the *flattening* is shared too.
    ///
    /// **It used to be `sidebarListItem(contextID: UUID)`** — a non-optional the caller filled in
    /// from whichever `Context` it was iterating, which is precisely how a list with no context
    /// became undrawable on this column rather than merely un-grouped. There is no parameter to
    /// fill in now; the bridge reads `area.context?.id`, which is the optional the model declares.
    var sidebarListItem: CadenceSidebarLists.Item {
        switch self {
        case .area(let area): return CadenceSidebarLists.Item(area)
        case .project(let project): return CadenceSidebarLists.Item(project)
        }
    }

    fileprivate var dragItem: SidebarListDragItem {
        switch self {
        case .area(let area): return SidebarListDragItem(kind: .area, id: area.id)
        case .project(let project): return SidebarListDragItem(kind: .project, id: project.id)
        }
    }

    fileprivate func matches(_ item: SidebarListDragItem) -> Bool {
        dragItem == item
    }

    /// The paired reader for `setOrder(_:)`, and the reason `CadenceOrderCommit.commit` takes
    /// closures rather than a `KeyPath`: this is an `enum` over two models, so its order lives
    /// behind a `switch` and not in a stored property either case shares.
    var order: Int {
        switch self {
        case .area(let area): return area.order
        case .project(let project): return project.order
        }
    }

    func setOrder(_ value: Int) {
        switch self {
        case .area(let area): area.order = value
        case .project(let project): project.order = value
        }
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
    private func reorderList(dropped: SidebarListDragItem, target: SidebarListDragItem) {
        guard let fromIndex = entries.firstIndex(where: { $0.matches(dropped) }),
              let toIndex = entries.firstIndex(where: { $0.matches(target) }) else { return }
        // Treat the row we drop on as the destination row itself. This avoids the
        // "no-op" feeling when dragging onto the next item down in the list.
        let sorted = SidebarListDropPlacement.reordered(entries, moving: fromIndex, onto: toIndex)
        let reordered = withAnimation(.spring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.08)) {
            CadenceOrderCommit.commit(
                sorted,
                readOrder: { $0.order },
                writeOrder: { $0.setOrder($1) },
                in: modelContext
            )
        }
        reorderFailureNotice = reordered ? nil : CadenceOrderCommit.failureNotice
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
    /// dragged in from another section draws no line, because the drop does nothing there.
    @ViewBuilder
    private func dropIndicator(for target: SidebarListDragItem) -> some View {
        if dragOverListItem == target,
           let toIndex = entries.firstIndex(where: { $0.matches(target) }),
           let edge = SidebarListDropPlacement.indicatorEdge(
               draggedIndex: SidebarDragContext.shared.draggedListItem.flatMap { dragged in
                   entries.firstIndex(where: { $0.matches(dragged) })
               },
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
            onEdit: { areaForEdit = area }
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
            onEdit: { projectForEdit = project }
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
    static func reordered<Element>(_ items: [Element], moving from: Int, onto to: Int) -> [Element] {
        guard items.indices.contains(from), items.indices.contains(to) else { return items }
        var result = items
        let element = result.remove(at: from)
        result.insert(element, at: min(to, result.count))
        return result
    }

    /// The edge of the target row the dragged row will sit against once dropped, or `nil` when
    /// the drop moves nothing — the row itself, or a row from another section (`nil` index).
    static func indicatorEdge(draggedIndex: Int?, targetIndex: Int) -> Edge? {
        guard let draggedIndex, draggedIndex != targetIndex else { return nil }
        return draggedIndex < targetIndex ? .bottom : .top
    }

    /// `dragged` when the drag's payload is that list's own `providerText`, otherwise `nil`: a
    /// task (`TaskDragPayload`), foreign text, or a payload that never loaded is not a list drag,
    /// whatever `SidebarDragContext` still holds from an earlier one ([[T-7701]]).
    static func confirmedListDrag(payload: String?, dragged: SidebarListDragItem?) -> SidebarListDragItem? {
        guard let dragged, let payload, payload == dragged.providerText as String else { return nil }
        return dragged
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
        .buttonStyle(.cadencePlain)
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

    /// Draws the line at once, then checks the payload: one that is not the in-flight list means
    /// that list's drag was abandoned, so the line comes down and the stale item is forgotten.
    /// The late answer can only take the line away, never put it up after the drag has left.
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

    /// The drag's plain-text payload, delivered on the main actor (`nil` when there is none).
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
