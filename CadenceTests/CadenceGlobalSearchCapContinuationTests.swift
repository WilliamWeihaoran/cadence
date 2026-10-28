// T-3244: compiled for macOS only. `CadenceTests` now also builds for an iOS destination, and
// this suite reaches macOS-only app types that do not exist there. The gate preserves exactly the
// coverage this file had before; narrowing it so any cross-platform half runs on iOS too is
// follow-up, not part of making the target iOS-capable.
#if os(macOS)
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

    /// **The keyboard must walk the rows that are on screen, continuation rows included**
    /// (T-1473, T-4320). `keyboardRows` drives the arrow keys, the highlight sync and Return; if it
    /// flattened the uncapped section, Down-arrow would move the highlight onto a row the list is
    /// not drawing. And if it left the "N more results" row out — as it did until T-4320 — the
    /// reveal was mouse-only: Down from the last visible result stayed on it.
    @Test func arrowKeyOrderCoversExactlyTheVisibleRowsAndGrowsWhenASectionIsRevealed() throws {
        let built = sections(tasks: roadmapTasks(count: 20, completedCount: 0), notes: roadmapNotes(count: 18), query: "roadmap", includesCompleted: false)
        let collapsedSections = GlobalSearchDataSupport.visibleSections(from: built, expandedCategories: [])
        let expandedSections = GlobalSearchDataSupport.visibleSections(from: built, expandedCategories: [GlobalSearchCategory.notes.rawValue])

        let collapsed = GlobalSearchOverlayStateSupport.keyboardRows(from: collapsedSections)
        let expanded = GlobalSearchOverlayStateSupport.keyboardRows(from: expandedSections)

        // The exact order: each section's visible results, then its continuation row if capped.
        let expectedOrder = collapsedSections.flatMap { section -> [String] in
            section.results.map(\.id)
                + (section.hidden == nil ? [] : [GlobalSearchKeyboardRow.continuationID(forSection: section.id)])
        }
        #expect(collapsed.map(\.id) == expectedOrder)
        // Two capped sections (Tasks 14 of 20, Notes 12 of 18), so exactly two continuation stops.
        #expect(collapsed.filter { if case .moreResults = $0 { true } else { false } }.count == 2)

        // The results on the path are exactly the drawn ones, never a withheld one.
        let visibleIDs = Set(collapsedSections.flatMap(\.results).map(\.id))
        let pathResultIDs = collapsed.compactMap { row -> String? in
            if case .result(let result) = row { result.id } else { nil }
        }
        #expect(Set(pathResultIDs) == visibleIDs)
        #expect(pathResultIDs.count == visibleIDs.count)

        // Revealing Notes adds its six rows and removes its continuation stop: +6 - 1.
        #expect(expanded.count == collapsed.count + 5)
        let notesContinuation = GlobalSearchKeyboardRow.continuationID(forSection: GlobalSearchCategory.notes.rawValue)
        #expect(!expanded.contains { $0.id == notesContinuation })

        // Down from the last visible Tasks result lands on the Tasks continuation row, and Up from
        // there returns to that same result.
        let tasksSection = try #require(collapsedSections.first { $0.category == .tasks })
        let lastTask = try #require(tasksSection.results.last)
        let tasksContinuation = GlobalSearchKeyboardRow.continuationID(forSection: tasksSection.id)
        #expect(
            GlobalSearchOverlayStateSupport.moveHighlight(direction: .down, currentID: lastTask.id, rows: collapsed) == tasksContinuation
        )
        #expect(
            GlobalSearchOverlayStateSupport.moveHighlight(direction: .up, currentID: tasksContinuation, rows: collapsed) == lastTask.id
        )
        // A highlight resting on a continuation row survives a re-sync rather than snapping to the top.
        #expect(GlobalSearchOverlayStateSupport.syncedHighlightID(current: tasksContinuation, rows: collapsed) == tasksContinuation)
        // And the end of the path still stops rather than wrapping or walking off it.
        let last = try #require(collapsed.last)
        #expect(
            GlobalSearchOverlayStateSupport.moveHighlight(direction: .down, currentID: last.id, rows: collapsed) == last.id
        )
    }

    /// **Return on the continuation row reveals and selects nothing** (T-4320); Return on a result
    /// still selects it and reveals nothing.
    @Test func returnOnTheContinuationRowRevealsTheSectionAndDoesNotSelect() throws {
        let built = sections(tasks: roadmapTasks(count: 20, completedCount: 0), notes: [], query: "roadmap", includesCompleted: false)
        let rows = GlobalSearchOverlayStateSupport.keyboardRows(
            from: GlobalSearchDataSupport.visibleSections(from: built, expandedCategories: [])
        )
        let tasksID = GlobalSearchCategory.tasks.rawValue

        var selected: [String] = []
        var revealed: [String] = []
        GlobalSearchInteractionSupport.submitHighlightedResult(
            highlightedResultID: GlobalSearchKeyboardRow.continuationID(forSection: tasksID),
            rows: rows,
            onSelect: { selected.append($0.id) },
            onReveal: { revealed.append($0) }
        )
        #expect(revealed == [tasksID])
        #expect(selected.isEmpty)

        let firstResult = try #require(rows.first)
        selected.removeAll()
        revealed.removeAll()
        GlobalSearchInteractionSupport.submitHighlightedResult(
            highlightedResultID: firstResult.id,
            rows: rows,
            onSelect: { selected.append($0.id) },
            onReveal: { revealed.append($0) }
        )
        #expect(selected == [firstResult.id])
        #expect(revealed.isEmpty)
    }

    /// After a reveal the highlight lands on the first newly revealed result — the fifteenth task,
    /// which now sits where the continuation row was.
    @Test func revealingASectionHighlightsItsFirstNewlyRevealedResult() throws {
        let built = sections(tasks: roadmapTasks(count: 20, completedCount: 0), notes: [], query: "roadmap", includesCompleted: false)
        let tasksID = GlobalSearchCategory.tasks.rawValue
        let before = GlobalSearchDataSupport.visibleSections(from: built, expandedCategories: [])
        let after = GlobalSearchDataSupport.visibleSections(from: built, expandedCategories: [tasksID])
        let fullTasks = try section(.tasks, in: built)

        let target = GlobalSearchOverlayStateSupport.firstRevealedResultID(sectionID: tasksID, before: before, after: after)
        #expect(target == fullTasks.results[14].id)
        // An uncapped section reveals nothing, so there is nowhere new to land.
        #expect(GlobalSearchOverlayStateSupport.firstRevealedResultID(sectionID: tasksID, before: after, after: after) == nil)
    }

    /// **The row the keyboard is on has to look like it** (T-4320). A view the suite does not host
    /// cannot be asked what it drew, so this pins the wiring: the list hands the continuation row
    /// the highlight under the same id `keyboardRows` uses, hover moves the highlight there just as
    /// it does for a result, and the row's body actually branches on the flag.
    @Test func theContinuationRowDrawsTheKeyboardHighlightAndTakesHover() throws {
        let list = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/GlobalSearchOverlayShellViews.swift"))
        #expect(list.contains("let continuationID = GlobalSearchKeyboardRow.continuationID(forSection: section.id)"))
        #expect(list.contains("isHighlighted: highlightedResultID == continuationID"))
        #expect(list.contains("onHover: { onHover(continuationID) }"))

        let views = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/GlobalSearchSupportViews.swift"))
        let row = try #require(
            CadenceSourceScan.declarationBody("struct GlobalSearchMoreResultsRow", in: views),
            "could not read GlobalSearchMoreResultsRow"
        )
        #expect(row.contains("let isHighlighted: Bool"))
        #expect(CadenceSourceScan.matchCount("isHighlighted \\?", in: row) == 2)
        #expect(row.contains("if hovering { onHover() }"))
    }

    /// **[[T-8063]] — the list follows the keyboard highlight.** The palette is a fixed-height
    /// card, so an arrow move past the rows that fit left the highlight off-screen. Pinned as wiring,
    /// as `MarkdownSlashCommandPickerMetricsTests` pins the slash menu's: the list sits in a
    /// `ScrollViewReader`, scrolls to the highlight on every change, and tags both kinds of row the
    /// highlight can name with exactly that id.
    @Test func theSectionsListScrollsTheHighlightedRowIntoView() throws {
        let file = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/GlobalSearchOverlayShellViews.swift"))
        let list = try #require(
            CadenceSourceScan.declarationBody("struct GlobalSearchSectionsList: View", in: file),
            "could not read GlobalSearchSectionsList"
        ).filter { !$0.isWhitespace }
        #expect(list.contains("ScrollViewReader{proxyin"))
        #expect(list.contains(".onChange(of:highlightedResultID){_,_inscrollToHighlighted(proxy)}"),
                "an arrow move, hover or reveal must scroll the highlighted row into view")
        #expect(list.contains(".onAppear{scrollToHighlighted(proxy)}"))
        #expect(list.contains("proxy.scrollTo(highlightedResultID)"))
        #expect(list.contains(".id(result.id)"), "scrollTo needs each result row tagged with its id")
        #expect(list.contains(".id(continuationID)"), "scrollTo needs the continuation row tagged with its keyboard id")
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
        // [[T-6971]]'s `withheldCompletedTaskMatchCount` is carved out: it asks the widened
        // question on purpose, to count what the filter is holding back, and builds no rows.
        let index = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/GlobalSearchIndexSupport.swift"))
        let withheldStart = try #require(index.range(of: "static func withheldCompletedTaskMatchCount("))
        let withheldEnd = try #require(index.range(of: "static func taskIcon(", range: withheldStart.upperBound..<index.endIndex))
        var rowBuilders = index
        rowBuilders.removeSubrange(withheldStart.lowerBound..<withheldEnd.lowerBound)
        #expect(CadenceSourceScan.matchCount("includingCompleted: true", in: rowBuilders) == 0)
        #expect(rowBuilders.contains("includingCompleted: includingCompleted"))
    }

    /// The four `*Results` functions must not hand back a prefix again. This is the assertion that
    /// would have caught the original defect, and it is written against the file because the shape
    /// — "returns a truncated array" — is what the ticket forbids, not any one number.
    @Test func noSearchSectionBuilderTruncatesItsOwnResults() throws {
        let index = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/GlobalSearchIndexSupport.swift"))

        #expect(CadenceSourceScan.matchCount("\\.prefix\\(", in: index) == 0)
        #expect(index.contains("static func resultCap(for category: GlobalSearchCategory, query: String) -> Int"))
    }

    // MARK: - T-6971: an empty result set says when Completed is holding matches back

    /// The count the empty state reads is exactly the rows turning Completed on would add: the
    /// finished matches, never the active ones, never a cancelled one, never a non-match — and
    /// zero once the filter is on or the field is blank, so nothing is claimed to be hidden.
    @Test func withheldCompletedCountIsExactlyTheRowsTheFilterWouldAdd() {
        let tasks = roadmapTasks(count: 6, completedCount: 3)
        let cancelled = AppTask(title: "Roadmap cancelled")
        cancelled.status = .cancelled
        let unrelatedDone = AppTask(title: "Invoice")
        unrelatedDone.status = .done
        let all = tasks + [cancelled, unrelatedDone]

        let withheld = GlobalSearchIndexSupport.withheldCompletedTaskMatchCount(tasks: all, query: "roadmap", includingCompleted: false)
        let excluded = GlobalSearchIndexSupport.taskResults(tasks: all, query: "roadmap", includingCompleted: false)
        let included = GlobalSearchIndexSupport.taskResults(tasks: all, query: "roadmap", includingCompleted: true)

        #expect(withheld == 3)
        #expect(withheld == included.count - excluded.count)
        #expect(GlobalSearchIndexSupport.withheldCompletedTaskMatchCount(tasks: all, query: "roadmap", includingCompleted: true) == 0)
        #expect(GlobalSearchIndexSupport.withheldCompletedTaskMatchCount(tasks: all, query: "  ", includingCompleted: false) == 0)
    }

    /// The reported defect: every match finished, Completed off, and the palette said "No matches
    /// found — try a cleaner title". It now names the count and the control, singular and plural,
    /// and keeps the ordinary advice when nothing is held back.
    @Test func emptyStateNamesWithheldCompletedMatchesAndTheFilter() {
        let finished = roadmapTasks(count: 2, completedCount: 2)
        let sections = sections(tasks: finished, notes: [], query: "roadmap", includesCompleted: false)
        #expect(!sections.contains { $0.category == .tasks })

        let count = GlobalSearchIndexSupport.withheldCompletedTaskMatchCount(tasks: finished, query: "roadmap", includingCompleted: false)
        #expect(GlobalSearchEmptyState.subtitle(query: "roadmap", withheldCompletedTaskCount: count)
            == "2 completed tasks match. Turn on Completed to show them.")
        #expect(GlobalSearchEmptyState.subtitle(query: "roadmap", withheldCompletedTaskCount: 1)
            == "1 completed task matches. Turn on Completed to show it.")

        let ordinary = GlobalSearchEmptyState.subtitle(query: "roadmap", withheldCompletedTaskCount: 0)
        #expect(!ordinary.contains("Completed"))
        #expect(!ordinary.contains("cleaner"))
    }

    /// Declared and reached: the overlay must hand the count down to the empty state, or the hint
    /// is a sentence nothing ever draws.
    @Test func overlayPassesTheWithheldCountToTheEmptyState() throws {
        let shell = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/GlobalSearchOverlayShellViews.swift"))
        #expect(shell.contains("GlobalSearchEmptyState(query: query, withheldCompletedTaskCount: withheldCompletedTaskCount)"))
        let view = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/GlobalSearchView.swift"))
        #expect(CadenceSourceScan.matchCount("withheldCompletedTaskCount: withheldCompletedTaskCount", in: view) == 2)
        #expect(view.contains("GlobalSearchIndexSupport.withheldCompletedTaskMatchCount("))
    }
}

#endif
