import Foundation
import SwiftData

/// The one place a live `Area` or `Project` becomes a `CadenceSidebarLists.Item`.
///
/// Kept out of `CadenceSidebarListsSupport.swift` on purpose: that file's rules are deliberately
/// model-free so they can be tested without a container, and this is the seam where the models
/// meet them.
///
/// **Why it is shared rather than per-platform (T-538).** iPad had this bridge, privately, in
/// `iOSRootSidebar`; macOS had its own, in `SidebarComponents`, and macOS's took the context id as
/// a **non-optional parameter** which the caller filled in from whichever `Context` it was
/// iterating. `Area.context` and `Project.context` are optional — iOS writes `nil` there from the
/// "None" row of its list editor — and the macOS spelling had no way to say so, so the one state
/// the phone can create was the one state the Mac could not represent, let alone draw. Reading the
/// relationship *here*, once, is what makes that unspellable: there is no `contextID` argument for
/// a renderer to supply.
extension CadenceSidebarLists.Item {
    init(_ area: Area) {
        self.init(
            id: area.id,
            kind: .area,
            name: area.name,
            colorHex: area.colorHex,
            order: area.order,
            contextID: area.context?.id,
            dueDateKey: nil,
            openTaskCount: CadenceTaskQuerySupport.openTaskCount(for: area)
        )
    }

    init(_ project: Project) {
        self.init(
            id: project.id,
            kind: .project,
            name: project.name,
            colorHex: project.colorHex,
            order: project.order,
            contextID: project.context?.id,
            dueDateKey: project.dueDate.isEmpty ? nil : project.dueDate,
            openTaskCount: CadenceTaskQuerySupport.openTaskCount(for: project)
        )
    }

    /// The same row **without the open-task tally**, for a surface that only wants the sidebar's
    /// *order* ([[T-13851]]): the Tasks page's Kanban board and every by-list grouping place their
    /// columns and groups through `CadenceSidebarLists`, and the tally is a relationship walk per
    /// list they would compute and throw away. Everything the ordering reads — `order`, kind,
    /// name, id, context — is the same as `init(_:)`'s.
    static func orderingOnly(_ area: Area) -> Self {
        Self(
            id: area.id,
            kind: .area,
            name: area.name,
            colorHex: area.colorHex,
            order: area.order,
            contextID: area.context?.id
        )
    }

    static func orderingOnly(_ project: Project) -> Self {
        Self(
            id: project.id,
            kind: .project,
            name: project.name,
            colorHex: project.colorHex,
            order: project.order,
            contextID: project.context?.id
        )
    }
}

/// A list's `order` when it is re-filed into another context from a list editor ([[T-16401]]).
///
/// **The editors used to write the new context and keep the old number.** `order` is a sequence
/// *within one context section* (`CadenceSidebarListReorder` renumbers a section from 0), so a
/// number carried in from another section is a number some row of the destination usually already
/// holds. `sorted(_:)` keeps a user-dragged interleaving of areas and projects only while every row
/// holds a distinct `order`, so the destination dropped to areas-first -- the project the user had
/// dragged to the top fell below every area -- and the moved list itself landed wherever its old
/// number happened to fall, on every device, because the numbers sync. It is [[T-14621]]'s failure
/// reached by editing a list instead of creating one. The Mac's cross-section DRAG already
/// renumbered (`SidebarListContextMove`); the Mac's `EditAreaSheet` / `EditProjectSheet` and the
/// iOS list editor did not.
///
/// A moved list goes to the END of its new section, numbered exactly as a list created there would
/// be (`nextOrder(inContextWithID:areas:projects:)`). An edit that leaves the context alone keeps
/// its number: a rename must not reshuffle anything.
extension CadenceSidebarLists {
    /// The pure rule. **`areas` / `projects` are read before the list's context is written**, so
    /// the moved list's own slot still names its old context and is not counted in the new one.
    static func orderAfterRefiling(
        currentOrder: Int,
        from oldContextID: UUID?,
        to newContextID: UUID?,
        areas: [OrderSlot],
        projects: [OrderSlot]
    ) -> Int {
        guard oldContextID != newContextID else { return currentOrder }
        return nextOrder(inContextWithID: newContextID, areas: areas, projects: projects)
    }

    /// Writes `area.context` and, when it changed, the `order` that puts the area last in its new
    /// section. The caller's undo has to hold `order` too -- `CadenceListEditSnapshot` does.
    static func refile(_ area: Area, into context: Context?) {
        if area.context?.id != context?.id {
            area.order = orderAfterRefiling(
                currentOrder: area.order,
                from: area.context?.id,
                to: context?.id,
                areas: orderSlots(Area.self, of: area),
                projects: orderSlots(Project.self, of: area)
            )
        }
        area.context = context
    }

    /// The project twin. Only `project.context` places a project in the sidebar (the bridge above
    /// reads `project.context?.id`), so a change of parent AREA alone keeps its number.
    static func refile(_ project: Project, into context: Context?) {
        if project.context?.id != context?.id {
            project.order = orderAfterRefiling(
                currentOrder: project.order,
                from: project.context?.id,
                to: context?.id,
                areas: orderSlots(Area.self, of: project),
                projects: orderSlots(Project.self, of: project)
            )
        }
        project.context = context
    }

    /// Every area's (or project's) slot in the store the list lives in. Read only when the context
    /// actually changes; a list not yet inserted has no siblings to number against.
    private static func orderSlots(_ kind: Area.Type, of model: any PersistentModel) -> [OrderSlot] {
        guard let modelContext = model.modelContext,
              let areas = try? modelContext.fetch(FetchDescriptor<Area>()) else { return [] }
        return areas.map { ($0.context?.id, $0.order) }
    }

    private static func orderSlots(_ kind: Project.Type, of model: any PersistentModel) -> [OrderSlot] {
        guard let modelContext = model.modelContext,
              let projects = try? modelContext.fetch(FetchDescriptor<Project>()) else { return [] }
        return projects.map { ($0.context?.id, $0.order) }
    }
}

/// A list's `order` when it is brought back to the sidebar -- reopened from Done, Archived, Paused
/// or Cancelled ([[T-16658]]).
///
/// **The reopen used to write `status = .active` and nothing else.** A list that is not active is
/// not in any sidebar section, so while it is away the section is free to be reordered without it,
/// and a reorder renumbers the visible rows densely from 0 (`CadenceSidebarListReorder.commit`).
/// The number the reopened list kept is then usually one a visible row already holds, and
/// `sorted(_:)` keeps a dragged area/project interleaving only while every row's `order` is
/// distinct -- so the whole section fell back to areas-first (a project the user had dragged to the
/// top dropped below every area) on every device, because the numbers sync. [[T-16401]]'s failure,
/// reached by reopening a list instead of re-filing one.
///
/// The reopened list keeps its number when no active list in its section holds it -- so archiving
/// and at once reopening puts it back exactly where it was -- and otherwise goes to the END of the
/// section, numbered as a list created there would be.
extension CadenceSidebarLists {
    /// The pure rule. `activeSiblings` are the slots of the OTHER active lists in the store (any
    /// context; only the reopened list's own context is compared); `areas` / `projects` are every
    /// slot in the store, active or not, which is what `nextOrder` numbers against.
    static func orderAfterReopening(
        currentOrder: Int,
        contextID: UUID?,
        activeSiblings: [OrderSlot],
        areas: [OrderSlot],
        projects: [OrderSlot]
    ) -> Int {
        CadenceOrderAllocation.orderAfterReopening(
            currentOrder: currentOrder,
            activeSiblingOrders: activeSiblings.filter { $0.contextID == contextID }.map(\.order),
            ordersInSection: (areas + projects).filter { $0.contextID == contextID }.map(\.order)
        )
    }

    /// Sets `area.status = .active` and, when it was not already active, the `order` that keeps its
    /// sidebar section's dragged order intact. An already-active area is left exactly as it is.
    /// The caller's undo has to hold `order` too -- `CadenceListEditSnapshot` does.
    static func reopen(_ area: Area) {
        if area.status != .active {
            let rows = listRows(of: area)
            area.order = orderAfterReopening(
                currentOrder: area.order,
                contextID: area.context?.id,
                activeSiblings: rows.filter { $0.isActive && $0.modelID != area.persistentModelID }.map(\.slot),
                areas: rows.filter { $0.kind == .area }.map(\.slot),
                projects: rows.filter { $0.kind == .project }.map(\.slot)
            )
        }
        area.status = .active
    }

    /// The project twin.
    static func reopen(_ project: Project) {
        if project.status != .active {
            let rows = listRows(of: project)
            project.order = orderAfterReopening(
                currentOrder: project.order,
                contextID: project.context?.id,
                activeSiblings: rows.filter { $0.isActive && $0.modelID != project.persistentModelID }.map(\.slot),
                areas: rows.filter { $0.kind == .area }.map(\.slot),
                projects: rows.filter { $0.kind == .project }.map(\.slot)
            )
        }
        project.status = .active
    }

    private struct ListRow {
        let kind: Kind
        let modelID: PersistentIdentifier
        let isActive: Bool
        let slot: OrderSlot
    }

    /// Every area and project in the store the list lives in, with whether the sidebar draws it.
    private static func listRows(of model: any PersistentModel) -> [ListRow] {
        guard let modelContext = model.modelContext else { return [] }
        let areas = (try? modelContext.fetch(FetchDescriptor<Area>())) ?? []
        let projects = (try? modelContext.fetch(FetchDescriptor<Project>())) ?? []
        return areas.map { ListRow(kind: .area, modelID: $0.persistentModelID, isActive: $0.isActive, slot: ($0.context?.id, $0.order)) }
            + projects.map { ListRow(kind: .project, modelID: $0.persistentModelID, isActive: $0.isActive, slot: ($0.context?.id, $0.order)) }
    }
}
