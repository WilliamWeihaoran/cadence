import Foundation
import SwiftData
import Testing
@testable import Cadence

@MainActor
struct CadenceReadServiceTests {
    @Test func coreNotesDoesNotCreateMissingNotes() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let service = CadenceReadService(container: container)

        let snapshot = try service.coreNotes(dateKey: "2026-04-28")

        #expect(snapshot.dateKey == "2026-04-28")
        #expect(snapshot.dailyNote == nil)
        #expect(snapshot.weeklyNote == nil)
        #expect(snapshot.permanentNote == nil)
    }

    @Test func listTasksFiltersByScheduleContainerAndCompletion() throws {
        let fixture = try Fixture()
        let todayTask = AppTask(title: "Write MCP bridge")
        todayTask.project = fixture.project
        todayTask.context = fixture.context
        todayTask.tags = TagSupport.resolveTags(named: ["enhancement"], in: fixture.modelContext)
        todayTask.scheduledDate = "2026-04-28"
        todayTask.scheduledStartMin = 600
        fixture.modelContext.insert(todayTask)

        let doneTask = AppTask(title: "Old completed task")
        doneTask.project = fixture.project
        doneTask.context = fixture.context
        doneTask.status = .done
        doneTask.scheduledDate = "2026-04-28"
        fixture.modelContext.insert(doneTask)
        try fixture.modelContext.save()

        let results = try fixture.service.listTasks(options: .init(
            scheduledDate: "2026-04-28",
            containerKind: "project",
            containerId: fixture.project.id.uuidString,
            textQuery: "bridge",
            tagSlugs: ["enhancement"],
            limit: 50
        ))

        #expect(results.map(\.title) == ["Write MCP bridge"])
    }

    @Test func containerSummaryCountsTasksAndDocuments() throws {
        let fixture = try Fixture()
        let active = AppTask(title: "Active")
        active.project = fixture.project
        active.sectionName = "Build"
        let complete = AppTask(title: "Complete")
        complete.project = fixture.project
        complete.status = .done
        let doc = Note(kind: .list, title: "Spec")
        doc.project = fixture.project
        let link = SavedLink(title: "Roadmap", url: "https://example.com/roadmap")
        link.project = fixture.project

        fixture.modelContext.insert(active)
        fixture.modelContext.insert(complete)
        fixture.modelContext.insert(doc)
        fixture.modelContext.insert(link)
        try fixture.modelContext.save()

        let summary = try fixture.service.containerSummary(kind: "project", id: fixture.project.id.uuidString)

        #expect(summary.activeTaskCount == 1)
        #expect(summary.completedTaskCount == 1)
        #expect(summary.sections.first { $0.name == "Build" }?.activeTaskCount == 1)
        #expect(summary.documents.map(\.title) == ["Spec"])
        #expect(summary.links.map(\.title) == ["Roadmap"])
    }

    @Test func readServiceExposesNewMcpSurfaces() throws {
        let fixture = try Fixture()
        fixture.project.sectionNames = [TaskSectionDefaults.defaultName, "Build"]
        let goal = Goal(title: "Ship Goals", context: fixture.context)
        let task = AppTask(title: "Goal task")
        task.project = fixture.project
        task.context = fixture.context
        task.goal = goal
        task.sectionName = "Build"
        task.tags = TagSupport.resolveTags(named: ["feature"], in: fixture.modelContext)

        let bundle = TaskBundle(title: "Planning block", dateKey: "2026-05-01", startMin: 600, durationMinutes: 45)
        task.bundle = bundle
        task.bundleOrder = 0

        let note = Note(
            kind: .list,
            title: "Design Note",
            content: "[[task:\(task.id.uuidString)|Goal task]]"
        )
        note.project = fixture.project
        note.tags = TagSupport.resolveTags(named: ["feature"], in: fixture.modelContext)
        let backlink = Note(
            kind: .permanent,
            title: "Knowledge Hub",
            content: "[[note:\(note.id.uuidString)|Design Note]]"
        )
        let parentGoal = Goal(title: "Cadence Platform", context: fixture.context)
        parentGoal.kind = .ongoing
        goal.parentGoal = parentGoal
        let habit = Habit(title: "Write daily", context: fixture.context, goal: goal)
        let completion = HabitCompletion(date: DateFormatters.todayKey(), habit: habit)
        let savedLink = SavedLink(title: "Goal Spec", url: "https://example.com/spec")
        savedLink.project = fixture.project
        let goalLink = GoalListLink(goal: goal, project: fixture.project)

        fixture.modelContext.insert(goal)
        fixture.modelContext.insert(parentGoal)
        fixture.modelContext.insert(task)
        fixture.modelContext.insert(bundle)
        fixture.modelContext.insert(note)
        fixture.modelContext.insert(backlink)
        fixture.modelContext.insert(habit)
        fixture.modelContext.insert(completion)
        fixture.modelContext.insert(savedLink)
        fixture.modelContext.insert(goalLink)
        try fixture.modelContext.save()

        let taskDetail = try fixture.service.getTask(taskID: task.id.uuidString)
        let noteDetail = try fixture.service.getNote(noteID: note.id.uuidString)
        let goalDetail = try fixture.service.getGoal(goalID: goal.id.uuidString)
        let bundleDetail = try fixture.service.getTaskBundle(bundleID: bundle.id.uuidString)

        #expect(taskDetail.summary.goal?.id == goal.id.uuidString)
        #expect(try fixture.service.listTags(query: "feature").first?.summary.slug == "feature")
        #expect(try fixture.service.listNotes(options: .init(kind: "list", query: "Design")).map(\.id) == [note.id.uuidString])
        #expect(noteDetail.linkedTasks.map(\.id) == [task.id.uuidString])
        #expect(noteDetail.backlinks.map(\.id) == [backlink.id.uuidString])
        #expect(try fixture.service.listGoals(options: .init(query: "Ship")).map(\.id) == [goal.id.uuidString])
        #expect(goalDetail.linkedContainers.map(\.id) == [fixture.project.id.uuidString])
        #expect(goalDetail.directTasks.map(\.id) == [task.id.uuidString])
        #expect(goalDetail.summary.parentGoalId == parentGoal.id.uuidString)
        #expect(goalDetail.summary.parentGoalTitle == parentGoal.title)
        #expect(goalDetail.summary.isTopLevel == false)
        #expect(goalDetail.summary.kind == GoalKind.completable.rawValue)
        #expect(try fixture.service.listHabits(options: .init(goalId: goal.id.uuidString)).first?.completedToday == true)
        #expect(try fixture.service.listHabits(options: .init(goalId: goal.id.uuidString)).first?.goal?.id == goal.id.uuidString)
        #expect(try fixture.service.listLinks(options: .init(containerKind: "project", containerId: fixture.project.id.uuidString)).map(\.id) == [savedLink.id.uuidString])
        #expect(try fixture.service.listTaskBundles(options: .init(dateKey: "2026-05-01")).map(\.id) == [bundle.id.uuidString])
        #expect(bundleDetail.tasks.map(\.id) == [task.id.uuidString])
        #expect(try fixture.service.search(query: "Goal Spec", scopes: ["links"]).first?.entityType == "saved_link")
        #expect(try fixture.service.search(query: "Write daily", scopes: ["habits"]).first?.entityType == "habit")
        #expect(try fixture.service.search(query: "Ship Goals", scopes: ["goals"]).first?.entityType == "goal")
        #expect(try fixture.service.search(query: "feature", scopes: ["tags"]).first?.entityType == "tag")

        // What used to be a pursuit is now a top-level ongoing goal owning the milestone.
        let parentSummary = try #require(try fixture.service.listGoals(options: .init(
            contextId: fixture.context.id.uuidString,
            query: "Cadence Platform"
        )).first)
        #expect(parentSummary.id == parentGoal.id.uuidString)
        #expect(parentSummary.isTopLevel)
        #expect(parentSummary.kind == GoalKind.ongoing.rawValue)
        #expect(parentSummary.subGoalCount == 1)

        let contexts = try fixture.service.listContexts()
        #expect(contexts.first { $0.id == fixture.context.id.uuidString }?.goalCount == 2)

        #expect(try fixture.service.search(query: "Cadence Platform", scopes: ["goals"]).first?.entityType == "goal")
    }

    @Test func readServiceMigratesLegacyListDocumentsOnInit() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let context = Context(name: "Work")
        let project = Project(name: "Launch", context: context)
        let legacyDoc = Document(title: "Launch Plan")
        legacyDoc.content = "Canonical content after migration"
        legacyDoc.project = project

        modelContext.insert(context)
        modelContext.insert(project)
        modelContext.insert(legacyDoc)
        try modelContext.save()

        let service = CadenceReadService(container: container)
        let documents = try service.listDocuments(containerKind: "project", containerID: project.id.uuidString)
        let detail = try service.getDocument(documentID: legacyDoc.id.uuidString)
        let searchHits = try service.search(query: "Canonical", scopes: ["documents"])

        #expect(documents.map(\.id) == [legacyDoc.id.uuidString])
        #expect(documents.map(\.title) == ["Launch Plan"])
        #expect(detail.id == legacyDoc.id.uuidString)
        #expect(detail.content == "Canonical content after migration")
        #expect(searchHits.map(\.entityId).contains(legacyDoc.id.uuidString))
    }

    @Test func searchHonorsScopes() throws {
        let fixture = try Fixture()
        let task = AppTask(title: "Deep work block")
        let doc = Note(kind: .list, title: "Deep research notes")
        let eventNote = Note(kind: .meeting, title: "Deep meeting", calendarEventID: "event-1")
        eventNote.content = "Decisions about launch planning"
        doc.content = "Long-form thinking about MCP"
        fixture.modelContext.insert(task)
        fixture.modelContext.insert(doc)
        fixture.modelContext.insert(eventNote)
        try fixture.modelContext.save()

        let taskHits = try fixture.service.search(query: "deep", scopes: ["tasks"])
        let docHits = try fixture.service.search(query: "deep", scopes: ["documents"])
        let eventNoteTitleHits = try fixture.service.search(query: "deep", scopes: ["event_notes"])
        let eventNoteBodyHits = try fixture.service.search(query: "launch")
        let eventNoteScopedBodyHits = try fixture.service.search(query: "launch", scopes: ["event_notes"])

        #expect(taskHits.map(\.entityType) == ["task"])
        #expect(docHits.map(\.entityType) == ["document"])
        #expect(eventNoteTitleHits.map(\.entityType) == ["event_note"])
        #expect(eventNoteBodyHits.contains { $0.entityType == "event_note" })
        #expect(eventNoteScopedBodyHits.map(\.entityType) == ["event_note"])
    }

    /// A week-based streak must be spelled in weeks on the MCP search surface.
    ///
    /// `Habit.currentStreak` counts *weeks* for `.timesPerWeek` and *days* for every other
    /// frequency, but the habit search subtitle hardcoded `"\(streak) day streak"`, so three kept
    /// weeks were handed to an MCP client as "3 day streak" — a number the client then repeats to
    /// the user as if the habit were three days old. The unit belongs to the frequency
    /// (`Habit.streakUnit`), so both spellings are pinned here: a mislabel is only visible as a
    /// bug when the two frequencies are asserted against each other.
    @Test func habitSearchSubtitleSpellsStreakInTheFrequencysOwnUnit() throws {
        let fixture = try Fixture()
        let isoCalendar = Habit.isoWeekCalendar()
        guard let currentWeekStart = isoCalendar.dateInterval(of: .weekOfYear, for: Date())?.start else {
            Issue.record("Could not resolve the current ISO week")
            return
        }

        // Three complete prior weeks satisfied, current (in-progress) week empty. `weeklyStreak`
        // forgives the in-progress week, so this is a deterministic streak of 3 regardless of
        // which weekday the suite runs on.
        let weekly = Habit(title: "Swim laps", context: fixture.context)
        weekly.frequencyType = .timesPerWeek
        weekly.targetCount = 1
        fixture.modelContext.insert(weekly)
        for weeksBack in 1...3 {
            guard let weekStart = isoCalendar.date(byAdding: .day, value: -7 * weeksBack, to: currentWeekStart) else { continue }
            let completion = HabitCompletion(
                date: DateFormatters.dateKey(from: weekStart, calendar: isoCalendar),
                habit: weekly
            )
            fixture.modelContext.insert(completion)
        }

        // Same shape, day-based frequency: completed today and yesterday, so a streak of 2 days.
        let daily = Habit(title: "Swim warmup", context: fixture.context)
        daily.frequencyType = .daily
        daily.targetCount = 1
        fixture.modelContext.insert(daily)
        for daysBack in 0...1 {
            guard let day = isoCalendar.date(byAdding: .day, value: -daysBack, to: Date()) else { continue }
            let completion = HabitCompletion(
                date: DateFormatters.dateKey(from: day, calendar: isoCalendar),
                habit: daily
            )
            fixture.modelContext.insert(completion)
        }
        try fixture.modelContext.save()

        let weeklySubtitle = try #require(
            fixture.service.search(query: "Swim laps", scopes: ["habits"]).first?.subtitle
        )
        #expect(weeklySubtitle == "Work - 3 week streak")
        #expect(!weeklySubtitle.contains("day"))

        let dailySubtitle = try #require(
            fixture.service.search(query: "Swim warmup", scopes: ["habits"]).first?.subtitle
        )
        #expect(dailySubtitle == "Work - 2 day streak")
    }

    @Test func invalidEnumsAndPartialContainerFiltersThrow() throws {
        let fixture = try Fixture()

        #expect(throws: CadenceReadError.self) {
            try fixture.service.search(query: "cadence", scopes: ["events"])
        }

        #expect(throws: CadenceReadError.self) {
            try fixture.service.listTasks(options: .init(statuses: ["not-a-status"]))
        }

        #expect(throws: CadenceReadError.self) {
            try fixture.service.listDocuments(containerKind: "project")
        }
    }

    /// **T-278: the MCP search subtitle must speak the app's vocabulary, and its keys must not
    /// move.**
    ///
    /// `noteSubtitle` was the fifth spelling of the note-kind switch and the last one still in the
    /// retired vocabulary — "Permanent note" and "Meeting note" for the surfaces the app calls
    /// **Notepad** and **Event Notes** — with a sixth literal `"Meeting note"` hardcoded at the
    /// `event_notes` scope beside it. T-239 consolidated the other four and left this one alone on
    /// purpose, because it is MCP *response* content.
    ///
    /// Both halves are asserted together, and that pairing is the test:
    /// - the **prose** now reads `NoteReferencePanelSupport.noteKindLabel`, so a rename cannot leave
    ///   this surface behind again;
    /// - the **keys** — `entityType` — are byte-for-byte what they were, because those are what an
    ///   MCP client actually matches on and `CadenceMCPServer/AGENTS.md` says response DTOs change
    ///   on purpose or not at all.
    ///
    /// Asserting the subtitle alone would pass a change that also renamed `permanent_note`;
    /// asserting the type alone would pass the stale prose that was there before.
    @Test func noteSearchSubtitlesSpeakTheAppsVocabularyWhileTheKeysStayPut() throws {
        let fixture = try Fixture()

        let notepad = Note(kind: .permanent, title: "Zettel inbox")
        let daily = Note(kind: .daily, title: "Zettel Monday")
        daily.dateKey = "2026-04-28"
        let weekly = Note(kind: .weekly, title: "Zettel week")
        weekly.weekKey = "2026-W18"
        let eventNote = Note(kind: .meeting, title: "Zettel standup", calendarEventID: "event-1")
        eventNote.eventDateKey = "2026-04-28"
        let listNote = Note(kind: .list, title: "Zettel spec")
        listNote.project = fixture.project
        for note in [notepad, daily, weekly, eventNote, listNote] {
            fixture.modelContext.insert(note)
        }
        try fixture.modelContext.save()

        let hits = try fixture.service.search(query: "Zettel", scopes: ["notes"])
        let byType = Dictionary(uniqueKeysWithValues: hits.map { ($0.entityType, $0.subtitle) })

        // The prose, in the vocabulary the app's own tabs use.
        #expect(byType["permanent_note"] == "Notepad")
        #expect(byType["event_note"] == "Event note")
        #expect(byType["daily_note"] == "Daily note")
        #expect(byType["weekly_note"] == "Weekly note")
        // A list note keeps naming its container rather than its kind — the useful half here, and
        // the reason this field cannot have been a matched enumeration for any client.
        #expect(byType["document"] == "Cadence MCP")

        // The retired vocabulary is gone from every subtitle in the response, not just from the two
        // asserted above.
        #expect(!hits.contains { $0.subtitle == "Permanent note" || $0.subtitle == "Meeting note" })

        // The stable keys: unchanged, and asserted as the whole set so a rename cannot hide in one.
        #expect(Set(byType.keys) == ["daily_note", "weekly_note", "permanent_note", "document", "event_note"])
    }

    /// The sixth literal: the `event_notes` scope hardcoded `subtitle: "Meeting note"` rather than
    /// calling the switch three lines away, so consolidating the switch alone would have left the
    /// retired word on the one scope named for that kind of note.
    @Test func theEventNotesScopeReadsTheSameLabelAsEverythingElse() throws {
        let fixture = try Fixture()
        let eventNote = Note(kind: .meeting, title: "Zettel standup", calendarEventID: "event-1")
        fixture.modelContext.insert(eventNote)
        try fixture.modelContext.save()

        let scoped = try #require(fixture.service.search(query: "Zettel", scopes: ["event_notes"]).first)
        let unscoped = try #require(fixture.service.search(query: "Zettel", scopes: ["notes"]).first)

        #expect(scoped.entityType == "event_note")
        #expect(scoped.subtitle == "Event note")
        #expect(scoped.subtitle == unscoped.subtitle)
        #expect(scoped.subtitle == NoteReferencePanelSupport.noteKindLabel(.meeting))
    }

    @MainActor
    private final class Fixture {
        let container: ModelContainer
        let modelContext: ModelContext
        let service: CadenceReadService
        let context: Context
        let project: Project

        init() throws {
            container = try CadenceModelContainerFactory.makeInMemoryContainer()
            modelContext = ModelContext(container)
            service = CadenceReadService(container: container)
            context = Context(name: "Work")
            project = Project(name: "Cadence MCP", context: context)
            modelContext.insert(context)
            modelContext.insert(project)
            try modelContext.save()
        }
    }
}
