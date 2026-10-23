#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **T-5010 — the iOS Calendar reads the page's observed day, the iOS half of [[T-3140]].**
///
/// Every "is this today" question on the iOS Calendar was a clock read in a body whose inputs are
/// the same on both sides of midnight, so an iPad left on Calendar overnight kept yesterday's day
/// header, today wash, now-line, month and agenda marks and the Board's amber column — and the new
/// day's column never built a now-line at all, because the gate that would build it was never
/// re-evaluated.
///
/// `iOSCalendarView` now owns a `CadenceObservedDay` (pinned as an adopter by
/// `CadenceDayChangeAdoptionTests`) and hands its key to every presentation; this suite pins that
/// each one compares against the key it is handed and asks the clock nowhere. Source pins, like
/// T-3140's wiring half: these are iOS-only views, and the comparison is one `==`. Nothing here
/// moves `NSTimeZone.default`.
@MainActor
struct CadenceIOSCalendarObservedDayTests {
    private static func code(_ file: String) throws -> String {
        CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/" + file))
    }

    private static let clockReads = ["isDateInToday(", "DateFormatters.todayKey()"]

    private static func expectNoClockRead(_ body: String, _ name: String) {
        for read in clockReads {
            #expect(!body.contains(read), "\(name) asks the clock for today again: \(read)")
        }
    }

    @Test func thePageHandsItsObservedDayToEveryPresentation() throws {
        let source = try Self.code("iOSCalendarView.swift")
        let page = try #require(CadenceSourceScan.declarationBody("struct iOSCalendarView: View", in: source))
        // Board, timeline grid, month grid, month stack and agenda: five presentations, one key.
        #expect(CadenceSourceScan.matchCount(#"todayKey: observedDay\.todayKey"#, in: page) == 5)
        for child in [
            "iOSCalendarBoardPlanner(", "iOSCalendarTimelineGrid(", "iOSCalendarMonthGrid(",
            "iOSCalendarMonthStack(", "iOSCalendarMonthAgendaList(",
        ] {
            #expect(page.contains(child), "non-vacuity: the page stopped drawing \(child)")
        }
        Self.expectNoClockRead(page, "iOSCalendarView")
    }

    @Test func theTimelineGridForwardsTheKeyToItsHeadersAndColumns() throws {
        let source = try Self.code("iOSCalendarTimelineViews.swift")
        let grid = try #require(CadenceSourceScan.declarationBody("struct iOSCalendarTimelineGrid: View", in: source))
        #expect(grid.contains("let todayKey: String"))
        #expect(grid.contains("events: CadenceScheduleSupport.items(on: key, in: eventsByDate),\n            todayKey: todayKey,"))
        #expect(grid.contains("date: date,\n                            todayKey: todayKey,"))
        #expect(grid.contains("showsToday: visibleDates.contains { DateFormatters.dateKey(from: $0) == todayKey }"))
        Self.expectNoClockRead(grid, "iOSCalendarTimelineGrid")
    }

    @Test func theTimelineHeaderAndColumnCompareAgainstTheHandedDownKey() throws {
        let source = try Self.code("iOSCalendarTimelineViews.swift")
        for name in ["private struct iOSCalendarTimelineDayHeader: View", "private struct iOSCalendarTimelineDayColumn: View"] {
            let view = try #require(CadenceSourceScan.declarationBody(name, in: source), "\(name)")
            #expect(view.contains("let todayKey: String"), "\(name)")
            #expect(view.contains("private var isToday: Bool { DateFormatters.dateKey(from: date) == todayKey }"), "\(name)")
            Self.expectNoClockRead(view, name)
        }
        let column = try #require(CadenceSourceScan.declarationBody("private struct iOSCalendarTimelineDayColumn: View", in: source))
        // The now-line gate and the wash: the two the ticket saw stay on yesterday's column.
        let nowLine = try #require(CadenceSourceScan.declarationBody("private var nowLine: some View", in: column))
        #expect(nowLine.contains("if isToday {"))
        let wash = try #require(CadenceSourceScan.declarationBody("private var dayWash: some View", in: column))
        #expect(wash.contains("if isToday {"))
        // Yesterday's column stops accepting a `+` drop when the day turns.
        let drop = try #require(CadenceSourceScan.declarationBody("private var dropKey: String", in: column))
        #expect(drop.contains("guard key >= todayKey else"))
    }

    @Test func theMonthCellsAndTheAgendaCompareAgainstTheHandedDownKey() throws {
        let month = try Self.code("iOSCalendarMonthViews.swift")
        let grid = try #require(CadenceSourceScan.declarationBody("struct iOSCalendarMonthGrid: View", in: month))
        #expect(grid.contains("let todayKey: String"))
        #expect(grid.contains("todayKey: todayKey,\n                    minHeight: rowHeight"))
        let cell = try #require(CadenceSourceScan.declarationBody("private struct iOSCalendarMonthDayCell: View", in: month))
        #expect(cell.contains("private var isToday: Bool { DateFormatters.dateKey(from: date) == todayKey }"))
        Self.expectNoClockRead(cell, "iOSCalendarMonthDayCell")

        let agendaFile = try Self.code("iOSCalendarMonthAgendaViews.swift")
        let stack = try #require(CadenceSourceScan.declarationBody("struct iOSCalendarMonthStack<Detail: View>: View", in: agendaFile))
        #expect(stack.contains("eventsByDate: eventsByDate,\n                    todayKey: todayKey"))
        let compact = try #require(CadenceSourceScan.declarationBody("private struct iOSCalendarMonthCompactGrid: View", in: agendaFile))
        #expect(compact.contains("todayKey: todayKey,\n                rowHeight: rowHeight"))
        let compactCell = try #require(CadenceSourceScan.declarationBody("private struct iOSCalendarMonthCompactDayCell: View", in: agendaFile))
        #expect(compactCell.contains("private var isToday: Bool { DateFormatters.dateKey(from: date) == todayKey }"))
        Self.expectNoClockRead(compactCell, "iOSCalendarMonthCompactDayCell")

        let agenda = try #require(CadenceSourceScan.declarationBody("struct iOSCalendarMonthAgendaList: View", in: agendaFile))
        #expect(agenda.contains("let isToday = section.key == todayKey"))
        Self.expectNoClockRead(agenda, "iOSCalendarMonthAgendaList")
    }

    @Test func theBoardColumnsCompareAgainstTheHandedDownKey() throws {
        let source = try Self.code("iOSCalendarBoardView.swift")
        let planner = try #require(CadenceSourceScan.declarationBody("struct iOSCalendarBoardPlanner: View", in: source))
        #expect(planner.contains("dateKey: dateKey,\n                        todayKey: todayKey,"))
        Self.expectNoClockRead(planner, "iOSCalendarBoardPlanner")
        let column = try #require(CadenceSourceScan.declarationBody("private struct iOSCalendarBoardDayColumn: View", in: source))
        #expect(column.contains("dateKey == todayKey"))
        Self.expectNoClockRead(column, "iOSCalendarBoardDayColumn")
    }

    @Test func todaysPaneHandsTheGridItsOwnObservedDay() throws {
        let source = try Self.code("iOSTodaySchedulePanel.swift")
        let pane = try #require(CadenceSourceScan.declarationBody("struct iOSSchedulePanel: View", in: source))
        #expect(pane.contains("eventsByDate: [todayKey: todayEvents],\n                todayKey: todayKey,"))
    }
}
#endif
