import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-17047]]: the MCP context summary's Inbox count is open work only.** It spelled its own
/// filter (`area == nil && project == nil && !isCancelled`), so a finished Inbox task counted while
/// the same response's `activeTaskCount`, the brief's `inbox` section and every on-screen Inbox
/// badge (`CadenceTaskQuerySupport.openInboxTaskCount`) did not count it.
@Suite(.preservesTheStoredLaunchReports)
@MainActor
struct CadenceContextSummaryInboxCountTests {
    @Test func theContextSummaryCountsOnlyOpenInboxTasks() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let context = Context(name: "Work")
        modelContext.insert(context)

        let open = AppTask(title: "Open inbox task")
        open.context = context
        let done = AppTask(title: "Finished inbox task")
        done.context = context
        done.status = .done
        let cancelled = AppTask(title: "Cancelled inbox task")
        cancelled.context = context
        cancelled.status = .cancelled
        for task in [open, done, cancelled] { modelContext.insert(task) }
        try modelContext.save()

        let summary = try CadenceReadService(container: container)
            .contextSummary(contextID: context.id.uuidString)

        #expect(summary.inboxTaskCount == 1, "a done or cancelled Inbox task is counted as Inbox work")
        // The relation the field must keep with its neighbour: every task here is in the Inbox, so
        // the open Inbox count and the active count are the same number.
        #expect(summary.inboxTaskCount == summary.activeTaskCount)
        #expect(summary.completedTaskCount == 1)
    }
}

/// **[[T-17048]]: the Mac Focus "Pick a task" card forgets its search once a session starts.**
/// `idleSearchText` is the view's `@State` and nothing cleared it, so the card came back after the
/// session filtered to the old query with most ready tasks hidden. A scan, because a view's
/// `@State` is not something a unit test can drive; it strips comments, so a comment cannot pass it.
@Suite
struct CadenceMacFocusIdleSearchClearsTests {
    @Test func startingASessionFromThePickCardClearsItsSearch() throws {
        // Comments stripped but string literals kept: the assertion is about the empty `""`.
        let view = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/FocusView.swift")
        )
        // The idle card's argument list: from the call to the split's sidebar that follows it.
        let start = try #require(view.range(of: "FocusPickSessionCard("))
        let end = try #require(view.range(of: "SchedulePanel(", range: start.upperBound..<view.endIndex))
        let card = String(view[start.upperBound..<end.lowerBound])
        #expect(card.contains("searchText: $idleSearchText"), "the scan is not reading the idle card")
        // Cleared inside the branch taken only when the start committed, so a refused start keeps
        // the search the user typed.
        #expect(
            CadenceSourceScan.matchCount(
                #"if reportingFocusFailure\(\{\s*try focusManager\.startFocus\(task: task, in: modelContext\)\s*\}\)\s*\{\s*idleSearchText = """#,
                in: card
            ) == 1,
            "a session started from the pick card leaves its search behind for the next idle card"
        )
    }
}
