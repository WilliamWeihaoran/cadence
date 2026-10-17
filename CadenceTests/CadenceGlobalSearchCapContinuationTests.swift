import SwiftUI
import Foundation
import Testing
@testable import Cadence

/// What macOS search holds back, and what it says about it (T-1473), plus which tasks it looks at
/// in the first place (T-1476).
///
/// **Why these two live in one suite.** They are one change. T-1476 makes the Mac stop returning
/// completed tasks, which is the Mac *losing* results it used to give; T-1473 makes the Mac say
/// what it is withholding. Shipping the first alone produces a search that silently hides finished
/// work, which is precisely the defect the second exists to remove — so the pair is asserted
/// together, at the sizes that matter.
///
/// **The sizes matter because the old suites never reached them.** `CadenceSearchResultCapTests`
/// guards the mobile surface, and the macOS assertions that existed pinned the cap *as the length
/// of the returned array* — which is green exactly when the overflow is unreachable. Everything
/// below uses more than fourteen matching tasks and more than twelve matching notes, which is the
/// smallest input that can tell a reported cap from a silent one.
@MainActor
struct CadenceGlobalSearchCapContinuationTests {

    // MARK: - Fixtures

    /// `count` tasks that all match "roadmap", the first `completedCount` of them done.
    ///
    /// **Twenty-and-five is chosen, not arbitrary.** Twenty minus five is fifteen, which is one
    /// past the old fourteen-row cap — so a result of fourteen can only mean truncation, and a
    /// fixture whose active count happened to *be* fourteen could not tell the two apart.
    private func roadmapTasks(count: Int, completedCount: Int) -> [AppTask] {
        (0..<count).map { index in
            let task = AppTask(title: "Roadmap task \(index)")
            if index < completedCount { task.status = .done }
            return task
        }
    }

    private func roadmapNotes(count: Int) -> [Note] {
        (0..<count).map { Note(kind: .permanent, title: "Roadmap followup \($0)") }
    }

    private func sections(tasks: [AppTask], notes: [Note], query: String, includesCompleted: Bool) -> [GlobalSearchSection] {
        GlobalSearchIndexSupport.buildIndexedSource(
            query: query,
            hiddenTabs: [],
            areas: [],
            projects: [],
            tasks: tasks,
            notes: notes,
            eventResults: [],
            sidebarTabColorsRaw: "",
            includesCompletedTasks: includesCompleted
        ).sections
    }

    private func section(_ category: GlobalSearchCategory, in sections: [GlobalSearchSection]) throws -> GlobalSearchSection {
        try #require(sections.first { $0.category == category })
    }

    // MARK: - T-1476: completed tasks are out unless asked for

    @Test func macSearchLeavesCompletedTasksOutUntilTheFilterAsksForThem() throws {
        // Five of the twenty are finished, so each answer is a different *set*, not merely a
        // different length — a filter that returned the same rows either way would still pass a
        // count-only assertion, which is why the sets are compared too.
        let tasks = roadmapTasks(count: 20, completedCount: 5)
        let done = Set(tasks.filter { $0.isDone }.map { CadenceSearchIdentity.task($0.id) })
        #expect(done.count == 5)

        let excluded = GlobalSearchIndexSupport.taskResults(tasks: tasks, query: "roadmap", includingCompleted: false)
        let included = GlobalSearchIndexSupport.taskResults(tasks: tasks, query: "roadmap", includingCompleted: true)

        // Fifteen, not fourteen: one past the old cap, so this cannot pass by truncating.
        #expect(excluded.count == 15)
        #expect(included.count == 20)
        #expect(Set(excluded.map(\.id)).isDisjoint(with: done))
        #expect(done.isSubset(of: Set(included.map(\.id))))
    }

    /// **The default is the decision.** A call site that says nothing gets the owner's answer —
    /// exclude — rather than the `includingCompleted: true` the palette used to hard-code.
    @Test func theDefaultForTaskResultsExcludesCompletedWork() {
        let tasks = roadmapTasks(count: 5, completedCount: 5)

        #expect(GlobalSearchIndexSupport.taskResults(tasks: tasks, query: "roadmap").isEmpty)
        #expect(GlobalSearchIndexSupport.taskResults(tasks: tasks, query: "roadmap", includingCompleted: true).count == 5)
    }

    @Test func theIndexCarriesTheFilterIntoTheTasksSection() throws {
        let tasks = roadmapTasks(count: 20, completedCount: 5)

        let hidden = try section(.tasks, in: sections(tasks: tasks, notes: [], query: "roadmap", includesCompleted: false))
        let shown = try section(.tasks, in: sections(tasks: tasks, notes: [], query: "roadmap", includesCompleted: true))

        #expect(hidden.results.count == 15)
        #expect(shown.results.count == 20)
        // Cancelled work stays unsearchable either way: the filter is a user setting, not a second
        // inclusion policy (T-377).
        let cancelled = AppTask(title: "Roadmap cancelled")
        cancelled.status = .cancelled
        let withCancelled = try section(.tasks, in: sections(tasks: tasks + [cancelled], notes: [], query: "roadmap", includesCompleted: true))
        #expect(!withCancelled.results.contains { $0.id == CadenceSearchIdentity.task(cancelled.id) })
    }

    // MARK: - T-1473: the sections say what they are holding back

    @Test func theTasksSectionReportsTheMatchesPastFourteenAndRevealsThemInPlace() throws {
        // Twenty active matches: six past the cap, which is the number the row has to say.
        let built = sections(tasks: roadmapTasks(count: 20, completedCount: 0), notes: [], query: "roadmap", includesCompleted: false)
        let tasks = try section(.tasks, in: built)

        #expect(tasks.results.count == 20)
        #expect(tasks.cap == 14)

        let collapsed = GlobalSearchDataSupport.visibleSections(from: built, expandedCategories: [])
        let tasksCollapsed = try #require(collapsed.first { $0.category == .tasks })
        #expect(tasksCollapsed.results.count == 14)
        #expect(tasksCollapsed.hidden == 6)
        #expect(CadenceSearchResultCap.continuationLabel(hidden: 6) == "6 more results")

        let expanded = GlobalSearchDataSupport.visibleSections(from: built, expandedCategories: [tasks.id])
        let tasksExpanded = try #require(expanded.first { $0.category == .tasks })
        #expect(tasksExpanded.results.count == 20)
        #expect(tasksExpanded.hidden == nil)
        // Expanding reveals the whole remainder rather than another capful, which is what the row
        // promised when it named the number.
        #expect(tasksExpanded.results.map(\.id) == tasks.results.map(\.id))
    }

    @Test func theNotesSectionReportsTheMatchesPastTwelve() throws {
        let built = sections(tasks: [], notes: roadmapNotes(count: 18), query: "roadmap", includesCompleted: false)
        let notes = try section(.notes, in: built)

        #expect(notes.results.count == 18)
        #expect(notes.cap == 12)

        let collapsed = try #require(
            GlobalSearchDataSupport.visibleSections(from: built, expandedCategories: []).first { $0.category == .notes }
        )
        #expect(collapsed.results.count == 12)
        #expect(collapsed.hidden == 6)
    }

    /// The Event Notes section truncated at exactly the same numbers and was not named in the
    /// audit. It is fixed in the same change rather than left as the one section that still drops
    /// matches in silence.
    @Test func theEventNotesSectionIsCappedOnTheSameTermsAsOrdinaryNotes() throws {
        let meetings = (0..<18).map { Note(kind: .meeting, title: "Roadmap review \($0)") }
        let built = sections(tasks: [], notes: meetings, query: "roadmap", includesCompleted: false)
        let events = try section(.meetingNotes, in: built)

        #expect(events.results.count == 18)
        #expect(events.cap == 12)
        #expect(GlobalSearchIndexSupport.resultCap(for: .meetingNotes, query: "") == 8)
    }

    @Test func aSectionListingEveryMatchSaysNothingAboutARemainder() throws {
        let built = sections(tasks: roadmapTasks(count: 3, completedCount: 0), notes: [], query: "roadmap", includesCompleted: false)
        let visible = try #require(
            GlobalSearchDataSupport.visibleSections(from: built, expandedCategories: []).first { $0.category == .tasks }
        )

        #expect(visible.results.count == 3)
        // `nil` rather than `0`, so there is no "0 more results" row to draw by accident.
        #expect(visible.hidden == nil)
        #expect(CadenceSearchResultCap.continuationLabel(hidden: 0) == nil)
    }

    /// **The keyboard must walk the rows that are on screen.** `flattenedResults` drives the arrow
    /// keys, the highlight sync and Return; if it flattened the uncapped section, Down-arrow would
    /// move the highlight onto a row the list is not drawing and Return would open something
    /// invisible — a worse bug than the one being fixed.
    @Test func arrowKeyOrderCoversExactlyTheVisibleRowsAndGrowsWhenASectionIsRevealed() throws {
        let built = sections(tasks: roadmapTasks(count: 20, completedCount: 0), notes: roadmapNotes(count: 18), query: "roadmap", includesCompleted: false)

        let collapsed = GlobalSearchOverlayStateSupport.flattenedResults(
            from: GlobalSearchDataSupport.visibleSections(from: built, expandedCategories: [])
        )
        let expanded = GlobalSearchOverlayStateSupport.flattenedResults(
            from: GlobalSearchDataSupport.visibleSections(from: built, expandedCategories: [GlobalSearchCategory.notes.rawValue])
        )

        #expect(!collapsed.isEmpty)
        #expect(expanded.count > collapsed.count)
        // Every flattened row is one the collapsed/expanded sections actually list.
        let visibleIDs = Set(
            GlobalSearchDataSupport.visibleSections(from: built, expandedCategories: []).flatMap(\.results).map(\.id)
        )
        #expect(Set(collapsed.map(\.id)) == visibleIDs)
        // And moving down from the last visible row stays on it rather than walking into a
        // withheld one.
        let last = try #require(collapsed.last)
        #expect(
            GlobalSearchOverlayStateSupport.moveHighlight(direction: .down, currentID: last.id, results: collapsed) == last.id
        )
    }

    // MARK: - Where the numbers live

    @Test func everyCappedCategoryKeepsItsOwnIdleAndLiveNumbers() {
        #expect(GlobalSearchIndexSupport.resultCap(for: .tasks, query: "x") == 14)
        #expect(GlobalSearchIndexSupport.resultCap(for: .tasks, query: "") == 10)
        #expect(GlobalSearchIndexSupport.resultCap(for: .events, query: "x") == 12)
        #expect(GlobalSearchIndexSupport.resultCap(for: .events, query: "") == 6)
        #expect(GlobalSearchIndexSupport.resultCap(for: .notes, query: "x") == 12)
        #expect(GlobalSearchIndexSupport.resultCap(for: .notes, query: "") == 8)
        // The four catalogs that were never capped stay uncapped.
        for category in [GlobalSearchCategory.commands, .pages, .areas, .projects] {
            #expect(GlobalSearchIndexSupport.resultCap(for: category, query: "x") == Int.max)
        }
        // A whitespace-only field is an idle field, which is the answer `eventResults` already
        // gave and the other sections did not.
        #expect(GlobalSearchIndexSupport.resultCap(for: .tasks, query: "   ") == 10)
    }

    // MARK: - The toggle is persisted, on both platforms, under one key

    /// **The source scan is the point, not a shortcut.** What broke T-1476's own ticket text was
    /// that iOS *looked* like it remembered this and did not: `@State private var
    /// includeCompletedTasks = false` resets on every rebuild. A behavioural test cannot see the
    /// difference between `@State` and `@AppStorage` in a view it does not host, so the thing to
    /// pin is that neither surface declares it as view-local state.
    @Test func bothSearchSurfacesPersistTheCompletedFilterUnderTheSharedKey() throws {
        let key = "CadencePreferenceKeys.searchIncludesCompletedTasks"
        for path in ["Cadence/iOS/iOSSearchView.swift", "Cadence/macOS/Views/GlobalSearchView.swift"] {
            let source = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            #expect(source.contains("@AppStorage(\(key))"), "\(path) must read the shared key")
            #expect(
                CadenceSourceScan.matchCount("@State private var includes?CompletedTasks", in: source) == 0,
                "\(path) must not keep the completed filter in view-local state"
            )
        }
        // One spelling, declared once, so the two surfaces cannot drift onto different keys.
        // The declaration is checked as *code* and its value behaviourally: `codeOnly` blanks
        // string literals along with comments, so a scan for the stored string would be asserting
        // against a run of spaces.
        let keys = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/Shared/CadencePreferenceKeys.swift"))
        #expect(keys.contains("static let searchIncludesCompletedTasks"))
        // The raw value is on disk on the owner's devices; renaming it silently resets the
        // preference rather than migrating it, which is the warning this file already carries.
        #expect(CadencePreferenceKeys.searchIncludesCompletedTasks == "searchIncludesCompletedTasks")
    }

    /// macOS is losing results it used to return, so the control that gets them back ships in the
    /// same change — and in the palette, not in Settings: a filter you cannot see from the list it
    /// is filtering is how a search comes to look broken.
    @Test func theMacPaletteDrawsItsOwnCompletedFilterBesideTheField() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/GlobalSearchSupportViews.swift")
        let views = CadenceSourceScan.codeOnly(raw)

        #expect(views.contains("struct GlobalSearchCompletedFilterToggle"))
        // Declared AND reached: a control nothing builds is not a control.
        #expect(views.contains("GlobalSearchCompletedFilterToggle("))
        // The word the user reads, checked against the raw file — `codeOnly` blanks string
        // literals, so this one assertion cannot be made against the stripped text.
        #expect(raw.contains("Text(\"Completed\")"))
        // It hands first responder back, or the palette stops accepting typing after one click.
        #expect(views.contains("restoreFocus()"))

        // And the index no longer decides for itself.
        let index = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/GlobalSearchIndexSupport.swift"))
        #expect(CadenceSourceScan.matchCount("includingCompleted: true", in: index) == 0)
        #expect(index.contains("includingCompleted: includingCompleted"))
    }

    /// The four `*Results` functions must not hand back a prefix again. This is the assertion that
    /// would have caught the original defect, and it is written against the file because the shape
    /// — "returns a truncated array" — is what the ticket forbids, not any one number.
    @Test func noSearchSectionBuilderTruncatesItsOwnResults() throws {
        let index = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/GlobalSearchIndexSupport.swift"))

        #expect(CadenceSourceScan.matchCount("\\.prefix\\(", in: index) == 0)
        #expect(index.contains("static func resultCap(for category: GlobalSearchCategory, query: String) -> Int"))
    }
}
