#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **T-5011 — the sidebars read an observed day, not the clock.**
///
/// The Today row's overdue badge and each list row's due-date flag were computed from
/// `DateFormatters.todayKey()` in a body whose inputs are the same on both sides of midnight, so a
/// Mac or iPad left open overnight kept yesterday's badge beside a Today page showing today's. The
/// iPhone copy sat behind `.equatable()` with an `==` that compared only `style`, so it could not
/// re-run on a day change even if its parent did.
///
/// Which views install the observer is pinned by `CadenceDayChangeAdoptionTests`. This suite pins
/// the rest of the wire — the key reaching the count, the flag and the `==` — and the flag's
/// colour rule by behaviour. Nothing here moves `NSTimeZone.default`: every key is a literal.
@MainActor
struct CadenceSidebarObservedDayTests {
    private static func code(_ path: String) throws -> String {
        CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
    }

    // MARK: - The flag's rule

    @Test func aListDueYesterdayIsPastOnceTheObservedDayTurns() {
        #expect(CadenceSidebarLayout.listDueDateIsPast("2026-10-21", todayKey: "2026-10-22"))
        // Before midnight the same list was due today, and today is not late.
        #expect(!CadenceSidebarLayout.listDueDateIsPast("2026-10-21", todayKey: "2026-10-21"))
    }

    @Test func aListDueLaterIsNotPast() {
        #expect(!CadenceSidebarLayout.listDueDateIsPast("2026-10-23", todayKey: "2026-10-22"))
        #expect(!CadenceSidebarLayout.listDueDateIsPast("2027-01-01", todayKey: "2026-12-31"))
    }

    // MARK: - macOS

    @Test func theMacListRowColoursItsFlagAgainstItsObservedDay() throws {
        let source = try Self.code("Cadence/macOS/Views/SidebarSupportViews.swift")
        let row = try #require(CadenceSourceScan.declarationBody("struct SidebarListRow: View", in: source))
        #expect(row.contains("CadenceSidebarLayout.listDueDateIsPast(key, todayKey: observedDay.todayKey)"))
        #expect(!row.contains("DateFormatters.todayKey()"))
    }

    // MARK: - iPad

    @Test func theIPadColumnHandsItsObservedDayToTheListRows() throws {
        let source = try Self.code("Cadence/iOS/iOSRootSidebar.swift")
        let column = try #require(CadenceSourceScan.declarationBody("struct iOSSidebar: View", in: source))
        #expect(column.contains("todayKey: observedDay.todayKey,\n            isSelected:"))

        let region = try #require(CadenceSourceScan.declarationBody("struct iOSSidebarListsRegion: View", in: source))
        #expect(region.contains("let todayKey: String"))
        #expect(region.contains("style: style,\n                    todayKey: todayKey,"))
        #expect(!region.contains("DateFormatters.todayKey()"))

        let row = try #require(CadenceSourceScan.declarationBody("struct iOSSidebarListRow: View", in: source))
        #expect(row.contains("let todayKey: String"))
        #expect(row.contains("CadenceSidebarLayout.listDueDateIsPast(key, todayKey: todayKey)"))
        #expect(!row.contains("DateFormatters.todayKey()"))
    }

    // MARK: - iPhone

    @Test func theIPhoneIndexComparesTheDayInItsEqualityAndCountsAgainstIt() throws {
        let source = try Self.code("Cadence/iOS/iOSTasksTabView.swift")
        let rows = try #require(CadenceSourceScan.declarationBody(
            "private struct iOSTasksIndexDestinationRows: View, Equatable", in: source
        ))
        #expect(rows.contains("let todayKey: String"))
        let equality = try #require(CadenceSourceScan.declarationBody(
            "static func == (lhs: Self, rhs: Self) -> Bool", in: rows
        ))
        #expect(
            CadenceSourceScan.matchCount(#"lhs\.todayKey == rhs\.todayKey"#, in: equality) == 1,
            "== ignores the day, so .equatable() keeps yesterday's overdue count past midnight"
        )
        #expect(rows.contains("from: allTasks,\n                todayKey: todayKey"))
        #expect(!rows.contains("DateFormatters.todayKey()"))
    }

    @Test func theIPhoneTabHandsItsObservedDayToTheRowsTheListsAndTheDateEyebrow() throws {
        let source = try Self.code("Cadence/iOS/iOSTasksTabView.swift")
        let tab = try #require(CadenceSourceScan.declarationBody("struct iOSTasksTabView: View", in: source))
        #expect(tab.contains("iOSTasksTabHeader(todayKey: observedDay.todayKey,"))
        let index = try #require(CadenceSourceScan.declarationBody("private var index: some View", in: tab))
        #expect(index.contains("let todayKey = observedDay.todayKey"))
        #expect(index.contains("iOSTasksIndexDestinationRows(style: style, todayKey: todayKey, onOpen: open)"))
        #expect(index.contains("style: style,\n                todayKey: todayKey,"))

        let header = try #require(CadenceSourceScan.declarationBody("private struct iOSTasksTabHeader: View", in: source))
        #expect(header.contains("dateEyebrow(for: DateFormatters.date(from: todayKey) ?? Date())"))
        // T-5020: the hour-based greeting reads a minute-aligned timeline's date, not a one-shot
        // `Date()` that froze it at the last re-render.
        #expect(CadenceSourceScan.matchCount(#"TimelineView\(\.everyMinute\) \{ context in"#, in: header) == 1)
        #expect(header.contains("greeting(for: context.date)"))
        #expect(!header.contains("greeting(for: Date())"), "the greeting goes stale within the day")
    }
}
#endif
