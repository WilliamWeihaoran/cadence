import Foundation
import SwiftData

/// Today's rollover notice — the banner offering to move yesterday's unfinished plans onto today —
/// stated once, for both platforms.
///
/// It was macOS-only (T-195), and macOS-only in three separate pieces: the `@AppStorage` key, an
/// inline `shouldShowRolloverNotice` predicate on `TasksPanel`, and a `todayGroupedTaskItems`
/// method on `TasksPanelDerivedState` that withheld the offered tasks from the grouped list while
/// the banner was up. None of the three touched AppKit; the only genuinely macOS-bound half was the
/// mutation, `SchedulingActions.rollOverTaskToToday`, which is
/// `CadenceTaskMutationSupport.rollOverTaskToToday` now.
///
/// Everything here is pure except `rollOver(_:todayKey:modelContext:)`, so the decision can be
/// tested without a view on either platform — which matters more than usual, because
/// `Cadence/iOS/` is invisible to the macOS-built test target.
enum CadenceTodayRolloverSupport {
    /// The `UserDefaults` key both platforms read.
    ///
    /// **The same key on purpose.** Dismissing the notice is a statement about the *day* — "yes, I
    /// have seen yesterday's leftovers" — not about the device it was made on, and the value is a
    /// `yyyy-MM-dd` day key rather than a flag, so it self-expires at midnight. A second key would
    /// mean the phone re-offered a roll the Mac had already performed, over tasks that are no
    /// longer past-do.
    static let dismissedDateStorageKey = "todayRolloverNoticeDismissedDate"

    static let title = "Leftover tasks are rolling over to today"
    static let confirmActionTitle = "Roll Over"

    /// The over-do bucket: open work planned for a day that has gone by. **The do date is the
    /// whole question; the due date is not asked about at all.**
    ///
    /// It used to be asked. This built a `claimedByDueDate` set — every open task due today or
    /// earlier — and subtracted it, on the reading that "a due date outranks a do date everywhere
    /// on Today, so a task that is both due yesterday and planned for yesterday reads as overdue
    /// and is not something the banner offers to reschedule". **T-1432 overturned that**, from the
    /// owner's own rule over a screenshot of the macOS Today column: *"today = today and anything
    /// before today. over do do date should be reschedule to today, but the overdue due date
    /// should not be rescheduled"*. The two dates answer different questions — the do date is a
    /// plan, and a plan that has gone by is exactly what wants moving; the due date is a promise,
    /// and a promise that has gone by is a fact about the past that moving would erase. Excluding
    /// on the due date entangled them, so a task planned 22 days ago that was *also* overdue was
    /// never offered and its do date stayed 22 days stale forever. That row is what the owner
    /// photographed: a sun reading `22 days ago` beside a flag reading `51 days ago`.
    ///
    /// **The roll still does not move a due date** — `CadenceTaskMutationSupport.rollOverTaskToToday`
    /// writes `scheduledDate`, `scheduledStartMin` and `calendarEventID` and nothing else — so an
    /// overdue task offered here is still overdue afterwards, still red, and still on Today. That
    /// is the invariant this widening rests on; `CadenceTodayRolloverSurfaceTests` asserts it
    /// directly rather than reading it off this comment.
    ///
    /// **Today's *ranking* is untouched and still puts the due date first.** `AppTask.todayStanding`
    /// answers `.pastDue` before `.pastDo`, and `CadenceTaskQuerySupport.todayRank` sorts on it.
    /// What the banner offers to reschedule and where a row sorts are separate concerns; only the
    /// first one moved.
    ///
    /// Safe to call with either the whole store or an already-Today-filtered array: the filtering
    /// is per-task and idempotent, which it is now more plainly than before — there is no longer a
    /// set derived from the argument, so the answer for one task cannot depend on which other
    /// tasks came with it.
    static func pastDoTasks(from tasks: [AppTask], todayKey: String) -> [AppTask] {
        tasks.filter { task in
            !task.isDone &&
            !task.isCancelled &&
            !task.scheduledDate.isEmpty &&
            task.scheduledDate < todayKey
        }
    }

    /// Whether the banner is on screen: there is something to roll, and it has not already been
    /// dismissed *today*.
    ///
    /// The comparison is against `todayKey` rather than "is non-empty", which is what makes the
    /// dismissal expire on its own overnight.
    static func isNoticeVisible(
        pastDoTaskCount: Int,
        dismissedDateKey: String,
        todayKey: String
    ) -> Bool {
        pastDoTaskCount > 0 && dismissedDateKey != todayKey
    }

    /// Today's tasks as the grouped list should show them while the banner is up: the offered tasks
    /// are withheld, because the banner is already listing them and a Past Do section under it
    /// would be the same rows twice.
    ///
    /// Dismissing merges them back in — there is no third state, and nothing is written to do it:
    /// `isNoticeVisible` goes false and the same array comes back whole.
    static func groupedTasks(
        from todayTasks: [AppTask],
        withholding pastDoTasks: [AppTask],
        isNoticeVisible: Bool
    ) -> [AppTask] {
        guard isNoticeVisible else { return todayTasks }
        let withheld = Set(pastDoTasks.map(\.id))
        return todayTasks.filter { !withheld.contains($0.id) }
    }

    /// The sentence the banner shows when the roll was refused (T-635).
    ///
    /// It carries the delete family's second clause — `CadenceTaskMutationSupport.deleteFailureNotice`,
    /// `bundleDeleteFailureNotice` and `CadenceListDeletionKind.deleteFailureNotice` all promise the
    /// same thing — because `rollOver` commits through `commitDelete`, whose `rollback()` puts the
    /// emptied block and the tasks' own slots back. The promise is earned rather than claimed.
    ///
    /// It names the roll rather than saying "these changes", for the reason the other four notices
    /// name their own object: four screens, four nouns, one shape.
    static let rollFailureNotice = "Couldn't roll these tasks over. Nothing was changed."

    /// Performs the roll and returns the day key to store as dismissed.
    ///
    /// One commit for the whole batch. The per-task slot clearing is
    /// `CadenceTaskMutationSupport.rollOverTaskToToday`.
    ///
    /// **It throws, and that is the whole of T-635.** This used to end `try? modelContext.save()`
    /// and `return todayKey` unconditionally, and both hosts assigned the return straight into the
    /// `@AppStorage` `rolloverNoticeDismissedDate`. Every other false success in the save-commit
    /// ledger is state a redraw repairs; a defaults write is not, so a refused roll hid the banner
    /// for the rest of the day over a store that still held yesterday's plans — and hid it on the
    /// *other* device too, since the key is deliberately shared.
    ///
    /// `commitDelete` rather than `commitEdit` for the *existence* half, because the roll is an
    /// existence change two frames down: `rollOverTaskToToday` reaches `deleteBundleIfFullySettled`,
    /// which does `modelContext.delete(bundle)`. A block whose last active member was carried away
    /// has no object left to hand back, so `rollback()` is the only undo that makes it visible
    /// again — the same reasoning `CadenceTaskMutationSupport.deleteBundle` records.
    ///
    /// **And `commitEdit` around it for the other half ([[T-1336]]).** Almost everything this
    /// writes lands on a task that *survives* the roll — the day it sits on, the minute it starts
    /// at, the block it left and the order of whatever stayed behind — and `rollback()`'s reach
    /// onto an already-materialised reference is the one thing this repository's two toolchains
    /// disagree about. So the roll's own writes are snapshotted and put back explicitly, from
    /// inside `commitDelete`'s `commit:` so the restore lands *before* the rollback;
    /// `CadenceDeleteSurvivorSnapshot` carries the full argument, including why that order is what
    /// keeps `hasChanges` false on every toolchain.
    ///
    /// - Parameter commit: See `CadencePendingChangePersistence.commitInsert(of:in:commit:)`.
    @discardableResult
    static func rollOver(
        _ tasks: [AppTask],
        todayKey: String,
        modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> String {
        // Every task rolled, and every other member of every block they are leaving, because
        // `rollOverTaskToToday` renumbers the block it empties and may dispose of it — and all of
        // those rows **survive** the one delete this commit carries (T-1336). The refusal has to
        // put their slots back, not only un-delete the block; `CadenceDeleteSurvivorSnapshot`
        // carries the argument for why `rollback()` alone does not.
        var survivors = CadenceDeleteSurvivorSnapshot()
        for task in tasks {
            survivors.captureSlot(of: task)
            guard let bundle = task.bundle else { continue }
            survivors.captureMembership(of: bundle)
            for member in bundle.tasks ?? [] {
                survivors.captureSlot(of: member)
            }
        }

        for task in tasks {
            CadenceTaskMutationSupport.rollOverTaskToToday(task, todayKey: todayKey, modelContext: modelContext)
        }
        try CadencePendingChangePersistence.commitDelete(
            in: modelContext,
            commit: { try CadencePendingChangePersistence.commitEdit(in: $0, commit: commit, undo: survivors.restore) }
        )
        return todayKey
    }
}
