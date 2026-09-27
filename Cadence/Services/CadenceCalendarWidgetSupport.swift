import Foundation
import SwiftData

nonisolated enum CadenceCalendarWidgetSnapshotState: String, Hashable {
    case ready
    case empty
    case unavailable
}

nonisolated struct CadenceCalendarWidgetDay: Identifiable, Hashable {
    let dateKey: String
    let weekdayLabel: String
    let dayNumberLabel: String
    let dueCount: Int
    let scheduledCount: Int
    let totalCount: Int
    let isToday: Bool

    var id: String { dateKey }
}

nonisolated struct CadenceCalendarWidgetSnapshot: Hashable {
    let date: Date
    let state: CadenceCalendarWidgetSnapshotState
    let statusMessage: String?
    let days: [CadenceCalendarWidgetDay]
    let overdueCount: Int
    let upcomingTitle: String?
    /// `yyyy-MM-dd` due date of the `upcomingTitle` task, empty when it has none. Defaulted so
    /// snapshot literals that only care about the title stay source-compatible.
    var upcomingDueDate: String = ""

    /// Points at the day this snapshot is *about*, which is the first cell of the strip it draws.
    /// See `CadenceDeepLink.calendar` for what a link without one used to do.
    var calendarURL: URL {
        CadenceDeepLink.calendar(dateKey: CadenceWidgetDateSupport.dateKey(from: date)).url
    }

    var isUnavailable: Bool {
        state == .unavailable
    }
}

nonisolated enum CadenceCalendarWidgetSupport {
    /// **This fetch used to carry no predicate at all, and [[T-1366]] measured what that cost.**
    ///
    /// The instrument's `rowsFetched` is what named the population: holding the qualifying rows —
    /// open work carrying at least one date — at 120 and adding ballast the derivation cannot
    /// read, this generation grew with the ballast and the Today widget's, over the *same* store,
    /// did not. Medians of 7 on an M3 Pro, disk-backed fixtures, Xcode 27: 10,000 settled rows
    /// took Calendar from 9.98ms to 337ms (fetch 4.25 -> 307.7ms) while Today stayed at 9.79ms,
    /// and 10,000 open-but-undated rows took it to 579ms — worse, because those survive
    /// `openTasks` and are then walked again by every day in the strip. The whole of that is rows
    /// that cannot appear in the answer.
    ///
    /// **They cannot, and that is an argument rather than an observation.** Every term below
    /// reads a task either through `$0.dueDate == dateKey` / `$0.scheduledDate == dateKey` for a
    /// non-empty `dateKey`, through `!$0.dueDate.isEmpty`, or through
    /// `CadenceTodayWidgetSupport.todayTasks`, whose membership test is `AppTask.isTodayWork` and
    /// so needs a standing, and so needs a date. All of them sit behind `openTasks`. So the
    /// predicate `datedOpenTaskFetchDescriptor()` already spells — unfinished, and carrying at
    /// least one date — admits every row that can change this snapshot and nothing else, and
    /// sharing that one descriptor rather than writing a second predicate here is the T-353 rule
    /// this file has already been bitten by once.
    ///
    /// `probe` is [[T-1366]]'s instrument, `nil` for every caller but the timeline provider, and
    /// `rowsFetched` is the bound: it is now the qualifying population and must not move with the
    /// rest of the table again.
    nonisolated static func snapshot(
        modelContext: ModelContext,
        dayCount: Int,
        probe: CadenceWidgetGenerationProbe? = nil
    ) throws -> CadenceCalendarWidgetSnapshot {
        let today = Calendar.current.startOfDay(for: Date())
        let tasks = try modelContext.fetch(CadenceTodayWidgetSupport.datedOpenTaskFetchDescriptor())
        probe?.finished(.fetch, rows: tasks.count)
        let built = snapshot(from: tasks, today: today, dayCount: dayCount)
        probe?.finished(.derive)
        return built
    }

    nonisolated static func snapshot(
        from tasks: [AppTask],
        today: Date = Calendar.current.startOfDay(for: Date()),
        dayCount: Int
    ) -> CadenceCalendarWidgetSnapshot {
        let safeDayCount = max(dayCount, 1)
        let calendar = Calendar.current
        let todayKey = CadenceWidgetDateSupport.dateKey(from: today)
        let openTasks = tasks.filter { !$0.isDone && !$0.isCancelled }
        let days = (0..<safeDayCount).compactMap { offset -> CadenceCalendarWidgetDay? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let dateKey = CadenceWidgetDateSupport.dateKey(from: date)
            let dueCount = openTasks.filter { $0.dueDate == dateKey }.count
            let scheduledOnlyCount = openTasks.filter {
                $0.scheduledDate == dateKey && $0.dueDate != dateKey
            }.count
            return CadenceCalendarWidgetDay(
                dateKey: dateKey,
                weekdayLabel: CadenceWidgetDateSupport.weekdayLabel(from: date),
                dayNumberLabel: CadenceWidgetDateSupport.dayNumberLabel(from: date),
                dueCount: dueCount,
                scheduledCount: scheduledOnlyCount,
                totalCount: dueCount + scheduledOnlyCount,
                isToday: offset == 0
            )
        }

        let overdueCount = openTasks.filter {
            !$0.dueDate.isEmpty && $0.dueDate < todayKey
        }.count

        let upcomingTask = CadenceTodayWidgetSupport
            .todayTasks(from: openTasks, todayKey: todayKey)
            .first

        // **`upcomingTask != nil` is load-bearing, not belt-and-braces.** `.empty` is not a
        // count — it swaps the whole body for `emptyState`, and "Next up" is inside the branch it
        // replaces. So a store whose only open work is a task planned for an earlier day rendered
        // the empty state even once `todayTasks` could see it: `days` spans today forward, and
        // `overdueCount` is due-dates only, so neither term has a past-do branch. That is the same
        // missing rule as T-353, a third time, and fixing the picker alone left this widget still
        // saying nothing was urgent while the app's Today page had work on it. Asking the picker
        // whether it found anything reuses `AppTask.isTodayWork` instead of adding a fourth date
        // comparison here.
        let totalVisibleCount = days.reduce(0) { $0 + $1.totalCount }
        let isEmpty = totalVisibleCount == 0 && overdueCount == 0 && upcomingTask == nil

        return CadenceCalendarWidgetSnapshot(
            date: today,
            state: isEmpty ? .empty : .ready,
            statusMessage: nil,
            days: days,
            overdueCount: overdueCount,
            upcomingTitle: upcomingTask?.title,
            upcomingDueDate: upcomingTask?.dueDate ?? ""
        )
    }

    nonisolated static func unavailableSnapshot(
        today: Date = Calendar.current.startOfDay(for: Date()),
        message: String = "Open Cadence once to finish setting up shared widget data."
    ) -> CadenceCalendarWidgetSnapshot {
        CadenceCalendarWidgetSnapshot(
            date: today,
            state: .unavailable,
            statusMessage: message,
            days: [],
            overdueCount: 0,
            upcomingTitle: nil
        )
    }

    /// Shares `CadenceWidgetReloadPolicy` (T-851) with the other three widget support types, rather
    /// than computing the same fallback-plus-midnight-clamp shape by hand.
    nonisolated static func recommendedReloadDate(
        for snapshot: CadenceCalendarWidgetSnapshot,
        referenceDate: Date = Date()
    ) -> Date {
        CadenceWidgetReloadPolicy.recommendedReloadDate(
            referenceDate: referenceDate,
            isUnavailable: snapshot.state == .unavailable,
            isEmpty: snapshot.state == .empty,
            readyInterval: 20 * 60,
            emptyInterval: 45 * 60
        )
    }
}
