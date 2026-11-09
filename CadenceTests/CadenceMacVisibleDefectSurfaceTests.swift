// macOS only: `ListLogView` and the calendar chip views are macOS app types. `ListLogRowPresentation`
// is shared since [[T-14292]]; `CadenceListCompletedCountEyebrowTests` covers it on both platforms.
#if os(macOS)
import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// **[[T-6995]] — a list's Completed tab on the Mac**, and **[[T-12791]]**, which made its rows the
/// shared task row. T-6995 found a hand-rolled row drawing a green tick for every task (canceled
/// ones included), a blank title as a struck-through blank line and the due date as its raw key;
/// it fixed each through shared helpers. The row was still inert -- no click opened the task, the
/// circle reopened nothing, no right-click menu -- where iOS's Completed tab draws the full row.
/// It is `TaskListDisplayRow` now, which answers the glyph, the title fallback and the due chip
/// the way every other Mac task surface does.
@MainActor
struct CadenceMacListLogRowPresentationTests {

    @Test func theCountNamesCancelledTasksApart() {
        func task(_ status: TaskStatus) -> AppTask {
            let task = AppTask(title: "t")
            task.status = status
            return task
        }
        #expect(ListLogRowPresentation.countLabel(for: [task(.done), task(.done)]) == "2 completed")
        #expect(ListLogRowPresentation.countLabel(for: [task(.cancelled)]) == "1 canceled")
        #expect(ListLogRowPresentation.countLabel(for: [task(.done), task(.cancelled), task(.done)])
                == "2 completed, 1 canceled")
    }

    /// [[T-12791]]: the tab draws the shared row, so a finished task opens, reopens and offers its
    /// menu here as it does in the Tasks tab's folded Completed section and on iOS's Completed tab.
    @Test func theCompletedTabDrawsTheSharedTaskRow() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/ListDetailSupportViews.swift")
        )
        let view = try #require(CadenceSourceScan.declarationBody("struct ListLogView: View", in: source))
        #expect(view.contains("ListLogRowPresentation.countLabel(for:"), "non-vacuity: the tab's eyebrow")
        #expect(CadenceSourceScan.matchCount(#"ForEach\(doneTasks\) \{ task in\s+TaskListDisplayRow\("#, in: view) == 1,
                "the Completed tab's rows are not the shared task row")
        #expect(view.contains("todayKey: todayKey,"), "the row is handed the tab's observed day")
        #expect(!view.contains("CadenceTaskCompletionCircle("), "the inert hand-rolled glyph is back")
        #expect(!view.contains(".strikethrough("), "the inert hand-rolled title is back")
    }
}

/// **[[T-6996]] — the Mac calendar drew a task's title raw.** The month cell's task chip, the
/// all-day strip's task chip and both layouts of the day/week timeline block passed `task.title`
/// straight to `Text`, so a task whose title is blank or spaces (an import, an MCP write, a
/// cleared inspector field) drew an empty plate. Every other Mac task surface trims and falls
/// back to "Untitled" through `TaskTitleSupport.displayTitle`.
struct CadenceMacCalendarTaskTitleFallbackTests {

    private static let files = [
        "Cadence/macOS/Views/CalendarPageMonthSupportViews.swift": ["struct MonthTaskChip: View", "struct AllDayTaskChip: View"],
        "Cadence/macOS/Views/TimelineTaskBlockSupportViews.swift": [],
    ]

    @Test func noCalendarTaskSurfaceDrawsTheRawTitle() throws {
        var fallbackSites = 0
        for (path, declarations) in Self.files {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            #expect(!source.contains("Text(task.title)"), "\(path) draws task.title raw again")
            for declaration in declarations {
                let body = try #require(CadenceSourceScan.declarationBody(declaration, in: source), "\(declaration) moved")
                #expect(body.contains("Text(TaskTitleSupport.displayTitle(task.title"),
                        "\(declaration) no longer routes its title through the fallback")
            }
            fallbackSites += CadenceSourceScan.matchCount(
                "Text\\(TaskTitleSupport\\.displayTitle\\(task\\.title", in: source
            )
        }
        // Two month-grid chips, the timeline block's tall and short layouts, and the
        // dragged plate's own title ([[T-8456]]) -- the plate draws the task being moved,
        // so it reads a title like any other surface here and must fall back like one.
        #expect(fallbackSites == 5)
    }

    @Test func theCompactFallbackIsUntitledForABlankTitle() {
        #expect(TaskTitleSupport.displayTitle("  \n", fallback: TaskTitleSupport.defaultCompactDisplayTitle) == "Untitled")
    }
}
#endif
