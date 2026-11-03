import Foundation
import Testing
@testable import Cadence

/// **[[T-8564]] and [[T-8565]]: the iOS list board and list editor take the Mac's column-delete
/// confirmation and its "Show Archived" control** (owner calls of 2026-11-03, both YES; one app,
/// two platforms -- [[T-8201]]).
///
/// The rules are pinned by VALUE through the shared types both platforms read; the iOS wiring by
/// source scan, since `CadenceTests` builds for macOS and never compiles `Cadence/iOS/`.
@MainActor
struct CadenceIOSListBoardMacParityTests {
    private static let editorFile = "Cadence/iOS/iOSListEditorViews.swift"
    private static let pageFile = "Cadence/iOS/iOSListDetailView.swift"
    private static let boardFile = "Cadence/iOS/iOSListSupportViews.swift"
    private static let macColumnFile = "Cadence/macOS/Views/KanbanSectionColumnView.swift"
    private static let macBoardFile = "Cadence/macOS/Views/KanbanListSectionSupportViews.swift"
    private static let macPageFile = "Cadence/macOS/Views/ListDetailView.swift"

    private func code(_ path: String) throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }

    // MARK: - T-8565: Show Archived

    /// Off draws the live columns, on draws the archived ones and ONLY those -- the Mac board's rule,
    /// now the one rule both boards read.
    @Test func showArchivedSwapsTheBoardToTheArchivedColumnsAlone() {
        let configs = [
            TaskSectionConfig(name: TaskSectionDefaults.defaultName),
            TaskSectionConfig(name: "Doing"),
            TaskSectionConfig(name: "Shipped", isArchived: true),
            TaskSectionConfig(name: "Retired", isCompleted: true, isArchived: true),
        ]
        let live = ListDetailKanbanBoard.visibleSectionConfigs(configs, showArchived: false).map(\.name)
        let archived = ListDetailKanbanBoard.visibleSectionConfigs(configs, showArchived: true).map(\.name)

        #expect(live == [TaskSectionDefaults.defaultName, "Doing"])
        #expect(archived == ["Shipped", "Retired"])
    }

    @Test func theToggleSpeaksTheMacPillsWordsInBothStates() {
        typealias Copy = ListDetailKanbanBoard.ArchivedColumnsToggle
        #expect(Copy.title(showingArchived: false) == "Show Archived")
        #expect(Copy.title(showingArchived: true) == "Archived")
        #expect(Copy.systemImage(showingArchived: false) == "archivebox")
        #expect(Copy.systemImage(showingArchived: true) == "archivebox.fill")
        #expect(Copy.accessibilityLabel(showingArchived: false) == "Show archived columns")
        #expect(Copy.accessibilityLabel(showingArchived: true) == "Hide archived columns")
    }

    /// Both boards read the shared rule and the shared words; neither keeps a private copy.
    @Test func bothBoardsReadTheSharedArchivedRuleAndWords() throws {
        let macBoard = try code(Self.macBoardFile)
        #expect(macBoard.contains("ListDetailKanbanBoard.visibleSectionConfigs(baseSectionConfigs, showArchived: showArchivedBinding.wrappedValue)"))
        #expect(!macBoard.contains("configs.filter(\\.isArchived)"), "the Mac board grew its own filter back")

        let macPage = try code(Self.macPageFile)
        #expect(macPage.contains("ArchivedColumnsToggle.title(showingArchived: showArchivedKanbanColumns)"))
        #expect(!macPage.contains("\"Show Archived\""), "the Mac pill spells its own label again")

        let page = try code(Self.pageFile)
        #expect(page.contains("ListDetailKanbanBoard.visibleSectionConfigs(sectionConfigs, showArchived: true)"))
        #expect(page.contains("ArchivedColumnsToggle.title(showingArchived: isOn)"))
        #expect(page.contains("ArchivedColumnsToggle.accessibilityLabel(showingArchived: isOn)"))
        #expect(page.contains("sectionNames: kanbanSectionNames"), "the iOS board ignores the chip")
        #expect(page.contains("showsArchivedColumns: showArchivedKanbanColumns"))
        let kanbanPage = try #require(
            CadenceSourceScan.declarationBody("private var kanbanPage: some View", in: page),
            "the iOS Kanban tab body is gone"
        )
        #expect(kanbanPage.contains("archivedColumnsChip"), "the chip is not drawn on the Kanban tab")
        // Per list, like the tab pick (T-7032): an "on" made on list A must not open list B archived.
        #expect(page.contains("showArchivedKanbanColumnsListKey == rememberedPageKey"))
    }

    /// Under Show Archived the iOS board offers no add-column control, as the Mac board does not:
    /// a column made there would be a live one, on a board not showing live columns.
    @Test func theIOSArchivedBoardDrawsNoAddColumnControl() throws {
        let board = try code(Self.boardFile)
        let panel = try #require(
            CadenceSourceScan.declarationBody("struct iOSListKanbanPanel: View", in: board),
            "the iOS list board is gone"
        )
        let creationRows = panel.components(separatedBy: "CadenceSectionCreationRow(").count - 1
        let guarded = panel.components(separatedBy: "if !showsArchivedColumns {\n").count - 1
        #expect(creationRows == 2, "non-vacuity: the board's two add-column rows moved")
        #expect(guarded == creationRows, "an add-column row is drawn on the archived board")
        #expect(panel.contains("CadenceEmptyStateCopy.listKanbanArchivedTitle"))
    }

    // MARK: - T-8564: Delete Column?

    @Test func theDeleteConfirmationSaysWhereTheCardsGo() {
        #expect(CadenceSectionEditingSupport.columnDeleteConfirmationTitle == "Delete Column?")
        #expect(
            CadenceSectionEditingSupport.columnDeleteConfirmationMessage(columnName: "Doing")
                == "This will delete the column \"Doing\" and move its tasks into Default."
        )
    }

    /// A column the editor opened with asks; one added during this edit holds no card and goes at
    /// once; Default cannot be swiped at all (T-5835), so it never reaches the question.
    @Test func onlyASavedNonDefaultColumnAsksBeforeItGoes() {
        let saved = CadenceSectionDraft(config: TaskSectionConfig(name: "Doing"))
        let added = CadenceSectionDraft(name: "Fresh")
        let defaultColumn = CadenceSectionDraft(config: TaskSectionConfig(name: TaskSectionDefaults.defaultName))

        #expect(CadenceSectionEditingSupport.deletionNeedsConfirmation(saved))
        #expect(!CadenceSectionEditingSupport.deletionNeedsConfirmation(added))
        #expect(!CadenceSectionEditingSupport.deletionNeedsConfirmation(defaultColumn))
    }

    @Test func theConfirmationNamesTheRowAsItReadsAndFallsBackWhenCleared() {
        var renamed = CadenceSectionDraft(config: TaskSectionConfig(name: "Doing"))
        renamed.name = "  In Progress "
        #expect(CadenceSectionEditingSupport.deletionConfirmationName(for: renamed) == "In Progress")

        var cleared = CadenceSectionDraft(config: TaskSectionConfig(name: "Doing"))
        cleared.name = "   "
        #expect(CadenceSectionEditingSupport.deletionConfirmationName(for: cleared) == "Doing")
    }

    /// The swipe asks rather than removing, and both platforms read the one sentence.
    @Test func theIOSSwipeAsksInTheMacsWords() throws {
        let editor = try code(Self.editorFile)
        #expect(editor.contains(".onDelete(perform: requestColumnDeletion)"))
        #expect(!editor.contains("sectionDrafts.remove(atOffsets: offsets)"), "the swipe deletes silently again")
        #expect(editor.contains("CadenceSectionEditingSupport.columnDeleteConfirmationTitle"))
        #expect(editor.contains("CadenceSectionEditingSupport.columnDeleteConfirmationMessage("))
        let request = try #require(
            CadenceSourceScan.declarationBody("private func requestColumnDeletion(at offsets: IndexSet)", in: editor),
            "the iOS column-delete request is gone"
        )
        #expect(request.contains("pendingColumnDeletion = first"))

        let mac = try code(Self.macColumnFile)
        #expect(mac.contains("title: CadenceSectionEditingSupport.columnDeleteConfirmationTitle"))
        #expect(mac.contains("CadenceSectionEditingSupport.columnDeleteConfirmationMessage(columnName: section.name)"))
        #expect(!mac.contains("\"Delete Column?\""), "the Mac popover spells its own title again")
    }
}
