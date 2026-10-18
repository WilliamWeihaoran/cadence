import Foundation
@testable import Cadence

/// Puts a task into an existing `TaskBundle` for a test's fixture, by writing the model directly.
///
/// **Fixture setup only, never a subject under test.** [[T-3170]]'s trio pass deleted the last
/// app paths that could add a task to a block -- SchedulingActions.addTask(_:to:) and
/// CadenceTaskMutationSupport.addTask(_:to:modelContext:commit:) -- but blocks still exist in
/// stores (the retirement migration, rollover, unbundle and delete all still act on them), so the
/// suites that test those paths still need a task that is already a member. This writes the same
/// fields the deleted paths wrote, so those fixtures describe the state the app used to produce:
/// a detach from any previous block, the next `bundleOrder`, the block's day, no time-of-day slot
/// of its own, and no calendar-event link.
enum CadenceTestBundleFixture {

    static func place(_ task: AppTask, in bundle: TaskBundle) {
        if let previous = task.bundle, previous.id != bundle.id {
            previous.tasks = (previous.tasks ?? []).filter { $0.id != task.id }
            task.bundle = nil
        }
        if task.bundle?.id != bundle.id {
            let members = (bundle.tasks ?? []).filter { $0.id != task.id }
            task.bundleOrder = (members.map(\.bundleOrder).max() ?? -1) + 1
        }
        task.bundle = bundle
        task.scheduledDate = bundle.dateKey
        task.scheduledStartMin = -1
        task.calendarEventID = ""
        if !(bundle.tasks ?? []).contains(where: { $0.id == task.id }) {
            bundle.tasks = (bundle.tasks ?? []) + [task]
        }
    }
}
