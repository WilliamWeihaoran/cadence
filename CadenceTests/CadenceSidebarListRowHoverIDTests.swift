import Foundation
import Testing
@testable import Cadence

#if os(macOS)

/// **T-17039: two same-named Mac sidebar lists shared one Cmd+E hover registration.**
///
/// The row's hover id was built from its kind and NAME, and `HoveredEditableManager.beginHovering`
/// returns early on an id it already holds, so moving the pointer from one "Q4" project straight
/// to another kept the first row's edit action. It is the list's id now.
struct CadenceSidebarListRowHoverIDTests {

    /// **Behavioural.**
    @Test func twoListsWithOneNameHaveTwoHoverIDs() {
        let first = UUID()
        let second = UUID()
        #expect(SidebarListRow.hoverID(for: .project(first)) != SidebarListRow.hoverID(for: .project(second)))
        #expect(SidebarListRow.hoverID(for: .area(first)) != SidebarListRow.hoverID(for: .project(first)))
        #expect(SidebarListRow.hoverID(for: .area(first)) == SidebarListRow.hoverID(for: .area(first)))
    }

    /// **Source scan**: the row registers under that id, not under its label.
    @Test func theSidebarRowRegistersItsHoverUnderTheListID() throws {
        let row = try CadenceSourceScan.strippedSourceReader()("Cadence/macOS/Views/SidebarSupportViews.swift")
        #expect(row.contains("Self.hoverID(for: item)"))
        #expect(!row.contains("\"sidebar-\\(kind.label)-\\(label)\""))
    }
}
#endif
