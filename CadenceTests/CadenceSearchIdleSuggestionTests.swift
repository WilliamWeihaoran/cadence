// Compiled for macOS only: the palette half (`GlobalSearchIndexSupport`) is a macOS type, and the
// iOS half is pinned by scanning `iOSSearchView.swift`, which this bundle cannot call.
#if os(macOS)
import Foundation
import SwiftData
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

    /// **[[T-14011]]: work planned for an earlier day and never done is suggested** -- Today's
    /// Leftover -- because Today lists it. The rule had no past-do arm, so such a task sat on Today
    /// and was missing from both search surfaces' idle Tasks list. Due-dated work still leads; a
    /// past-do task with no due date sorts with the other undated rows, by manual order.
    @Test func workPlannedForAnEarlierDayAndNeverDoneIsSuggestedAsTodayListsIt() {
        let leftover = task("Leftover from yesterday", scheduled: "2026-10-29", order: 0)
        let leftoverDoneOnTime = task("Finished leftover", scheduled: "2026-10-29", status: .done)
        let leftoverCancelled = task("Dropped leftover", scheduled: "2026-10-28", status: .cancelled)
        let dueToday = task("Due today", due: Self.today)
        let doToday = task("Do today", scheduled: Self.today, order: 1)
        let tomorrow = task("Tomorrow", scheduled: "2026-10-31")
        let all = [tomorrow, doToday, leftoverCancelled, leftover, leftoverDoneOnTime, dueToday]

        // Membership is Today's own, task by task.
        for candidate in all {
            #expect(
                CadenceSearchIdleSuggestions.isSuggested(candidate, today: Self.today)
                    == candidate.isTodayWork(todayKey: Self.today),
                "\(candidate.title)"
            )
        }
        #expect(CadenceSearchIdleSuggestions.isSuggested(leftover, today: Self.today))

        let suggested = CadenceSearchIdleSuggestions.tasks(all, today: Self.today)
        #expect(suggested.map(\.id) == [dueToday.id, leftover.id, doToday.id])

        // The palette's idle Tasks section reads the same list.
        let palette = GlobalSearchIndexSupport.taskResults(tasks: all, query: "", today: Self.today)
        #expect(palette.map(\.id).contains(CadenceSearchIdentity.task(leftover.id)))
        #expect(palette.count == 3)
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

    // MARK: - [[T-11194]]: lists, pages and commands idle in one order, and event notes excerpt

    private struct ListFixture {
        let container: ModelContainer
        let areas: [Area]
        let projects: [Project]
    }

    /// Manual order runs opposite to title order in both tables, and two areas tie on `order` so the
    /// identity leg has something to decide.
    private func makeListFixture() throws -> ListFixture {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let home = Context(name: "Home")
        modelContext.insert(home)
        let areaZulu = Area(name: "Zulu area", context: home)
        areaZulu.order = 0
        let areaYankeeA = Area(name: "Yankee area", context: home)
        areaYankeeA.order = 1
        let areaYankeeB = Area(name: "Xray area", context: home)
        areaYankeeB.order = 1
        let projectWhiskey = Project(name: "Whiskey project", context: home)
        projectWhiskey.order = 0
        let projectAlpha = Project(name: "Alpha project", context: home)
        projectAlpha.order = 5
        for model in [areaZulu, areaYankeeA, areaYankeeB] { modelContext.insert(model) }
        for model in [projectWhiskey, projectAlpha] { modelContext.insert(model) }
        try modelContext.save()
        return ListFixture(
            container: container,
            areas: [areaYankeeB, areaZulu, areaYankeeA],
            projects: [projectAlpha, projectWhiskey]
        )
    }

    @Test func theSharedListRuleIsAreasThenProjectsInTheUsersOrderTiesOnIdentity() throws {
        let fixture = try makeListFixture()
        let areas = fixture.areas
        let tied = [areas[0], areas[2]].sorted { $0.id.uuidString < $1.id.uuidString }
        let expectedAreas = [areas[1]] + tied
        let expectedProjects = [fixture.projects[1], fixture.projects[0]]

        let all = CadenceSearchIdleSuggestions.lists(areas: fixture.areas, projects: fixture.projects)
        #expect(all.areas.map(\.id) == expectedAreas.map(\.id))
        #expect(all.projects.map(\.id) == expectedProjects.map(\.id))

        // One window across both kinds: four rows is all three areas and the first project.
        let window = CadenceSearchIdleSuggestions.lists(areas: fixture.areas, projects: fixture.projects, limit: 4)
        #expect(window.areas.map(\.id) == expectedAreas.map(\.id))
        #expect(window.projects.map(\.id) == [expectedProjects[0].id])
    }

    @Test func anEmptyPaletteQueryListsAreasAndProjectsInTheUsersOrderNotAToZ() throws {
        let fixture = try makeListFixture()
        let shared = CadenceSearchIdleSuggestions.lists(areas: fixture.areas, projects: fixture.projects)

        for query in ["", "   "] {
            let areas = GlobalSearchIndexSupport.areaResults(areas: fixture.areas, query: query)
            let projects = GlobalSearchIndexSupport.projectResults(projects: fixture.projects, query: query)
            #expect(areas.map(\.id) == shared.areas.map { CadenceSearchIdentity.area($0.id) }, "query \"\(query)\"")
            #expect(projects.map(\.id) == shared.projects.map { CadenceSearchIdentity.project($0.id) }, "query \"\(query)\"")
        }
        // Non-vacuity: A to Z, which the palette drew before, is a different list for both kinds.
        let idleAreas = GlobalSearchIndexSupport.areaResults(areas: fixture.areas, query: "")
        #expect(idleAreas.map(\.title) != idleAreas.map(\.title).sorted())
        let idleProjects = GlobalSearchIndexSupport.projectResults(projects: fixture.projects, query: "")
        #expect(idleProjects.map(\.title) == ["Whiskey project", "Alpha project"])

        // Searching still ranks.
        let searched = GlobalSearchIndexSupport.projectResults(projects: fixture.projects, query: "alpha")
        #expect(searched.map(\.title) == ["Alpha project"])
    }

    @Test func anEmptyPaletteQueryListsPagesAndCommandsInCatalogOrder() {
        let pages = GlobalSearchIndexSupport.pageResults(query: "", hiddenTabs: [], sidebarTabColorsRaw: "")
        let expectedPages = CadenceFeatureDestination.searchPages.filter { $0.macSidebarItem != nil }
        #expect(pages.map(\.title) == expectedPages.map(\.title))
        #expect(pages.count == 7, "read \(pages.count) idle page rows")
        // The one destination the palette leaves out is the routing fact, and nothing else.
        #expect(Set(CadenceFeatureDestination.searchPages).subtracting(expectedPages) == [.lists])
        #expect(!CadenceFeatureDestination.searchPages.contains(.search))
        #expect(pages.map(\.title) != pages.map(\.title).sorted(), "the idle Pages section reads A to Z again")

        let commands = GlobalSearchIndexSupport.commandResults(query: "", sidebarTabColorsRaw: "")
        #expect(commands.map(\.title) == GlobalSearchCommandDefinition.all.map(\.title))
        #expect(commands.first?.title == "New Task")

        // Searching still ranks: an exact title beats the catalog's first row.
        #expect(GlobalSearchIndexSupport.pageResults(query: "settings", hiddenTabs: [], sidebarTabColorsRaw: "").first?.title == "Settings")
    }

    @Test func aPaletteEventNoteRowCarriesTheSharedBodyExcerpt() {
        let note = Note(kind: .meeting, title: "Planning sync", content: "Agree the **launch** date")
        let row = GlobalSearchIndexSupport.eventNoteResults(notes: [note], query: "planning", taskTitles: [:]).first
        #expect(row?.detail == CadenceSearchNoteExcerpt.text(for: note, taskTitles: [:]))
        #expect(row?.detail.isEmpty == false)
        #expect(row?.detail.contains("launch") == true)
        let idle = GlobalSearchIndexSupport.eventNoteResults(notes: [note], query: "", taskTitles: [:]).first
        #expect(idle?.detail == row?.detail)
    }

    // MARK: - iOS reads it (source shape: `Cadence/iOS/` is behind `#if os(iOS)`)

    @Test func iOSSearchCutsItsIdleTaskAndNoteWindowsFromTheSharedRule() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSearchView.swift")
        let code = CadenceSourceScan.codeOnly(raw)
        #expect(code != raw)
        #expect(code.contains("struct iOSSearchView"))

        #expect(CadenceSourceScan.matchCount(#"CadenceSearchIdleSuggestions\.tasks\("#, in: code) == 1)
        #expect(CadenceSourceScan.matchCount(#"CadenceSearchIdleSuggestions\.notes\("#, in: code) == 1)
        // Three: tasks, notes, and the lists window [[T-11194]] moved onto the shared rule.
        #expect(CadenceSourceScan.matchCount(#"limit: CadenceSearchIdleSuggestions\.limit"#, in: code) == 3)
        // The hand-rolled task predicate the shared rule replaced.
        #expect(!code.contains("$0.scheduledDate == today"))
    }

    @Test func iOSSearchCutsItsIdleListsAndPagesFromTheSharedOrder() throws {
        let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSearchView.swift"))
        #expect(code.contains("struct iOSSearchView"))
        #expect(CadenceSourceScan.matchCount(#"CadenceSearchIdleSuggestions\.lists\("#, in: code) == 1)
        #expect(CadenceSourceScan.matchCount(#"CadenceFeatureDestination\.searchPages"#, in: code) == 1)
        // The two the shared order replaced: a window cut from the row candidates, and allCases.
        #expect(!code.contains("CadenceSearchSuggestionWindow.take("))
        #expect(!code.contains("CadenceFeatureDestination.allCases"))
    }
}
#endif
