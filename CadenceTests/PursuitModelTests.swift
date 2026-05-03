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
}
