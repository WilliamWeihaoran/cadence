import Foundation
import SwiftData
import Testing
@testable import Cadence

@MainActor
struct GoalContributionResolverTests {
    @Test func contributionSummaryDedupesDirectTasksAndLinkedLists() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let context = Context(name: "Work")
        let area = Area(name: "Goals Area", context: context)
        let project = Project(name: "Side Project", context: context)
        let goal = Goal(title: "Ship Goals", context: context)
        goal.loggedHours = 1.5

        let directDone = AppTask(title: "Direct done")
        directDone.area = area
        directDone.context = context
        directDone.goal = goal
        directDone.status = .done
        directDone.actualMinutes = 30
        directDone.completedAt = Date()

        let cancelledDirect = AppTask(title: "Cancelled")
        cancelledDirect.goal = goal
        cancelledDirect.status = .cancelled

        let areaOpen = AppTask(title: "Area open")
        areaOpen.area = area
        areaOpen.context = context
        areaOpen.priority = .high
        areaOpen.dueDate = "2026-04-01"

        let areaDone = AppTask(title: "Area done")
        areaDone.area = area
        areaDone.context = context
        areaDone.status = .done

        let unrelatedProjectTask = AppTask(title: "Unrelated")
        unrelatedProjectTask.project = project
        unrelatedProjectTask.context = context

        let link = GoalListLink(goal: goal, area: area)

        modelContext.insert(context)
        modelContext.insert(area)
        modelContext.insert(project)
        modelContext.insert(goal)
        modelContext.insert(directDone)
        modelContext.insert(cancelledDirect)
        modelContext.insert(areaOpen)
        modelContext.insert(areaDone)
        modelContext.insert(unrelatedProjectTask)
        modelContext.insert(link)
        try modelContext.save()

        let summary = GoalContributionResolver.summary(for: goal, now: DateFormatters.date(from: "2026-04-30") ?? Date())

        #expect(summary.totalTasks == 3)
        #expect(summary.completedTasks == 2)
        #expect(summary.directTaskCount == 1)
        #expect(summary.linkedListCount == 1)
        #expect(summary.focusMinutes == 120)
        #expect(summary.overdueTaskCount == 1)
        #expect(summary.nextActionTitle == "Area open")
        #expect(goal.progress == 2.0 / 3.0)
    }

    @Test func taskContainerNamePrefersListOverGoal() {
        let context = Context(name: "Personal")
        let area = Area(name: "Life", context: context, colorHex: "#22cc88")
        let goal = Goal(title: "Health", context: context)
        goal.colorHex = "#ff55aa"

        let task = AppTask(title: "Book appointment")
        task.area = area
        task.goal = goal

        #expect(task.containerName == "Life")
        #expect(task.containerColor == "#22cc88")

        let goalOnlyTask = AppTask(title: "Loose contributor")
        goalOnlyTask.goal = goal

        #expect(goalOnlyTask.containerName == "")
        #expect(goalOnlyTask.containerColor == "#6b7a99")
    }
}
