// Compiled for macOS only: the palette half (`GlobalSearchIndexSupport`) is a macOS type, and the
// iOS half is pinned by scanning `iOSSearchView.swift`, which this bundle cannot call.
#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **One idle rule behind both search surfaces** ([[T-8764]]).
///
/// With nothing typed, iOS Search suggested today's and overdue open work and the most recently
/// edited notes, while Cmd+K ranked an empty query — every row scored alike, the tie broke on title,
/// and the palette listed tasks and notes A to Z. Both now read `CadenceSearchIdleSuggestions`.
///
/// Every fixture title is chosen so that the alphabetical order and the suggestion order disagree,
/// so a palette that fell back to ranking fails on order, not merely on membership.
@MainActor
struct CadenceSearchIdleSuggestionTests {

    private static let today = "2026-10-30"

    private func task(
        _ title: String,
        due: String = "",
        scheduled: String = "",
        order: Int = 0,
        status: TaskStatus? = nil
    ) -> AppTask {
        let task = AppTask(title: title)
        task.dueDate = due
        task.scheduledDate = scheduled
        task.order = order
        if let status { task.status = status }
        return task
    }

    private struct TaskFixture {
        let all: [AppTask]
        /// The suggestion order, written out by hand rather than derived from the rule under test.
        let expected: [AppTask]
    }

    private func makeTaskFixture() -> TaskFixture {
        let overdueEarly = task("Zebra overdue", due: "2026-10-01")
        let overdueLateFirst = task("Yak overdue", due: "2026-10-20", order: 1)
        let overdueLateSecond = task("Xylophone overdue", due: "2026-10-20", order: 2)
        let dueToday = task("Walrus due today", due: Self.today)
        let scheduledTodayDueLater = task("Vulture scheduled", due: "2026-11-15", scheduled: Self.today)
        let scheduledTodayUndated = task("Umbrella scheduled", scheduled: Self.today)
        // Not suggested: future, undated, finished, cancelled.
        let future = task("Aardvark future", due: "2026-12-01")
        let undated = task("Badger undated")
        let done = task("Cat done", due: "2026-10-01", status: .done)
        let cancelled = task("Dog cancelled", scheduled: Self.today, status: .cancelled)

        return TaskFixture(
            all: [future, scheduledTodayUndated, done, overdueLateSecond, undated, dueToday,
                  cancelled, overdueEarly, scheduledTodayDueLater, overdueLateFirst],
            expected: [overdueEarly, overdueLateFirst, overdueLateSecond, dueToday,
                       scheduledTodayDueLater, scheduledTodayUndated]
        )
    }

    // MARK: - The shared rule

    @Test func theSharedRuleSuggestsTodayAndOverdueOpenWorkByDueDateThenOrder() {
        let fixture = makeTaskFixture()
        let suggested = CadenceSearchIdleSuggestions.tasks(fixture.all, today: Self.today)
        #expect(suggested.map(\.id) == fixture.expected.map(\.id))
        // The window is the rule's order cut, not a different selection.
        let window = CadenceSearchIdleSuggestions.tasks(fixture.all, today: Self.today, limit: 3)
        #expect(window.map(\.id) == Array(fixture.expected.prefix(3)).map(\.id))
        #expect(CadenceSearchIdleSuggestions.limit == 8)
    }

    @Test func theSharedRuleOrdersNotesMostRecentlyEditedFirst() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let oldest = Note(kind: .permanent, title: "Alpha", updatedAt: base)
        let newest = Note(kind: .permanent, title: "Charlie", updatedAt: base.addingTimeInterval(200))
        let middle = Note(kind: .permanent, title: "Bravo", updatedAt: base.addingTimeInterval(100))

        let suggested = CadenceSearchIdleSuggestions.notes([oldest, newest, middle])
        #expect(suggested.map(\.id) == [newest.id, middle.id, oldest.id])
    }

    // MARK: - The palette reads it

    @Test func anEmptyPaletteQuerySuggestsTheSharedTaskWindowNotAnAlphabeticalOne() {
        let fixture = makeTaskFixture()
        let shared = CadenceSearchIdleSuggestions.tasks(fixture.all, today: Self.today).map {
            CadenceSearchIdentity.task($0.id)
        }

        for query in ["", "   "] {
            let palette = GlobalSearchIndexSupport.taskResults(tasks: fixture.all, query: query, today: Self.today)
            #expect(palette.map(\.id) == shared, "query \"\(query)\"")
        }
        // The Completed filter widens a search, not the suggestions.
        let withCompleted = GlobalSearchIndexSupport.taskResults(
            tasks: fixture.all, query: "", includingCompleted: true, today: Self.today
        )
        #expect(withCompleted.map(\.id) == shared)

        // Non-vacuity: the alphabetical answer this ticket replaced is a different list.
        let alphabetical = fixture.all.sorted { $0.title < $1.title }.map { CadenceSearchIdentity.task($0.id) }
        #expect(Array(alphabetical.prefix(shared.count)) != shared)

        // Searching still ranks: a query reaches a task the idle rule would never suggest.
        let searched = GlobalSearchIndexSupport.taskResults(tasks: fixture.all, query: "aardvark", today: Self.today)
        #expect(searched.count == 1)
        #expect(searched.first?.title == "Aardvark future")
    }

    @Test func anEmptyPaletteQuerySuggestsTheMostRecentlyEditedNotes() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let notes = (0..<12).map { index in
            // Title order runs opposite to edit order.
            Note(kind: .permanent, title: "Note \(String(format: "%02d", index))",
                 updatedAt: base.addingTimeInterval(Double(index)))
        }
        let shared = CadenceSearchIdleSuggestions.notes(notes).map { CadenceSearchIdentity.note($0.id) }
        let palette = GlobalSearchIndexSupport.noteResults(notes: notes, query: "", taskTitles: [:])

        #expect(palette.count == 12)
        #expect(palette.map(\.id) == shared)
        #expect(palette.first?.title == "Note 11")
        // The first window the palette draws is the same eight iOS draws.
        let cap = GlobalSearchIndexSupport.resultCap(for: .notes, query: "")
        #expect(cap == CadenceSearchIdleSuggestions.limit)
        #expect(Array(palette.prefix(cap)).map(\.id)
            == CadenceSearchIdleSuggestions.notes(notes, limit: CadenceSearchIdleSuggestions.limit)
                .map { CadenceSearchIdentity.note($0.id) })
    }

    @Test func anEmptyPaletteQuerySuggestsTheMostRecentlyEditedEventNotes() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let older = Note(kind: .meeting, title: "Alpha sync", updatedAt: base)
        let newer = Note(kind: .meeting, title: "Zulu sync", updatedAt: base.addingTimeInterval(60))
        let idle = GlobalSearchIndexSupport.eventNoteResults(notes: [older, newer], query: "", taskTitles: [:])
        #expect(idle.map(\.destination) == [.eventNote(newer.id), .eventNote(older.id)])

        let searched = GlobalSearchIndexSupport.eventNoteResults(notes: [older, newer], query: "sync", taskTitles: [:])
        #expect(Set(searched.map(\.id)) == [CadenceSearchIdentity.eventNote(newer.id), CadenceSearchIdentity.eventNote(older.id)])
    }

    // MARK: - iOS reads it (source shape: `Cadence/iOS/` is behind `#if os(iOS)`)

    @Test func iOSSearchCutsItsIdleTaskAndNoteWindowsFromTheSharedRule() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSearchView.swift")
        let code = CadenceSourceScan.codeOnly(raw)
        #expect(code != raw)
        #expect(code.contains("struct iOSSearchView"))

        #expect(CadenceSourceScan.matchCount(#"CadenceSearchIdleSuggestions\.tasks\("#, in: code) == 1)
        #expect(CadenceSourceScan.matchCount(#"CadenceSearchIdleSuggestions\.notes\("#, in: code) == 1)
        #expect(CadenceSourceScan.matchCount(#"limit: CadenceSearchIdleSuggestions\.limit"#, in: code) == 2)
        // The hand-rolled task predicate the shared rule replaced.
        #expect(!code.contains("$0.scheduledDate == today"))
    }
}
#endif
