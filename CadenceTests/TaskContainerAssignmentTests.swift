import Foundation
import SwiftData
import Testing
@testable import Cadence

/// `assignContainer` re-places a task at the end of its container, which is right for a move and
/// wrong for everything else.
///
/// The iOS task detail sheet seeds its `containerSelection` state in `onAppear` and reacts to the
/// resulting change by calling `moveToContainer`, so simply *opening* a task's sheet re-asserted
/// the container it was already in and dropped the task to the bottom of its list — under "List
/// order", the default sort for All Tasks and a list's Tasks tab. Reopening it bumped it again.
/// The two "Move to List" menus have the same shape: they tick the current list, so choosing it
/// reads as a no-op and silently re-ordered the task.
@MainActor
struct TaskContainerAssignmentTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
    }

    /// Ten tasks at orders 0…9; the one at 3 must still be at 3 after its own container is
    /// re-asserted.
    @Test func reassertingTheSameAreaLeavesTheTaskWhereItIs() throws {
        let modelContext = try makeContext()
        let area = Area(name: "Documents")
        modelContext.insert(area)

        var tasks: [AppTask] = []
        for index in 0..<10 {
            let task = AppTask(title: "Task \(index)")
            task.order = index
            task.area = area
            modelContext.insert(task)
            tasks.append(task)
        }
        area.tasks = tasks
        try modelContext.save()

        let subject = tasks[3]
        CadenceTaskMutationSupport.moveToContainer(
            subject,
            area: area,
            project: nil,
            sectionName: subject.resolvedSectionName,
            allTasks: tasks,
            modelContext: modelContext
        )

        #expect(subject.order == 3)
        #expect(subject.area?.id == area.id)
    }

    /// Same rule for Inbox, where both sides of the comparison are nil.
    @Test func reassertingInboxLeavesTheTaskWhereItIs() throws {
        let modelContext = try makeContext()

        var tasks: [AppTask] = []
        for index in 0..<4 {
            let task = AppTask(title: "Inbox \(index)")
            task.order = index
            modelContext.insert(task)
            tasks.append(task)
        }
        try modelContext.save()

        let subject = tasks[1]
        CadenceTaskMutationSupport.moveToContainer(
            subject,
            area: nil,
            project: nil,
            allTasks: tasks,
            modelContext: modelContext
        )

        #expect(subject.order == 1)
    }

    /// The reorder is not removed, only narrowed: a real move still places the task at the end of
    /// the list it arrives in, because its old `order` means nothing among its new siblings.
    @Test func movingToADifferentAreaPlacesTheTaskAtTheEnd() throws {
        let modelContext = try makeContext()
        let source = Area(name: "Source")
        let destination = Area(name: "Destination")
        modelContext.insert(source)
        modelContext.insert(destination)

        let subject = AppTask(title: "Traveller")
        subject.order = 0
        subject.area = source

        var destinationTasks: [AppTask] = []
        for index in 0..<3 {
            let task = AppTask(title: "Resident \(index)")
            task.order = index
            task.area = destination
            modelContext.insert(task)
            destinationTasks.append(task)
        }
        modelContext.insert(subject)
        source.tasks = [subject]
        destination.tasks = destinationTasks
        try modelContext.save()

        CadenceTaskMutationSupport.moveToContainer(
            subject,
            area: destination,
            project: nil,
            allTasks: destinationTasks + [subject],
            modelContext: modelContext
        )

        #expect(subject.area?.id == destination.id)
        #expect(subject.order == 3)
    }

    /// Moving out to Inbox is a move too.
    @Test func movingFromAnAreaToInboxPlacesTheTaskAtTheEnd() throws {
        let modelContext = try makeContext()
        let area = Area(name: "Source")
        modelContext.insert(area)

        let subject = AppTask(title: "Traveller")
        subject.order = 0
        subject.area = area
        modelContext.insert(subject)
        area.tasks = [subject]

        var inboxTasks: [AppTask] = []
        for index in 0..<2 {
            let task = AppTask(title: "Loose \(index)")
            task.order = index
            modelContext.insert(task)
            inboxTasks.append(task)
        }
        try modelContext.save()

        CadenceTaskMutationSupport.moveToContainer(
            subject,
            area: nil,
            project: nil,
            allTasks: inboxTasks + [subject],
            modelContext: modelContext
        )

        #expect(subject.area == nil)
        #expect(subject.order == 2)
    }

    /// `isAlreadyInContainer` answers about the whole container, not one half of it: a task
    /// carrying both an area and a project is in neither cleanly, so re-asserting the area is a
    /// real change.
    @Test func aTaskCarryingBothRelationshipsIsNotAlreadyInEither() throws {
        let modelContext = try makeContext()
        let area = Area(name: "Area")
        let project = Project(name: "Project")
        let task = AppTask(title: "Confused")
        task.area = area
        task.project = project
        modelContext.insert(area)
        modelContext.insert(project)
        modelContext.insert(task)
        try modelContext.save()

        #expect(CadenceTaskMutationSupport.isAlreadyInContainer(task, area: area, project: nil) == false)
        #expect(CadenceTaskMutationSupport.isAlreadyInContainer(task, area: nil, project: project) == false)
        #expect(CadenceTaskMutationSupport.isAlreadyInContainer(task, area: nil, project: nil) == false)
    }
}
