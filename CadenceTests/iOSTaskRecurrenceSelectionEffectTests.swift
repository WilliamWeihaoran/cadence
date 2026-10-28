import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Cadence

// T-3244: the first suite in this target that exercises `#if os(iOS)` code BY EFFECT.
//
// Until this file, nothing inside `Cadence/iOS/` could be held by anything but a source scan.
// `CadenceTests` built for macOS alone, so an iOS-only declaration was not merely untested — it
// was not in the module. Every iOS pin in this target is therefore a string search over the file,
// and `CadenceInPlaceEditFlushCommitTests` says so out loud at `:529`, where it asserts that the
// body of `selectRecurrenceRule` *contains the text* `iOSTaskRecurrenceSelection.select(`. That
// pin cannot tell a call that works from a call that returns the wrong answer; it only knows the
// characters are present.
//
// This suite calls the thing. It is gated `#if os(iOS)` because `iOSTaskRecurrenceSelection` does
// not exist on the macOS leg, and it runs on an iOS destination because the target now compiles
// for one.
//
// **The branch that matters is the second one, and it is the one a scan is blindest to.** A task
// that belongs to a series must NOT have its rule rewritten until the user has said whether they
// mean this occurrence or the whole series: the chosen rule is parked in `pendingRecurrenceRule`
// for `iOSTaskRowRecurrenceScopeDialog` to ask about, and the store is left exactly as it was
// found. "The store was left alone" is a statement about the model after the call. No amount of
// reading the source establishes it.
#if os(iOS)

@Suite @MainActor
struct iOSTaskRecurrenceSelectionEffectTests {

    /// A standalone, non-recurring task: the rule is written and the store is committed.
    ///
    /// `hasChanges` is the half that matters beside the value. `select` reports `true` for both a
    /// successful commit and a parked series edit, so the return value alone cannot separate
    /// "saved" from "deferred" — a context with no pending changes after the call is what says the
    /// write actually reached the store rather than sitting dirty in memory.
    @Test func aStandaloneTaskTakesTheRuleAndTheStoreIsCommitted() throws {
        let context = ModelContext(try CadenceTestStore.container())
        let task = AppTask(title: "Water the plants")
        context.insert(task)
        try context.save()

        #expect(task.recurrenceRule == .none, "fixture is not the non-recurring case it claims")
        #expect(task.isRecurrenceSeriesMember == false, "fixture is already a series member")

        var parked: TaskRecurrenceRule?
        let landed = iOSTaskRecurrenceSelection.select(
            .weekly,
            for: task,
            allTasks: [task],
            modelContext: context,
            pendingRecurrenceRule: Binding(get: { parked }, set: { parked = $0 })
        )

        #expect(!landed, "the picker was told to stay open over a store that accepted the edit")
        #expect(task.recurrenceRule == .weekly, "the rule never reached the task")
        #expect(parked == nil, "a standalone task armed the scope dialog it has no series for")
        #expect(context.hasChanges == false, "the edit was applied but never committed")
    }

    /// The series branch: the rule is parked, and the task is left exactly as it was found.
    ///
    /// This is the assertion `CadenceInPlaceEditFlushCommitTests:529` cannot make. That pin reads
    /// the characters `iOSTaskRecurrenceSelection.select(` in the caller's body; it would still
    /// pass if this guard were deleted and a series member's rule were rewritten under the user.
    @Test func aSeriesMemberParksTheRuleAndTheStoreIsNotTouched() throws {
        let context = ModelContext(try CadenceTestStore.container())
        let task = AppTask(title: "Stand-up")
        task.recurrenceRule = .weekly
        context.insert(task)
        try context.save()

        #expect(task.isRecurrenceSeriesMember, "fixture is not the series case this test is about")

        var parked: TaskRecurrenceRule?
        let landed = iOSTaskRecurrenceSelection.select(
            .monthly,
            for: task,
            allTasks: [task],
            modelContext: context,
            pendingRecurrenceRule: Binding(get: { parked }, set: { parked = $0 })
        )

        #expect(landed, "the picker stayed open over an edit that was deferred, not refused")
        #expect(parked == .monthly, "the scope dialog was never armed with the chosen rule")
        #expect(
            task.recurrenceRule == .weekly,
            "a series member's rule was rewritten before the user chose a scope"
        )
        #expect(context.hasChanges == false, "the series branch wrote to the store")
    }

    /// Re-picking the rule a task already has is a no-op that still lets the picker close.
    @Test func reselectingTheCurrentRuleWritesNothingAndStillCloses() throws {
        let context = ModelContext(try CadenceTestStore.container())
        let task = AppTask(title: "Weekly review")
        task.recurrenceRule = .weekly
        context.insert(task)
        try context.save()

        var parked: TaskRecurrenceRule?
        let landed = iOSTaskRecurrenceSelection.select(
            .weekly,
            for: task,
            allTasks: [task],
            modelContext: context,
            pendingRecurrenceRule: Binding(get: { parked }, set: { parked = $0 })
        )

        #expect(landed, "picking the rule already in force refused to close the picker")
        #expect(parked == nil, "an unchanged rule armed the scope dialog")
        #expect(task.recurrenceRule == .weekly)
        #expect(context.hasChanges == false)
    }
}

#endif
