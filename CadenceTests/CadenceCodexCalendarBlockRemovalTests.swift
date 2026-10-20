#if os(macOS)
import Foundation
import Testing
@testable import Cadence

struct CadenceCodexCalendarBlockRemovalTests {
    @Test func calendarOnlyPassesTaskAndEventDataThroughItsMonthAndTimelineViews() throws {
        for file in ["CalendarPageView", "CalendarPageComponents", "CalendarPageSupportViews", "CalendarTimelineViewportSupportViews", "CalendarPageMonthSupportViews"] {
            let source = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/\(file).swift"))
            #expect(!source.isEmpty)
            for symbol in ["TaskBundle", "allBundles", "bundlesByDate"] {
                #expect(CadenceSourceScan.matchCount("\\b\(symbol)\\b", in: source) == 0, "\(file): retired \(symbol)")
            }
        }
        let page = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarPageView.swift"))
        #expect(page.contains("CalendarPageDataSupport.tasksByScheduledDate(allTasks)"))
        let first = try #require(CadenceSourceScan.declarationBody("private func firstTimedMinute", in: page))
        #expect(first.contains("CalendarEventItem.timedSegments("))
        #expect(first.contains("(tasksByDate[key] ?? []).map(\\.scheduledStartMin)"))
        #expect(first.contains("+ eventMinutes"))
        #expect(first.contains("CadenceScheduleSupport.earliestTimedStartMinute("))
        let viewport = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarTimelineViewportSupportViews.swift"))
        #expect(viewport.contains("CalDayColumn("))
        #expect(viewport.contains("tasks: tasksByDate[key] ?? []"))
        let month = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarPageComponents.swift"))
        #expect(month.contains("MonthDayCell("))
        #expect(month.contains("tasks: tasksByDate[key] ?? []"))
    }
}
#endif
