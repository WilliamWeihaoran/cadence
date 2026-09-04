#if os(macOS)
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// Non-SwiftUI storage for the currently-dragged sidebar row ID.
// Using a plain class instead of @State/@Binding so it's never nil'd by
// SwiftUI view updates between onDrag and performDrop.
private final class SidebarDragContext {
    static let shared = SidebarDragContext()
    var draggedListItem: SidebarListDragItem?
    private init() {}
}

private enum SidebarListKind: String {
    case area
    case project
}

private struct SidebarListDragItem: Equatable {
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

            if hasLists {
                VStack(alignment: .leading, spacing: SidebarMetrics.listRowSpacing) {
                    // Top drop zone — lets the user drag any item to the first position
                    if let firstItem = entries.first?.dragItem {
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .frame(height: 4)
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
                Button(action: onAddList) {
                    // Starts on the same x as a list name would, so an empty context and a
                    // populated one share a left edge.
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: SidebarMetrics.listIconSize, weight: .semibold))
                        Text("Add first list")
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
        var sorted = entries
        guard let fromIndex = sorted.firstIndex(where: { $0.matches(dropped) }),
              let toIndex = sorted.firstIndex(where: { $0.matches(target) }) else { return }
        let element = sorted.remove(at: fromIndex)
        // Treat the row we drop on as the destination row itself. This avoids the
        // "no-op" feeling when dragging onto the next item down in the list.
        sorted.insert(element, at: min(toIndex, sorted.count))
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

    private func areaRow(_ area: Area, target: SidebarListDragItem) -> some View {
        SidebarListRow(
            item: .area(area.id),
            label: area.name,
            color: Color(hex: area.colorHex),
            kind: .area,
            count: CadenceSidebarLayout.listCount(
                openTaskCount: CadenceTaskQuerySupport.openTaskCount(for: area)
            ),
            dueDateKey: nil,
            onSetDueDate: nil,
            selection: $selection,
            onEdit: { areaForEdit = area }
        )
        .overlay(alignment: .top) {
            if dragOverListItem == target {
                Rectangle().fill(Theme.blue).frame(height: 2).transition(.opacity)
            }
        }
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
            color: Color(hex: project.colorHex),
            kind: .project,
            count: CadenceSidebarLayout.listCount(
                openTaskCount: CadenceTaskQuerySupport.openTaskCount(for: project)
            ),
            dueDateKey: project.dueDate,
            onSetDueDate: { newKey in
                project.dueDate = newKey
            },
            selection: $selection,
            onEdit: { projectForEdit = project }
        )
        .overlay(alignment: .top) {
            if dragOverListItem == target {
                Rectangle().fill(Theme.blue).frame(height: 2).transition(.opacity)
            }
        }
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

// MARK: - Drop Delegates

private struct SidebarListDropDelegate: DropDelegate {
    let target: SidebarListDragItem
    @Binding var dragOverItem: SidebarListDragItem?
    let onDrop: (SidebarListDragItem, SidebarListDragItem) -> Void

    func validateDrop(info: DropInfo) -> Bool { true }

    func dropEntered(info: DropInfo) { dragOverItem = target }

    func dropExited(info: DropInfo) {
        if dragOverItem == target { dragOverItem = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        if dragOverItem == target { dragOverItem = nil }
        guard let dropped = SidebarDragContext.shared.draggedListItem,
              dropped != target else { return false }
        SidebarDragContext.shared.draggedListItem = nil
        onDrop(dropped, target)
        return true
    }
}
#endif
