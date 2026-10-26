// macOS only: `ListLogRowPresentation` and the calendar chip views are macOS app types.
#if os(macOS)
import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// **[[T-6995]] — a list's Completed tab on the Mac.** Every row drew a green tick, cancelled
/// tasks included; a title of spaces drew a struck-through blank line; and the line under the
/// title was the raw due-date key, `2026-10-19`, with nothing to say it was the deadline.
@MainActor
struct CadenceMacListLogRowPresentationTests {

    @Test func aCancelledRowDrawsTheCancelledGlyphNotTheTick() {
        let done = AppTask(title: "Ship it")
        done.status = .done
        let cancelled = AppTask(title: "Drop it")
        cancelled.status = .cancelled

        #expect(ListLogRowPresentation.glyph(for: done).symbolName == "checkmark.circle.fill")
        #expect(ListLogRowPresentation.glyph(for: cancelled).symbolName == "xmark.circle.fill")
        #expect(ListLogRowPresentation.glyph(for: cancelled) == CadenceTaskCompletionGlyph.resolve(task: cancelled),
                "the tab must settle on the task row's own glyph")
    }

    @Test func aBlankTitleReadsAsUntitled() {
        let blank = AppTask(title: "   ")
        blank.status = .done
        #expect(ListLogRowPresentation.title(for: blank) == TaskTitleSupport.defaultDisplayTitle)
        #expect(ListLogRowPresentation.title(for: AppTask(title: "  Buy milk ")) == "Buy milk")
    }

    @Test func theDueLineIsLabelledAndSpelledNotTheRawKey() throws {
        let task = AppTask(title: "Report")
        task.status = .done
        #expect(ListLogRowPresentation.dueLine(for: task) == nil)

        task.dueDate = "2026-03-14"
        let line = try #require(ListLogRowPresentation.dueLine(for: task))
        #expect(line == "Due \(DateFormatters.relativeDate(from: "2026-03-14"))")
        #expect(!line.contains("2026-03-14"), "the raw key is back")
    }

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

    /// The view has to read the presentation, or every assertion above is about dead code.
    @Test func theCompletedTabReadsThePresentation() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/ListDetailSupportViews.swift")
        )
        let view = try #require(CadenceSourceScan.declarationBody("struct ListLogView: View", in: source))
        for call in ["ListLogRowPresentation.countLabel(for:", "ListLogRowPresentation.glyph(for:",
                     "ListLogRowPresentation.title(for:", "ListLogRowPresentation.dueLine(for:"] {
            #expect(view.contains(call), "ListLogView no longer reads \(call)")
        }
        #expect(!view.contains("Text(task.title)"), "the raw title is drawn again")
        #expect(!view.contains("Text(task.dueDate)"), "the raw due-date key is drawn again")
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
        // Two month-grid chips plus the timeline block's tall and short layouts.
        #expect(fallbackSites == 4)
    }

    @Test func theCompactFallbackIsUntitledForABlankTitle() {
        #expect(TaskTitleSupport.displayTitle("  \n", fallback: TaskTitleSupport.defaultCompactDisplayTitle) == "Untitled")
    }
}
#endif
