// macOS only: `ListTasksSectionGroups` and `ListTasksView` are macOS app types.
#if os(macOS)
import Foundation
import SwiftData
import SwiftUI
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
            pageIsEmpty: false,
            filing: nil
        )
        #expect(groups.map(\.title) == project.sectionNames)
        let later = try #require(groups.first { $0.title == "Later" })
        #expect(later.tasks.isEmpty)
        #expect(groups.first { $0.title == "Documents" }?.tasks.map(\.id) == tasks.map(\.id))
    }

    /// **[[T-6201]], the owner's 2026-10-26 ruling: an empty page draws its sections.** This used
    /// to assert the opposite (`aPageWithNoTasksDrawsNoEmptyHeadings`), which is what left
    /// "+ Section" on an empty list creating a section that never appeared. The user's sections are
    /// drawn, in order; Default — the section nobody made — is not, so the risk the ruling named
    /// (an empty list reading as a column of blank headings) is held to the headings the user
    /// asked for.
    @Test func anEmptyPageDrawsTheUsersSectionsButNotDefault() {
        let groups = ListTasksSectionGroups.groups(
            from: [],
            sectionNames: [TaskSectionDefaults.defaultName, "Documents", "Later"],
            pageIsEmpty: true,
            filing: nil
        )
        #expect(groups.map(\.title) == ["Documents", "Later"])
        #expect(groups.allSatisfy { $0.tasks.isEmpty })

        // A brand-new list has only Default, so it still reads as empty: no heading at all.
        let fresh = ListTasksSectionGroups.groups(
            from: [],
            sectionNames: [TaskSectionDefaults.defaultName],
            pageIsEmpty: true,
            filing: nil
        )
        #expect(fresh.isEmpty)

        // On a page with any task Default is drawn as before, empty or not — it is where a task
        // with no section lands. Matched case-insensitively, as `isDefault` is.
        let spec = AppTask(title: "Spec")
        spec.sectionName = "Documents"
        let populated = ListTasksSectionGroups.groups(
            from: [spec],
            sectionNames: ["default", "Documents", "Later"],
            pageIsEmpty: false,
            filing: nil
        )
        #expect(populated.map(\.title) == ["default", "Documents", "Later"])
        let emptyDefault = CadenceTaskQuerySupport.listSectionGroups(
            from: [],
            sectionNames: ["DEFAULT", "Later"],
            pageIsEmpty: true,
            filing: nil
        )
        #expect(emptyDefault.map(\.title) == ["Later"])
    }

    /// iOS reads the same rule ([[T-6201]] changes both platforms). A source pin: the tab's
    /// groups and its empty gate are `private` members of a SwiftUI view this target cannot render.
    @Test func theIOSListTabDrawsAnEmptyPagesSectionsFromTheSharedRule() throws {
        let source = try CadenceSourceScan.strippedSourceReader()("Cadence/iOS/iOSListDetailView.swift")
        let groups = try #require(CadenceSourceScan.declarationBody("private var sectionGroups: [CadenceTaskDisplayGroup]", in: source))
        // [[T-13561]]: through the Group chip's switch, whose By Section arm is the shared rule.
        #expect(groups.contains("ListDetailSortControls.taskGroups("))
        #expect(groups.contains("pageIsEmpty: isTaskColumnEmpty"))
        let shared = try CadenceSourceScan.strippedSourceReader()("Cadence/Shared/CadenceListDetailSortControls.swift")
        let arms = try #require(CadenceSourceScan.declarationBody("static func taskGroups(", in: shared))
        #expect(arms.contains("CadenceTaskQuerySupport.listSectionGroups("))
        let column = try #require(CadenceSourceScan.declarationBody("private var taskColumn: some View", in: source))
        #expect(column.contains("if isTaskColumnEmpty && sectionGroups.isEmpty {"))
        // The empty state heads the stack when the page is empty but has sections to draw.
        let stack = try #require(CadenceSourceScan.declarationBody("private var sectionStack: some View", in: source))
        #expect(CadenceSourceScan.matchCount(#"if isTaskColumnEmpty \{\s*listEmptyPanel\s*\}\s*ForEach\(sectionGroups\)"#, in: stack) == 1)
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
        #expect(grouped.contains("return ListTasksSectionGroups.keepingEmptySections(frozen, live: liveSectionGroups)"))
        // T-11214 moved the live `switch` into `liveGroups` so the frozen path can read the live
        // groups' tints; the live path is still the one return below it.
        #expect(grouped.contains("return liveGroups"))
        let liveGrouped = try #require(CadenceSourceScan.declarationBody("private var liveGroups: [ListTasksGroup]", in: source))
        #expect(liveGrouped.contains("case .byList:\n            return liveSectionGroups"))
        let live = try #require(CadenceSourceScan.declarationBody("private var liveSectionGroups: [ListTasksGroup]", in: source))
        #expect(live.contains("pageIsEmpty: activeTasks.isEmpty && doneTasks.isEmpty"))
        // [[T-6201]]: the helper is the shared rule iOS reads, not a Mac-only copy of it.
        let helper = try #require(CadenceSourceScan.declarationBody("enum ListTasksSectionGroups", in: source))
        #expect(helper.contains("CadenceTaskQuerySupport.listSectionGroups("))
    }

    /// **[[T-5832]] (b) — the "+ Section" row is offered only under By List.** Under By Date (the
    /// Mac default), None and By Priority the row created a section that the page then never drew,
    /// which reads as the button doing nothing. The owner's decision was to hide the row there
    /// rather than switch the grouping under the user.
    ///
    /// A source pin because `body` is a `private`-state SwiftUI view this target cannot render:
    /// the scan is scoped to the one declaration, and the two assertions pull in opposite
    /// directions — the row must be inside a `.byList` gate, and the gate must still be the only
    /// place the row is drawn.
    @Test func theSectionCreationRowIsDrawnOnlyUnderByList() throws {
        let source = try CadenceSourceScan.strippedSourceReader()("Cadence/macOS/Views/ListDetailComponents.swift")
        let body = try #require(CadenceSourceScan.declarationBody("var body: some View", in: source))
        #expect(
            CadenceSourceScan.matchCount(#"CadenceSectionCreationRow\("#, in: body) == 1,
            "the list Tasks tab draws the row in exactly one place"
        )
        #expect(
            CadenceSourceScan.matchCount(
                #"if groupingMode == \.byList \{\s*CadenceSectionCreationRow\(area: area, project: project\)"#,
                in: body
            ) == 1,
            "the row is drawn under By List and nowhere else"
        )
        // Not vacuous: the scan really is reading this view's body.
        #expect(body.contains("ListTasksGroupSectionView("))
    }

    /// **[[T-11214]] — a section's heading is the section's colour, on both platforms.** The rule
    /// was a private helper on the iOS list page alone while the Mac's headings drew no tint; the
    /// Mac's list Tasks tab draws the shared `CadenceTaskGroupHeading` now and reads the same
    /// function. Run here rather than pinned: it is a plain function of the configs.
    @Test func aSectionHeadingIsItsSectionsColourGreenOnceCompletedAndDimWhenUnknown() {
        let configs = [
            TaskSectionConfig(name: "Documents", colorHex: "#FF3366"),
            TaskSectionConfig(name: "Shipped", colorHex: "#3366FF", isCompleted: true),
        ]
        #expect(CadenceTaskQuerySupport.sectionAccent(named: "Documents", configs: configs) == Color(hex: "#FF3366"))
        // The match is case-insensitive, as every board matches a section name.
        #expect(CadenceTaskQuerySupport.sectionAccent(named: "documents", configs: configs) == Color(hex: "#FF3366"))
        #expect(CadenceTaskQuerySupport.sectionAccent(named: "Shipped", configs: configs) == Theme.green)
        #expect(CadenceTaskQuerySupport.sectionAccent(named: "Nowhere", configs: configs) == Theme.dim)
        // Non-vacuity: the three answers really are three colours.
        #expect(Color(hex: "#FF3366") != Theme.green)
        #expect(Color(hex: "#FF3366") != Theme.dim)
    }

    /// The Mac's list Tasks tab hands every group the colour iOS heads it with ([[T-11214]]): "Tasks"
    /// blue, the shared date and priority buckets' own accents, a section's configured colour, and
    /// green for Completed. A source pin: `liveGroups` is a `private` member of a SwiftUI view.
    @Test func theListTasksTabTintsEveryGroupAsIOSDoes() throws {
        let source = try CadenceSourceScan.strippedSourceReader()("Cadence/macOS/Views/ListDetailComponents.swift")
        let live = try #require(CadenceSourceScan.declarationBody("private var liveGroups: [ListTasksGroup]", in: source))
        #expect(live.contains(#"ListTasksGroup(id: "all", title: "Tasks", tasks: activeTasks, tint: Theme.blue)"#))
        #expect(CadenceSourceScan.matchCount(#"tint: \$0\.accent\)"#, in: live) == 2, "the date and priority buckets")
        let sections = try #require(CadenceSourceScan.declarationBody("private var liveSectionGroups: [ListTasksGroup]", in: source))
        #expect(sections.contains("CadenceTaskQuerySupport.sectionAccent(named: group.title, configs: configs)"))
        let grouped = try #require(CadenceSourceScan.declarationBody("private var groupedActiveTasks: [ListTasksGroup]", in: source))
        #expect(grouped.contains("tint: liveTints[group.id] ?? Theme.dim"), "a frozen group keeps its live group's tint")

        let support = try CadenceSourceScan.strippedSourceReader()("Cadence/macOS/Views/ListDetailSupportViews.swift")
        let section = try #require(CadenceSourceScan.declarationBody("struct ListTasksGroupSectionView: View", in: support))
        #expect(section.contains("tint: group.tint,"))
        let completed = try #require(CadenceSourceScan.declarationBody("struct ListTasksCompletedSectionView: View", in: support))
        #expect(completed.contains("tint: Theme.green,"))

        // iOS's half, so the two cannot drift apart again: the same rule, the same green.
        let page = try CadenceSourceScan.strippedSourceReader()("Cadence/iOS/iOSListDetailView.swift")
        // [[T-13561]]: the group carries its tint from the shared switch, as the Mac's do.
        #expect(page.contains("color: group.accent,"))
        let shared = try CadenceSourceScan.strippedSourceReader()("Cadence/Shared/CadenceListDetailSortControls.swift")
        #expect(shared.contains("CadenceTaskQuerySupport.sectionAccent(named: group.title, configs: sectionConfigs)"))
        #expect(page.contains(#"title: "Completed",\#n                    tint: Theme.green,"#))
    }

    /// **[[T-12541]]: the empty list page draws one glyph at both widths.** The Mac drew
    /// `checkmark.circle` ("all done") where iOS drew `checklist`, over the same shared title and
    /// subtitle. Both read `CadenceEmptyStateCopy.listDetailSystemImage` now; a source pin, since
    /// both empty states are `private` members of SwiftUI views.
    @Test func theEmptyListPageDrawsTheSharedGlyphOnBothPlatforms() throws {
        #expect(CadenceEmptyStateCopy.listDetailSystemImage == "checklist")
        let read = CadenceSourceScan.strippedSourceReader()

        let mac = try read("Cadence/macOS/Views/ListDetailComponents.swift")
        #expect(CadenceSourceScan.matchCount(
            #"message:\s*CadenceEmptyStateCopy\.listDetailTitle,\s*subtitle:\s*CadenceEmptyStateCopy\.listDetailSubtitle,\s*icon:\s*CadenceEmptyStateCopy\.listDetailSystemImage\s*\)"#,
            in: mac
        ) == 1, "the Mac list page no longer draws the shared empty glyph (T-12541)")
        #expect(!mac.contains(#""checkmark.circle""#), "the Mac list page spells its own empty glyph again (T-12541)")

        let iOS = try read("Cadence/iOS/iOSListDetailView.swift")
        let panel = try #require(CadenceSourceScan.declarationBody("private var listEmptyPanel: some View", in: iOS))
        #expect(panel.contains("systemImage: CadenceEmptyStateCopy.listDetailSystemImage,"),
                "the iOS list page no longer draws the shared empty glyph (T-12541)")
        #expect(!panel.contains(#""checklist""#), "the iOS list page spells its own empty glyph again (T-12541)")
    }
}

#endif
