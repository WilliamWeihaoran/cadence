import Foundation
import SwiftData
import Testing
@testable import Cadence

/// [[T-17789]]: with no contexts and every list archived or completed, both sidebars' lists
/// regions resolve to no sections -- and both drew the fresh-install row over a store full of
/// lists ("Add first list" on the Mac, "No lists yet" over it on iOS). The row's words now come
/// from one value that knows whether lists exist, and both columns draw it in one shape.
struct CadenceSidebarEmptyListsTests {
    @Test func aFreshStoreStillSaysNoListsYetOverAddFirstList() {
        let row = CadenceEmptyStateCopy.sidebarEmptyLists(hasInactiveLists: false)
        #expect(row.statement == "No lists yet")
        #expect(row.statement == CadenceEmptyStateCopy.listsTitle(isNarrowed: false))
        #expect(row.action == "Add first list")
        #expect(row.action == CadenceEmptyStateCopy.addFirstListAction)
    }

    @Test func aStoreOfInactiveListsSaysNoActiveListsOverNewList() {
        let row = CadenceEmptyStateCopy.sidebarEmptyLists(hasInactiveLists: true)
        #expect(row.statement == "No active lists")
        #expect(row.statement == CadenceEmptyStateCopy.activeListsTitle)
        #expect(row.action == "New list")
        for words in [row.statement, row.action] {
            #expect(!words.lowercased().contains("yet"), "\"\(words)\" claims nothing has been made")
            #expect(!words.lowercased().contains("first"), "\"\(words)\" claims nothing has been made")
        }
    }

    /// Archived and completed both count: either is a list the sections leave out.
    @Test func theInactivePredicateCountsArchivedAndCompletedListsButNotActiveOnes() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        #expect(CadenceSidebarLists.hasInactiveLists(areas: [], projects: []) == false)

        let active = Area(name: "Active")
        let live = Project(name: "Live")
        context.insert(active)
        context.insert(live)
        #expect(CadenceSidebarLists.hasInactiveLists(areas: [active], projects: [live]) == false)

        let archived = Area(name: "Archived")
        archived.status = .archived
        context.insert(archived)
        #expect(CadenceSidebarLists.hasInactiveLists(areas: [archived], projects: []))
        #expect(CadenceSidebarLists.hasInactiveLists(areas: [active, archived], projects: [live]))

        let finished = Project(name: "Finished")
        finished.status = .done
        context.insert(finished)
        #expect(CadenceSidebarLists.hasInactiveLists(areas: [], projects: [finished]))
        try context.save()
    }

    /// The wiring: each column reads the value, from the predicate, over its own query.
    @Test func bothSidebarsDrawTheRowFromTheValueInOneShape() throws {
        let mac = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/SidebarView.swift")
        )
        let region = try #require(CadenceSourceScan.declarationBody("var listsSection: some View", in: mac))
        #expect(region.contains("case .firstListAction:"), "non-vacuity: the empty-store branch moved")
        #expect(region.contains("CadenceEmptyStateCopy.sidebarEmptyLists("))
        #expect(region.contains("CadenceSidebarLists.hasInactiveLists(areas: areas, projects: projects)"))
        #expect(region.contains("Text(empty.statement)"), "the Mac row lost the statement the iOS row draws")
        #expect(region.contains("SidebarAddFirstListButton(title: empty.action)"))

        let iOS = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSRootSidebar.swift")
        )
        let row = try #require(CadenceSourceScan.declarationBody("private var emptyListsRow: some View", in: iOS))
        #expect(row.contains("Text(emptyLists.statement)"))
        #expect(row.contains("addFirstListButton"))
        let button = try #require(CadenceSourceScan.declarationBody("private var addFirstListButton: some View", in: iOS))
        #expect(button.contains("Text(emptyLists.action)"))
        #expect(iOS.contains("CadenceEmptyStateCopy.sidebarEmptyLists(hasInactiveLists: hasInactiveLists)"))

        // Both hosts of the touch region feed it the predicate over their own query.
        for path in ["Cadence/iOS/iOSRootSidebar.swift", "Cadence/iOS/iOSTasksTabView.swift"] {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            #expect(code.contains("iOSSidebarListsRegion("), "non-vacuity: \(path) stopped drawing the region")
            #expect(
                code.contains("hasInactiveLists: CadenceSidebarLists.hasInactiveLists(areas: areas, projects: projects)"),
                "\(path) does not tell the region whether lists exist"
            )
        }
    }
}

/// [[T-17787]]: an empty board day column said "Nothing scheduled" on iOS and nothing on the Mac.
/// One rule now decides it for both, with `dayEmptyText(notice:)`'s answer as the line.
struct CadenceCalendarDayColumnEmptyLineTests {
    @Test func anEmptyDaySaysTheAccessAwareLine() {
        for notice in [nil, CadenceCalendarAccessNotice.connectOffer, .denied] {
            let text = CadenceCalendarAccessNotice.dayEmptyText(notice: notice)
            #expect(
                CadenceCalendarAccessNotice.dayColumnEmptyLine(text: text, activeItemCount: 0, completedTaskCount: 0)
                    == text
            )
        }
    }

    /// A day with anything in it -- an open card, an event, or only a finished task under its
    /// Completed fold -- draws no line.
    @Test func aDayWithAnyItemDrawsNoLine() {
        let text = CadenceEmptyStateCopy.nothingScheduledTitle
        #expect(CadenceCalendarAccessNotice.dayColumnEmptyLine(text: text, activeItemCount: 1, completedTaskCount: 0) == nil)
        #expect(CadenceCalendarAccessNotice.dayColumnEmptyLine(text: text, activeItemCount: 0, completedTaskCount: 1) == nil)
        #expect(CadenceCalendarAccessNotice.dayColumnEmptyLine(text: text, activeItemCount: 3, completedTaskCount: 2) == nil)
    }

    @Test func bothDayColumnsAskTheRuleAndTheMacPageFeedsItTheGate() throws {
        let macColumn = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarBoardDayColumnSupportViews.swift")
        )
        #expect(macColumn.contains("struct CalendarBoardDayColumn: View {"), "non-vacuity: wrong file read")
        let content = try #require(CadenceSourceScan.declarationBody("private var content: some View", in: macColumn))
        #expect(content.contains("CadenceCalendarAccessNotice.dayColumnEmptyLine("))
        #expect(content.contains("text: emptyDayText"))
        #expect(content.contains("CadenceInlineEmpty(text: emptyLine, surface: .desktop)"))

        let iOSBoard = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarBoardView.swift")
        )
        #expect(iOSBoard.contains("CadenceCalendarAccessNotice.dayColumnEmptyLine("))
        #expect(iOSBoard.contains("CadenceInlineEmpty(text: emptyLine, surface: .touch)"))

        let macBoard = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarPageBoardSupportViews.swift")
        )
        #expect(macBoard.contains("emptyDayText: emptyDayText,"), "the board does not hand its columns the line")

        let macPage = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarPageView.swift")
        )
        #expect(macPage.contains("emptyDayText: CadenceCalendarAccessNotice.dayEmptyText(notice: accessNotice)"))
    }
}
