import Foundation
import SwiftData
import Testing
@testable import Cadence

/// The three cascades are cross-platform since T-187
/// (`Cadence/Services/CadenceListDeleteHelpers.swift`). The guard below survives **only** for the
/// last two tests in this file, which exercise `ModelContext.deleteTask(_:)` — the macOS wrapper
/// that supplies the AppKit-shaped hooks around the shared deletion core, and still genuinely
/// macOS-only. It is no longer a statement about `deleteArea`/`deleteProject`/`deleteContext`.
#if os(macOS)
@MainActor
struct ListDeleteHelpersTests {
    @Test func deleteContextRemovesDescendantsAndSavesCleanly() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let context = Context(name: "Work")
        let area = Area(name: "Area", context: context)
        let project = Project(name: "Project", context: context, area: area)
        // Legacy row: pursuits were merged into Goal, but unmigrated rows must still cascade.
        let pursuit = Pursuit(title: "Pursuit", context: context)
        let goal = Goal(title: "Goal", context: context)
        let subGoal = Goal(title: "Milestone", context: context)
        subGoal.parentGoal = goal
        let goalListLink = GoalListLink(goal: goal, area: area)
        let habit = Habit(title: "Habit", context: context, goal: goal)
        let habitCompletion = HabitCompletion(date: "2026-04-29", habit: habit)

        let contextTask = AppTask(title: "Context task")
        contextTask.context = context
        let areaTask = AppTask(title: "Area task")
        areaTask.area = area
        areaTask.context = context
        let projectTask = AppTask(title: "Project task")
        projectTask.project = project
        projectTask.context = context
        let goalTask = AppTask(title: "Goal task")
        goalTask.goal = goal
        goalTask.context = context

        let subtask = Subtask(title: "Nested")
        subtask.parentTask = goalTask

        let areaNote = Note(kind: .list, title: "Area doc")
        areaNote.area = area
        let projectNote = Note(kind: .list, title: "Project doc")
        projectNote.project = project
        let areaDocument = Document(title: "Area legacy document")
        areaDocument.area = area
        let projectDocument = Document(title: "Project legacy document")
        projectDocument.project = project
        let noteAsset = MarkdownImageAsset(
            data: Data([1, 2, 3]),
            mimeType: "image/png",
            pixelWidth: 20,
            pixelHeight: 20,
            displayWidth: 20
        )
        areaNote.content = "![area](cadence-image://\(noteAsset.id.uuidString))"
        let areaLink = SavedLink(title: "Area link", url: "https://example.com/area")
        areaLink.area = area
        let projectLink = SavedLink(title: "Project link", url: "https://example.com/project")
        projectLink.project = project

        modelContext.insert(context)
        modelContext.insert(area)
        modelContext.insert(project)
        modelContext.insert(pursuit)
        modelContext.insert(goal)
        modelContext.insert(subGoal)
        modelContext.insert(goalListLink)
        modelContext.insert(habit)
        modelContext.insert(habitCompletion)
        modelContext.insert(contextTask)
        modelContext.insert(areaTask)
        modelContext.insert(projectTask)
        modelContext.insert(goalTask)
        modelContext.insert(subtask)
        modelContext.insert(areaNote)
        modelContext.insert(projectNote)
        modelContext.insert(areaDocument)
        modelContext.insert(projectDocument)
        modelContext.insert(noteAsset)
        modelContext.insert(areaLink)
        modelContext.insert(projectLink)
        try modelContext.save()

        modelContext.deleteContext(context)
        try modelContext.save()

        #expect(try modelContext.fetch(FetchDescriptor<Context>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<Area>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<Project>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<Pursuit>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<Goal>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<GoalListLink>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<Habit>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<HabitCompletion>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<AppTask>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<Subtask>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<Note>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<Document>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<MarkdownImageAsset>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<SavedLink>()).isEmpty)
    }

    @Test func deleteUnreferencedMarkdownImageAssetsKeepsAssetsStillReferencedElsewhere() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let deletedAsset = MarkdownImageAsset(data: Data([1]), mimeType: "image/png", pixelWidth: 20, pixelHeight: 20, displayWidth: 20)
        let retainedAsset = MarkdownImageAsset(data: Data([2]), mimeType: "image/png", pixelWidth: 20, pixelHeight: 20, displayWidth: 20)
        // **Both assets are referenced by the doomed note (T-620).** The sweep is a candidate-set
        // delete now, so an asset the deleted markdown never mentioned survives trivially — and
        // this test is about the *other* reason to survive: another note still references it.
        // Naming both in the doomed body keeps `retainedAsset` a candidate, so its survival is
        // still attributable to `retainedNote` and nothing else.
        let deletedNote = Note(
            kind: .list,
            title: "Deleted",
            content: [
                "![gone](cadence-image://\(deletedAsset.id.uuidString))",
                "![shared](cadence-image://\(retainedAsset.id.uuidString))"
            ].joined(separator: "\n")
        )
        let retainedNote = Note(kind: .permanent, title: "Retained", content: "![keep](cadence-image://\(retainedAsset.id.uuidString))")

        modelContext.insert(deletedAsset)
        modelContext.insert(retainedAsset)
        modelContext.insert(deletedNote)
        modelContext.insert(retainedNote)
        try modelContext.save()

        let doomedBody = deletedNote.content
        modelContext.delete(deletedNote)
        modelContext.deleteUnreferencedMarkdownImageAssets(
            referencedByDeletedMarkdown: [doomedBody],
            excludingNoteIDs: [deletedNote.id]
        )
        try modelContext.save()

        let remainingAssets = try modelContext.fetch(FetchDescriptor<MarkdownImageAsset>())
        #expect(remainingAssets.map(\.id) == [retainedAsset.id])
    }

    /// **T-350.** The surviving note writes its image *inside a sentence*, which is what
    /// hand-editing a reference into prose produces. The note displays it; the sweep used to ask
    /// the rendering question — "is this reference alone on its line?" — decide "no", and collect
    /// the asset's `.externalStorage` bytes out from under a live picture. Unrecoverable.
    ///
    /// Asserted by identity: the asset is still in the store, not merely "the count changed".
    @Test func deleteSweepKeepsAnAssetASurvivingNoteShowsInline() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let inlineAsset = MarkdownImageAsset(data: Data([7]), mimeType: "image/png", pixelWidth: 20, pixelHeight: 20, displayWidth: 20)
        let orphanAsset = MarkdownImageAsset(data: Data([8]), mimeType: "image/png", pixelWidth: 20, pixelHeight: 20, displayWidth: 20)
        // Both assets are named by the doomed note, because the sweep only considers assets the
        // deleted markdown referenced (T-620). Without the second line `inlineAsset` would never
        // be a candidate and would survive for a reason that has nothing to do with T-350 — the
        // sweep could go back to asking the rendering question and this test would stay green.
        let deletedNote = Note(
            kind: .list,
            title: "Deleted",
            content: [
                "![gone](cadence-image://\(orphanAsset.id.uuidString))",
                "![chart](cadence-image://\(inlineAsset.id.uuidString))"
            ].joined(separator: "\n")
        )
        let survivingNote = Note(
            kind: .permanent,
            title: "Retained",
            content: "See ![the chart](cadence-image://\(inlineAsset.id.uuidString)) before Friday."
        )

        modelContext.insert(inlineAsset)
        modelContext.insert(orphanAsset)
        modelContext.insert(deletedNote)
        modelContext.insert(survivingNote)
        try modelContext.save()

        let doomedBody = deletedNote.content
        modelContext.delete(deletedNote)
        modelContext.deleteUnreferencedMarkdownImageAssets(
            referencedByDeletedMarkdown: [doomedBody],
            excludingNoteIDs: [deletedNote.id]
        )
        try modelContext.save()

        let remaining = try modelContext.fetch(FetchDescriptor<MarkdownImageAsset>())
        #expect(remaining.contains { $0.id == inlineAsset.id })
        #expect(!remaining.contains { $0.id == orphanAsset.id })
    }

    /// The area cascade's own coverage, filling what `TaskDeleteHelpersScenarioTests` test 4 leaves
    /// out. That test pins tasks, subtasks, legacy `Document`s, `SavedLink`s and the nested project;
    /// it inserts no `Note`, no `GoalListLink` and no `MarkdownImageAsset`, so the three parts of
    /// `deleteArea` that handle them were unpinned. They matter for different reasons: a list note
    /// is a first-class user document, a `GoalListLink` left behind is a goal whose progress counts
    /// tasks that no longer exist, and an orphaned image asset is `.externalStorage` bytes that
    /// nothing will ever reclaim.
    ///
    /// It also pins the one thing `deleteArea` deliberately does *not* take: a note attached to the
    /// area whose kind is not `.list`.
    @Test func deleteAreaCascadesThroughListNotesGoalLinksAndImageAssets() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let context = Context(name: "Work")
        let area = Area(name: "Area", context: context)
        let project = Project(name: "Nested", context: context, area: area)
        let goal = Goal(title: "Goal", context: context)
        let areaLink = GoalListLink(goal: goal, area: area)
        let projectLink = GoalListLink(goal: goal, project: project)

        let asset = MarkdownImageAsset(
            data: Data([9, 9, 9]),
            mimeType: "image/png",
            pixelWidth: 20,
            pixelHeight: 20,
            displayWidth: 20
        )
        let areaNote = Note(kind: .list, title: "Area note")
        areaNote.area = area
        areaNote.content = "![area](cadence-image://\(asset.id.uuidString))"
        let projectNote = Note(kind: .list, title: "Project note")
        projectNote.project = project
        // Not a list note: the cascade leaves it, and its `area` relationship nullifies.
        let survivingNote = Note(kind: .permanent, title: "Notepad entry")
        survivingNote.area = area

        let areaTask = AppTask(title: "Area task")
        areaTask.area = area
        let projectTask = AppTask(title: "Project task")
        projectTask.project = project

        modelContext.insert(context)
        modelContext.insert(area)
        modelContext.insert(project)
        modelContext.insert(goal)
        modelContext.insert(areaLink)
        modelContext.insert(projectLink)
        modelContext.insert(asset)
        modelContext.insert(areaNote)
        modelContext.insert(projectNote)
        modelContext.insert(survivingNote)
        modelContext.insert(areaTask)
        modelContext.insert(projectTask)
        try modelContext.save()

        #expect(modelContext.deleteArea(area))
        try modelContext.save()

        #expect(try modelContext.fetch(FetchDescriptor<Area>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<Project>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<AppTask>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<GoalListLink>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<MarkdownImageAsset>()).isEmpty)
        // The goal itself is not the area's to delete, and the non-list note survives.
        #expect(try modelContext.fetch(FetchDescriptor<Goal>()).count == 1)
        let remainingNotes = try modelContext.fetch(FetchDescriptor<Note>())
        #expect(remainingNotes.map(\.id) == [survivingNote.id])
    }

    @Test func deleteTaskRemovesScheduledCompletedTaskAndSubtasksCleanly() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let context = Context(name: "Work")
        let task = AppTask(title: "Scheduled")
        task.context = context
        task.scheduledDate = "2026-04-29"
        task.scheduledStartMin = 540
        task.estimatedMinutes = 45
        task.calendarEventID = "test-event-id"
        task.status = .done
        task.completedAt = Date()

        let subtask = Subtask(title: "Nested")
        subtask.parentTask = task

        modelContext.insert(context)
        modelContext.insert(task)
        modelContext.insert(subtask)
        try modelContext.save()

        modelContext.deleteTask(task)
        try modelContext.save()

        #expect(try modelContext.fetch(FetchDescriptor<Context>()).count == 1)
        #expect(try modelContext.fetch(FetchDescriptor<AppTask>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<Subtask>()).isEmpty)
    }

    @Test func deleteTaskIgnoresStaleSubtaskRelationshipEntries() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let task = AppTask(title: "Hovered task")
        let deletedSubtask = Subtask(title: "Already gone")
        deletedSubtask.parentTask = task
        let liveSubtask = Subtask(title: "Still here")
        liveSubtask.parentTask = task

        modelContext.insert(task)
        modelContext.insert(deletedSubtask)
        modelContext.insert(liveSubtask)
        try modelContext.save()

        modelContext.delete(deletedSubtask)
        modelContext.deleteTask(task)
        try modelContext.save()

        #expect(try modelContext.fetch(FetchDescriptor<AppTask>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<Subtask>()).isEmpty)
    }
}
#endif
