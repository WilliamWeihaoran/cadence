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
    static let message = "Review these tasks, then confirm to move them into today's groups."
    static let confirmActionTitle = "Roll Over"

    /// The over-do bucket: open work planned for a day that has gone by, on which no *due* date has
    /// a prior claim.
    ///
    /// A due date outranks a do date everywhere on Today — `CadenceTaskQuerySupport.todayGroups`
    /// hands overdue and due-today their tasks before `.pastDo` sees what is left — so a task that
    /// is both due yesterday and planned for yesterday belongs to Overdue and is not something the
    /// banner offers to reschedule.
    ///
    /// Safe to call with either the whole store or an already-Today-filtered array: the extra
    /// filtering is idempotent, and the exclusion set is derived from the same array rather than
    /// passed in.
    static func pastDoTasks(from tasks: [AppTask], todayKey: String) -> [AppTask] {
        let open = tasks.filter { !$0.isDone && !$0.isCancelled }
        let claimedByDueDate = Set(
            open
                .filter { $0.dueDate == todayKey || (!$0.dueDate.isEmpty && $0.dueDate < todayKey) }
                .map(\.id)
        )
        return open.filter { task in
            !claimedByDueDate.contains(task.id) &&
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

    /// Performs the roll and returns the day key to store as dismissed.
    ///
    /// One save for the whole batch. The per-task slot clearing is
    /// `CadenceTaskMutationSupport.rollOverTaskToToday`.
    @discardableResult
    static func rollOver(
        _ tasks: [AppTask],
        todayKey: String,
        modelContext: ModelContext
    ) -> String {
        for task in tasks {
            CadenceTaskMutationSupport.rollOverTaskToToday(task, todayKey: todayKey, modelContext: modelContext)
        }
        try? modelContext.save()
        return todayKey
    }
}
