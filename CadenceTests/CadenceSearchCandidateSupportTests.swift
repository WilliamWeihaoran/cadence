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
}
