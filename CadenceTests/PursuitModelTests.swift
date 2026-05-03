import Foundation
import SwiftData
import Testing
@testable import Cadence

@MainActor
struct PursuitModelTests {
    @Test func pursuitOwnsGoalsAndHabitsUnderContext() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let context = Context(name: "Personal")
        let pursuit = Pursuit(title: "Become more knowledgeable", context: context)
        let goal = Goal(title: "Read 12 books", context: context)
        let habit = Habit(title: "Read 30 minutes", context: context)
        goal.pursuit = pursuit
        habit.pursuit = pursuit

        modelContext.insert(context)
        modelContext.insert(pursuit)
        modelContext.insert(goal)
        modelContext.insert(habit)
        try modelContext.save()

        let savedPursuit = try #require(try modelContext.fetch(FetchDescriptor<Pursuit>()).first)
        #expect(savedPursuit.context?.id == context.id)
        #expect(savedPursuit.goals?.map(\.id).contains(goal.id) == true)
        #expect(savedPursuit.habits?.map(\.id).contains(habit.id) == true)
        #expect(context.pursuits?.map(\.id).contains(pursuit.id) == true)
    }

    @Test func pursuitDoesNotReplaceLegacyHabitGoalLinkOrGoalProgress() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let pursuit = Pursuit(title: "Get stronger")
        let goal = Goal(title: "Deadlift 300")
        let habit = Habit(title: "Lift three times", goal: goal)
        habit.pursuit = pursuit
        let completion = HabitCompletion(date: "2026-04-30", habit: habit)

        modelContext.insert(pursuit)
        modelContext.insert(goal)
        modelContext.insert(habit)
        modelContext.insert(completion)
        try modelContext.save()

        #expect(habit.goal?.id == goal.id)
        #expect(habit.pursuit?.id == pursuit.id)
        #expect(goal.pursuit == nil)
        #expect(goal.progress == 0)
    }

    @Test func pursuitRequiredRulesBlockOrphanGoalAndHabitSaves() {
        let pursuitID = UUID()

        #expect(PursuitAssignmentRules.canSaveGoal(title: "Read 12 books", pursuitID: pursuitID))
        #expect(PursuitAssignmentRules.canSaveHabit(title: "Read daily", pursuitID: pursuitID))
        #expect(!PursuitAssignmentRules.canSaveGoal(title: "Read 12 books", pursuitID: nil))
        #expect(!PursuitAssignmentRules.canSaveHabit(title: "Read daily", pursuitID: nil))
        #expect(!PursuitAssignmentRules.canSaveGoal(title: "   ", pursuitID: pursuitID))
        #expect(!PursuitAssignmentRules.canSaveHabit(title: "", pursuitID: pursuitID))
    }

    @Test func unassignedReviewQueuesAndManualAssignmentPreserveSignals() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let context = Context(name: "Personal")
        let area = Area(name: "Reading", context: context)
        let pursuit = Pursuit(title: "Become more knowledgeable", context: context)
        let goal = Goal(title: "Read 12 books", context: context)
        let link = GoalListLink(goal: goal, area: area)

        let doneTask = AppTask(title: "Finish first book")
        doneTask.area = area
        doneTask.context = context
        doneTask.status = .done
        let openTask = AppTask(title: "Start second book")
        openTask.area = area
        openTask.context = context

        let habit = Habit(title: "Read 30 minutes", context: context)
        let completion = HabitCompletion(date: "2026-04-30", habit: habit)

        modelContext.insert(context)
        modelContext.insert(area)
        modelContext.insert(pursuit)
        modelContext.insert(goal)
        modelContext.insert(link)
        modelContext.insert(doneTask)
        modelContext.insert(openTask)
        modelContext.insert(habit)
        modelContext.insert(completion)
        try modelContext.save()

        let progressBeforeAssignment = goal.progress
        let completionCountBeforeAssignment = habit.completions?.count ?? 0
        #expect(PursuitAssignmentRules.unassignedGoals(from: [goal]).map(\.id) == [goal.id])
        #expect(PursuitAssignmentRules.unassignedHabits(from: [habit]).map(\.id) == [habit.id])

        goal.pursuit = pursuit
        habit.pursuit = pursuit
        try modelContext.save()

        #expect(PursuitAssignmentRules.unassignedGoals(from: [goal]).isEmpty)
        #expect(PursuitAssignmentRules.unassignedHabits(from: [habit]).isEmpty)
        #expect(goal.progress == progressBeforeAssignment)
        #expect(habit.completions?.count == completionCountBeforeAssignment)
    }
}
