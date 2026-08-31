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
}
