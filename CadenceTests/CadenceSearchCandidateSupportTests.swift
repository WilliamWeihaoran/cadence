import Foundation
import SwiftData
import Testing
@testable import Cadence

/// The candidate layer both search surfaces now share (T-377) and the list-inclusion rule they
/// now share (T-378).
///
/// `Cadence/iOS/` is behind `#if os(iOS)` and this bundle builds for macOS, so the macOS half is
/// pinned by calling it and the iOS half by scanning its source for the shared calls it must make
/// and the hand-rolled field lists it must no longer contain. Every scan below carries its own
/// non-vacuity assertions; every behavioural test asserts something matched before asserting
/// something did not.
@MainActor
struct CadenceSearchCandidateSupportTests {

    private static let iOSSearchViewPath = "Cadence/iOS/iOSSearchView.swift"

    // MARK: - Fixture

    private struct TaskFixture {
        let tasks: [AppTask]
        let completed: AppTask
        let active: AppTask
        let cancelled: AppTask
        let scheduled: AppTask
        let slugTagged: AppTask
    }

    private func makeTaskFixture() throws -> TaskFixture {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let workContext = Context(name: "Work")
        let area = Area(name: "Operations", context: workContext)
        // A slug the user set by hand, so it does not fold to the same string as the name. This is
        // the only case where searching by slug can find something searching by name cannot.
        let tag = Cadence.Tag(name: "Waiting On", slug: "blocked")

        let completed = AppTask(title: "Ship the beta")
        completed.status = .done
        completed.area = area

        let active = AppTask(title: "Draft the invoice")
        active.area = area

        // Titled with the literal word the alias test searches for, and cancelled: it must stay out
        // of every result set on the strength of its status, not on the strength of its text.
        let cancelled = AppTask(title: "Done deal cleanup")
        cancelled.status = .cancelled

        let scheduled = AppTask(title: "Review the roadmap")
        scheduled.scheduledStartMin = 540

        let slugTagged = AppTask(title: "Chase the vendor")
        slugTagged.tags = [tag]

        let tasks = [completed, active, cancelled, scheduled, slugTagged]
        modelContext.insert(workContext)
        modelContext.insert(area)
        modelContext.insert(tag)
        for task in tasks { modelContext.insert(task) }
        try modelContext.save()

        return TaskFixture(
            tasks: tasks,
            completed: completed,
            active: active,
            cancelled: cancelled,
            scheduled: scheduled,
            slugTagged: slugTagged
        )
    }

    /// The identities the *shared* candidate layer resolves for a query — which is exactly what
    /// `iOSSearchView.rankedTaskResults` now computes, and what `GlobalSearchIndexSupport`
    /// must agree with.
    private func sharedTaskIdentities(_ tasks: [AppTask], query: String) -> Set<String> {
        Set(
            tasks
                .filter { CadenceTaskSearchSupport.isSearchable($0, includingCompleted: true) }
                .filter { CadenceTaskSearchSupport.matchScore(query: query, task: $0) != nil }
                .map { "task-\($0.id.uuidString)" }
        )
    }

    /// The field list `iOSSearchView` built before T-377: no lifecycle aliases, tag *names* only.
    private func fieldsBeforeTheSharedHelper(_ task: AppTask) -> [String] {
        [
            task.title,
            task.notes,
            task.containerName,
            task.resolvedSectionName,
            task.priority.label,
            task.sortedTags.map(\.name).joined(separator: " ")
        ]
    }

    // MARK: - T-377: one task-candidate layer

    @Test func searchingDoneResolvesOneFixtureToTheSameTaskIdentitiesOnBothSurfaces() throws {
        let fixture = try makeTaskFixture()

        let desktop = Set(GlobalSearchIndexSupport.taskResults(tasks: fixture.tasks, query: "done").map(\.id))
        let shared = sharedTaskIdentities(fixture.tasks, query: "done")

        // Non-vacuity: the fixture is real, something matched, and the match was selective.
        #expect(fixture.tasks.count == 5)
        #expect(!desktop.isEmpty)
        #expect(desktop.count < fixture.tasks.count)

        #expect(desktop == shared)
        #expect(desktop == ["task-\(fixture.completed.id.uuidString)"])
        // Cancelled work is unsearchable even when the query is a word in its title.
        #expect(!desktop.contains("task-\(fixture.cancelled.id.uuidString)"))

        // And the same call over an empty fixture pins nothing, which is why the assertions above
        // had to say what they found rather than only what they did not.
        #expect(GlobalSearchIndexSupport.taskResults(tasks: [], query: "done").isEmpty)
        #expect(sharedTaskIdentities([], query: "done").isEmpty)
    }

    @Test func aCompletedTaskAnswersToDoneAndCompletedThroughTheSharedAliases() throws {
        let fixture = try makeTaskFixture()

        #expect(CadenceTaskSearchSupport.matchScore(query: "done", task: fixture.completed) != nil)
        #expect(CadenceTaskSearchSupport.matchScore(query: "completed", task: fixture.completed) != nil)
        #expect(CadenceTaskSearchSupport.matchScore(query: "done", task: fixture.active) == nil)
        #expect(CadenceTaskSearchSupport.matchScore(query: "active", task: fixture.active) != nil)

        // What iOS did before: the same task, scored against a field list with no aliases in it.
        #expect(
            CadenceSearchMatcher.matchScore(
                query: "done",
                fields: fieldsBeforeTheSharedHelper(fixture.completed)
            ) == nil
        )
    }

    @Test func aTaskTagMatchesByItsNameAndByItsHandSetSlug() throws {
        let fixture = try makeTaskFixture()
        let tag = try #require(fixture.slugTagged.sortedTags.first)

        #expect(tag.name == "Waiting On")
        #expect(tag.slug == "blocked")
        #expect(CadenceTaskSearchSupport.matchScore(query: "waiting", task: fixture.slugTagged) != nil)
        #expect(CadenceTaskSearchSupport.matchScore(query: "blocked", task: fixture.slugTagged) != nil)

        // The slug half is the half iOS was missing.
        #expect(
            CadenceSearchMatcher.matchScore(
                query: "blocked",
                fields: fieldsBeforeTheSharedHelper(fixture.slugTagged)
            ) == nil
        )

        let byName = Set(GlobalSearchIndexSupport.taskResults(tasks: fixture.tasks, query: "waiting").map(\.id))
        let bySlug = Set(GlobalSearchIndexSupport.taskResults(tasks: fixture.tasks, query: "blocked").map(\.id))
        #expect(byName == ["task-\(fixture.slugTagged.id.uuidString)"])
        #expect(bySlug == byName)
        #expect(bySlug == sharedTaskIdentities(fixture.tasks, query: "blocked"))
    }

    @Test func theSharedGlyphSeparatesScheduledFromDoneAndActive() throws {
        let fixture = try makeTaskFixture()

        #expect(CadenceTaskSearchSupport.glyph(for: fixture.scheduled) == .scheduled)
        #expect(CadenceTaskSearchSupport.glyph(for: fixture.completed) == .completed)
        #expect(CadenceTaskSearchSupport.glyph(for: fixture.active) == .active)

        let result = try #require(
            GlobalSearchIndexSupport.taskResults(tasks: fixture.tasks, query: "roadmap").first
        )
        #expect(result.icon == "calendar.badge.clock")
        #expect(GlobalSearchIndexSupport.taskIcon(for: .active) == "checkmark.circle")
    }

    @Test func anInboxTaskIsFindableByTypingInboxOnBothSurfaces() throws {
        let fixture = try makeTaskFixture()

        #expect(CadenceTaskSearchSupport.containerLabel(for: fixture.scheduled) == "Inbox")
        #expect(CadenceTaskSearchSupport.containerLabel(for: fixture.active) == "Operations")

        let inboxHits = sharedTaskIdentities(fixture.tasks, query: "inbox")
        #expect(inboxHits.contains("task-\(fixture.scheduled.id.uuidString)"))
        #expect(!inboxHits.contains("task-\(fixture.active.id.uuidString)"))
    }

    // MARK: - T-378: one list-inclusion policy

    private struct ListFixture {
        let areas: [Area]
        let projects: [Project]
        let activeArea: Area
        let archivedArea: Area
        let completedProject: Project
        let cancelledProject: Project
    }

    private func makeListFixture() throws -> ListFixture {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let home = Context(name: "Home")
        let activeArea = Area(name: "Operations", context: home)
        let archivedArea = Area(name: "Garage Rebuild", context: home)
        archivedArea.status = .archived

        let completedProject = Project(name: "Kitchen Remodel", context: home)
        completedProject.status = .done
        let cancelledProject = Project(name: "Atlas Migration", context: home)
        cancelledProject.status = .cancelled

        modelContext.insert(home)
        modelContext.insert(activeArea)
        modelContext.insert(archivedArea)
        modelContext.insert(completedProject)
        modelContext.insert(cancelledProject)
        try modelContext.save()

        return ListFixture(
            areas: [activeArea, archivedArea],
            projects: [completedProject, cancelledProject],
            activeArea: activeArea,
            archivedArea: archivedArea,
            completedProject: completedProject,
            cancelledProject: cancelledProject
        )
    }

    @Test func typingReachesFinishedListsWhileIdleSuggestionsStayActiveOnly() throws {
        let fixture = try makeListFixture()

        #expect(CadenceListSearchSupport.isSearchable(fixture.archivedArea, query: "garage"))
        #expect(!CadenceListSearchSupport.isSearchable(fixture.archivedArea, query: "   "))
        #expect(CadenceListSearchSupport.isSearchable(fixture.activeArea, query: ""))
        #expect(CadenceListSearchSupport.isSearchable(fixture.completedProject, query: "kitchen"))
        #expect(!CadenceListSearchSupport.isSearchable(fixture.completedProject, query: ""))

        let idle = GlobalSearchIndexSupport.areaResults(areas: fixture.areas, query: "")
        let searched = GlobalSearchIndexSupport.areaResults(areas: fixture.areas, query: "garage")

        // Non-vacuity: the idle list is not simply empty, and the search found something.
        #expect(idle.map(\.id) == ["area-\(fixture.activeArea.id.uuidString)"])
        #expect(searched.map(\.id) == ["area-\(fixture.archivedArea.id.uuidString)"])
    }

    @Test func aFinishedListAnswersToItsOwnLifecycleWords() throws {
        let fixture = try makeListFixture()

        #expect(CadenceListSearchSupport.matchScore(query: "archived", area: fixture.archivedArea) != nil)
        #expect(CadenceListSearchSupport.matchScore(query: "archived", area: fixture.activeArea) == nil)
        #expect(CadenceListSearchSupport.matchScore(query: "completed", project: fixture.completedProject) != nil)
        #expect(CadenceListSearchSupport.matchScore(query: "done", project: fixture.completedProject) != nil)
        #expect(CadenceListSearchSupport.matchScore(query: "done", project: fixture.cancelledProject) == nil)

        let archivedHits = GlobalSearchIndexSupport.areaResults(areas: fixture.areas, query: "archived")
        #expect(archivedHits.map(\.id) == ["area-\(fixture.archivedArea.id.uuidString)"])
    }

    @Test func aCancelledProjectIsLabelledCancelledRatherThanActive() throws {
        let fixture = try makeListFixture()

        #expect(CadenceListSearchSupport.lifecycle(of: fixture.cancelledProject).statusLabel == "Cancelled")
        #expect(CadenceListSearchSupport.lifecycle(of: fixture.completedProject).statusLabel == "Completed")
        #expect(CadenceListSearchSupport.lifecycle(of: fixture.archivedArea).statusLabel == "Archived")

        let result = try #require(
            GlobalSearchIndexSupport.projectResults(projects: fixture.projects, query: "atlas").first
        )
        #expect(result.subtitle.hasSuffix("Cancelled"))
        #expect(!result.subtitle.contains("Active"))
    }

    // MARK: - The iOS half, read as source

    @Test func theIOSSearchSurfaceRoutesTaskCandidatesThroughTheSharedHelper() throws {
        let raw = try CadenceSourceScan.sourceFile(Self.iOSSearchViewPath)
        let stripped = CadenceSourceScan.strippingComments(raw)

        // Non-vacuity: the file was read, and the stripper ran without shortening it.
        #expect(raw.contains("struct iOSSearchView"))
        #expect(stripped != raw)
        #expect(stripped.count == raw.count)
        #expect(stripped.contains("private var rankedTaskResults"))

        #expect(stripped.contains("CadenceTaskSearchSupport.isSearchable("))
        #expect(stripped.contains("CadenceTaskSearchSupport.matchScore(query: trimmedQuery, task: task)"))
        #expect(stripped.contains("CadenceTaskSearchSupport.glyph(for: task)"))
        #expect(stripped.contains("CadenceSearchTagSupport.text(for: note.sortedTags)"))

        // Scoped to the function, not to the file: `eventResult` also draws
        // `calendar.badge.clock`, so a file-wide `contains` for it would pass at HEAD.
        let iconBody = try #require(CadenceSourceScan.functionBody(named: "taskIcon", in: stripped))
        #expect(iconBody.contains("case .scheduled: \"calendar.badge.clock\""))
        #expect(iconBody.contains("case .completed: \"checkmark.circle.fill\""))
        #expect(iconBody.contains("case .active: \"circle\""))

        // The hand-rolled halves that drifted: a tag field built from names alone, and a task
        // filter written out longhand.
        #expect(!stripped.contains("sortedTags.map(\\.name)"))
        #expect(!stripped.contains("includeCompletedTasks || !task.isDone"))
        #expect(CadenceSourceScan.matchCount("task\\.priority\\.label,", in: stripped) == 0)
        // Self-check for the regex above: it must match the shape it is looking for.
        #expect(CadenceSourceScan.matchCount("task\\.priority\\.label,", in: "  task.priority.label,\n") == 1)
    }

    @Test func theIOSSearchSurfaceRoutesListInclusionThroughTheSharedPolicy() throws {
        let raw = try CadenceSourceScan.sourceFile(Self.iOSSearchViewPath)
        let stripped = CadenceSourceScan.strippingComments(raw)

        #expect(raw.contains("struct iOSSearchView"))
        #expect(stripped != raw)
        #expect(stripped.contains("private var listResults"))

        #expect(stripped.contains("CadenceListSearchSupport.isSearchable($0, query: trimmedQuery)"))
        #expect(stripped.contains("CadenceListSearchSupport.searchFields(for: area)"))
        #expect(stripped.contains("CadenceListSearchSupport.searchFields(for: project)"))
        #expect(stripped.contains("CadenceListSearchSupport.lifecycle(of: area)"))

        // The pre-filter this ticket removed. `filter(\.isActive)` is still the right thing for a
        // picker; it is no longer the right thing for search.
        #expect(!stripped.contains("filter(\\.isActive)"))
        #expect(CadenceSourceScan.matchCount("areas\\.filter\\(\\\\\\.isActive\\)", in: stripped) == 0)
        #expect(
            CadenceSourceScan.matchCount(
                "areas\\.filter\\(\\\\\\.isActive\\)",
                in: "let x = areas.filter(\\.isActive)\n"
            ) == 1
        )
    }

    // MARK: - T-372a: Cmd+K's tie-break

    /// **`Cmd+K` ranks two indistinguishable rows by id, not by whatever `@Query` handed over.**
    ///
    /// `rankedResults` is the one call site every macOS search section funnels through, and until
    /// T-372a it called `CadenceSearchMatcher.rank` without an `identity`, so its order stopped at
    /// title. Two tasks called "Admin" in two lists score the same and title the same, so the
    /// comparator answered "neither" and the sort could only echo the order the index was built
    /// in — which changes when an unrelated task is edited, moving the arrow-key target between
    /// keystrokes.
    ///
    /// The fixture is handed over in *descending* id order on purpose: with the tie-break removed
    /// the answer is the input, so an ascending fixture would pass either way.
    @Test func cmdKRanksTwoIdenticalRowsByIdRatherThanTheOrderTheIndexWasBuiltIn() {
        func result(id: String) -> GlobalSearchResult {
            GlobalSearchResult(
                id: id,
                category: .tasks,
                title: "Admin",
                subtitle: "Inbox • Active",
                icon: "checkmark.circle",
                tintHex: Theme.blueHex,
                destination: .goals
            )
        }
        let descending = ["task-c", "task-b", "task-a"].map(result(id:))

        let ranked = GlobalSearchIndexSupport.rankedResults(descending, query: "admin")

        #expect(ranked.map(\.id) == ["task-a", "task-b", "task-c"])
        // And it is the *set* that decides, not the arrival order.
        #expect(GlobalSearchIndexSupport.rankedResults(descending.reversed(), query: "admin").map(\.id) == ranked.map(\.id))
    }

    // MARK: - T-479: the iOS surface's tie-break

    private static let iOSSearchSupportPath = "Cadence/iOS/iOSSearchSupportViews.swift"

    /// A UUID identifies a row only as long as no second table is in the list with it.
    ///
    /// **Behavioural.** iOS's Lists section is areas *and* projects and its "Goals and Habits"
    /// section is both; macOS's palette merges nine categories into one ranked list. So the
    /// identity leg has to carry the entity **type**, which is the same conclusion
    /// `CadenceReadService.search` reached when it tied on `entityType:entityId` rather than on
    /// `entityId` (T-372a).
    ///
    /// The fixture gives every case the *same* UUID on purpose: that is the collision a bare
    /// `uuidString` cannot survive, and nothing else in the string would distinguish them.
    @Test func aSearchIdentityCarriesTheEntityTypeSoOneSectionCanMergeTwoTables() {
        let shared = UUID()
        let byType = [
            CadenceSearchIdentity.task(shared),
            CadenceSearchIdentity.area(shared),
            CadenceSearchIdentity.project(shared),
            CadenceSearchIdentity.goal(shared),
            CadenceSearchIdentity.habit(shared),
            CadenceSearchIdentity.note(shared),
            CadenceSearchIdentity.eventNote(shared)
        ]

        #expect(byType.count == 7)
        #expect(Set(byType).count == 7, "two entity types share an identity: \(byType)")
        #expect(byType.allSatisfy { $0.hasSuffix(shared.uuidString) })

        // The values, pinned. macOS's palette has spelled these nine since long before T-479 and
        // this change moved them behind the enum without changing one of them.
        #expect(CadenceSearchIdentity.task(shared) == "task-\(shared.uuidString)")
        #expect(CadenceSearchIdentity.area(shared) == "area-\(shared.uuidString)")
        #expect(CadenceSearchIdentity.project(shared) == "project-\(shared.uuidString)")
        #expect(CadenceSearchIdentity.goal(shared) == "goal-\(shared.uuidString)")
        #expect(CadenceSearchIdentity.habit(shared) == "habit-\(shared.uuidString)")
        #expect(CadenceSearchIdentity.note(shared) == "note-\(shared.uuidString)")
        #expect(CadenceSearchIdentity.eventNote(shared) == "event-note-\(shared.uuidString)")
        #expect(CadenceSearchIdentity.event("series-1") == "event-series-1")
        #expect(CadenceSearchIdentity.page("today") == "page-today")
        #expect(CadenceSearchIdentity.command("newTask") == "command-newTask")
    }

    /// The macOS half of the same claim, called rather than read: the two catalog sections need no
    /// store, so their ids can be checked against the strings the palette shipped with.
    @Test func theMacOSPaletteStillBuildsTheIdsItAlwaysDid() throws {
        let commands = GlobalSearchIndexSupport.commandResults(
            query: "",
            sidebarTabColorsRaw: CadencePreferenceKeys.emptySidebarPreference
        )
        let pages = GlobalSearchIndexSupport.pageResults(
            query: "",
            hiddenTabs: [],
            sidebarTabColorsRaw: CadencePreferenceKeys.emptySidebarPreference
        )

        // Non-vacuity: both catalogs produced rows, so `allSatisfy` is not passing on nothing.
        #expect(commands.count > 3)
        #expect(pages.count > 3)
        #expect(commands.allSatisfy { $0.id.hasPrefix("command-") })
        #expect(pages.allSatisfy { $0.id.hasPrefix("page-") })
        #expect(Set(commands.map(\.id)).count == commands.count)
        #expect(Set(pages.map(\.id)).count == pages.count)

        let first = try #require(GlobalSearchCommandDefinition.all.first)
        #expect(commands.contains { $0.id == "command-\(first.command.rawValue)" })

        let fixture = try makeTaskFixture()
        let tasks = GlobalSearchIndexSupport.taskResults(tasks: fixture.tasks, query: "roadmap")
        #expect(tasks.map(\.id) == ["task-\(fixture.scheduled.id.uuidString)"])
    }

    /// **Behavioural, and it is the type prefix that is under test.**
    ///
    /// Four rows from the one section that merges goals and habits. Every adjacent pair disagrees
    /// on exactly one tier while the tiers *below* it point the other way, which is what makes the
    /// expectation discriminating — the trap T-372a's agent recorded is a fixture whose score order
    /// and title order agree, where sorting by either alone gives the same answer.
    ///
    /// - `Admin/goal-…0002` before `Admin/habit-…0001`: same score, same title, **identity**
    ///   decides — and it decides on the prefix, because the UUIDs point the other way. That pair
    ///   is the whole argument for the prefix, asserted again below by ranking the same rows on
    ///   bare UUIDs and watching them swap.
    /// - both before `Zulu/goal-…0001`: same score, **title** decides, against an identity that
    ///   sorts first.
    /// - all before `AAA/goal-…0000`, whose title and identity both sort first and whose **score**
    ///   does not.
    @Test func twoRowsFromDifferentTablesInOneSectionRankByTypeThenEntity() {
        func uuid(_ tail: Int) -> UUID {
            UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", tail)) ?? UUID()
        }
        struct Row { let title: String; let score: Int; let identity: String; let entity: UUID }

        let rows = [
            Row(title: "Admin", score: 100, identity: CadenceSearchIdentity.goal(uuid(2)), entity: uuid(2)),
            Row(title: "Admin", score: 100, identity: CadenceSearchIdentity.habit(uuid(1)), entity: uuid(1)),
            Row(title: "Zulu", score: 100, identity: CadenceSearchIdentity.goal(uuid(1)), entity: uuid(1)),
            Row(title: "AAA", score: 50, identity: CadenceSearchIdentity.goal(uuid(0)), entity: uuid(0))
        ]

        func ranked(_ input: [Row], identity: @escaping (Row) -> String) -> [String] {
            CadenceSearchMatcher.rank(input, score: { $0.score }, title: { $0.title }, identity: identity)
                .map { "\($0.title)/\($0.identity)" }
        }

        let byIdentity = ranked(rows) { $0.identity }
        #expect(byIdentity == [
            "Admin/\(CadenceSearchIdentity.goal(uuid(2)))",
            "Admin/\(CadenceSearchIdentity.habit(uuid(1)))",
            "Zulu/\(CadenceSearchIdentity.goal(uuid(1)))",
            "AAA/\(CadenceSearchIdentity.goal(uuid(0)))"
        ])

        // A function of the *set*, not of the order the store handed the rows over in — the
        // property the whole leg exists for, and the one a bare `.sorted { $0.score > $1.score }`
        // cannot have.
        #expect(ranked(rows.reversed()) { $0.identity } == byIdentity)

        // The prefix is load-bearing: on bare UUIDs the first two swap, because habit …0001 sorts
        // ahead of goal …0002.
        let byBareUUID = ranked(rows) { $0.entity.uuidString }
        #expect(byBareUUID != byIdentity)
        #expect(byBareUUID.first == "Admin/\(CadenceSearchIdentity.habit(uuid(1)))")
    }

    /// **Behavioural.** An event row's identity is occurrence-scoped, and it has to be.
    ///
    /// `CadenceCalendarEventSearchSupport.identity(of:)` deliberately drops the `#occurrence=`
    /// suffix and says why: the leg before it there is the start instant, which two occurrences of
    /// one series never share. Here the leg before it is the **score**, and a week of the same
    /// standup scores and titles identically — so the suffix is the only thing left to separate
    /// them, and `rawIdentifier` would put the whole series back in fetch order.
    @Test func aRecurringSeriesRanksByOccurrenceRatherThanByTheIdentifierItsOccurrencesShare() {
        let base = "series-1"
        let monday = Date(timeIntervalSince1970: 1_700_000_000)
        let tuesday = monday.addingTimeInterval(86_400)
        let first = CadenceEventNoteSupport.occurrenceIdentifier(baseIdentifier: base, occurrenceDate: monday)
        let second = CadenceEventNoteSupport.occurrenceIdentifier(baseIdentifier: base, occurrenceDate: tuesday)

        #expect(first != second)
        #expect(CadenceEventNoteSupport.lookupIdentifier(from: first) == base)
        #expect(CadenceEventNoteSupport.lookupIdentifier(from: second) == base)

        struct Row { let occurrence: String }
        let rows = [Row(occurrence: second), Row(occurrence: first)]

        func ranked(_ input: [Row], identity: @escaping (Row) -> String) -> [String] {
            CadenceSearchMatcher.rank(input, score: { _ in 100 }, title: { _ in "Standup" }, identity: identity)
                .map(\.occurrence)
        }

        let scoped = ranked(rows) { CadenceSearchIdentity.event($0.occurrence) }
        #expect(scoped == [first, second])
        #expect(ranked(rows.reversed()) { CadenceSearchIdentity.event($0.occurrence) } == scoped)

        // The identifier the other comparator uses is the same string for both, so it cannot break
        // this tie: the sort can only echo its input, and the two calls disagree.
        let raw = { (row: Row) in CadenceEventNoteSupport.lookupIdentifier(from: row.occurrence) }
        #expect(ranked(rows) { CadenceSearchIdentity.event(raw($0)) } != ranked(rows.reversed()) { CadenceSearchIdentity.event(raw($0)) })
    }

    /// **Source-shape, not behavioural.** `Cadence/iOS/` is behind `#if os(iOS)` and this bundle
    /// builds for macOS, so nothing here calls `iOSSearchIndexSupport.rankedResults`; the claim is
    /// that all six scored sections reach it and that none of them still sorts on score alone.
    @Test func everyScoredIOSSearchSectionRanksThroughTheOneFunnel() throws {
        let raw = try CadenceSourceScan.sourceFile(Self.iOSSearchViewPath)
        let stripped = CadenceSourceScan.strippingComments(raw)

        // Non-vacuity: the file was read, the stripper ran, and all six sections are still here.
        #expect(raw.contains("struct iOSSearchView"))
        #expect(stripped != raw)
        #expect(stripped.count == raw.count)
        for section in ["pageResults", "listResults", "noteResults", "progressResults", "eventResults", "rankedTaskResults"] {
            #expect(stripped.contains("private var \(section)"), "\(section) is no longer a section on this screen")
        }

        #expect(CadenceSourceScan.matchCount("iOSSearchIndexSupport\\.rankedResults\\(", in: stripped) == 6)

        // The six bare comparators this ticket removed, and a self-check that the pattern still
        // matches the shape it is looking for.
        #expect(CadenceSourceScan.matchCount("\\.sorted \\{ \\$0\\.score", in: stripped) == 0)
        #expect(
            CadenceSourceScan.matchCount("\\.sorted \\{ \\$0\\.score", in: "    .sorted { $0.score > $1.score }\n") == 1
        )
    }

    /// **Source-shape.** The funnel itself, and the identity it ties on.
    ///
    /// `iOSSearchResult.id` was `let id = UUID()`, minted per construction — total, but a
    /// *different* total order on every recomputation, which is the nondeterminism the leg exists
    /// to remove rather than a fix for it.
    @Test func theIOSFunnelTiesOnAStableIdentityRatherThanAFreshUUID() throws {
        let raw = try CadenceSourceScan.sourceFile(Self.iOSSearchSupportPath)
        let stripped = CadenceSourceScan.strippingComments(raw)

        #expect(raw.contains("struct iOSSearchResult"))
        #expect(stripped != raw)
        #expect(stripped.contains("enum iOSSearchIndexSupport"))

        let funnel = try #require(CadenceSourceScan.functionBody(named: "rankedResults", in: stripped))
        #expect(funnel.contains("CadenceSearchMatcher.rank("))
        #expect(funnel.contains("score: { $0.score }"))
        #expect(funnel.contains("title: { $0.title }"))
        #expect(funnel.contains("identity: { $0.id }"))

        #expect(stripped.contains("let id: String"))
        #expect(CadenceSourceScan.matchCount("let id = UUID\\(\\)", in: stripped) == 0)
        #expect(CadenceSourceScan.matchCount("let id = UUID\\(\\)", in: "    let id = UUID()\n") == 1)

        // Every section's identity is spelled by the shared enum: areas and projects here, the
        // other five in the view.
        #expect(stripped.contains("CadenceSearchIdentity.area(id)"))
        #expect(stripped.contains("CadenceSearchIdentity.project(id)"))
        #expect(stripped.contains("CadenceSearchIdentity.page(destination.rawValue)"))

        let view = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.iOSSearchViewPath))
        #expect(view.contains("CadenceSearchIdentity.task(task.id)"))
        #expect(view.contains("CadenceSearchIdentity.note(note.id)"))
        #expect(view.contains("CadenceSearchIdentity.goal(goal.id)"))
        #expect(view.contains("CadenceSearchIdentity.habit(habit.id)"))
        #expect(view.contains("CadenceSearchIdentity.event(CadenceEventNoteSupport.identifier(for: event))"))
    }

    // MARK: - T-498: the idle window

    /// **Behavioural, and about *membership* rather than arrangement.**
    ///
    /// T-479 fixed the scored branches. The idle ones cut `prefix(8)` out of a partial order, and
    /// on a partial order the window is not merely arranged unpredictably — rows tied with the last
    /// one that fits are *dropped* by fetch order, so which suggestions the screen offers changes
    /// between two identical reads.
    ///
    /// The fixture is the smallest shape that shows it: three rows, a limit of two, and a tie
    /// spanning the cut. Handed over in both directions on purpose — with the identity leg removed
    /// the answer is whichever of the tied rows the input happened to list first, so a single
    /// direction would pass either way.
    @Test func anIdleSuggestionWindowKeepsTheSameRowsWhicheverOrderTheStoreHandsThemOver() {
        struct Row: Equatable { let key: Int; let identity: String }
        let rows = [
            Row(key: 0, identity: "task-b"),
            Row(key: 1, identity: "task-c"),
            Row(key: 1, identity: "task-a")
        ]

        func window(_ input: [Row]) -> [String] {
            CadenceSearchSuggestionWindow.take(
                input,
                limit: 2,
                identity: \.identity,
                orderedBefore: { $0.key < $1.key }
            ).map(\.identity)
        }

        #expect(window(rows) == ["task-b", "task-a"])
        #expect(window(rows.reversed()) == ["task-b", "task-a"])

        // The claim the ticket is actually about: a bare `prefix` off the same partial order
        // answers with a *different set* depending on which way the rows arrived. Both of these
        // are what the four idle sections used to return.
        #expect(Array(rows.prefix(2)).map(\.identity) == ["task-b", "task-c"])
        #expect(Array(rows.reversed().prefix(2)).map(\.identity) == ["task-a", "task-c"])
    }

    /// The caller's comparator still decides, and the identity leg is strictly last: a row that
    /// sorts first by identity and last by key stays last.
    @Test func theIdleWindowBreaksTiesWithoutOverridingTheOrderTheSectionAskedFor() {
        struct Row { let key: Int; let identity: String }
        let rows = [Row(key: 9, identity: "aaa"), Row(key: 1, identity: "zzz")]

        let ordered = CadenceSearchSuggestionWindow.take(
            rows,
            limit: 2,
            identity: \.identity,
            orderedBefore: { $0.key < $1.key }
        )
        #expect(ordered.map(\.identity) == ["zzz", "aaa"])

        // A shorter limit is a window, not a sort: it must cut *after* ordering.
        #expect(
            CadenceSearchSuggestionWindow.take(rows, limit: 1, identity: \.identity, orderedBefore: { $0.key < $1.key })
                .map(\.identity) == ["zzz"]
        )
    }

    /// The two-table rank the Lists and Goals-and-Habits sections merge on: table first, then the
    /// user's manual order. Both legs, because a rank that compared only `order` would interleave
    /// projects into the areas and a rank that compared only `table` would be no order at all.
    @Test func theTwoTableSuggestionRankPutsTheTableBeforeTheManualOrder() {
        let firstArea = CadenceSearchSuggestionRank(table: 0, order: 0)
        let lastArea = CadenceSearchSuggestionRank(table: 0, order: 99)
        let firstProject = CadenceSearchSuggestionRank(table: 1, order: 0)

        #expect(firstArea < lastArea)
        #expect(lastArea < firstProject)
        #expect((firstProject < firstArea) == false)
        // Equal ranks are equal, which is what leaves the identity leg something to decide.
        #expect((firstArea < CadenceSearchSuggestionRank(table: 0, order: 0)) == false)
        #expect(firstArea == CadenceSearchSuggestionRank(table: 0, order: 0))
    }

    /// **Source-shape.** `Cadence/iOS/` is behind `#if os(iOS)`, so this bundle cannot call the
    /// four idle branches; the claim is that each of them cuts its window through the shared
    /// helper and that the two sections the ticket exempts are untouched.
    @Test func everyIdleIOSSearchSectionCutsItsWindowFromATotalOrder() throws {
        let raw = try CadenceSourceScan.sourceFile(Self.iOSSearchViewPath)
        let stripped = CadenceSourceScan.strippingComments(raw)

        // Non-vacuity: the file was read, the stripper ran, and the sections are still here.
        #expect(raw.contains("struct iOSSearchView"))
        #expect(stripped != raw)
        #expect(stripped.count == raw.count)
        for section in ["taskResults", "listResults", "noteResults", "progressResults", "eventResults", "pageResults"] {
            #expect(stripped.contains("private var \(section)"), "\(section) is no longer a section on this screen")
        }

        // Four idle branches, four windows.
        #expect(CadenceSourceScan.matchCount("CadenceSearchSuggestionWindow\\.take\\(", in: stripped) == 4)

        // And the bare cuts they replaced are gone. `pageResults` takes its five off a static
        // catalog and `eventResults` its eight off `CadenceCalendarEventSearchSupport.precedes`,
        // which has been total since T-373 — so exactly one `.prefix(8)` is correct here, and it
        // is the events one.
        #expect(CadenceSourceScan.matchCount("\\.prefix\\(8\\)", in: stripped) == 1)
        #expect(stripped.contains("calendarSearchEvents.prefix(8)"))
        #expect(stripped.contains("candidates.prefix(5)"))
        // Self-check for the regex above: it matches the shape it is looking for.
        #expect(CadenceSourceScan.matchCount("\\.prefix\\(8\\)", in: "  return notes.prefix(8)\n") == 1)

        // Each window's identity leg is the shared spelling, not a tenth inline one.
        for identity in [
            "identity: { CadenceSearchIdentity.task($0.id) }",
            "identity: { CadenceSearchIdentity.note($0.id) }",
            "identity: \\.identity",
            "identity: { $0.result.id }"
        ] {
            #expect(stripped.contains(identity), "an idle window ties on something else: \(identity)")
        }

        // The score funnel is still the *searching* branches' and only theirs: six sections, six
        // calls. An idle list is chronological or manual on purpose, and routing it through the
        // funnel would re-sort all four to alphabetical, since with no query every row scores 0.
        #expect(CadenceSourceScan.matchCount("iOSSearchIndexSupport\\.rankedResults\\(", in: stripped) == 6)
    }
}
