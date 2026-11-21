import Foundation
import SwiftData
import Testing
@testable import Cadence

/// [[T-7031]]: the list-detail Notes tab's "Task Notes" and event-note sections, and its search and
/// tag filter, are one derivation — `CadenceListRelatedNotes` — that macOS's `ListNotesView` and the
/// iPad's `iOSListNotesView` both read. The first half pins the derivation as values; the second
/// pins both call sites, because `Cadence/iOS/` does not compile into this macOS target and a view
/// cannot be driven from a unit test.
@Suite(.preservesTheStoredLaunchReports)
@MainActor
struct CadenceListRelatedNotesTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
    }

    private func task(
        _ title: String,
        notes: String,
        status: TaskStatus = .todo,
        area: Area,
        in context: ModelContext
    ) -> AppTask {
        let task = AppTask(title: title)
        task.notes = notes
        task.statusRaw = status.rawValue
        task.area = area
        context.insert(task)
        return task
    }

    // MARK: - Task Notes

    /// Open tasks in this list with non-blank notes, and nothing else: not a done or cancelled task,
    /// not one whose notes are whitespace, not another list's.
    @Test func taskNotesAreThisListsOpenTasksThatCarryNotes() throws {
        let context = try makeContext()
        let area = Area(name: "Home")
        let other = Area(name: "Work")
        context.insert(area)
        context.insert(other)

        let open = task("Open", notes: "Call the plumber", area: area, in: context)
        let started = task("Started", notes: "Halfway", status: .inProgress, area: area, in: context)
        _ = task("Blank", notes: "  \n ", area: area, in: context)
        _ = task("Done", notes: "Finished", status: .done, area: area, in: context)
        _ = task("Cancelled", notes: "Dropped", status: .cancelled, area: area, in: context)
        _ = task("Elsewhere", notes: "Other list", area: other, in: context)
        try context.save()

        let all = try context.fetch(FetchDescriptor<AppTask>())
        let listed = CadenceListRelatedNotes.taskNotes(for: area, project: nil, in: all)
        #expect(Set(listed.map(\.id)) == Set([open.id, started.id]))
        #expect(listed.count == 2)
    }

    // MARK: - Event notes

    /// The linked calendar's meeting notes that have not ended: undated ones always, future days,
    /// and today's only while their end (or start, without an end) is still ahead.
    @Test func eventNotesAreTheLinkedCalendarsNotesThatHaveNotEnded() {
        let calendar = "cal-1"
        let yesterday = Note(kind: .meeting, title: "Yesterday", calendarID: calendar, eventDateKey: "2026-10-25", eventStartMin: 600, eventEndMin: 660)
        let endedToday = Note(kind: .meeting, title: "Ended", calendarID: calendar, eventDateKey: "2026-10-26", eventStartMin: 480, eventEndMin: 540)
        let laterToday = Note(kind: .meeting, title: "Later", calendarID: calendar, eventDateKey: "2026-10-26", eventStartMin: 900, eventEndMin: 960)
        let startOnlyPast = Note(kind: .meeting, title: "StartOnly", calendarID: calendar, eventDateKey: "2026-10-26", eventStartMin: 500)
        let tomorrow = Note(kind: .meeting, title: "Tomorrow", calendarID: calendar, eventDateKey: "2026-10-27")
        let undated = Note(kind: .meeting, title: "Undated", calendarID: calendar)
        let otherCalendar = Note(kind: .meeting, title: "Other", calendarID: "cal-2", eventDateKey: "2026-10-27")
        let notMeeting = Note(kind: .list, title: "List", calendarID: calendar, eventDateKey: "2026-10-27")
        let notes = [yesterday, endedToday, laterToday, startOnlyPast, tomorrow, undated, otherCalendar, notMeeting]

        let listed = CadenceListRelatedNotes.upcomingEventNotes(
            linkedCalendarID: calendar,
            in: notes,
            todayKey: "2026-10-26",
            nowMinutes: 600
        )
        #expect(Set(listed.map(\.id)) == Set([laterToday.id, tomorrow.id, undated.id]))
        #expect(listed.count == 3)

        // No linked calendar lists nothing, whatever the notes say.
        #expect(CadenceListRelatedNotes.upcomingEventNotes(linkedCalendarID: "", in: notes, todayKey: "2026-10-26", nowMinutes: 600).isEmpty)
    }

    /// An area's link is the one read, and it is not merged with a project's.
    @Test func theAreasCalendarLinkWins() {
        let area = Area(name: "Home")
        area.linkedCalendarID = "area-cal"
        let project = Project(name: "Kitchen")
        project.linkedCalendarID = "project-cal"
        #expect(CadenceListRelatedNotes.linkedCalendarID(area: area, project: project) == "area-cal")
        #expect(CadenceListRelatedNotes.linkedCalendarID(area: nil, project: project) == "project-cal")
        #expect(CadenceListRelatedNotes.linkedCalendarID(area: nil, project: nil).isEmpty)
    }

    // MARK: - Search and tag filter

    @Test func searchAndTagsNarrowNotesAndTaskNotes() throws {
        let context = try makeContext()
        let area = Area(name: "Home")
        context.insert(area)
        let urgent = Tag(name: "Urgent")
        context.insert(urgent)

        let plan = Note(kind: .list, title: "Plan", content: "# Plan\n\nbudget figures")
        plan.tags = [urgent]
        let diary = Note(kind: .list, title: "Diary", content: "# Diary\n\nweather")
        context.insert(plan)
        context.insert(diary)

        let tagged = task("Fix sink", notes: "washer size", area: area, in: context)
        tagged.tags = [urgent]
        let untagged = task("Paint", notes: "budget for paint", area: area, in: context)
        try context.save()

        let notes = [plan, diary]
        let taskNotes = [tagged, untagged]

        // No query and no tag: everything.
        #expect(CadenceListRelatedNotes.filter(notes, query: "  ", requiredTagSlugs: [], tasks: []).count == 2)
        #expect(CadenceListRelatedNotes.filter(taskNotes: taskNotes, query: "", requiredTagSlugs: []).count == 2)

        // A query reaches a note's body and a task's notes, case-insensitively.
        #expect(CadenceListRelatedNotes.filter(notes, query: "BUDGET", requiredTagSlugs: [], tasks: []).map(\.id) == [plan.id])
        #expect(CadenceListRelatedNotes.filter(taskNotes: taskNotes, query: "budget", requiredTagSlugs: []).map(\.id) == [untagged.id])

        // A required tag keeps only what carries it.
        let slugs: Set<String> = [urgent.slug]
        #expect(CadenceListRelatedNotes.filter(notes, query: "", requiredTagSlugs: slugs, tasks: []).map(\.id) == [plan.id])
        #expect(CadenceListRelatedNotes.filter(taskNotes: taskNotes, query: "", requiredTagSlugs: slugs).map(\.id) == [tagged.id])

        // [[T-13761]]: a typed tag name reaches a task note as it reaches a note -- neither "Fix
        // sink" nor "washer size" says urgent, only the tag does.
        #expect(CadenceListRelatedNotes.filter(notes, query: "urgent", requiredTagSlugs: [], tasks: []).map(\.id) == [plan.id])
        #expect(CadenceListRelatedNotes.filter(taskNotes: taskNotes, query: "urgent", requiredTagSlugs: []).map(\.id) == [tagged.id])
        #expect(CadenceListRelatedNotes.filter(taskNotes: taskNotes, query: "#Urg", requiredTagSlugs: []).map(\.id) == [tagged.id])

        // Both at once are an AND.
        #expect(CadenceListRelatedNotes.filter(taskNotes: taskNotes, query: "budget", requiredTagSlugs: slugs).isEmpty)

        // The bar offers the tags that something listed carries.
        let spare = Tag(name: "Spare")
        context.insert(spare)
        let offered = CadenceListRelatedNotes.filterableTags(notes: [diary], taskNotes: [tagged], in: [urgent, spare])
        #expect(offered.map(\.slug) == [urgent.slug])
    }

    /// [[T-18412]]: the field matches through the one scorer Cmd+K and iOS Search use, so an
    /// unaccented query finds an accented title and the words may come in either order, on both
    /// overloads -- and a note that has neither word stays filtered out. The raw substring test
    /// this replaced dropped both hits.
    @Test func theNotesTabSearchMatchesThroughTheSharedScorer() throws {
        let context = try makeContext()
        let area = Area(name: "Home")
        context.insert(area)

        let cafe = Note(kind: .list, title: "Café menu", content: "# Café menu\n\nespresso")
        let report = Note(kind: .list, title: "Draft report", content: "# Draft report\n\nfigures")
        let other = Note(kind: .list, title: "Garden", content: "# Garden\n\ntomatoes")
        for note in [cafe, report, other] { context.insert(note) }

        let cafeTask = task("Café rota", notes: "who opens", area: area, in: context)
        let reportTask = task("Draft report", notes: "for Monday", area: area, in: context)
        let otherTask = task("Water plants", notes: "back garden", area: area, in: context)
        try context.save()

        let notes = [cafe, report, other]
        let taskNotes = [cafeTask, reportTask, otherTask]
        func noteIDs(_ query: String) -> [UUID] {
            CadenceListRelatedNotes.filter(notes, query: query, requiredTagSlugs: [], tasks: []).map(\.id)
        }
        func taskIDs(_ query: String) -> [UUID] {
            CadenceListRelatedNotes.filter(taskNotes: taskNotes, query: query, requiredTagSlugs: []).map(\.id)
        }

        // Diacritics fold.
        #expect(noteIDs("cafe") == [cafe.id])
        #expect(taskIDs("cafe") == [cafeTask.id])
        // Each word matches on its own, in any order.
        #expect(noteIDs("report draft") == [report.id])
        #expect(taskIDs("report draft") == [reportTask.id])
        // A note with neither word stays out, and so does one with only one of the words.
        #expect(noteIDs("report garden").isEmpty)
        #expect(taskIDs("report garden").isEmpty)
        #expect(noteIDs("pizza").isEmpty)
        #expect(taskIDs("pizza").isEmpty)
        // Filtering, not ranking: a query every row answers keeps the incoming order.
        #expect(noteIDs("e") == notes.map(\.id))
        #expect(taskIDs("e") == taskNotes.map(\.id))
    }

    /// [[T-14451]]: the bar's whole decision is this one shared list, for both platforms. Nine
    /// active tags yield nine (the Mac's old cap was eight), an archived tag and a second row
    /// sharing a slug add nothing, and the order is the catalogue's.
    @Test func theFilterBarOffersEveryActiveTagOncePerSlugInCatalogueOrder() throws {
        let context = try makeContext()
        // Inserted out of order so the catalogue's `order` -- not insertion -- decides the strip.
        let active = (0..<9).reversed().map { index in
            Tag(name: "Tag \(index)", order: index)
        }
        let archived = Tag(name: "Old", order: 20, isArchived: true)
        let duplicate = Tag(name: "Tag 4", slug: active.first { $0.order == 4 }!.slug, order: 30)
        for tag in active + [archived, duplicate] { context.insert(tag) }

        let note = Note(kind: .list, title: "Tagged", content: "# Tagged")
        note.tags = Array(active.prefix(5)) + [archived, duplicate]
        context.insert(note)
        let area = Area(name: "Home")
        context.insert(area)
        let taskNote = task("Fix sink", notes: "washer size", area: area, in: context)
        taskNote.tags = Array(active.suffix(4))
        try context.save()

        let catalogue = active + [archived, duplicate]
        let offered = CadenceListRelatedNotes.filterableTags(notes: [note], taskNotes: [taskNote], in: catalogue)

        #expect(offered.count == 9)
        #expect(offered.map(\.name) == (0..<9).map { "Tag \($0)" })
        #expect(!offered.contains { $0.isArchived })
        #expect(Set(offered.map(\.slug)).count == offered.count)
    }

    /// The Mac bar draws what it is handed: the cap, and its own archived/slug pass, are gone, so
    /// the search field's `hasTagFilters` and the strip read one list ([[T-14451]]).
    @Test func theMacTagFilterBarDrawsTheSharedListUncapped() throws {
        let bar = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TagPickerSupportViews.swift")
        )
        #expect(!bar.contains("maxVisibleTags"))
        #expect(bar.contains("private var visibleTags: [Tag] { tags }"))
        let iPadTab = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSListNotesView.swift")
        )
        #expect(!iPadTab.contains(".filter { !$0.isArchived }"), "the iPad tab re-spells the archived rule")
    }

    // MARK: - A new note is revealed

    /// [[T-18596]]: a note the tab just made is blank and untagged. A query it does not match, or
    /// any chip, would hide it from the column beside the editor writing it, so both controls clear
    /// together; a filter the note already passes -- none, or a query its "Untitled" title meets --
    /// is kept. The note is never tagged to fit the chips.
    @Test func aNewNoteTheFilterWouldHideClearsTheSearchAndChips() throws {
        let context = try makeContext()
        let urgent = Tag(name: "Urgent")
        context.insert(urgent)
        let created = Note(kind: .list, title: "", content: "")
        context.insert(created)
        try context.save()

        typealias Controls = CadenceListRelatedNotes.FilterControls
        func reveal(_ current: Controls, slugs: Set<String>) -> Controls {
            CadenceListRelatedNotes.controls(revealing: created, from: current, requiredTagSlugs: slugs, tasks: [])
        }

        // A query the blank note does not match: both controls clear, chips too.
        let queried = Controls(query: "budget", selectedTagIDs: [urgent.id])
        #expect(reveal(queried, slugs: [urgent.slug]) == .cleared)
        #expect(reveal(Controls(query: "budget", selectedTagIDs: []), slugs: []) == .cleared)

        // A chip alone: the untagged note fails it, so the chip clears.
        #expect(reveal(Controls(query: "", selectedTagIDs: [urgent.id]), slugs: [urgent.slug]) == .cleared)

        // Nothing on, or a query the note meets: the controls are kept as they were.
        let idle = Controls(query: "", selectedTagIDs: [])
        #expect(reveal(idle, slugs: []) == idle)
        let untitled = Controls(query: "untitled", selectedTagIDs: [])
        #expect(reveal(untitled, slugs: []) == untitled)

        // Whatever the controls become, the note now passes them -- and was not tagged to do so.
        let after = reveal(queried, slugs: [urgent.slug])
        #expect(CadenceListRelatedNotes.filter([created], query: after.query, requiredTagSlugs: [], tasks: []).map(\.id) == [created.id])
        #expect((created.tags ?? []).isEmpty)
    }

    /// Both tabs' create paths -- the Mac's and iPad's `addNote`, and the iPad folder sheet's
    /// `.created` adoption -- ask the shared rule and write back both controls.
    @Test func bothTabsRevealANewNoteThroughTheSharedRule() throws {
        for path in ["Cadence/macOS/Views/ListNotesView.swift", "Cadence/iOS/iOSListNotesView.swift"] {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            #expect(code.contains("CadenceListRelatedNotes.controls(\n            revealing: note,"), "\(path)")
            #expect(code.contains("searchText = controls.query"), "\(path)")
            #expect(code.contains("selectedTagFilterIDs = controls.selectedTagIDs"), "\(path)")
        }
        let mac = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/ListNotesView.swift"))
        #expect(mac.contains("revealInColumn(note)\n        select(.list(note.id), clearsRequestedEventNote: false)"))
        // [[T-18740]]: opening an EXISTING note -- a Cmd+K pick (list or event) or a `[[note]]`
        // link -- reveals it too, or the column keeps a filter that hides the open note.
        #expect(mac.contains("revealInColumn(note)\n        select(.list(noteID), clearsRequestedEventNote: false)"))
        #expect(mac.contains("revealInColumn(note)\n        select(.event(note.id))"))
        #expect(mac.contains("revealInColumn(note)\n        select(.list(note.id))\n"))
        #expect(mac.contains("revealInColumn(note)\n            select(.event(note.id))"))
        let ios = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSListNotesView.swift"))
        #expect(ios.contains("revealInColumn(note)\n        selectedNoteID = note.id"))
        #expect(ios.contains("if let created { revealInColumn(created) }"))
    }

    /// [[T-18760]]: a list Notes tab with nothing in it draws no search field -- it would narrow
    /// nothing -- while a list whose notes the query hides keeps the field, so the query can be
    /// cleared. The iPad tab's rule; the Mac tab drew the field whatever the list held.
    @Test func theFilterRowWaitsForTheListsFirstNote() {
        #expect(CadenceListRelatedNotes.showsFilterRow(hasAnyNotes: false) == false)
        #expect(CadenceListRelatedNotes.showsFilterRow(hasAnyNotes: true))
    }

    /// Both tabs read that rule, and the Mac draws the list OR the empty panel, never both: an
    /// empty scroll view beside the panel took a share of the column and pushed it off centre.
    @Test func bothTabsGateTheFilterRowAndTheMacDrawsTheListOrThePanel() throws {
        let mac = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/ListNotesView.swift"))
        #expect(mac.contains("""
            if CadenceListRelatedNotes.showsFilterRow(hasAnyNotes: hasAnyNotes) {
                            ListNotesSearchField(
            """))
        #expect(mac.components(separatedBy: "ListNotesSearchField(").count - 1 == 1)
        #expect(mac.contains("""
            if hasAnyFilteredMatches {
                            notesScroll
                        } else {
                            notesListEmptyState
                        }
            """))
        let ios = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSListNotesView.swift"))
        #expect(ios.contains("""
            if CadenceListRelatedNotes.showsFilterRow(hasAnyNotes: hasAnyNotes) {
                            filterRow
            """))
    }

    /// [[T-18770]]: the list's last note gone clears the query and chips the hidden field held, so
    /// a note arriving later without `addNote` is not filtered by a query the user can no longer
    /// see they left on; a list that still has a note keeps whatever the user set.
    @Test func theListsLastNoteGoneClearsTheFilters() {
        let tagID = UUID()
        let set = CadenceListRelatedNotes.FilterControls(query: "budget", selectedTagIDs: [tagID])
        #expect(CadenceListRelatedNotes.controls(set, hasAnyNotes: false) == .cleared)
        #expect(CadenceListRelatedNotes.controls(set, hasAnyNotes: true) == set)
    }

    /// Both tabs run that rule when the list empties, and write back both controls.
    @Test func bothTabsClearTheFiltersWhenTheListEmpties() throws {
        for path in ["Cadence/macOS/Views/ListNotesView.swift", "Cadence/iOS/iOSListNotesView.swift"] {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            #expect(code.contains("""
                .onChange(of: hasAnyNotes) { _, _ in
                            clearFiltersIfListEmptied(hasAnyNotes: hasAnyNotes)
                """), "\(path)")
            #expect(code.contains("""
                let controls = CadenceListRelatedNotes.controls(
                            .init(query: searchText, selectedTagIDs: selectedTagFilterIDs),
                            hasAnyNotes: hasAnyNotes
                        )
                        searchText = controls.query
                        selectedTagFilterIDs = controls.selectedTagIDs
                """), "\(path)")
        }
    }

    // MARK: - Both tabs read it

    /// macOS kept these as private members of `ListNotesView`; the iPad tab had none of them. Both
    /// now read the one derivation, and neither spells the open-task predicate on its own.
    @Test func bothListNotesTabsReadTheSharedDerivation() throws {
        for path in ["Cadence/macOS/Views/ListNotesView.swift", "Cadence/iOS/iOSListNotesView.swift"] {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            for call in [
                "CadenceListRelatedNotes.taskNotes(",
                "CadenceListRelatedNotes.upcomingEventNotes(",
                "CadenceListRelatedNotes.filterableTags(",
                "CadenceListRelatedNotes.filter(",
                "CadenceListRelatedNotes.filter(\n            taskNotes:",
            ] {
                #expect(code.contains(call), "\(path) does not call \(call)")
            }
            #expect(!code.contains("!$0.isCancelled"), "\(path) re-spells the task-note predicate")
            #expect(!code.contains("eventDateKey < "), "\(path) re-spells the past-event rule")
        }
    }

    /// The iPad tab draws both sections and opens each through its platform's host: a task note in
    /// the task inspector, an event note in the event-note sheet.
    @Test func theIPadTabDrawsBothSectionsAndOpensThemThroughTheirHosts() throws {
        let code = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSListNotesView.swift")
        )
        // Declared once and drawn once each: a declared-but-undrawn section is the pre-fix tree.
        #expect(code.components(separatedBy: "eventNoteSection").count - 1 == 2)
        #expect(code.components(separatedBy: "taskNoteSection").count - 1 == 2)
        // [[T-15433]]: the headings are the shared section's, with the Mac's count and fold.
        #expect(code.contains("CadenceListNotesSectionHeading.heading(.taskNotes, count: filteredTaskNotes.count)"))
        #expect(code.contains("CadenceListNotesSectionHeading.heading(.events, count: filteredEventNotes.count)"))
        #expect(CadenceListNotesSection.taskNotes.title == "Task Notes")
        #expect(CadenceListNotesSection.events.title == CadenceNotesTabVocabulary.events.columnTitle)
        #expect(code.contains("@Environment(\\.iOSTaskInspector)"))
        #expect(code.contains("taskInspector(task)"))
        #expect(code.contains("iOSEventNoteEditorSheet("))
        #expect(code.contains("TextField(\"Search notes\""))
        #expect(code.contains("CadenceEmptyStateCopy.listNotesNoMatchesTitle"))
    }

    /// **[[T-7206]]: the Notes tab's no-match panel names the tag filter too.** A tag chip narrows
    /// it on both platforms with the search field empty, and the subtitle said only "Try a
    /// different search", with no full stop.
    @Test func theNotesNoMatchesSubtitleNamesBothNarrowingControls() throws {
        #expect(CadenceEmptyStateCopy.listNotesNoMatchesSubtitle == "Try a different search or tag.")
        // Both surfaces that draw the panel narrow it by tag, so the word is true on each.
        for path in ["Cadence/macOS/Views/ListNotesView.swift", "Cadence/iOS/iOSListNotesView.swift"] {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            #expect(code.contains("requiredTagSlugs: requiredTagFilterSlugs"), "\(path) no longer narrows by tag")
        }
    }

    // MARK: - [[T-17014]] the selection follows the tag, not its slug

    /// A chip selection is held as tag ids. Renaming the selected tag rewrites its slug; the
    /// selection survives the bar's prune and the filter requires the NEW slug, so the list stays
    /// narrowed. A tag that leaves the bar -- archived, or no longer on anything listed -- drops out.
    @Test func aRenamedTagKeepsItsChipOnAndTheFilterApplied() throws {
        let context = try makeContext()
        let work = Tag(name: "work")
        let home = Tag(name: "home")
        context.insert(work)
        context.insert(home)
        let plan = Note(kind: .list, title: "Plan", content: "# Plan")
        plan.tags = [work]
        let diary = Note(kind: .list, title: "Diary", content: "# Diary")
        diary.tags = [home]
        context.insert(plan)
        context.insert(diary)
        try context.save()

        let notes = [plan, diary]
        func offered() -> [Cadence.Tag] {
            CadenceListRelatedNotes.filterableTags(notes: notes, taskNotes: [], in: [work, home])
        }
        var selection: Set<UUID> = [work.id]
        #expect(CadenceListRelatedNotes.requiredTagSlugs(selectedTagIDs: selection, filterableTags: offered()) == ["work"])

        _ = TagSupport.rename(work, to: "Job")
        #expect(work.slug == "job")
        selection = CadenceListRelatedNotes.prunedTagSelection(selection, filterableTags: offered())
        #expect(selection == [work.id], "the rename let go of the chip")
        let required = CadenceListRelatedNotes.requiredTagSlugs(selectedTagIDs: selection, filterableTags: offered())
        #expect(required == ["job"])
        #expect(CadenceListRelatedNotes.filter(notes, query: "", requiredTagSlugs: required, tasks: []).map(\.id) == [plan.id])

        // Archived: it leaves the bar, so it leaves the selection and requires nothing.
        work.isArchived = true
        selection = CadenceListRelatedNotes.prunedTagSelection(selection, filterableTags: offered())
        #expect(selection.isEmpty)
        #expect(CadenceListRelatedNotes.requiredTagSlugs(selectedTagIDs: [work.id], filterableTags: offered()).isEmpty)

        // No longer on anything listed: same.
        selection = [home.id]
        diary.tags = []
        selection = CadenceListRelatedNotes.prunedTagSelection(selection, filterableTags: offered())
        #expect(selection.isEmpty)
    }

    /// Both tabs and the Mac bar hold ids and read the shared derivation; neither re-spells the
    /// slug intersection that let a rename clear the filter.
    @Test func bothTabsHoldTheTagSelectionAsIds() throws {
        for path in ["Cadence/macOS/Views/ListNotesView.swift", "Cadence/iOS/iOSListNotesView.swift"] {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            #expect(code.contains("@State private var selectedTagFilterIDs: Set<UUID> = []"), "\(path)")
            #expect(code.contains("CadenceListRelatedNotes.requiredTagSlugs(selectedTagIDs: selectedTagFilterIDs"), "\(path)")
            #expect(code.contains("CadenceListRelatedNotes.prunedTagSelection("), "\(path)")
            #expect(!code.contains("selectedTagFilterSlugs"), "\(path) still holds slugs")
            #expect(!code.contains("formIntersection"), "\(path) re-spells the prune")
        }
        let bar = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TagPickerSupportViews.swift")
        )
        #expect(bar.contains("@Binding var selectedTagIDs: Set<UUID>"))
        #expect(!bar.contains("selectedSlugs"))
    }
}
