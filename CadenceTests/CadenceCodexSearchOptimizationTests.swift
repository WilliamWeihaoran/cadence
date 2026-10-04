import Foundation
import SwiftData
import Testing
#if os(macOS)
import AppKit
import Observation
import SwiftUI
#endif
@testable import Cadence

@MainActor
struct CadenceCodexSearchOptimizationTests {
    @Test func codexPreparedQueryPreservesScoresIncludingEmptyAndPunctuation() {
        let cases: [(String, [String], Int?)] = [
            ("", [], 1), ("  \n", [""], 1), ("!!!", [], 1),
            ("cafe", ["Caf\u{00e9}"], 1260),
            ("admin", ["Admin"], 1260), ("admin", ["Administrator"], 1060),
            ("road map", ["Road map"], 1506),
            ("admin", ["Work", "admin"], 484),
            ("min", ["Admin"], 405), ("zzz", ["Admin"], nil),
            ("admin missing", ["Admin"], nil), ("admin", [], nil),
        ]
        for (query, fields, expected) in cases {
            let prepared = CadenceSearchMatcher.PreparedQuery(query)
            #expect(CadenceSearchMatcher.matchScore(query: prepared, fields: fields) == expected)
            #expect(CadenceSearchMatcher.matchScore(query: query, fields: fields) == expected)
        }
    }

    @Test func codexPreparedRankingKeepsTotalOrderAndEvaluatesFieldsOnce() {
        struct Row { let id: String; let title: String }
        let rows = [Row(id: "b", title: "Admin"), Row(id: "a", title: "admin"), Row(id: "c", title: "Elsewhere")]
        var fieldCalls = 0
        let ranked = CadenceSearchMatcher.rank(
            rows, query: CadenceSearchMatcher.PreparedQuery("admin"),
            title: { $0.title }, fields: { fieldCalls += 1; return [$0.title] }, identity: { $0.id }
        )
        #expect(fieldCalls == rows.count)
        #expect(ranked.map(\.id) == ["a", "b", "c"])
        let reversed = CadenceSearchMatcher.rank(
            rows.reversed(), query: "admin", title: { $0.title }, fields: { [$0.title] }, identity: { $0.id }
        )
        #expect(reversed.map(\.id) == ranked.map(\.id))
    }

    #if os(macOS)
    @Test func codexHostedHoverIsolationLeavesDerivationAloneButQueryRefreshesIt() async throws {
        // Compare the old value-read shape against the shipped binding child using the same host.
        for isolated in [false, true] {
            let probe = CodexSearchDerivationProbe()
            let host = NSHostingView(rootView: CodexSearchDerivationHost(probe: probe, isolated: isolated))
            host.frame = NSRect(x: 0, y: 0, width: 640, height: 300)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(60))
            let selection = try #require(probe.selection)
            let initial = probe.derivations
            #expect(initial > 0)
            selection.wrappedValue = "hovered"
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(60))
            let afterHover = probe.derivations
            if isolated {
                #expect(afterHover == initial)
            } else {
                #expect(afterHover > initial, "positive control: original parent read must invalidate")
            }
            probe.query = "changed"
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(60))
            #expect(probe.derivations > afterHover, "query updates must still derive fresh sections")
        }
    }

    @Test func codexTaskSearchKeepsFilteringSeparateFromDisplayRanking() {
        let titleHit = AppTask(title: "Needle")
        titleHit.order = 999
        let notesHit = AppTask(title: "Aardvark")
        notesHit.notes = "Needle needle needle"
        let excluded = AppTask(title: "Not a hit")
        for input in [[notesHit, excluded, titleHit], [titleHit, excluded, notesHit]] {
            let results = GlobalSearchIndexSupport.taskResults(tasks: input, query: "needle")
            #expect(results.map(\.id) == [CadenceSearchIdentity.task(titleHit.id), CadenceSearchIdentity.task(notesHit.id)])
        }
        let tied = (0..<20).map { index -> AppTask in
            let task = AppTask(title: "Admin")
            task.id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
            task.order = 20 - index
            return task
        }
        let ascending = GlobalSearchIndexSupport.taskResults(tasks: tied, query: "admin").map(\.id)
        #expect(ascending.count == 14)
        #expect(ascending == ascending.sorted())
        #expect(GlobalSearchIndexSupport.taskResults(tasks: tied.reversed(), query: "admin").map(\.id) == ascending)
    }
    #endif

    @Test func codexNextActionMatchesThePriorSortAcrossTiesAndPermutations() {
        let goal = Goal(title: "Selection")
        let tasks = (0..<60).map { index -> AppTask in
            let task = AppTask(title: "Task \(index)")
            task.priority = [.none, .low, .medium, .high][index % 4]
            task.dueDate = index % 3 == 0 ? "" : "2026-10-\(index % 2 == 0 ? "05" : "06")"
            task.scheduledDate = index % 5 == 0 ? "" : "2026-10-07"
            task.order = index % 2
            task.createdAt = Date(timeIntervalSince1970: Double(index % 3))
            return task
        }
        let expected = tasks.sorted { lhs, rhs in
            if lhs.priority.rank != rhs.priority.rank { return lhs.priority.rank > rhs.priority.rank }
            let lhsDue = TaskOrdering.dateSortKey(lhs.dueDate)
            let rhsDue = TaskOrdering.dateSortKey(rhs.dueDate)
            if lhsDue != rhsDue { return lhsDue < rhsDue }
            let lhsDo = TaskOrdering.dateSortKey(lhs.scheduledDate)
            let rhsDo = TaskOrdering.dateSortKey(rhs.scheduledDate)
            if lhsDo != rhsDo { return lhsDo < rhsDo }
            return TaskOrdering.fallbackPrecedes(lhs, rhs)
        }.first
        for input in [tasks, Array(tasks.reversed()), Array(tasks.dropFirst(17)) + tasks.prefix(17)] {
            goal.tasks = input
            let summary = GoalContributionResolver.summary(for: goal)
            #expect(summary.totalTasks == tasks.count)
            #expect(summary.nextActionTitle == expected?.title)
            #expect(summary.nextActionDueDate == expected?.dueDate)
        }
        goal.tasks = []
        #expect(GoalContributionResolver.summary(for: goal).nextActionTitle == nil)
    }

    @Test func codexSearchHoverBodyReadsSelectionOnlyInItsChild() throws {
        let rule = try CadenceScanInstrument(
            "search highlight binding boundary",
            fires: "GlobalSearchHighlightList(sections: sections, highlightedResultID: $highlightedResultID)",
            andNotOn: "// GlobalSearchHighlightList(highlightedResultID: $highlightedResultID)\nGlobalSearchSectionsList(highlightedResultID: highlightedResultID)",
            by: { source in
                let code = CadenceSourceScan.codeOnly(source)
                return code.contains("GlobalSearchHighlightList(") && code.contains("highlightedResultID: $highlightedResultID")
            }
        )
        let paths = ["Cadence/macOS/Views/GlobalSearchView.swift"]
        #expect(try rule.sweep(paths, atLeast: 1, including: paths[0], read: CadenceSourceScan.strippedSourceReader()) == paths)
        let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(paths[0]))
        let parent = try #require(CadenceSourceScan.declarationBody("struct GlobalSearchOverlay: View", in: code))
        #expect(!parent.contains("GlobalSearchSectionsList("))
        #expect(parent.contains("sections: sections"))
        let child = try #require(CadenceSourceScan.declarationBody("struct GlobalSearchHighlightList: View", in: code))
        #expect(child.contains("@Binding var highlightedResultID"))
        #expect(child.contains("onHover: { highlightedResultID = $0 }"))
    }
}

#if os(macOS)
@MainActor @Observable
private final class CodexSearchDerivationProbe {
    var query = ""
    @ObservationIgnored var derivations = 0
    @ObservationIgnored var selection: Binding<String?>?
}

private struct CodexSearchDerivationHost: View {
    let probe: CodexSearchDerivationProbe
    let isolated: Bool
    @State private var highlightedResultID: String?

    private var sections: [GlobalSearchSection] {
        probe.derivations += 1
        return []
    }

    var body: some View {
        Group {
            if isolated {
                GlobalSearchHighlightList(sections: sections, query: probe.query, highlightedResultID: $highlightedResultID, onSelect: { _ in })
            } else {
                GlobalSearchSectionsList(sections: sections, query: probe.query, highlightedResultID: highlightedResultID, onSelect: { _ in }, onHover: { highlightedResultID = $0 })
            }
        }
        .onAppear { probe.selection = $highlightedResultID }
    }
}
#endif
