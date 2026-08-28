import Foundation
import SwiftData
import Testing
@testable import Cadence

/// `AppTask.context` is a denormalized copy of the context the task's list belongs to, and a copy
/// is only as good as the rule that writes it.
///
/// Two ways that copy went wrong, both closed by spelling the rule once as
/// `Project.resolvedContext`:
///
/// - **T-292, create versus move.** A project can inherit its context from its area. The move path
///   (`CadenceTaskMutationSupport.assignContainer`) applied that fallback; seven creation and drag
///   paths wrote `project.context` alone. So two tasks sitting in one project carried different
///   contexts based only on how they got there.
/// - **T-293, editing the list.** Changing a project's context or area on iOS re-pointed the
///   project and left every task in it pointing at the old context.
///
/// The fixture below is the shape that tells the difference: a project whose **own** `context` is
/// `nil`, owned by an area that has one. Any test using a project with its own context passes
/// either way.
@MainActor
struct CadenceTaskContextInheritanceTests {
    private struct Fixture {
        let modelContext: ModelContext
        let work: Context
        let personal: Context
        let operations: Area
        let launch: Project
    }

    private func makeFixture() throws -> Fixture {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())

        let work = Context(name: "Work")
        let personal = Context(name: "Personal")
        let operations = Area(name: "Operations", context: work)
        // The project names no context of its own; everything it has, it has from `operations`.
        let launch = Project(name: "Launch", context: nil, area: operations)
        launch.sectionNames = [TaskSectionDefaults.defaultName, "Build"]
        for model in [work, personal] { modelContext.insert(model) }
        modelContext.insert(operations)
        modelContext.insert(launch)
        try modelContext.save()

        return Fixture(
            modelContext: modelContext,
            work: work,
            personal: personal,
            operations: operations,
            launch: launch
        )
    }

    // MARK: - T-292, create versus move

    @Test func creatingAndMovingIntoOneAreaOwnedProjectAgreeOnTheAreasContext() throws {
        let fixture = try makeFixture()

        let created = try #require(
            TaskCreationService(areas: [fixture.operations], projects: [fixture.launch])
                .insertTask(
                    from: TaskCreationDraft(
                        title: "Created here",
                        notes: "",
                        priority: .none,
                        container: .project(fixture.launch.id),
                        sectionName: TaskSectionDefaults.defaultName,
                        dueDateKey: "",
                        scheduledDateKey: "",
                        subtaskTitles: [],
                        tags: []
                    ),
                    into: fixture.modelContext
                )
        )

        let moved = AppTask(title: "Moved here")
        fixture.modelContext.insert(moved)
        try fixture.modelContext.save()
        CadenceTaskMutationSupport.moveToContainer(
            moved,
            area: nil,
            project: fixture.launch,
            allTasks: [created, moved],
            modelContext: fixture.modelContext
        )

        #expect(created.project?.id == fixture.launch.id)
        #expect(moved.project?.id == fixture.launch.id)
        #expect(created.context?.id == fixture.work.id)
        #expect(moved.context?.id == fixture.work.id)
        #expect(created.context?.id == moved.context?.id)
    }

    @Test func anMCPWriteFilesIntoAnAreaOwnedProjectWithTheAreasContext() throws {
        let fixture = try makeFixture()
        let writeService = CadenceWriteService(context: fixture.modelContext)

        let detail = try writeService.createTask(options: .init(
            title: "Filed by an agent",
            containerKind: "project",
            containerId: fixture.launch.id.uuidString
        ))

        let taskID = try #require(UUID(uuidString: detail.summary.id))
        let stored = try fixture.modelContext.fetch(FetchDescriptor<AppTask>())
        let task = try #require(stored.first { $0.id == taskID })
        #expect(task.project?.id == fixture.launch.id)
        #expect(task.context?.id == fixture.work.id)
    }

    @Test func aProjectsOwnContextStillBeatsItsAreas() throws {
        let fixture = try makeFixture()
        fixture.launch.context = fixture.personal
        try fixture.modelContext.save()

        let task = AppTask(title: "Owned by the project's own context")
        fixture.modelContext.insert(task)
        CadenceTaskMutationSupport.assignContainer(
            task,
            area: nil,
            project: fixture.launch,
            allTasks: [task]
        )

        #expect(task.context?.id == fixture.personal.id)
        #expect(fixture.launch.resolvedContext?.id == fixture.personal.id)
    }

    @Test func anInboxTaskInheritsNoContext() throws {
        let fixture = try makeFixture()
        let task = AppTask(title: "Loose")
        task.context = fixture.work
        fixture.modelContext.insert(task)

        CadenceTaskMutationSupport.assignContainer(task, area: nil, project: nil, allTasks: [task])

        #expect(task.context == nil)
    }

    // MARK: - T-293, the list changes owner

    @Test func givingAProjectANewAreaRePointsTheTasksAlreadyInIt() throws {
        let fixture = try makeFixture()

        let task = AppTask(title: "Already filed")
        task.project = fixture.launch
        task.context = fixture.work
        fixture.modelContext.insert(task)
        fixture.launch.tasks = [task]
        try fixture.modelContext.save()

        let errands = Area(name: "Errands", context: fixture.personal)
        fixture.modelContext.insert(errands)
        fixture.launch.area = errands

        CadenceTaskMutationSupport.reassignInheritedContext(
            in: fixture.launch.tasks ?? [],
            project: fixture.launch
        )

        #expect(task.context?.id == fixture.personal.id)
        #expect(task.project?.id == fixture.launch.id)
    }

    @Test func givingAProjectItsOwnContextRePointsTheTasksAlreadyInIt() throws {
        let fixture = try makeFixture()

        let first = AppTask(title: "First")
        let second = AppTask(title: "Second")
        for task in [first, second] {
            task.project = fixture.launch
            task.context = fixture.work
            fixture.modelContext.insert(task)
        }
        fixture.launch.tasks = [first, second]
        try fixture.modelContext.save()

        fixture.launch.context = fixture.personal
        CadenceTaskMutationSupport.reassignInheritedContext(
            in: fixture.launch.tasks ?? [],
            project: fixture.launch
        )

        #expect(first.context?.id == fixture.personal.id)
        #expect(second.context?.id == fixture.personal.id)
    }

    @Test func clearingAProjectsContextAndAreaLeavesItsTasksWithNoContext() throws {
        let fixture = try makeFixture()

        let task = AppTask(title: "Orphaned")
        task.project = fixture.launch
        task.context = fixture.work
        fixture.modelContext.insert(task)
        fixture.launch.tasks = [task]
        try fixture.modelContext.save()

        fixture.launch.context = nil
        fixture.launch.area = nil
        CadenceTaskMutationSupport.reassignInheritedContext(
            in: fixture.launch.tasks ?? [],
            project: fixture.launch
        )

        #expect(task.context == nil)
    }

    @Test func givingAnAreaANewContextRePointsTheTasksAlreadyInIt() throws {
        let fixture = try makeFixture()

        let task = AppTask(title: "In the area")
        task.area = fixture.operations
        task.context = fixture.work
        fixture.modelContext.insert(task)
        fixture.operations.tasks = [task]
        try fixture.modelContext.save()

        fixture.operations.context = fixture.personal
        CadenceTaskMutationSupport.reassignInheritedContext(
            in: fixture.operations.tasks ?? [],
            area: fixture.operations
        )

        #expect(task.context?.id == fixture.personal.id)
    }

    // MARK: - T-340, the same defect one level down

    /// **An area owns two levels of tasks.** `fixture.launch` names no context of its own, so it
    /// reads `operations`'s. Re-pointing the area's context therefore invalidates `task.context`
    /// on the tasks inside `launch` just as much as on the tasks filed directly in the area — but
    /// every caller passes `area.tasks ?? []`, which does not contain them, and nothing walked the
    /// projects.
    ///
    /// The direct task is asserted alongside so a fix that cascades and drops the original walk
    /// cannot pass.
    @Test func givingAnAreaANewContextRePointsTasksInItsAreaOwnedProjectsToo() throws {
        let fixture = try makeFixture()

        let direct = AppTask(title: "In the area")
        direct.area = fixture.operations
        direct.context = fixture.work
        let nested = AppTask(title: "In the area's project")
        nested.project = fixture.launch
        nested.context = fixture.work
        fixture.modelContext.insert(direct)
        fixture.modelContext.insert(nested)
        fixture.operations.tasks = [direct]
        fixture.launch.tasks = [nested]
        try fixture.modelContext.save()

        fixture.operations.context = fixture.personal
        CadenceTaskMutationSupport.reassignInheritedContext(
            in: fixture.operations.tasks ?? [],
            area: fixture.operations
        )

        #expect(direct.context?.id == fixture.personal.id)
        #expect(nested.context?.id == fixture.personal.id)
    }

    /// The cascade stops where `resolvedContext` stops. A project under the area that names its
    /// **own** context does not inherit, so the area's change must not reach its tasks — otherwise
    /// the fix above trades one wrong context for another, and this is the assertion that tells a
    /// rule-following cascade apart from a blanket overwrite of everything under the area.
    @Test func theAreaContextCascadeSkipsProjectsThatNameTheirOwnContext() throws {
        let fixture = try makeFixture()

        let owned = Project(name: "Owned", context: fixture.work, area: fixture.operations)
        fixture.modelContext.insert(owned)
        let task = AppTask(title: "In a project with its own context")
        task.project = owned
        task.context = fixture.work
        fixture.modelContext.insert(task)
        owned.tasks = [task]
        try fixture.modelContext.save()

        fixture.operations.context = fixture.personal
        CadenceTaskMutationSupport.reassignInheritedContext(
            in: fixture.operations.tasks ?? [],
            area: fixture.operations
        )

        #expect(task.context?.id == fixture.work.id)
    }

    // MARK: - The rule is spelled once, and every surface calls it

    /// `Cadence/iOS/` is behind `#if os(iOS)` and is not compiled by this macOS test target, and
    /// `reassignTasks` is private to a SwiftUI view, so the iOS half of T-293 can only be pinned as
    /// text. The behaviour it routes to is covered by value above.
    @Test func theIOSListEditorRePointsTaskContextsWhenTheListChangesOwner() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSListEditorViews.swift")
        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped != raw)
        #expect(stripped.count == raw.count)

        let reassign = try #require(CadenceSourceScan.functionBody(named: "reassignTasks", in: stripped))
        #expect(reassign.contains("CadenceSectionEditingSupport.applySectionNameChanges("))
        #expect(reassign.contains("CadenceTaskMutationSupport.reassignInheritedContext(in: tasks, area: area, project: project)"))

        let save = try #require(CadenceSourceScan.functionBody(named: "save", in: stripped))
        #expect(save.contains("reassignTasks(in: area.tasks ?? [], area: area)"))
        #expect(save.contains("reassignTasks(in: project.tasks ?? [], project: project)"))
    }

    /// Every path that files a task into a project, by name. These are inline in SwiftUI closures
    /// or private to a view, so the call site itself is only reachable as text; what the call site
    /// resolves to is covered by value above.
    ///
    /// Both assertions are counts, not `contains`, for two reasons: a failing `contains` on a
    /// source string prints the whole file into the failure message, and `matchCount` returns `-1`
    /// for a pattern that does not compile, which no `>= 1` or `== 0` check can pass by accident.
    /// The positive count is also the non-vacuity check — an empty or wrong-path read cannot match
    /// it. `stripped != raw` is *not* used here: `DataIntegrityRepairService.swift` contains no
    /// comments at all, so that check is red no matter what the code says.
    @Test func everyPathThatFilesATaskIntoAProjectAsksTheProjectToResolveItsContext() throws {
        let sites: [(file: String, owner: String)] = [
            ("Cadence/Services/TaskCreationService.swift", "project"),
            ("Cadence/Services/MCPReadOnly/CadenceWriteService.swift", "project"),
            ("Cadence/Services/DataIntegrityRepairService.swift", "target"),
            ("Cadence/macOS/Views/SchedulePanelComponents.swift", "project"),
            ("Cadence/macOS/Views/TasksPanelComponents.swift", "project"),
            ("Cadence/macOS/Views/TasksPanelSupport.swift", "target"),
            ("Cadence/macOS/Views/KanbanBoardSupport.swift", "project"),
            ("Cadence/macOS/Views/KanbanSectionColumnView.swift", "project"),
        ]

        #expect(sites.count == 8)
        for site in sites {
            let raw = try CadenceSourceScan.sourceFile(site.file)
            let stripped = CadenceSourceScan.strippingComments(raw)
            #expect(stripped.count == raw.count, "\(site.file): the stripper changed the length")

            let routed = CadenceSourceScan.matchCount(
                #"task\.context = \#(site.owner)\.resolvedContext\b"#,
                in: stripped
            )
            #expect(routed >= 1, "\(site.file) does not file a task through the shared rule (\(routed))")

            let openCoded = CadenceSourceScan.matchCount(
                #"task\.context = (project|source)\.context\b"#,
                in: stripped
            )
            #expect(
                openCoded == 0,
                "\(site.file) still writes a project's own context without the area fallback (\(openCoded))"
            )
        }
    }

    /// The area fallback exists in exactly one place. `CadenceTaskMutationSupport` used to hold the
    /// only correct copy; now it asks the model, so re-typing the rule there would be a regression.
    @Test func theAreaFallbackIsSpelledOnlyOnTheModel() throws {
        let modelRaw = try CadenceSourceScan.sourceFile("Cadence/Models/Project.swift")
        let modelStripped = CadenceSourceScan.strippingComments(modelRaw)
        #expect(modelStripped != modelRaw)
        #expect(modelStripped.count == modelRaw.count)
        #expect(CadenceSourceScan.matchCount(
            #"var resolvedContext: Context\? \{ context \?\? area\?\.context \}"#,
            in: modelStripped
        ) == 1)

        let raw = try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceTaskMutationSupport.swift")
        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped != raw)
        #expect(stripped.count == raw.count)

        let pattern = #"project\.context \?\? project\.area\?\.context"#
        // Self-check: the needle must match the text it describes and miss the fixed source.
        #expect(CadenceSourceScan.matchCount(pattern, in: "project.context ?? project.area?.context") == 1)
        #expect(CadenceSourceScan.matchCount(pattern, in: stripped) == 0)

        let assign = try #require(CadenceSourceScan.functionBody(named: "assignContainer", in: stripped))
        #expect(assign.contains("task.context = inheritedContext(area: area, project: project)"))
    }
}
