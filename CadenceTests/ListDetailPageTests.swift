import Foundation
import Testing
@testable import Cadence

/// `ListDetailPage` is read back from two persisted places — the Settings "default list page"
/// preference (`CadencePreferenceKeys.listDetailDefaultPage`) and macOS's per-list remembered tab —
/// and both can still hold "Planning", a page neither platform has any more.
@Suite("List detail page resolution")
struct ListDetailPageTests {
    @Test("A stored Planning preference resolves to Tasks")
    func planningResolvesToTasks() {
        #expect(ListDetailPage.resolved("Planning") == .tasks)
        #expect(ListDetailPage.resolved("planning") == .tasks)
    }

    @Test("Planning is not a page")
    func planningIsNotACase() {
        #expect(ListDetailPage(rawValue: "Planning") == nil)
        #expect(!ListDetailPage.allCases.contains { $0.rawValue.lowercased() == "planning" })
    }

    @Test("An unset or unknown preference resolves to the default page")
    func unknownResolvesToDefault() {
        #expect(ListDetailPage.resolved("") == ListDetailPage.defaultPage)
        #expect(ListDetailPage.resolved("Timeline") == ListDetailPage.defaultPage)
        #expect(ListDetailPage.defaultPage == .tasks)
    }

    @Test("Every live page round-trips through its stored raw value")
    func livePagesRoundTrip() {
        for page in ListDetailPage.allCases {
            #expect(ListDetailPage.resolved(page.rawValue) == page)
        }
    }

    /// The T-351 case, exactly as reported: a list still remembering `Planning`, a user whose
    /// global default is `Links`, and an expected `Tasks`.
    ///
    /// `restoreRememberedTab()` read the per-list value through the *failable*
    /// `ListDetailPage(rawValue:)` and, on `nil`, threw it away and resolved the **global**
    /// default instead. But a stale remembered tab is an unrecognised page name, which is the one
    /// thing `resolved(_:)` exists to map to Tasks; it is not evidence about what the user wants
    /// for this list.
    @Test("A stale per-list tab resolves to Tasks, not to the global default")
    func aStalePerListTabResolvesToTasksRatherThanTheGlobalDefault() {
        #expect(
            ListDetailPage.rememberedPage(storedRawValue: "Planning", defaultPageRawValue: "Links") == .tasks
        )
        // And it is the *stale* case that is being handled, not "always Tasks": a global default
        // still wins when the list has never remembered anything.
        #expect(
            ListDetailPage.rememberedPage(storedRawValue: nil, defaultPageRawValue: "Links") == .links
        )
        #expect(
            ListDetailPage.rememberedPage(storedRawValue: "", defaultPageRawValue: "Links") == .links
        )
    }

    @Test("A live remembered tab still wins over the global default")
    func aLiveRememberedTabWins() {
        for page in ListDetailPage.allCases {
            #expect(
                ListDetailPage.rememberedPage(
                    storedRawValue: page.rawValue,
                    defaultPageRawValue: ListDetailPage.links.rawValue
                ) == page
            )
        }
    }

    /// A stale *global* default is still resolved too, so neither half of the pair can strand a
    /// list on a page that does not exist.
    @Test("A stale global default also resolves to Tasks")
    func aStaleGlobalDefaultAlsoResolvesToTasks() {
        #expect(
            ListDetailPage.rememberedPage(storedRawValue: nil, defaultPageRawValue: "Planning") == .tasks
        )
    }

    /// `restoreRememberedTab()` is private to a SwiftUI view, so this reads the one thing a test
    /// cannot call: that the restore goes through the shared rule rather than re-deriving it.
    @Test("macOS restores a remembered tab through the shared rule")
    func macOSRestoreUsesTheSharedRule() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/ListDetailView.swift")
        let source = CadenceSourceScan.strippingComments(raw)
        #expect(source != raw, "the comment stripper never fired, so this read prose as code")
        #expect(source.count == raw.count, "the stripper changed the file's length, so it is not blanking")

        // Needle self-check: it must match the failable initialiser being banned, and must not
        // match the shared rule that replaces it.
        #expect(CadenceSourceScan.matchCount("ListDetailPage\\(rawValue:", in: "ListDetailPage(rawValue: raw)") == 1)
        #expect(
            CadenceSourceScan.matchCount("ListDetailPage\\(rawValue:", in: "ListDetailPage.rememberedPage(") == 0
        )

        let body = try #require(
            CadenceSourceScan.functionBody(named: "restoreRememberedTab", in: source),
            "restoreRememberedTab() is gone or its braces do not balance"
        )
        #expect(body.contains("ListDetailPage.rememberedPage"), "got: \(body)")
        #expect(
            CadenceSourceScan.matchCount("ListDetailPage\\(rawValue:", in: body) == 0,
            "the restore still parses the remembered value with the failable initialiser"
        )

        // T-7037: the per-list key is the shared builder iOS writes, not a macOS-local spelling.
        let key = try #require(
            CadenceSourceScan.declarationBody("private var tabDefaultsKey: String", in: source),
            "tabDefaultsKey is gone or its braces do not balance"
        )
        #expect(
            key.contains("ListDetailPage.rememberedPageDefaultsKey(areaID: area?.id, projectID: project?.id)"),
            "got: \(key)"
        )
        #expect(!key.contains("listDetailTab."), "macOS spells the remembered-tab key inline again")
    }

    // MARK: - T-7032: iPad kept the previous list's tab

    /// The exact iPad report: Links picked on list A, the sidebar moves to list B — which remembers
    /// Kanban — under the same live view. B must open on Kanban, not on A's Links.
    @Test("A tab picked on one list does not carry to the next")
    func pickOnListADoesNotCarryToListB() {
        let listA = ListDetailPage.rememberedPageDefaultsKey(areaID: UUID(), projectID: nil)
        let listB = ListDetailPage.rememberedPageDefaultsKey(areaID: nil, projectID: UUID())
        #expect(listA != listB)

        let onB = ListDetailPage.displayedPage(
            choice: .links,
            choiceListKey: listA,
            listKey: listB,
            storedRawValue: ListDetailPage.kanban.rawValue,
            defaultPageRawValue: ListDetailPage.completed.rawValue
        )
        #expect(onB == .kanban)

        // And a list with nothing remembered falls to the global default, still not A's pick.
        let onFreshB = ListDetailPage.displayedPage(
            choice: .links,
            choiceListKey: listA,
            listKey: listB,
            storedRawValue: nil,
            defaultPageRawValue: ListDetailPage.completed.rawValue
        )
        #expect(onFreshB == .completed)
    }

    @Test("A tab picked on this list wins over what it remembers")
    func pickOnThisListWins() {
        let list = ListDetailPage.rememberedPageDefaultsKey(areaID: UUID(), projectID: nil)
        let page = ListDetailPage.displayedPage(
            choice: .documents,
            choiceListKey: list,
            listKey: list,
            storedRawValue: ListDetailPage.kanban.rawValue,
            defaultPageRawValue: ListDetailPage.tasks.rawValue
        )
        #expect(page == .documents)
    }

    /// The key is the one macOS has always written, so a list's remembered tab survives the
    /// builder moving to Shared.
    @Test("The per-list key is macOS's existing spelling")
    func rememberedKeyMatchesMacOS() throws {
        let id = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        #expect(
            ListDetailPage.rememberedPageDefaultsKey(areaID: id, projectID: nil)
                == "listDetailTab.area.00000000-0000-0000-0000-000000000001"
        )
        #expect(
            ListDetailPage.rememberedPageDefaultsKey(areaID: nil, projectID: id)
                == "listDetailTab.project.00000000-0000-0000-0000-000000000001"
        )
        #expect(ListDetailPage.rememberedPageDefaultsKey(areaID: nil, projectID: nil) == "listDetailTab.unknown")
    }

    /// `Cadence/iOS/` is invisible to this target, so this reads that the iOS page goes through the
    /// shared rule and writes the per-list key rather than holding one untagged `@State`.
    @Test("iOS list detail resolves its tab through the per-list rule")
    func iOSUsesThePerListRule() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSListDetailView.swift")
        let source = CadenceSourceScan.strippingComments(raw)
        #expect(source.contains("ListDetailPage.displayedPage("))
        #expect(source.contains("CadenceDefaults.store.set(newPage.rawValue, forKey: key)"))
        #expect(!source.contains("selectedPage ?? ListDetailPage.resolved"))
    }

    @Test("A tab's spoken label keeps the count it draws")
    func tabAccessibilityLabelKeepsCount() {
        #expect(ListDetailPage.tasks.tabAccessibilityLabel(count: 4) == "Tasks, 4")
        #expect(ListDetailPage.links.tabAccessibilityLabel(count: nil) == "Links")
        #expect(ListDetailPage.completed.tabAccessibilityLabel(count: 0) == "Completed")
    }

    /// The Settings picker highlights by identity and labels by raw value, so two pages sharing
    /// either would leave it ambiguous.
    @Test("Pages have distinct ids and icons")
    func pagesAreDistinct() {
        #expect(Set(ListDetailPage.allCases.map(\.id)).count == ListDetailPage.allCases.count)
        #expect(Set(ListDetailPage.allCases.map(\.icon)).count == ListDetailPage.allCases.count)
    }

    /// T-7033: the Kanban tab draws every configured column when the list has no open task. It
    /// used to branch on `tasks.isEmpty` and show "No kanban cards", hiding the columns — and the
    /// header drop targets on them — exactly when a fresh list needed them.
    @Test("The Kanban tab draws every configured column when the list has no open task")
    func kanbanDrawsEmptyColumns() {
        let columns = ListDetailKanbanBoard.columns(tasks: [], sectionNames: ["Backlog", "Doing", "Done"])
        #expect(columns.map(\.title) == ["Backlog", "Doing", "Done"])
        #expect(columns.allSatisfy { $0.tasks.isEmpty })
        #expect(ListDetailKanbanBoard.drawsColumns(columns))
    }

    /// A filled column sits beside its empty siblings rather than replacing them, and the empty
    /// panel is left for the one case with nothing to draw: no column at all.
    @Test("A filled column keeps its empty siblings; only a column-less list shows the empty panel")
    func kanbanEmptyPanelOnlyWithoutColumns() {
        let task = AppTask(title: "Card")
        task.sectionName = "Doing"
        let columns = ListDetailKanbanBoard.columns(tasks: [task], sectionNames: ["Backlog", "Doing"])
        #expect(columns.map(\.tasks.count) == [0, 1])

        let none = ListDetailKanbanBoard.columns(tasks: [], sectionNames: [])
        #expect(none.isEmpty)
        #expect(ListDetailKanbanBoard.drawsColumns(none) == false)
    }

    /// The iOS board reads the rule above rather than its own task count, ends with the shared
    /// add-column control (the store write the Tasks tab and the Mac list already use), and keeps
    /// its empty copy in `CadenceEmptyStateCopy`.
    @Test("The iOS Kanban board reads the shared column rule and ends with the shared add-column row")
    func iOSKanbanUsesTheSharedRuleAndCreationRow() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSListSupportViews.swift")
        )
        let body = try #require(
            CadenceSourceScan.declarationBody("struct iOSListKanbanPanel: View", in: source),
            "non-vacuity: the iOS Kanban panel is gone"
        )
        #expect(body.contains("ListDetailKanbanBoard.columns(tasks: tasks, sectionNames: sectionNames)"))
        #expect(body.contains("if !ListDetailKanbanBoard.drawsColumns(columns)"))
        #expect(!body.contains("tasks.isEmpty"), "the board branches on its open-task count again")
        #expect(CadenceSourceScan.matchCount(#"CadenceSectionCreationRow\(area: area, project: project\)"#, in: body) == 2)
        #expect(body.contains("CadenceEmptyStateCopy.listKanbanTitle"))
        #expect(!source.contains("No kanban cards"))

        let detail = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSListDetailView.swift")
        )
        #expect(
            detail.range(of: #"iOSListKanbanPanel\([^)]*area: area,\s*project: project\s*\)"#, options: .regularExpression) != nil,
            "the list detail does not hand the board its list, so the add-column row is inert"
        )
    }
}
