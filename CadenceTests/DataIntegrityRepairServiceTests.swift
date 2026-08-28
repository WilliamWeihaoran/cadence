import Foundation
import SwiftData
import Testing
@testable import Cadence

@MainActor
struct DataIntegrityRepairServiceTests {
    @Test func duplicateContextsAreMergedWithoutDroppingListsOrTasks() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let oldWork = Context(name: "Work", colorHex: "#4ECB71", icon: "briefcase.fill")
        oldWork.order = 0
        let restoredWork = Context(name: "Work", colorHex: "#22c55e", icon: "briefcase.fill")
        restoredWork.order = 0

        let sharedProjectID = UUID()
        let oldProject = Project(name: "POPSA", context: oldWork)
        oldProject.id = sharedProjectID
        let restoredProject = Project(name: "POPSA", context: restoredWork)
        restoredProject.id = sharedProjectID

        let oldTask = AppTask(title: "Old task")
        oldTask.project = oldProject
        oldTask.context = oldWork
        let restoredTask = AppTask(title: "Restored task")
        restoredTask.project = restoredProject
        restoredTask.context = restoredWork

        let restoredArea = Area(name: "General", context: restoredWork)
        let habit = Habit(title: "Ship", context: oldWork)
        let goal = Goal(title: "Outcome", context: oldWork)

        modelContext.insert(oldWork)
        modelContext.insert(restoredWork)
        modelContext.insert(oldProject)
        modelContext.insert(restoredProject)
        modelContext.insert(oldTask)
        modelContext.insert(restoredTask)
        modelContext.insert(restoredArea)
        modelContext.insert(habit)
        modelContext.insert(goal)
        try modelContext.save()

        let report = try DataIntegrityRepairService.repairIfNeeded(in: modelContext, source: "test")

        #expect(report.duplicateContextsMerged == 1)
        #expect(report.duplicateProjectsMerged == 1)

        let contexts = try modelContext.fetch(FetchDescriptor<Context>())
        let projects = try modelContext.fetch(FetchDescriptor<Project>())
        let tasks = try modelContext.fetch(FetchDescriptor<AppTask>())
        let areas = try modelContext.fetch(FetchDescriptor<Area>())
        let goals = try modelContext.fetch(FetchDescriptor<Goal>())
        let habits = try modelContext.fetch(FetchDescriptor<Habit>())

        #expect(contexts.count == 1)
        #expect(contexts.first?.name == "Work")
        #expect(projects.count == 1)
        #expect(projects.first?.id == sharedProjectID)
        #expect(areas.count == 1)
        #expect(tasks.count == 2)
        #expect(tasks.allSatisfy { $0.context === contexts.first })
        #expect(tasks.allSatisfy { $0.project === projects.first })
        #expect(areas.first?.context === contexts.first)
        #expect(goals.first?.context === contexts.first)
        #expect(habits.first?.context === contexts.first)
    }

    @Test func duplicateCanonicalNotesAreMergedWithoutDroppingContentOrTags() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let area = Area(name: "Writing")
        let project = Project(name: "Review")
        let tagA = Tag(name: "daily", order: 1)
        let tagB = Tag(name: "review", order: 2)
        let older = Note(
            kind: .daily,
            title: "Untitled",
            content: "Morning plan",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            dateKey: "2026-04-29",
            area: area
        )
        older.tags = [tagA]
        let newer = Note(
            kind: .daily,
            title: "Daily Review",
            content: "Evening notes",
            createdAt: Date(timeIntervalSince1970: 150),
            updatedAt: Date(timeIntervalSince1970: 300),
            dateKey: "2026-04-29",
            project: project
        )
        newer.tags = [tagB]

        modelContext.insert(area)
        modelContext.insert(project)
        modelContext.insert(tagA)
        modelContext.insert(tagB)
        modelContext.insert(older)
        modelContext.insert(newer)
        try modelContext.save()

        let report = try DataIntegrityRepairService.repairIfNeeded(in: modelContext, source: "test")
        let notes = try modelContext.fetch(FetchDescriptor<Note>())

        #expect(report.duplicateNotesMerged == 1)
        #expect(notes.count == 1)
        #expect(notes.first?.dateKey == "2026-04-29")
        #expect(notes.first?.content.contains("Morning plan") == true)
        #expect(notes.first?.content.contains("Evening notes") == true)
        #expect(notes.first?.area === area)
        #expect(notes.first?.project === project)
        #expect(Set(notes.first?.tags?.map(\.slug) ?? []) == ["daily", "review"])
    }

    @Test func unkeyedMeetingNotesAreNotMerged() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let first = Note(kind: .meeting, title: "First", content: "One")
        let second = Note(kind: .meeting, title: "Second", content: "Two")

        modelContext.insert(first)
        modelContext.insert(second)
        try modelContext.save()

        let report = try DataIntegrityRepairService.repairIfNeeded(in: modelContext, source: "test")
        let notes = try modelContext.fetch(FetchDescriptor<Note>())

        #expect(report.duplicateNotesMerged == 0)
        #expect(notes.count == 2)
    }

    // MARK: - T-340, the tasks already in the surviving project

    /// **The merge branch.** Two `Work` contexts and a project present under each with the same
    /// `id`, so `mergeProject` folds one into the other. `restoredWork` carries an extra area, and
    /// that weight is load-bearing: without it the two `contextScore`s tie at 21, the source and
    /// target roles are decided arbitrarily, and the resident task below gets re-pointed as an
    /// *arrival* by the loop that already existed. The first version of this test did tie, and
    /// passed against unmodified source while proving nothing.
    ///
    /// The task arriving from the source was always re-pointed. The task *already* in the target
    /// carries no context at all under a project that has one, and nothing ever re-derived it —
    /// nor does `mergeContext`'s sweep rescue it, because that walks `task.context === duplicate`
    /// and `nil` is not the duplicate. That is precisely why this gap survived.
    @Test func mergingAProjectRePointsTheTasksAlreadyInTheTargetNotOnlyTheArrivals() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let oldWork = Context(name: "Work")
        oldWork.order = 0
        let restoredWork = Context(name: "Work")
        restoredWork.order = 0

        let sharedID = UUID()
        let oldProject = Project(name: "Launch", context: oldWork)
        oldProject.id = sharedID
        let restoredProject = Project(name: "Launch", context: restoredWork)
        restoredProject.id = sharedID
        // Weight, so `restoredWork` is canonical and `restoredProject` is therefore the target.
        let restoredArea = Area(name: "General", context: restoredWork)

        let arriving = AppTask(title: "Arriving from the duplicate")
        arriving.project = oldProject
        arriving.context = oldWork
        // Already in the target, and pointing at nothing while its project points at a context.
        let resident = AppTask(title: "Already in the target")
        resident.project = restoredProject
        resident.context = nil

        for model in [oldWork, restoredWork] { modelContext.insert(model) }
        modelContext.insert(oldProject)
        modelContext.insert(restoredProject)
        modelContext.insert(restoredArea)
        modelContext.insert(arriving)
        modelContext.insert(resident)
        try modelContext.save()

        let report = try DataIntegrityRepairService.repairIfNeeded(in: modelContext, source: "test")

        #expect(report.duplicateProjectsMerged == 1)
        let survivingProject = try #require(try modelContext.fetch(FetchDescriptor<Project>()).first)
        // The fixture did its job: the survivor is the project the resident task was already in.
        #expect(survivingProject === restoredProject)
        #expect(resident.context != nil)
        #expect(resident.context === survivingProject.resolvedContext)
        #expect(arriving.context === survivingProject.resolvedContext)
    }

    /// **The no-duplicate branch.** No project is present twice; the project is simply adopted out
    /// of a duplicate area into the canonical one. The task inside it carries `nil`, so
    /// `mergeContext`'s `task.context === duplicate` sweep does not see it either, and before this
    /// fix the branch re-pointed the project and left its tasks behind entirely.
    ///
    /// **This is also where [[T-340]]'s stated mechanism turns out not to exist**, which the
    /// assertions below record rather than describe, because the ticket's version is what a reader
    /// would otherwise assume. The ticket says the merge changes the surviving project's *area* and
    /// so changes what it resolves to. It cannot: both branches end with `context` pinned to the
    /// canonical context — this one by assigning it outright, the merge branch by only ever
    /// selecting targets that already carry it — so `resolvedContext` is the canonical context no
    /// matter what happens to the area. The gap is real; the explanation was not.
    @Test func adoptingAProjectFromADuplicateAreaRePointsTheTasksInsideIt() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let duplicate = Context(name: "Work")
        duplicate.order = 1
        let canonical = Context(name: "Work")
        canonical.order = 0

        let sharedAreaID = UUID()
        let staleArea = Area(name: "Operations", context: duplicate)
        staleArea.id = sharedAreaID
        let canonicalArea = Area(name: "Operations", context: canonical)
        canonicalArea.id = sharedAreaID
        // Weight, so `canonical` wins `contextScore` by more than the ordering term alone.
        let ballast = AppTask(title: "Ballast")
        ballast.area = canonicalArea
        ballast.context = canonical
        let moreBallast = AppTask(title: "More ballast")
        moreBallast.area = canonicalArea
        moreBallast.context = canonical

        // Names no context: everything it has, it has from `staleArea`.
        let project = Project(name: "Launch", context: nil, area: staleArea)
        // `nil`, not `duplicate` — a task pointing at the duplicate is rescued by `mergeContext`,
        // and a fixture that used one would pass without this fix.
        let task = AppTask(title: "In the area-owned project")
        task.project = project
        task.context = nil

        for model in [duplicate, canonical] { modelContext.insert(model) }
        modelContext.insert(staleArea)
        modelContext.insert(canonicalArea)
        modelContext.insert(ballast)
        modelContext.insert(moreBallast)
        modelContext.insert(project)
        modelContext.insert(task)
        try modelContext.save()

        _ = try DataIntegrityRepairService.repairIfNeeded(in: modelContext, source: "test")

        #expect(try modelContext.fetch(FetchDescriptor<Context>()).count == 1)
        let survivingProject = try #require(try modelContext.fetch(FetchDescriptor<Project>()).first)
        #expect(survivingProject.area === canonicalArea)
        // The correction: this branch pins `context`, so the area never gets to decide.
        #expect(survivingProject.context === canonical)
        #expect(survivingProject.resolvedContext === canonical)
        #expect(task.context === canonical)
    }

    // MARK: - T-328, the boundary this service does not cross

    /// **Repair merges duplicates; it does not collect orphans, and that is a decision.**
    ///
    /// The four rows below are every orphan shape [[T-328]] names: a `Subtask` with no
    /// `parentTask`, a `TaskBundle` with no members, a `HabitCompletion` with no `habit`, and a
    /// `MarkdownImageAsset` no markdown references. Repair must leave all four alone and report
    /// `changed == false`, because `PersistenceController.performStartupMaintenance` runs it the
    /// instant the container opens with no gate on CloudKit sync state — so on a launch that races
    /// the first sync, an unowned row is indistinguishable from one whose owner has not arrived,
    /// and the emptier the store the more a sweep would delete.
    ///
    /// This test is the contract, not a description of missing work. A future sweep has to earn the
    /// right to delete by knowing the store is complete; changing these expectations without that
    /// is the failure mode it exists to catch.
    @Test func repairLeavesOrphanedRowsAloneRatherThanCollectingThemAtStartup() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let subtask = Subtask(title: "Targetless")
        let bundle = TaskBundle(title: "Empty", dateKey: "2026-08-21", startMin: 600, durationMinutes: 30)
        let completion = HabitCompletion(date: "2026-08-21")
        let asset = MarkdownImageAsset(
            data: Data([0x01, 0x02]),
            mimeType: "image/png",
            pixelWidth: 2,
            pixelHeight: 2,
            displayWidth: 100
        )
        modelContext.insert(subtask)
        modelContext.insert(bundle)
        modelContext.insert(completion)
        modelContext.insert(asset)
        try modelContext.save()

        let report = try DataIntegrityRepairService.repairIfNeeded(in: modelContext, source: "test")

        #expect(report.changed == false)
        #expect(try modelContext.fetch(FetchDescriptor<Subtask>()).count == 1)
        #expect(try modelContext.fetch(FetchDescriptor<TaskBundle>()).count == 1)
        #expect(try modelContext.fetch(FetchDescriptor<HabitCompletion>()).count == 1)
        #expect(try modelContext.fetch(FetchDescriptor<MarkdownImageAsset>()).count == 1)
    }
}
