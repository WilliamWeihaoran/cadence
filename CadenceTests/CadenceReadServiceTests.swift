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

        #expect(results.items.map(\.title) == ["Write MCP bridge"])
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
        #expect(try fixture.service.listTags(query: "feature").items.first?.summary.slug == "feature")
        #expect(try fixture.service.listNotes(options: .init(kind: "list", query: "Design")).items.map(\.id) == [note.id.uuidString])
        #expect(noteDetail.linkedTasks.map(\.id) == [task.id.uuidString])
        #expect(noteDetail.backlinks.map(\.id) == [backlink.id.uuidString])
        #expect(try fixture.service.listGoals(options: .init(query: "Ship")).items.map(\.id) == [goal.id.uuidString])
        #expect(goalDetail.linkedContainers.map(\.id) == [fixture.project.id.uuidString])
        #expect(goalDetail.directTasks.map(\.id) == [task.id.uuidString])
        #expect(goalDetail.summary.parentGoalId == parentGoal.id.uuidString)
        #expect(goalDetail.summary.parentGoalTitle == parentGoal.title)
        #expect(goalDetail.summary.isTopLevel == false)
        #expect(goalDetail.summary.kind == GoalKind.completable.rawValue)
        #expect(try fixture.service.listHabits(options: .init(goalId: goal.id.uuidString)).items.first?.completedToday == true)
        #expect(try fixture.service.listHabits(options: .init(goalId: goal.id.uuidString)).items.first?.goal?.id == goal.id.uuidString)
        #expect(try fixture.service.listLinks(options: .init(containerKind: "project", containerId: fixture.project.id.uuidString)).items.map(\.id) == [savedLink.id.uuidString])
        #expect(try fixture.service.listTaskBundles(options: .init(dateKey: "2026-05-01")).items.map(\.id) == [bundle.id.uuidString])
        #expect(bundleDetail.tasks.map(\.id) == [task.id.uuidString])
        #expect(try fixture.service.search(query: "Goal Spec", scopes: ["links"]).items.first?.entityType == "saved_link")
        #expect(try fixture.service.search(query: "Write daily", scopes: ["habits"]).items.first?.entityType == "habit")
        #expect(try fixture.service.search(query: "Ship Goals", scopes: ["goals"]).items.first?.entityType == "goal")
        #expect(try fixture.service.search(query: "feature", scopes: ["tags"]).items.first?.entityType == "tag")

        // What used to be a pursuit is now a top-level ongoing goal owning the milestone.
        let parentSummary = try #require(try fixture.service.listGoals(options: .init(
            contextId: fixture.context.id.uuidString,
            query: "Cadence Platform"
        )).items.first)
        #expect(parentSummary.id == parentGoal.id.uuidString)
        #expect(parentSummary.isTopLevel)
        #expect(parentSummary.kind == GoalKind.ongoing.rawValue)
        #expect(parentSummary.subGoalCount == 1)

        let contexts = try fixture.service.listContexts()
        #expect(contexts.items.first { $0.id == fixture.context.id.uuidString }?.goalCount == 2)

        #expect(try fixture.service.search(query: "Cadence Platform", scopes: ["goals"]).items.first?.entityType == "goal")
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

        #expect(documents.items.map(\.id) == [legacyDoc.id.uuidString])
        #expect(documents.items.map(\.title) == ["Launch Plan"])
        #expect(detail.id == legacyDoc.id.uuidString)
        #expect(detail.content == "Canonical content after migration")
        #expect(searchHits.items.map(\.entityId).contains(legacyDoc.id.uuidString))
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

        #expect(taskHits.items.map(\.entityType) == ["task"])
        #expect(docHits.items.map(\.entityType) == ["document"])
        #expect(eventNoteTitleHits.items.map(\.entityType) == ["event_note"])
        #expect(eventNoteBodyHits.items.contains { $0.entityType == "event_note" })
        #expect(eventNoteScopedBodyHits.items.map(\.entityType) == ["event_note"])
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
            fixture.service.search(query: "Swim laps", scopes: ["habits"]).items.first?.subtitle
        )
        #expect(weeklySubtitle == "Work - 3 week streak")
        #expect(!weeklySubtitle.contains("day"))

        let dailySubtitle = try #require(
            fixture.service.search(query: "Swim warmup", scopes: ["habits"]).items.first?.subtitle
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

    /// **T-278: the MCP search subtitle speaks the app's vocabulary, and its keys do not move.**
    ///
    /// `noteSubtitle` was the fifth spelling of the note-kind switch and the last one still in the
    /// retired vocabulary — "Permanent note" and "Meeting note" for the surfaces the app calls
    /// **Notepad** and **Event Notes** — with a sixth literal `subtitle: "Meeting note"` hardcoded at
    /// the `event_notes` scope beside it. T-239 consolidated the other four and left this one alone
    /// on purpose, because it is MCP *response* content.
    ///
    /// Both halves are asserted together, and the pairing is the test:
    /// - the **prose** now reads `NoteReferencePanelSupport.noteKindLabel`, so a rename cannot leave
    ///   this surface behind again;
    /// - the **keys** — `entityType` — are byte-for-byte what they were, because those are what an
    ///   MCP client matches on and `CadenceMCPServer/AGENTS.md` says response DTOs change on purpose
    ///   or not at all.
    ///
    /// Asserting the subtitle alone would pass a change that also renamed `permanent_note`;
    /// asserting the type alone would pass the stale prose that was there before.
    @Test func noteSearchSubtitlesSpeakTheAppsVocabularyWhileTheKeysStayPut() throws {
        let fixture = try Fixture()

        let notepad = Note(kind: .permanent, title: "Zettel inbox")
        let daily = Note(kind: .daily, title: "Zettel Monday", dateKey: "2026-04-28")
        let weekly = Note(kind: .weekly, title: "Zettel week", weekKey: "2026-W18")
        let eventNote = Note(kind: .meeting, title: "Zettel standup", calendarEventID: "event-1", eventDateKey: "2026-04-28")
        let listNote = Note(kind: .list, title: "Zettel spec", project: fixture.project)
        for note in [notepad, daily, weekly, eventNote, listNote] {
            fixture.modelContext.insert(note)
        }
        try fixture.modelContext.save()

        let hits = try fixture.service.search(query: "Zettel", scopes: ["notes"])
        let byType = Dictionary(uniqueKeysWithValues: hits.items.map { ($0.entityType, $0.subtitle) })

        // The prose, in the vocabulary the app's own tabs use.
        #expect(byType["permanent_note"] == "Notepad")
        #expect(byType["event_note"] == "Event note")
        #expect(byType["daily_note"] == "Daily note")
        #expect(byType["weekly_note"] == "Weekly note")
        // A list note keeps naming its container rather than its kind — the useful half here, and
        // the reason this field cannot have been a matched enumeration for any client.
        #expect(byType["document"] == "Cadence MCP")

        // The retired vocabulary is gone from every subtitle in the response, not only the two
        // asserted above.
        #expect(!hits.items.contains { $0.subtitle == "Permanent note" || $0.subtitle == "Meeting note" })

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

        let scoped = try #require(fixture.service.search(query: "Zettel", scopes: ["event_notes"]).items.first)
        let unscoped = try #require(fixture.service.search(query: "Zettel", scopes: ["notes"]).items.first)

        #expect(scoped.entityType == "event_note")
        #expect(scoped.subtitle == "Event note")
        #expect(scoped.subtitle == unscoped.subtitle)
        #expect(scoped.subtitle == NoteReferencePanelSupport.noteKindLabel(.meeting))
    }

    // MARK: - T-382 / T-383, a page that says it is a page

    /// **T-382: a full page names the rows it left behind.**
    ///
    /// Before the envelope, `list_tasks` answered with a bare array. Ask for 3 of 7 and you get
    /// three rows and no way at all to learn about the other four — the same response a store
    /// holding exactly three tasks produces. A person notices a suspiciously round list; an agent
    /// reasons on it as the population.
    @Test func aFullPageOfTasksReportsTheRowsItLeftBehind() throws {
        let fixture = try PagingFixture(taskCount: 7)

        let page = try fixture.service.listTasks(options: .init(limit: 3))

        #expect(page.returnedCount == 3)
        #expect(page.items.count == 3)
        #expect(page.totalCount == 7)
        #expect(page.totalCount > page.returnedCount)
        #expect(page.hasMore)
        #expect(page.offset == 0)
        #expect(page.nextOffset == 3)
    }

    /// A result under the cap says so, rather than leaving the caller to guess from the row count.
    @Test func aPageShorterThanItsLimitReportsCountsThatAgree() throws {
        let fixture = try PagingFixture(taskCount: 7)

        let page = try fixture.service.listTasks(options: .init(limit: 50))

        // Non-vacuity: the fixture really has rows, so equal counts are not two zeroes agreeing.
        #expect(page.returnedCount == 7)
        #expect(page.returnedCount == page.totalCount)
        #expect(page.hasMore == false)
        #expect(page.nextOffset == nil)
    }

    /// The sharp case: `returnedCount == limit` **and** nothing left.
    ///
    /// A `hasMore` computed as "did we fill the page?" is right on every input except this one,
    /// which is exactly the input a caller hits when the store size happens to be a multiple of
    /// the limit. Both spellings are asserted — a page whose last row is the last row, and a final
    /// page reached by walking an offset — because the first alone passes for `returnedCount <
    /// limit` logic and the second alone passes for a bare `offset + limit >= totalCount` that
    /// never looked at the rows.
    @Test func aPageThatEndsExactlyOnTheLastRowDoesNotClaimMore() throws {
        let fixture = try PagingFixture(taskCount: 7)

        let exact = try fixture.service.listTasks(options: .init(limit: 7))
        #expect(exact.returnedCount == 7)
        #expect(exact.totalCount == 7)
        #expect(exact.hasMore == false)
        #expect(exact.nextOffset == nil)

        let lastPage = try fixture.service.listTasks(options: .init(limit: 3, offset: 4))
        #expect(lastPage.returnedCount == 3)
        #expect(lastPage.offset == 4)
        #expect(lastPage.totalCount == 7)
        #expect(lastPage.hasMore == false)
        #expect(lastPage.nextOffset == nil)
    }

    /// **T-383: more areas than the limit no longer costs the caller every project.**
    ///
    /// `listContainers` used to sort each kind on its own, append projects behind areas, and only
    /// then apply the cap — so a capped unfiltered call returned a page that *could not* contain a
    /// project. [[T-372]] made that reproducible rather than random: you lose all of them, every
    /// read. The fix merges both kinds into one totally ordered candidate list before capping,
    /// which is also the only shape a single `offset` can page honestly.
    @Test func cappedContainerListsStillReachProjectsWhenAreasOutnumberTheLimit() throws {
        let fixture = try PagingFixture(taskCount: 0, areaNames: ["Area A", "Area B", "Area C", "Area D", "Area E"], projectNames: ["Alpha Project", "Beta Project"])

        // Non-vacuity: the store really holds five areas and two projects, and the areas really do
        // outnumber the limit under test.
        #expect(try fixture.service.listContainers(kind: "area", limit: 200).totalCount == 5)
        #expect(try fixture.service.listContainers(kind: "project", limit: 200).totalCount == 2)

        let page = try fixture.service.listContainers(limit: 3)

        #expect(page.totalCount == 7)
        #expect(page.returnedCount == 3)
        #expect(page.hasMore)
        // "Alpha Project" sorts ahead of every "Area …" at the same `order`, so a merged list puts
        // a project on the first page. A concatenated one cannot.
        #expect(page.items.contains { $0.kind == "project" })
        #expect(page.items.map(\.name) == ["Alpha Project", "Area A", "Area B"])
    }

    /// Walking `nextOffset` visits every row of both kinds once — the property `hasMore` is only
    /// worth reporting if it holds.
    @Test func containerPagingWalksEveryRowOfBothKindsExactlyOnce() throws {
        let fixture = try PagingFixture(taskCount: 0, areaNames: ["Area A", "Area B", "Area C", "Area D", "Area E"], projectNames: ["Alpha Project", "Beta Project"])

        var walked: [String] = []
        var offset: Int? = 0
        var guardRail = 0
        while let next = offset, guardRail < 20 {
            guardRail += 1
            let page = try fixture.service.listContainers(limit: 2, offset: next)
            walked += page.items.map(\.name)
            #expect(page.totalCount == 7)
            offset = page.nextOffset
        }

        #expect(walked == ["Alpha Project", "Area A", "Area B", "Area C", "Area D", "Area E", "Beta Project"])
        #expect(Set(walked).count == walked.count)
        #expect(walked.count == 7)
        #expect(guardRail == 4)
    }

    // MARK: - T-385, the brief's undisclosed inbox cap

    /// **51 active inbox tasks used to become 50, with nothing in the response saying so.**
    ///
    /// The cap was a bare `.prefix(50)` on one of four sections; `CadenceTodayBrief` carried plain
    /// arrays, so `inbox.count == 50` was both the response a store holding exactly 50 produces and
    /// the response a store holding 5,000 produces. `totalCount` is what separates them, and it is
    /// asserted against a store deliberately **one row over** the old cap — 51, not 200, because
    /// the boundary is where a cap-shaped bug survives.
    @Test func aTruncatedInboxSectionOfTheBriefReportsItsTrueTotal() throws {
        let fixture = try PagingFixture(taskCount: 51)

        // Non-vacuity: these are inbox tasks — no area, no project — and there really are 51.
        #expect(try fixture.service.listTasks(options: .init(limit: 200)).totalCount == 51)

        let brief = try fixture.service.todayBrief(dateKey: "2026-04-28")

        #expect(brief.inbox.totalCount == 51)
        #expect(brief.inbox.returnedCount == 50)
        #expect(brief.inbox.items.count == 50)
        #expect(brief.inbox.hasMore)
        #expect(brief.inbox.nextOffset == 50)
        #expect(brief.inbox.totalCount > brief.inbox.returnedCount)
    }

    /// A caller can now both raise the cap and page past it — the two things the old schema, which
    /// took `date` and nothing else, made impossible.
    @Test func theBriefsSectionsTakeALimitAndAnOffsetFromTheCaller() throws {
        let fixture = try PagingFixture(taskCount: 51)

        let raised = try fixture.service.todayBrief(dateKey: "2026-04-28", limit: 200)
        #expect(raised.inbox.returnedCount == 51)
        #expect(raised.inbox.hasMore == false)
        #expect(raised.inbox.nextOffset == nil)

        let secondPage = try fixture.service.todayBrief(dateKey: "2026-04-28", limit: 50, offset: 50)
        #expect(secondPage.inbox.offset == 50)
        #expect(secondPage.inbox.returnedCount == 1)
        #expect(secondPage.inbox.totalCount == 51)
        #expect(secondPage.inbox.hasMore == false)

        // The two pages together are the whole section, each row once.
        let firstPage = try fixture.service.todayBrief(dateKey: "2026-04-28")
        let walked = firstPage.inbox.items.map(\.id) + secondPage.inbox.items.map(\.id)
        #expect(walked.count == 51)
        #expect(Set(walked).count == 51)

        // `limit: 0` asks the totals question and nothing else.
        let countOnly = try fixture.service.todayBrief(dateKey: "2026-04-28", limit: 0)
        #expect(countOnly.inbox.items.isEmpty)
        #expect(countOnly.inbox.totalCount == 51)
        #expect(countOnly.inbox.hasMore)
    }

    /// **Every section is a page, not only the one that used to be capped.**
    ///
    /// The asymmetry was half the ticket: three unbounded sections beside one silently truncated
    /// one, so no single section told a caller the shape of the response. Each section here is over
    /// the default limit on its own, and each reports its own total.
    @Test func everyTaskSectionOfTheBriefCarriesItsOwnTotal() throws {
        let fixture = try SectionFixture(dateKey: "2026-04-28", perSectionCount: 51)

        let brief = try fixture.service.todayBrief(dateKey: "2026-04-28")

        for (name, section) in [
            ("scheduledTasks", brief.scheduledTasks),
            ("dueToday", brief.dueToday),
            ("overdue", brief.overdue),
            ("inbox", brief.inbox),
        ] {
            #expect(section.totalCount == 51, "\(name) lost its true total")
            #expect(section.returnedCount == 50, "\(name) is not capped at the shared default")
            #expect(section.hasMore, "\(name) does not admit it truncated")
            #expect(section.nextOffset == 50, "\(name) strands the caller")
        }
    }

    /// A brief that fits inside the limit says so, which is what makes `hasMore` worth reading.
    /// Written beside the truncation test because a `hasMore` hardcoded `true` passes that one
    /// alone.
    @Test func aBriefThatFitsInsideTheLimitClaimsNoMore() throws {
        let fixture = try SectionFixture(dateKey: "2026-04-28", perSectionCount: 2)

        let brief = try fixture.service.todayBrief(dateKey: "2026-04-28")

        for section in [brief.scheduledTasks, brief.dueToday, brief.overdue, brief.inbox] {
            // Non-vacuity: every section really holds rows, so this is not four empties agreeing.
            #expect(section.returnedCount == 2)
            #expect(section.totalCount == 2)
            #expect(section.hasMore == false)
            #expect(section.nextOffset == nil)
        }
    }

    /// A store with `perSectionCount` tasks in each of the brief's four task sections.
    ///
    /// The four predicates are not mutually exclusive in general — a task can be scheduled today
    /// *and* due today — so each group here is built to land in exactly one, which is what lets a
    /// per-section total be asserted as a number.
    @MainActor
    private final class SectionFixture {
        let container: ModelContainer
        let modelContext: ModelContext
        let service: CadenceReadService

        init(dateKey: String, perSectionCount: Int) throws {
            container = try CadenceModelContainerFactory.makeInMemoryContainer()
            modelContext = ModelContext(container)

            let context = Context(name: "Work")
            let project = Project(name: "Filed", context: context)
            modelContext.insert(context)
            modelContext.insert(project)

            for index in 0..<perSectionCount {
                let scheduled = AppTask(title: String(format: "Scheduled %02d", index))
                scheduled.project = project
                scheduled.scheduledDate = dateKey
                scheduled.scheduledStartMin = 540
                modelContext.insert(scheduled)

                let due = AppTask(title: String(format: "Due %02d", index))
                due.project = project
                due.dueDate = dateKey
                modelContext.insert(due)

                let overdue = AppTask(title: String(format: "Overdue %02d", index))
                overdue.project = project
                overdue.dueDate = "2026-01-01"
                modelContext.insert(overdue)

                // No container and no dates: the inbox section, and only that one.
                let inbox = AppTask(title: String(format: "Inbox %02d", index))
                modelContext.insert(inbox)
            }
            try modelContext.save()

            service = CadenceReadService(container: container, performsMigrations: false)
        }
    }

    @MainActor
    private final class PagingFixture {
        let container: ModelContainer
        let modelContext: ModelContext
        let service: CadenceReadService

        init(taskCount: Int, areaNames: [String] = [], projectNames: [String] = []) throws {
            container = try CadenceModelContainerFactory.makeInMemoryContainer()
            modelContext = ModelContext(container)

            let context = Context(name: "Work")
            modelContext.insert(context)

            for index in 0..<max(taskCount, 0) {
                let task = AppTask(title: String(format: "Task %02d", index))
                task.context = context
                modelContext.insert(task)
            }
            // Every container sits at `order == 0`, which is the normal shape of a store that
            // numbers each kind from zero — and the shape that makes the merged sort observable.
            for name in areaNames {
                let area = Area(name: name, context: context)
                area.order = 0
                modelContext.insert(area)
            }
            for name in projectNames {
                let project = Project(name: name, context: context)
                project.order = 0
                modelContext.insert(project)
            }
            try modelContext.save()

            service = CadenceReadService(container: container, performsMigrations: false)
        }
    }

    // MARK: - T-372, MCP list order is total or it is noise

    @Test func containerListsHoldTheirOrderWhenDifferentContextsShareAnOrderSlot() throws {
        let forward = try OrderingFixture(reversedInsertion: false)
        let reversed = try OrderingFixture(reversedInsertion: true)

        let forwardContainers = try forward.service.listContainers()
        let reversedContainers = try reversed.service.listContainers()

        #expect(forwardContainers.items.map(\.id) == reversedContainers.items.map(\.id))
        #expect(forwardContainers.items.map(\.id) == OrderingFixture.expectedContainerIDs.map(\.uuidString))
        // Two areas named "Admin" at the same `order` in two contexts: only identity separates them.
        // T-383 merged the two kinds into one ordered list before capping, so "Launch" and "Move"
        // now sit among the `order == 0` rows by name instead of behind every area.
        #expect(forwardContainers.items.map(\.name) == ["Errands", "Launch", "Move", "Operations", "Admin", "Admin"])

        let forwardContexts = try forward.service.listContexts()
        let reversedContexts = try reversed.service.listContexts()
        #expect(forwardContexts.items.map(\.id) == reversedContexts.items.map(\.id))
        #expect(forwardContexts.items.map(\.name) == ["Personal", "Work"])

        let forwardWork = try forward.service.contextSummary(contextID: OrderingFixture.workContextID.uuidString)
        let reversedWork = try reversed.service.contextSummary(contextID: OrderingFixture.workContextID.uuidString)
        #expect(forwardWork.areas.map(\.id) == reversedWork.areas.map(\.id))
        #expect(forwardWork.areas.map(\.name) == ["Operations", "Admin"])
        #expect(forwardWork.projects.map(\.id) == reversedWork.projects.map(\.id))
    }

    @Test func containerSummaryDocumentsAndLinksHoldTheirOrderAcrossReads() throws {
        let forward = try OrderingFixture(reversedInsertion: false)
        let reversed = try OrderingFixture(reversedInsertion: true)

        let forwardSummary = try forward.service.containerSummary(
            kind: "project",
            id: OrderingFixture.launchProjectID.uuidString
        )
        let reversedSummary = try reversed.service.containerSummary(
            kind: "project",
            id: OrderingFixture.launchProjectID.uuidString
        )

        #expect(forwardSummary.documents.map(\.id) == reversedSummary.documents.map(\.id))
        #expect(forwardSummary.documents.map(\.title) == ["Runbook", "Spec", "Charter"])

        #expect(forwardSummary.links.map(\.id) == reversedSummary.links.map(\.id))
        // Two links titled "Design" share `order == 0`; the id leg is the only thing left.
        #expect(forwardSummary.links.map(\.title) == ["Design", "Design", "Roadmap", "Tracker"])
        #expect(forwardSummary.links.map(\.id) == OrderingFixture.expectedLinkIDs.map(\.uuidString))
    }

    @Test func documentAndNoteListsBreakATiedUpdatedAtInsteadOfLeavingItToTheStore() throws {
        let forward = try OrderingFixture(reversedInsertion: false)
        let reversed = try OrderingFixture(reversedInsertion: true)

        let forwardDocs = try forward.service.listDocuments()
        let reversedDocs = try reversed.service.listDocuments()
        #expect(forwardDocs.items.map(\.id) == reversedDocs.items.map(\.id))
        #expect(forwardDocs.items.map(\.id) == OrderingFixture.expectedDocumentIDs.map(\.uuidString))
        #expect(forwardDocs.items.map(\.title) == ["Runbook", "Spec", "Charter"])

        let forwardNotes = try forward.service.listNotes(options: .init(limit: 50))
        let reversedNotes = try reversed.service.listNotes(options: .init(limit: 50))
        #expect(forwardNotes.items.map(\.id) == reversedNotes.items.map(\.id))
        #expect(forwardNotes.items.map(\.id) == OrderingFixture.expectedDocumentIDs.map(\.uuidString))
    }

    /// One store, built twice from the same rows in opposite insertion orders.
    ///
    /// Every id is pinned, so the two runs differ *only* in the sequence the store hands rows back
    /// — which is exactly the difference a partial comparator passes through to the response and a
    /// total one absorbs. Fixture values collide the way the real store collides: `order` is
    /// assigned per container, so areas in different contexts sit at the same slot, and two of them
    /// even share a name.
    ///
    /// The tests assert permutation equality **and** the exact expected sequence. The second half
    /// is what keeps them honest: an unsorted `FetchDescriptor` is free to return the same order
    /// twice, and on such a run permutation equality alone would hold for a partial comparator too.
    /// Asserting the reverse — that the two raw fetch orders *differ* — was tried and removed: it
    /// is a property of the store, not of the code under test, and it was observed both ways
    /// across runs, so it fails against correct code roughly at random.
    @MainActor
    private final class OrderingFixture {
        let container: ModelContainer
        let modelContext: ModelContext
        let service: CadenceReadService

        static func pinnedID(_ byte: UInt8) -> UUID {
            UUID(uuid: (0, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, byte))
        }

        static let workContextID = pinnedID(0x11)
        static let personalContextID = pinnedID(0x12)
        static let operationsAreaID = pinnedID(0x21)
        static let errandsAreaID = pinnedID(0x22)
        static let workAdminAreaID = pinnedID(0x31)
        static let personalAdminAreaID = pinnedID(0x32)
        static let launchProjectID = pinnedID(0x41)
        static let moveProjectID = pinnedID(0x42)
        static let specNoteID = pinnedID(0x51)
        static let runbookNoteID = pinnedID(0x52)
        static let charterNoteID = pinnedID(0x53)
        static let roadmapLinkID = pinnedID(0x61)
        static let designLinkID = pinnedID(0x62)
        static let trackerLinkID = pinnedID(0x63)
        static let duplicateDesignLinkID = pinnedID(0x64)

        /// One merged sequence (`order`, then name, then id) across both kinds — the shape
        /// `listContainers` produces since T-383. It used to concatenate areas ahead of projects,
        /// which is what let a capped call drop every project.
        static let expectedContainerIDs: [UUID] = [
            errandsAreaID, launchProjectID, moveProjectID, operationsAreaID,
            workAdminAreaID, personalAdminAreaID,
        ]

        static let expectedLinkIDs: [UUID] = [
            designLinkID, duplicateDesignLinkID, roadmapLinkID, trackerLinkID,
        ]

        /// `order` first, then title: "Runbook" and "Spec" both sit at slot 0.
        static let expectedDocumentIDs: [UUID] = [runbookNoteID, specNoteID, charterNoteID]

        /// One timestamp for every document, so `updatedAt` decides nothing.
        static let sharedStamp = Date(timeIntervalSince1970: 1_774_000_000)

        init(reversedInsertion: Bool) throws {
            // Locals, not the properties: the nested `insert` below would otherwise capture `self`
            // before every stored property is initialized.
            let container = try CadenceModelContainerFactory.makeInMemoryContainer()
            let modelContext = ModelContext(container)

            let work = Context(name: "Work")
            work.id = Self.workContextID
            work.order = 0
            let personal = Context(name: "Personal")
            personal.id = Self.personalContextID
            personal.order = 0

            let operations = Area(name: "Operations", context: work)
            operations.id = Self.operationsAreaID
            operations.order = 0
            let errands = Area(name: "Errands", context: personal)
            errands.id = Self.errandsAreaID
            errands.order = 0
            let workAdmin = Area(name: "Admin", context: work)
            workAdmin.id = Self.workAdminAreaID
            workAdmin.order = 1
            let personalAdmin = Area(name: "Admin", context: personal)
            personalAdmin.id = Self.personalAdminAreaID
            personalAdmin.order = 1

            let launch = Project(name: "Launch", context: work)
            launch.id = Self.launchProjectID
            launch.order = 0
            let move = Project(name: "Move", context: personal)
            move.id = Self.moveProjectID
            move.order = 0

            func listNote(id: UUID, title: String, order: Int) -> Note {
                Note(
                    id: id,
                    kind: .list,
                    title: title,
                    order: order,
                    createdAt: Self.sharedStamp,
                    updatedAt: Self.sharedStamp,
                    project: launch
                )
            }

            let spec = listNote(id: Self.specNoteID, title: "Spec", order: 0)
            let runbook = listNote(id: Self.runbookNoteID, title: "Runbook", order: 0)
            let charter = listNote(id: Self.charterNoteID, title: "Charter", order: 1)

            func savedLink(id: UUID, title: String, order: Int) -> SavedLink {
                let link = SavedLink(title: title, url: "https://example.com/\(title.lowercased())")
                link.id = id
                link.order = order
                link.project = launch
                return link
            }

            let roadmap = savedLink(id: Self.roadmapLinkID, title: "Roadmap", order: 0)
            let design = savedLink(id: Self.designLinkID, title: "Design", order: 0)
            let tracker = savedLink(id: Self.trackerLinkID, title: "Tracker", order: 1)
            let duplicateDesign = savedLink(id: Self.duplicateDesignLinkID, title: "Design", order: 0)

            func insert<T: PersistentModel>(_ models: [T]) {
                for model in reversedInsertion ? models.reversed() : models {
                    modelContext.insert(model)
                }
            }

            insert([work, personal])
            insert([operations, errands, workAdmin, personalAdmin])
            insert([launch, move])
            insert([spec, runbook, charter])
            insert([roadmap, design, tracker, duplicateDesign])
            try modelContext.save()

            self.container = container
            self.modelContext = modelContext

            // Migrations off: this fixture pins `updatedAt` on purpose, and a migration pass would
            // restamp the rows the recency test needs tied.
            service = CadenceReadService(container: container, performsMigrations: false)
        }
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
