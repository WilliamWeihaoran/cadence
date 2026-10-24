// macOS only: `ListTasksSectionGroups` and `ListTasksView` are macOS app types.
#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-5832]] (a) — a section made with "+ Section" on a list's Tasks tab appears at once under
/// By List.** The section is created through the row's own commit
/// (`CadenceSectionEditingSupport.createSection`) and the page's groups are asked of the helper
/// `ListTasksView` draws them from; the source pins are for the call sites, `private` members of a
/// SwiftUI view.
@MainActor
struct ListTasksSectionGroupsTests {

    private func seededProject(in modelContext: ModelContext) throws -> (Project, [AppTask]) {
        let project = Project(name: "Website")
        project.sectionNames = ["Documents"]
        modelContext.insert(project)
        let task = AppTask(title: "Spec")
        task.project = project
        task.sectionName = "Documents"
        modelContext.insert(task)
        try modelContext.save()
        return (project, [task])
    }

    @Test func aSectionAddedFromTheFooterRowIsDrawnAsAnEmptyGroup() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let (project, tasks) = try seededProject(in: modelContext)
        let sectionContainer = try #require(CadenceSectionConfigMerge.container(area: nil, project: project))
        let failure = CadenceSectionEditingSupport.createSection(
            named: "Later",
            colorHex: project.colorHex,
            in: sectionContainer,
            modelContext: modelContext
        )
        #expect(failure == nil)
        #expect(project.sectionNames.contains("Later"))

        let groups = ListTasksSectionGroups.groups(
            from: tasks,
            sectionNames: project.sectionNames,
            pageIsEmpty: false
        )
        #expect(groups.map(\.title) == project.sectionNames)
        let later = try #require(groups.first { $0.title == "Later" })
        #expect(later.tasks.isEmpty)
        #expect(groups.first { $0.title == "Documents" }?.tasks.map(\.id) == tasks.map(\.id))
    }

    /// iOS's rule, kept: a page with no tasks at all shows its empty state, not empty headings.
    @Test func aPageWithNoTasksDrawsNoEmptyHeadings() {
        let groups = ListTasksSectionGroups.groups(
            from: [],
            sectionNames: ["Documents", "Later"],
            pageIsEmpty: true
        )
        #expect(groups.isEmpty)
    }

    /// Under the hover freeze an empty section still shows, in its place, exactly once.
    @Test func theHoverFreezeKeepsEmptySectionsInTheirPlaces() {
        let spec = AppTask(title: "Spec")
        let ship = AppTask(title: "Ship")
        let frozen = [
            ListTasksGroup(id: "section-documents", title: "Documents", tasks: [spec]),
            ListTasksGroup(id: "section-review", title: "Review", tasks: [ship])
        ]
        let live = [
            ListTasksGroup(id: "section-inbox", title: "Inbox", tasks: []),
            ListTasksGroup(id: "section-documents", title: "Documents", tasks: [spec]),
            ListTasksGroup(id: "section-later", title: "Later", tasks: []),
            ListTasksGroup(id: "section-review", title: "Review", tasks: [ship]),
            ListTasksGroup(id: "section-someday", title: "Someday", tasks: [])
        ]
        let merged = ListTasksSectionGroups.keepingEmptySections(frozen, live: live)
        #expect(merged.map(\.title) == ["Inbox", "Documents", "Later", "Review", "Someday"])
        #expect(merged.first { $0.title == "Documents" }?.tasks.map(\.id) == [spec.id])
        // A frozen group keeps its frozen rows even when the live one differs.
        let moved = [
            ListTasksGroup(id: "section-documents", title: "Documents", tasks: []),
            ListTasksGroup(id: "section-review", title: "Review", tasks: [ship, spec])
        ]
        let held = ListTasksSectionGroups.keepingEmptySections(frozen, live: moved)
        #expect(held.map(\.title) == ["Documents", "Review"])
        #expect(held.first { $0.title == "Review" }?.tasks.map(\.id) == [ship.id])
    }

    @Test func listTasksViewDrawsByListFromTheHelperOnBothPaths() throws {
        let source = try CadenceSourceScan.strippedSourceReader()("Cadence/macOS/Views/ListDetailComponents.swift")
        let grouped = try #require(CadenceSourceScan.declarationBody("private var groupedActiveTasks: [ListTasksGroup]", in: source))
        #expect(grouped.contains("case .byList:\n            return liveSectionGroups"))
        #expect(grouped.contains("return ListTasksSectionGroups.keepingEmptySections(frozen, live: liveSectionGroups)"))
        let live = try #require(CadenceSourceScan.declarationBody("private var liveSectionGroups: [ListTasksGroup]", in: source))
        #expect(live.contains("pageIsEmpty: activeTasks.isEmpty && doneTasks.isEmpty"))
    }
}

#endif
