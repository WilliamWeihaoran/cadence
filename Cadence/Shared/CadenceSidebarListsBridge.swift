import Foundation

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
