import Foundation
import SwiftData

/// One row of the sidebar's lists region, still holding its model object: the row whose `order`
/// a reorder writes back.
///
/// **Shared since [[T-7260]](a).** It lived in `Cadence/macOS/Views/SidebarComponents.swift`,
/// because the Mac sidebar was the only surface that could reorder lists at all; an iPad-only owner
/// could not change list order anywhere. iOS reorders through the same type and the same commit
/// now (`CadenceSidebarListReorder`), so the enum moved here. The Mac's drag-only members
/// (`dragItem`, `resolve(_ item: SidebarListDragItem…)`) stay in that file, beside the drag.
///
/// `SidebarView` builds the Mac region's sections; `ContextSection` is handed a section's rows
/// already bucketed and already sorted.
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

    /// The live row a flattened `CadenceSidebarLists.Item` names, looked up in the store. The
    /// Mac's drag lookup (`resolve(_ item: SidebarListDragItem…)`) is this with a drag kind.
    static func resolve(
        kind: CadenceSidebarLists.Kind,
        id: UUID,
        in modelContext: ModelContext
    ) -> SidebarListEntry? {
        switch kind {
        case .area:
            var descriptor = FetchDescriptor<Area>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            return (try? modelContext.fetch(descriptor))?.first.map(SidebarListEntry.area)
        case .project:
            var descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            return (try? modelContext.fetch(descriptor))?.first.map(SidebarListEntry.project)
        }
    }
}

/// Reordering lists **within one context section** of the sidebar — the one implementation both
/// platforms call ([[T-7260]](a), [[T-8201]]).
///
/// The Mac reaches it by drag (`ContextSection.reorderList`); iOS and iPadOS by the row's
/// context-menu Move Up / Move Down (`iOSSidebarListsRegion`). The gesture differs because the
/// input does — a pointer drags a row inside a scroll view, while on touch a long press on these
/// rows is already the context menu and the `+` capture drag, and `.onMove` needs a `List` in edit
/// mode this `ScrollView` region is not — the same reasoning Settings' context rows gave for
/// their own Move Up / Move Down ([[T-581]]). What the two platforms share is everything after the
/// gesture: the arrangement (`reordered`), the renumber of the whole section from 0, and the
/// commit with its full restore (`CadenceOrderCommit`).
enum CadenceSidebarListReorder {

    /// `items` with the row at `from` moved to `onto`'s position: the dropped-on row is the
    /// destination itself, so a downward move lands after it and an upward move before it.
    nonisolated static func reordered<Element>(_ items: [Element], moving from: Int, onto to: Int) -> [Element] {
        guard items.indices.contains(from), items.indices.contains(to) else { return items }
        var result = items
        let element = result.remove(at: from)
        result.insert(element, at: min(to, result.count))
        return result
    }

    /// The index a one-step move of the row at `index` lands on, or `nil` at either end of the
    /// section and for any offset other than one step — so a menu can disable the item rather
    /// than offer a move that does nothing.
    nonisolated static func neighbourIndex(of index: Int, by offset: Int, count: Int) -> Int? {
        guard offset == 1 || offset == -1, (0..<count).contains(index) else { return nil }
        let target = index + offset
        return (0..<count).contains(target) ? target : nil
    }

    /// Moves the row at `from` onto `to`, renumbers the whole section from 0 and commits once.
    ///
    /// - Returns: Whether the new order is in the store. `false` means every row is back exactly
    ///   as it was found, so the caller shows `CadenceOrderCommit.failureNotice`.
    static func commit(
        _ entries: [SidebarListEntry],
        moving from: Int,
        onto to: Int,
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Bool {
        CadenceOrderCommit.commit(
            reordered(entries, moving: from, onto: to),
            readOrder: { $0.order },
            writeOrder: { $0.setOrder($1) },
            in: modelContext,
            commit: commit
        )
    }

    /// iOS's one-step move: the row `item` names, one place up (`-1`) or down (`1`) within
    /// `section`, the flattened rows of one context section in the order they are drawn.
    ///
    /// - Returns: `nil` when nothing moved and nothing was attempted — an end of the section, an
    ///   offset other than one step, or a row that is no longer in the store. Otherwise the
    ///   answer of `commit(_:moving:onto:in:commit:)`.
    static func commitStep(
        moving item: CadenceSidebarLists.Item,
        by offset: Int,
        within section: [CadenceSidebarLists.Item],
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Bool? {
        guard let from = section.firstIndex(where: { $0.id == item.id && $0.kind == item.kind }),
              let to = neighbourIndex(of: from, by: offset, count: section.count) else { return nil }
        let entries = section.compactMap { SidebarListEntry.resolve(kind: $0.kind, id: $0.id, in: modelContext) }
        guard entries.count == section.count else { return nil }
        return self.commit(entries, moving: from, onto: to, in: modelContext, commit: commit)
    }
}
