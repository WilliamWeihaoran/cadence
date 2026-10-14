import Foundation
import Testing
@testable import Cadence

/// **T-3159: Today reads the store in its body, not in its `GeometryReader`'s closure.**
///
/// `iOSTodayView` lays itself out in a `GeometryReader`, and the reader's content closure runs
/// again whenever its proxy changes, with no pass of the page's own body. T-3158's probes, on the
/// standing iPhone simulator at 0, 300 and 3,000 tasks, counted `iOSCompactTodayView` and
/// `iOSTodayTaskSections` rebuilt 3 times per New task present-and-Cancel with `@self changed`
/// while `iOSTodayView` itself ran 0 times — so the rebuilds came from that closure, which called
/// `todayTaskGroups`, `completedTodayTasks`, the rollover notice and `todaySummary`, each a filter
/// over the whole task `@Query`.
///
/// The page now builds one `CadenceTodayListContent` in `body` and hands it into the closure, and
/// the compact layout goes through `iOSCompactTodayHost` with `.equatable()`, so a closure pass
/// that moved nothing the list draws neither re-filters the store nor rebuilds the list.
/// `Cadence/iOS/` is behind `#if os(iOS)` and this target builds for macOS, so the source half is
/// pinned as counts and the equality — ordinary shared code — is run.
@MainActor
struct CadenceIOSTodayGeometryReadTests {
    private static let todayPath = "Cadence/iOS/iOSTodayView.swift"

    /// The page's derivations that read the whole store. None may be named inside the reader's
    /// closure or the layout functions it calls.
    private static let storeReads = [
        "todayTaskGroups", "completedTodayTasks", "todaySummary", "pastDoTasks",
        "isRolloverNoticeVisible", "todayTasks", "timedTodayTasks", "allTasks", "listContent",
    ]

    private func today() throws -> String {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.todayPath))
        return try #require(
            CadenceSourceScan.declarationBody("struct iOSTodayView: View", in: source),
            "struct iOSTodayView is gone from \(Self.todayPath)"
        )
    }

    private func storeReadCount(in text: String) -> Int {
        Self.storeReads.reduce(0) { $0 + CadenceSourceScan.matchCount(#"\b\#($1)\b"#, in: text) }
    }

    @Test func theStoreIsReadInTheBodyAndOnlyCapturedByTheReadersClosure() throws {
        let view = try today()
        let body = try #require(CadenceSourceScan.declarationBody("var body: some View", in: view))
        let closure = try #require(
            CadenceSourceScan.declarationBody("GeometryReader", in: body),
            "iOSTodayView.body no longer lays out in a GeometryReader; reconsider T-3159's pin"
        )
        #expect(
            storeReadCount(in: closure) == 0,
            "the GeometryReader closure reads the task store again, so every proxy change re-filters it (T-3159)"
        )
        // Read once, before the reader, and handed in.
        #expect(CadenceSourceScan.matchCount(#"let\s+content\s*=\s*listContent\b"#, in: body) == 1)
        let read = try #require(body.range(of: "let content = listContent"))
        let reader = try #require(body.range(of: "GeometryReader"))
        #expect(read.upperBound < reader.lowerBound)
        #expect(
            CadenceSourceScan.matchCount(#"todayLayout\(width:\s*proxy\.size\.width,\s*content:\s*content\)"#, in: closure) == 1
        )

        // The functions the closure calls take the content and read nothing else from the store.
        for name in ["todayLayout", "compactTodayLayout", "twoPaneTodayLayout", "todayTaskColumn", "todayTaskSections", "todaySections"] {
            let function = try #require(CadenceSourceScan.functionBody(named: name, in: view), "\(name) is gone")
            #expect(storeReadCount(in: function) == 0, "\(name) reads the task store, so the reader's closure does (T-3159)")
        }

        // Non-vacuity: the needle finds the reads where they still belong.
        let content = try #require(CadenceSourceScan.declarationBody("private var listContent: CadenceTodayListContent", in: view))
        #expect(storeReadCount(in: content) >= 4)
        #expect(storeReadCount(in: "let x = todayTaskGroups; let y = todayTaskGroupsLabel") == 1)
    }

    @Test func thePhoneListIsBuiltOnlyThroughTheEquatableHost() throws {
        let view = try today()
        let compact = try #require(CadenceSourceScan.functionBody(named: "compactTodayLayout", in: view))
        #expect(
            CadenceSourceScan.matchCount(#"iOSCompactTodayView\("#, in: compact) == 0,
            "compactTodayLayout builds iOSCompactTodayView directly again, so every proxy change rebuilds it (T-3159)"
        )
        // DEBUG and release, each through the host and each compared.
        #expect(CadenceSourceScan.matchCount(#"iOSCompactTodayHost\("#, in: compact) == 2)
        #expect(CadenceSourceScan.matchCount(#"\.equatable\(\)"#, in: compact) == 2)

        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.todayPath))
        let host = try #require(CadenceSourceScan.declarationBody("struct iOSCompactTodayHost: View, Equatable", in: source))
        let equality = try #require(CadenceSourceScan.declarationBody("static func == (lhs: iOSCompactTodayHost", in: host))
        // Values, not the live bindings, and the content; never a closure.
        for compared in ["content", "sortModeValue", "showCompletedValue", "showsHeader"] {
            #expect(
                CadenceSourceScan.matchCount(#"lhs\.\#(compared)\s*==\s*rhs\.\#(compared)"#, in: equality) == 1,
                "iOSCompactTodayHost.== no longer compares \(compared)"
            )
        }
        #expect(CadenceSourceScan.matchCount(#"\b(onRollOver|seedSampleData|sortMode|showCompleted)\b"#, in: equality) == 0)
        #expect(CadenceSourceScan.matchCount(#"iOSCompactTodayView\("#, in: host) == 2)
    }

    // MARK: - The equality, run

    private func content(
        todayKey: String = "2026-10-13",
        groups: [CadenceTodayTaskGroup],
        completed: [AppTask] = [],
        rollover: [AppTask]? = nil,
        failure: String? = nil,
        summary: CadenceTodaySummary = CadenceTodaySummary(activeCount: 1, timedCount: 0, completedCount: 0)
    ) -> CadenceTodayListContent {
        CadenceTodayListContent(
            todayKey: todayKey,
            taskGroups: groups,
            completedTasks: completed,
            rolloverTasks: rollover,
            rolloverFailureNotice: failure,
            summary: summary
        )
    }

    private func group(_ tasks: [AppTask], title: String = "Inbox", key: String = "inbox") -> CadenceTodayTaskGroup {
        CadenceTodayTaskGroup(
            listKey: key,
            title: title,
            accent: Theme.blue,
            listIcon: nil,
            contextIcon: nil,
            contextColor: nil,
            tasks: tasks
        )
    }

    @Test func theSameTasksUnderTheSameHeadingsAreEqualSoAProxyPassIsSkipped() {
        let one = AppTask(title: "One")
        let two = AppTask(title: "Two")
        let done = AppTask(title: "Done")
        let lhs = content(groups: [group([one, two])], completed: [done], rollover: [one])
        let rhs = content(groups: [group([one, two])], completed: [done], rollover: [one])
        #expect(lhs == rhs)
    }

    @Test func anyChangeTheListDrawsIsUnequal() {
        let one = AppTask(title: "One")
        let two = AppTask(title: "Two")
        let base = content(groups: [group([one, two])])

        // Another task object with the same contents is a different row.
        #expect(base != content(groups: [group([one, AppTask(title: "Two")])]))
        // Order is what a sort change produces.
        #expect(base != content(groups: [group([two, one])]))
        #expect(base != content(groups: [group([one])]))
        #expect(base != content(groups: [group([one, two], title: "Renamed")]))
        #expect(base != content(groups: [group([one, two], key: "a_other")]))
        #expect(base != content(groups: [group([one]), group([two], key: "a_other")]))
        #expect(base != content(todayKey: "2026-10-14", groups: [group([one, two])]))
        #expect(base != content(groups: [group([one, two])], completed: [two]))
        #expect(base != content(groups: [group([one, two])], rollover: []))
        #expect(content(groups: [], rollover: [one]) != content(groups: [], rollover: [two]))
        #expect(base != content(groups: [group([one, two])], failure: CadenceTodayRolloverSupport.rollFailureNotice))
        #expect(base != content(groups: [group([one, two])], summary: CadenceTodaySummary(activeCount: 2, timedCount: 0, completedCount: 0)))
    }
}
