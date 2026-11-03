import Foundation
import Testing
@testable import Cadence

/// **[[T-9837]]: an iOS list Kanban column closes with the Mac's "Completed N" toggle instead of
/// dropping its finished cards.**
///
/// `iOSListDetailView` handed `iOSListKanbanPanel` its `activeTasks` only and `iOSListKanbanColumn`
/// drew no footer, so a column whose work was all done read "0" and empty on an iPad while macOS's
/// `ListSectionKanbanColumn` split the same column with `KanbanBoardSupport.columnHalves` and
/// closed it with `KanbanCompletedTasksToggle`. The candidate reason -- the iOS list page has its
/// own Completed tab -- is not a hardware or input reason ([[T-8201]]), and the Mac list page has
/// finished work in more than one place too.
///
/// The bucketing is pinned by VALUE and the drawing by source scan. Both kinds: a scan that said
/// "a footer is drawn" would pass over a footer counting the wrong half.
@MainActor
struct iOSListBoardCompletedColumnTests {
    private static let boardFile = "Cadence/iOS/iOSListSupportViews.swift"
    private static let pageFile = "Cadence/iOS/iOSListDetailView.swift"

    private func boardSource() throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.boardFile))
    }

    private func column(in code: String) throws -> String {
        try #require(
            CadenceSourceScan.declarationBody("private struct iOSListKanbanColumn: View", in: code),
            "the iOS list board column is gone from \(Self.boardFile)"
        )
    }

    private func task(_ title: String, section: String, status: TaskStatus) -> AppTask {
        let task = AppTask(title: title)
        task.sectionName = section
        task.status = status
        return task
    }

    /// **Finished cards reach the column they belong to, by the same rule the open ones do.**
    ///
    /// *Failing-first:* bucketing by anything other than `sectionGroups` — a raw
    /// `filter { $0.sectionName == name }`, say — fails the case-insensitive expectation, which is
    /// the one a hand-rolled match gets wrong.
    @Test func finishedCardsAreBucketedIntoTheColumnTheyBelongTo() {
        let finished = [
            task("shipped", section: "Doing", status: .done),
            task("dropped", section: "doing", status: .cancelled),
            task("filed", section: "Backlog", status: .done)
        ]
        let byColumn = ListDetailKanbanBoard.completedTasksByColumn(
            tasks: finished,
            sectionNames: ["Backlog", "Doing", "Done"]
        )
        #expect(byColumn["Doing"]?.count == 2, "the finished half does not match a section name case-insensitively")
        #expect(byColumn["Backlog"]?.count == 1)
        // A CONFIGURED column with no finished work is ABSENT rather than present-and-empty, so
        // it draws no footer and a board of open columns looks exactly as it did.
        #expect(byColumn["Done"] == nil, "an empty Completed half is carried as a key, so an empty footer can be drawn")
        #expect(byColumn.count == 2)
    }

    /// **A cancelled task is finished work**, which is the one classification mistake this split
    /// can make — `!$0.isDone` would file it among the work you still intend to do, the
    /// T-147 / T-203 / T-342 / T-381 shape.
    ///
    /// *Failing-first:* splitting on `isDone` instead of `isFinishedTask` leaves the cancelled
    /// card out of the map entirely and fails the count.
    @Test func aCancelledCardCountsAsFinishedAndNotAsOpenWork() {
        let cancelled = task("dropped", section: "Doing", status: .cancelled)
        #expect(cancelled.isDone == false, "the premise moved: a cancelled task now reports isDone")
        let byColumn = ListDetailKanbanBoard.completedTasksByColumn(
            tasks: CadenceTaskQuerySupport.completedTasks(from: [cancelled]),
            sectionNames: ["Doing"]
        )
        #expect(byColumn["Doing"]?.count == 1, "a cancelled card is not treated as finished work")
    }

    /// **The page hands the board its finished half**, which it never did — without this the
    /// column has a footer and nothing to put in it, so the defect would ship unchanged.
    ///
    /// *Failing-first:* dropping `completedTasks: completedTasks` from the page's call fails here.
    @Test func theListPageHandsTheBoardItsFinishedHalf() throws {
        // Ordering rather than a fixed window: both comment strippers preserve the source's
        // LENGTH, so a `prefix(n)` after the call can be almost entirely blanked comment.
        let page = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(Self.pageFile))
        let call = try #require(page.range(of: "iOSListKanbanPanel("), "the list page draws no board")
        let active = try #require(page.range(of: "tasks: activeTasks,", range: call.upperBound..<page.endIndex),
                                  "non-vacuity: the call read is not the board's")
        let finished = try #require(
            page.range(of: "completedTasks: completedTasks,", range: active.upperBound..<page.endIndex),
            "the board is still handed the open half only, which is the [[T-9837]] defect"
        )
        let sections = try #require(page.range(of: "sectionNames: sectionNames,", range: call.upperBound..<page.endIndex))
        #expect(finished.upperBound <= sections.lowerBound,
                "the finished half is passed somewhere other than inside the board's own call")

        let board = try boardSource()
        let panel = try #require(
            CadenceSourceScan.declarationBody("struct iOSListKanbanPanel: View", in: board),
            "the iOS list board panel is gone"
        )
        #expect(panel.contains("var completedTasks: [AppTask] = []"), "the panel takes no finished half")
        #expect(panel.contains("ListDetailKanbanBoard.completedTasksByColumn(tasks: completedTasks, sectionNames: sectionNames)"),
                "the panel buckets the finished half some way other than the shared rule")
        #expect(panel.contains("completedTasks: finished[column.title] ?? []"),
                "the panel hands its columns no finished cards")
        // One pass for the board, not one filter per column inside the `ForEach` (T-1501).
        #expect(CadenceSourceScan.matchCount(#"let finished = completedByColumn"#, in: panel) == 1,
                "the finished map is derived per column again")
    }

    /// **The footer itself: the shared label, collapsed on arrival, over the column's own cards.**
    ///
    /// *Failing-first:* starting expanded (`= false`) fails the collapsed expectation; drawing the
    /// count with a hand-rolled row instead of `CadenceBoardCompletedToggleLabel` fails the shared
    /// label one, which is the second copy [[T-9835]] took out of the tree.
    @Test func theColumnClosesWithTheSharedCompletedToggleCollapsed() throws {
        let code = try boardSource()
        let column = try column(in: code)
        #expect(column.count > 1_000, "non-vacuity: the column read as \(column.count) characters")
        #expect(column.contains("var completedTasks: [AppTask] = []"), "the column takes no finished cards")
        #expect(column.contains("@State private var isCompletedCollapsed = true"),
                "the Completed section is not collapsed on arrival")
        #expect(column.contains("CadenceBoardCompletedToggleLabel("),
                "the column draws its own Completed row instead of the one shared with the Mac")
        #expect(column.contains("count: completedTasks.count,"), "the toggle counts something other than the finished cards")
        #expect(column.contains("isExpanded: !isCompletedCollapsed,"))
        #expect(column.contains("minimumHeight: 44"), "the toggle lost iOS's touch-row floor")
        // [[T-9833]]: the disclosure says which way it is, as the Mac's has since [[T-7081]].
        #expect(column.contains(#".accessibilityValue(isCompletedCollapsed ? "Collapsed" : "Expanded")"#),
                "the Completed toggle states neither Expanded nor Collapsed")
        #expect(column.contains("if !isCompletedCollapsed {"), "the finished cards are drawn whether or not it is open")
    }

    /// **The header's count stays the OPEN work.** The toggle carries its own count, so adding the
    /// two would state one number twice — T-571's rule, and the Mac's.
    ///
    /// *Failing-first:* `count: tasks.count + completedTasks.count` fails here.
    @Test func theColumnHeaderStillCountsOnlyTheOpenCards() throws {
        let code = try boardSource()
        let column = try column(in: code)
        let header = try #require(column.range(of: "CadenceBoardColumnHeader("), "the column has no header")
        let head = String(column[header.lowerBound...].prefix(300))
        #expect(head.contains("count: tasks.count,"), "the column header counts something other than its open cards")
        #expect(!head.contains("completedTasks.count"),
                "the header folds the finished cards into the number the toggle below already states")
    }

    /// **The footer is inside the card scroller, after the open stack** — [[T-9611]]'s answer for
    /// the Calendar Board's column, and where macOS puts its toggle. Pinned off the far bottom it
    /// would be a second thing competing for the column's height.
    ///
    /// *Failing-first:* moving `completedFooter` out of the `ScrollView` fails the ordering.
    @Test func theFooterScrollsWithTheCardsAboveIt() throws {
        let code = try boardSource()
        let column = try column(in: code)
        let scroller = try #require(column.range(of: "ScrollView {"), "the column's cards no longer scroll")
        let cards = try #require(column.range(of: "ForEach(tasks) { task in", range: scroller.upperBound..<column.endIndex))
        let footer = try #require(
            column.range(of: "completedFooter", range: cards.upperBound..<column.endIndex),
            "the column draws no Completed footer after its open cards"
        )
        let scrollerEnd = try #require(column.range(of: ".scrollIndicators(.hidden)"))
        #expect(footer.upperBound < scrollerEnd.lowerBound,
                "the footer is pinned outside the scroller, competing with the cards for the column's height")
    }
}
