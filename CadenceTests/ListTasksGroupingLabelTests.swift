// macOS only: `CadenceEnumPickerBadge` and `TaskGroupingMode` are macOS app types.
#if os(macOS)
import SwiftUI
import Testing
@testable import Cadence

/// **[[T-5833]] — a list's own Tasks tab calls its section grouping "By Section".** The tab drew
/// `TaskGroupingMode.byList`'s raw "By List" while grouping that one list's tasks by section, on a
/// page whose own controls say "Section". Today and All Tasks group by list and keep "By List".
@MainActor
struct ListTasksGroupingLabelTests {

    private func badge(labelOverride: @escaping (TaskGroupingMode) -> String? = { _ in nil })
        -> CadenceEnumPickerBadge<TaskGroupingMode> {
        CadenceEnumPickerBadge(title: "Group", selection: .constant(.byList), labelOverride: labelOverride)
    }

    @Test func theListTabsGroupBadgeCallsSectionGroupingBySection() {
        let listTab = badge(labelOverride: ListTasksGroupingLabel.label(for:))
        #expect(listTab.label(for: .byList) == "By Section", "the list tab still says By List")
        #expect(listTab.label(for: .byDate) == "By Date")
        #expect(listTab.label(for: .byPriority) == "By Priority")
        #expect(listTab.label(for: .none) == "None")
    }

    @Test func everyOtherBadgeKeepsByList() {
        #expect(badge().label(for: .byList) == "By List", "the override leaked onto pages that group by list")
        #expect(TaskGroupingMode.byList.rawValue == "By List", "the stored grouping key changed")
    }

    /// The call site: the list tab's Group badge is the one handed the override.
    @Test func theListTabsGroupBadgeIsHandedTheOverride() throws {
        let source = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Views/ListDetailView.swift")
        let compact = source.filter { !$0.isWhitespace }
        #expect(compact.contains(
            #"CadenceEnumPickerBadge(title:"Group",selection:$taskGroupingMode,labelOverride:ListTasksGroupingLabel.label(for:))"#
        ), "the list tab's Group badge draws the type's own labels")
    }
}
#endif
