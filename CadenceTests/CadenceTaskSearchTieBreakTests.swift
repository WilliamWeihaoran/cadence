import Foundation
import Testing
@testable import Cadence

/// [[T-18131]]: a searching Tasks section breaks a score tie on open-before-done, then on the
/// occurrence's date (do date, else due date, newest first), then `recurrenceOccurrenceIndex`
/// descending, and only then title and identity -- through the one comparator Cmd+K and iOS Search
/// both rank with (`CadenceTaskSearchSupport.rankMatches`).
///
/// Every occurrence of a repeating task scores and titles alike, so the old order fell to the
/// identity leg, a UUID. The fixture's UUIDs sort the OPEN occurrence LAST and the done ones
/// oldest first, which is exactly the order the old ranker produced.
struct CadenceTaskSearchTieBreakTests {
    private static func occurrence(_ label: String, uuidSuffix: Int, done: Bool, scheduled: String, index: Int) -> AppTask {
        let task = AppTask(title: "Water the plants")
        task.id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", uuidSuffix))!
        task.status = done ? .done : .todo
        task.scheduledDate = scheduled
        task.recurrenceOccurrenceIndex = index
        task.notes = label
        return task
    }

    /// One series: three done occurrences and the open one, the open one's UUID highest.
    private static func series() -> [AppTask] {
        [
            occurrence("done-1", uuidSuffix: 1, done: true, scheduled: "2026-11-13", index: 0),
            occurrence("done-2", uuidSuffix: 2, done: true, scheduled: "2026-11-14", index: 1),
            occurrence("done-3", uuidSuffix: 3, done: true, scheduled: "2026-11-15", index: 2),
            occurrence("open", uuidSuffix: 4, done: false, scheduled: "2026-11-16", index: 3)
        ]
    }

    private static let expected = ["open", "done-3", "done-2", "done-1"]

    private func rankedLabels(_ tasks: [AppTask]) -> [String] {
        CadenceTaskSearchSupport.rankMatches(
            tasks,
            task: { $0 },
            score: { _ in 10 },
            title: { $0.title },
            identity: { CadenceSearchIdentity.task($0.id) }
        )
        .map(\.notes)
    }

    @Test func theOpenOccurrenceRanksFirstAndDoneOnesNewestFirst() {
        let tasks = Self.series()
        // Non-vacuity: the identity leg alone would put the open occurrence last.
        let identities = tasks.map { CadenceSearchIdentity.task($0.id) }
        #expect(identities == identities.sorted())
        #expect(rankedLabels(tasks) == Self.expected)
        #expect(rankedLabels(tasks.reversed()) == Self.expected)
    }

    @Test func scoreStillLeadsAndTheOrderStaysTotal() {
        let key = { (score: Int, done: Bool, date: String, index: Int, identity: String) in
            CadenceTaskSearchSupport.SearchRankKey(
                score: score, isDone: done, date: date, occurrenceIndex: index, title: "A", identity: identity
            )
        }
        // A better score beats an open occurrence.
        #expect(CadenceTaskSearchSupport.isRankedBefore(key(20, true, "", 0, "z"), key(10, false, "2026-11-16", 0, "a")))
        // A dated task before a dateless one, both open.
        #expect(CadenceTaskSearchSupport.isRankedBefore(key(10, false, "2026-01-01", 0, "z"), key(10, false, "", 0, "a")))
        #expect(!CadenceTaskSearchSupport.isRankedBefore(key(10, false, "", 0, "a"), key(10, false, "2026-01-01", 0, "z")))
        // Same date: the later occurrence of the series first.
        #expect(CadenceTaskSearchSupport.isRankedBefore(key(10, true, "2026-01-01", 5, "z"), key(10, true, "2026-01-01", 4, "a")))
        // Everything equal but identity: identity ascending, and irreflexive.
        #expect(CadenceTaskSearchSupport.isRankedBefore(key(10, true, "", 0, "a"), key(10, true, "", 0, "b")))
        #expect(!CadenceTaskSearchSupport.isRankedBefore(key(10, true, "", 0, "a"), key(10, true, "", 0, "a")))
    }

    /// Open before done is its own leg, not a side effect of the date one: an open task whose do
    /// date has passed still outranks a done one dated after it (the fixture above dates the open
    /// occurrence newest, so on its own it cannot tell the two legs apart).
    @Test func anOpenTaskOutranksADoneOneDatedAfterIt() {
        let overdue = Self.occurrence("open-overdue", uuidSuffix: 2, done: false, scheduled: "2026-11-01", index: 0)
        let doneLater = Self.occurrence("done-later", uuidSuffix: 1, done: true, scheduled: "2026-11-15", index: 1)
        #expect(rankedLabels([doneLater, overdue]) == ["open-overdue", "done-later"])
        #expect(rankedLabels([overdue, doneLater]) == ["open-overdue", "done-later"])
    }

    /// The due date stands in when there is no do date.
    @Test func theDueDateStandsInForAMissingDoDate() {
        // The identity leg would put "older" first, so the date leg is what decides.
        let older = Self.occurrence("older", uuidSuffix: 1, done: true, scheduled: "", index: 0)
        older.dueDate = "2026-10-01"
        let newer = Self.occurrence("newer", uuidSuffix: 2, done: true, scheduled: "", index: 0)
        newer.dueDate = "2026-10-02"
        #expect(rankedLabels([older, newer]) == ["newer", "older"])
    }

    #if os(macOS)
    /// The Mac palette's real path: `taskResults` with Completed on.
    @Test func cmdKListsTheOpenOccurrenceFirst() {
        let tasks = Self.series()
        let results = GlobalSearchIndexSupport.taskResults(
            tasks: tasks, query: "water", includingCompleted: true, today: "2026-11-16"
        )
        let byID = Dictionary(uniqueKeysWithValues: tasks.map { (CadenceSearchIdentity.task($0.id), $0.notes) })
        #expect(results.map { byID[$0.id] ?? "?" } == Self.expected)
    }
    #endif

    /// **Source census.** Both surfaces rank tasks through the shared comparator, not the generic
    /// funnel ([[T-8201]]: one rule on both platforms).
    @Test func bothSurfacesRankTasksThroughTheSharedComparator() throws {
        let mac = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/GlobalSearchIndexSupport.swift")
        )
        let macBody = try #require(CadenceSourceScan.functionBody(named: "taskResults", in: mac))
        #expect(macBody.contains("CadenceTaskSearchSupport.rankMatches("))
        #expect(!macBody.contains("rankedByScore("))

        let iOS = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSearchView.swift")
        )
        #expect(iOS.contains("private var rankedTaskResults"))
        #expect(CadenceSourceScan.matchCount("CadenceTaskSearchSupport\\.rankMatches\\(", in: iOS) == 1)
    }
}
