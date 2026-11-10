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
            #expect(code.contains("requiredTagSlugs: selectedTagFilterSlugs"), "\(path) no longer narrows by tag")
        }
    }
}
