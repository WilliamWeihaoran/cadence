import Foundation
import Testing
@testable import Cadence

/// **T-3156: the Tasks tab's whole-store count lives in a child that a parent pass cannot re-run.**
///
/// Presenting the New task sheet re-runs `iOSTasksTabView` once each way on every Tasks-tab page:
/// the leased `iOSCompactTabShell` rebuilds its `section` and `path` bindings from
/// `Binding(get:set:)` closures whenever its body runs, and SwiftUI cannot compare closure-backed
/// bindings, so `Self._printChanges()` printed `_section, _path changed` with no value changed. That
/// body used to count open and overdue tasks over a `@Query` of every task — O(n) per pass.
///
/// The fix moves that `@Query` and both counts into `iOSTasksIndexDestinationRows`, drawn through
/// `.equatable()` with an `==` that ignores the one input a parent pass always changes (`onOpen`, a
/// fresh closure). `Cadence/iOS/` is behind `#if os(iOS)` and this target builds for macOS, so this
/// pins the structure that behaviour depends on, as counts.
struct CadenceIOSTasksIndexCountScopeTests {
    private static let path = "Cadence/iOS/iOSTasksTabView.swift"
    private static let taskQuery = #"@Query[^\n]*var\s+\w+\s*:\s*\[AppTask\]"#
    private static let counting = #"overdueTaskCount\(|openTaskCount\("#

    private static func source() throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }

    @Test func theTabBodyHoldsNoTaskQueryAndCountsNothing() throws {
        let source = try Self.source()
        let tab = try #require(
            CadenceSourceScan.declarationBody("struct iOSTasksTabView: View", in: source),
            "iOSTasksTabView is gone from \(Self.path)"
        )
        // Non-vacuity: this is the tab, and it still fetches the lists it draws.
        #expect(CadenceSourceScan.matchCount(#"@Query\(sort: \\Context\.order\)"#, in: tab) == 1)
        #expect(
            CadenceSourceScan.matchCount(Self.taskQuery, in: tab) == 0,
            "iOSTasksTabView fetches every task again, so each sheet presented over it re-counts the store (T-3156)"
        )
        #expect(CadenceSourceScan.matchCount(Self.counting, in: tab) == 0)
        #expect(CadenceSourceScan.matchCount(#"\ballTasks\b"#, in: tab) == 0)
        // It draws the rows through the child, compared by `==` rather than field by field.
        #expect(
            CadenceSourceScan.matchCount(
                #"iOSTasksIndexDestinationRows\(style: style, onOpen: open\)\s*\.equatable\(\)"#,
                in: tab
            ) == 1
        )
    }

    @Test func theChildAloneFetchesAndCountsAndItsEqualityIgnoresTheClosure() throws {
        let source = try Self.source()
        let rows = try #require(
            CadenceSourceScan.declarationBody("private struct iOSTasksIndexDestinationRows: View, Equatable", in: source),
            "iOSTasksIndexDestinationRows is gone from \(Self.path)"
        )
        #expect(CadenceSourceScan.matchCount(Self.taskQuery, in: rows) == 1)
        #expect(CadenceSourceScan.matchCount(#"overdueTaskCount\("#, in: rows) == 1)
        #expect(CadenceSourceScan.matchCount(#"openTaskCount\("#, in: rows) == 1)
        // The whole file: the child's fetch is the only task fetch on this tab.
        #expect(CadenceSourceScan.matchCount(Self.taskQuery, in: source) == 1)

        let equality = try #require(
            CadenceSourceScan.declarationBody("static func == (lhs: Self, rhs: Self) -> Bool", in: rows),
            "iOSTasksIndexDestinationRows lost its own ==, so a parent pass re-runs it again"
        )
        #expect(CadenceSourceScan.matchCount(#"lhs\.style == rhs\.style"#, in: equality) == 1)
        #expect(
            CadenceSourceScan.matchCount(#"onOpen"#, in: equality) == 0,
            "== compares onOpen, a fresh closure on every parent pass, so it never reads equal"
        )
    }
}
