import Darwin
import Dispatch
import Foundation
import SwiftData

/// Fixed-format content budgets shared by providers and views; these count selected entries,
/// not pixels measured after WidgetKit lays out the view.
nonisolated enum CadenceWidgetFamilyLayout: CaseIterable, Sendable {
    case small, medium, large, extraLarge

    var todayTaskLimit: Int {
        switch self {
        case .small: 1
        case .medium: 3
        case .large: 2
        case .extraLarge: 8
        }
    }

    var habitLimit: Int {
        switch self {
        case .small: 2
        case .medium: 3
        case .large, .extraLarge: 8
        }
    }

    var habitColumns: Int { self == .small ? 2 : 3 }

    var calendarDayLimit: Int {
        switch self {
        case .small: 3
        case .medium: 6
        case .large, .extraLarge: 14
        }
    }

    var milestoneGoalLimit: Int {
        switch self {
        case .small: 1
        case .medium: 3
        case .large, .extraLarge: 5
        }
    }
}

nonisolated enum CadenceTodayWidgetSnapshotState: String, Hashable {
    case ready
    case empty
    case unavailable
}

nonisolated struct CadenceTodayWidgetTask: Identifiable, Hashable {
    let id: UUID
    let title: String
    let priorityRaw: String
    let dueDate: String
    let scheduledDate: String
    let containerName: String

    var deepLinkURL: URL {
        CadenceDeepLink.task(id).url
    }
}

nonisolated struct CadenceTodayWidgetSnapshot: Hashable {
    let date: Date
    let dateKey: String
    let state: CadenceTodayWidgetSnapshotState
    let statusMessage: String?
    let totalCount: Int
    let overdueCount: Int
    let dueTodayCount: Int
    let scheduledTodayCount: Int
    let tasks: [CadenceTodayWidgetTask]
    var suppressionExpiresAt: Date? = nil

    var todayURL: URL {
        CadenceDeepLink.today.url
    }

    var isUnavailable: Bool {
        state == .unavailable
    }
}

nonisolated enum CadenceTodayWidgetSupport {
    nonisolated static func snapshot(
        modelContext: ModelContext,
        limit: Int = 3,
        probe: CadenceWidgetGenerationProbe? = nil
    ) throws -> CadenceTodayWidgetSnapshot {
        try snapshot(modelContext: modelContext, todayKey: currentTodayKey(), limit: limit, probe: probe)
    }

    /// `probe` is [[T-1366]]'s instrument and nothing else: with it left `nil` — which is every
    /// caller outside the four timeline providers — this reads exactly as it did before, and with
    /// one supplied the store fetch and the in-memory derivation are timed apart and the row count
    /// the fetch materialised is recorded. The count is the population Today *ranks*, not the
    /// prefix it draws; `CadenceTodayWidgetSupport.datedOpenTaskFetchDescriptor()` is a deliberate
    /// superset and this is the first thing that says how big a superset it is.
    nonisolated static func snapshot(
        modelContext: ModelContext,
        todayKey: String,
        limit: Int = 3,
        probe: CadenceWidgetGenerationProbe? = nil
    ) throws -> CadenceTodayWidgetSnapshot {
        let tasks = try modelContext.fetch(datedOpenTaskFetchDescriptor())
        probe?.finished(.fetch, rows: tasks.count)
        let expirations = CadenceWidgetRefreshCenter.taskCompletionExpirations()
        let built = snapshot(
            from: tasks,
            todayKey: todayKey,
            limit: limit,
            suppressedTaskIDs: Set(expirations.keys),
            suppressionExpirations: expirations
        )
        probe?.finished(.derive)
        return built
    }

    nonisolated static func snapshot(
        from tasks: [AppTask],
        todayKey: String,
        limit: Int = 3,
        suppressedTaskIDs: Set<UUID> = [],
        suppressionExpirations: [UUID: Date] = [:]
    ) -> CadenceTodayWidgetSnapshot {
        let visibleLimit = max(limit, 0)
        var totalCount = 0
        var overdueCount = 0
        var dueTodayCount = 0
        var scheduledTodayCount = 0
        var visibleTasks: [CadenceTodayWidgetTask] = []
        visibleTasks.reserveCapacity(visibleLimit)
        var suppressionExpiresAt: Date?

        for task in todayTasks(from: tasks, todayKey: todayKey) {
            if suppressedTaskIDs.contains(task.id) {
                if let expiration = suppressionExpirations[task.id] {
                    suppressionExpiresAt = min(suppressionExpiresAt ?? expiration, expiration)
                }
                continue
            }
            totalCount += 1
            // The badges read the shared standing rather than the dates a third time. Exhaustive
            // on purpose: the three counts must add up to `totalCount`, and before T-353 they did
            // not — a past-do task fell through all three branches, so a widget drawing one row
            // could read "0 overdue, 0 due, 0 planned" beside it.
            switch task.todayStanding(todayKey: todayKey) {
            case .pastDue:
                overdueCount += 1
            case .dueToday:
                dueTodayCount += 1
            case .pastDo, .doToday:
                // Yesterday's plan is still planned work; "Planned" is the badge it belongs under.
                scheduledTodayCount += 1
            case nil:
                break // Unreachable: `todayTasks` drops anything with no standing.
            }

            if visibleTasks.count < visibleLimit {
                visibleTasks.append(widgetTask(task))
            }
        }

        let state: CadenceTodayWidgetSnapshotState = totalCount == 0 ? .empty : .ready

        return CadenceTodayWidgetSnapshot(
            date: Date(),
            dateKey: todayKey,
            state: state,
            statusMessage: nil,
            totalCount: totalCount,
            overdueCount: overdueCount,
            dueTodayCount: dueTodayCount,
            scheduledTodayCount: scheduledTodayCount,
            tasks: visibleTasks,
            suppressionExpiresAt: suppressionExpiresAt
        )
    }

    nonisolated static func unavailableSnapshot(
        todayKey: String = currentTodayKey(),
        message: String = "Open Cadence once to finish setting up your shared widget data."
    ) -> CadenceTodayWidgetSnapshot {
        CadenceTodayWidgetSnapshot(
            date: Date(),
            dateKey: todayKey,
            state: .unavailable,
            statusMessage: message,
            totalCount: 0,
            overdueCount: 0,
            dueTodayCount: 0,
            scheduledTodayCount: 0,
            tasks: []
        )
    }

    nonisolated static func recommendedReloadDate(
        for snapshot: CadenceTodayWidgetSnapshot,
        referenceDate: Date = Date()
    ) -> Date {
        let regularReload = CadenceWidgetReloadPolicy.recommendedReloadDate(
            referenceDate: referenceDate,
            isUnavailable: snapshot.state == .unavailable,
            isEmpty: snapshot.state == .empty,
            readyInterval: 15 * 60,
            emptyInterval: 30 * 60
        )
        guard let expiration = snapshot.suppressionExpiresAt else { return regularReload }
        return min(regularReload, max(referenceDate, expiration))
    }

    /// The widget's Today list — **the app's Today scope, in the app's Today rank order**, with a
    /// priority tie-break of its own on top.
    ///
    /// Both of those used to be spelled here: a local `rank` with no past-do branch and a
    /// `rank < 3` membership test. So an unfinished task planned for an earlier day with no due
    /// date was on the app's Today page and missing from this list — and from the Calendar
    /// widget's "Next up", which is `.first` of this same call. That is T-353, and the reason it
    /// was two definitions rather than one missed case is that `Cadence/Shared/` is not compiled
    /// into `CadenceWidgets`. `AppTask.isTodayWork` / `todayStanding` are in `Models/`, which is,
    /// so this and `CadenceTaskQuerySupport.activeTodayTasks` now read the same rule.
    nonisolated static func todayTasks(
        from tasks: [AppTask],
        todayKey: String
    ) -> [AppTask] {
        tasks.compactMap { task -> (task: AppTask, rank: Int, priorityRank: Int)? in
            guard task.isTodayWork(todayKey: todayKey),
                  let standing = task.todayStanding(todayKey: todayKey) else { return nil }
            return (task, standing.rawValue, task.priority.rank)
        }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                if lhs.priorityRank != rhs.priorityRank {
                    return lhs.priorityRank > rhs.priorityRank
                }
                // The shared tie-break rather than a bare `order`. A widget renders the first
                // few rows of this list, so an unstable tail is the difference between "the
                // widget updated" and "the widget shuffled".
                return TaskOrdering.fallbackPrecedes(lhs.task, rhs.task)
            }
            .map(\.task)
    }

    private nonisolated static func widgetTask(_ task: AppTask) -> CadenceTodayWidgetTask {
        CadenceTodayWidgetTask(
            id: task.id,
            title: CadenceTitleNormalization.display(task.title, fallback: CadenceTitleNormalization.defaultCompactTitle),
            priorityRaw: task.priority.rawValue,
            dueDate: task.dueDate,
            scheduledDate: task.scheduledDate,
            containerName: task.containerName
        )
    }

    /// **Open work carrying at least one date** — the population every date-driven widget reads,
    /// and a deliberate superset of any one day's scope, deliberately ignorant of what day it is.
    ///
    /// A `#Predicate` is a macro compiled to a store query; it cannot call
    /// `AppTask.isTodayWork(todayKey:)`, so this is the one place a Today rule *could* only exist
    /// as a second copy. It used to be one: three date terms with no past-do branch, which is why
    /// fixing `todayTasks` alone would have left the shipping widget still missing the task —
    /// the row never reached it. So the date terms are gone rather than corrected. What is left
    /// says only "unfinished, and carrying at least one date", which every standing in
    /// `CadenceTodayStanding` implies and no future edit to that rule can outgrow.
    ///
    /// **The Calendar widget fetches through this too** ([[T-1366]]), which is why the name no
    /// longer says "today": all four of that widget's output terms — the day strip's due and
    /// scheduled counts, the overdue count and "Next up" — read a task only through a non-empty
    /// `dateKey` comparison or through `todayTasks`, and all four sit behind its own
    /// `!isDone && !isCancelled` filter. So a row this predicate drops could not have reached any
    /// of them, and dropping it in the store rather than in memory is the same snapshot for less.
    ///
    /// Internal rather than `private` so a test can drive the store query and the in-memory scope
    /// from one fixture set and require the same ids —
    /// `theWidgetsStoreQueryKeepsEveryTaskItsTodayScopeAdmits`.
    nonisolated static func datedOpenTaskFetchDescriptor() -> FetchDescriptor<AppTask> {
        let doneStatus = TaskStatus.done.rawValue
        let cancelledStatus = TaskStatus.cancelled.rawValue

        let predicate = #Predicate<AppTask> { task in
            task.statusRaw != doneStatus &&
            task.statusRaw != cancelledStatus &&
            (task.dueDate != "" || task.scheduledDate != "")
        }

        return FetchDescriptor<AppTask>(predicate: predicate)
    }

    private nonisolated static func currentTodayKey() -> String {
        CadenceWidgetDateSupport.dateKey(from: Date())
    }
}

/// The reload-timing rule every widget's `recommendedReloadDate` shares (T-851).
///
/// Three of the four `Cadence*WidgetSupport` types already computed the same shape by hand: a
/// fallback interval keyed by state, clamped to no later than the next midnight so a widget that
/// goes stale right before a day turns over still definitely reloads once it does. Milestone
/// Momentum's own copy never adopted the clamp — it returned `referenceDate.addingTimeInterval(_:)`
/// unbounded, so an empty pool at 23:50 reloaded around 00:50 the next day instead of 00:01. Widgets
/// ship inside the submitted binary, so that is not a hypothetical: it is a stale home screen a real
/// user can see for the better part of an hour after midnight, on the one widget that duplicated the
/// rule instead of sharing it.
///
/// Takes the two intervals a caller actually varies — `readyInterval` and `emptyInterval` — rather
/// than a whole state enum, because each support type declares its own `SnapshotState` and none of
/// the four needs another to agree with. `unavailableInterval` defaults to the one value every
/// existing caller already used.
nonisolated enum CadenceWidgetReloadPolicy {
    nonisolated static func recommendedReloadDate(
        referenceDate: Date = Date(),
        isUnavailable: Bool,
        isEmpty: Bool,
        readyInterval: TimeInterval,
        emptyInterval: TimeInterval,
        unavailableInterval: TimeInterval = 5 * 60
    ) -> Date {
        let calendar = Calendar.current
        let nextStartOfDay = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: referenceDate) ?? referenceDate
        ).addingTimeInterval(60)

        let fallbackInterval: TimeInterval = isUnavailable ? unavailableInterval : (isEmpty ? emptyInterval : readyInterval)
        return min(referenceDate.addingTimeInterval(fallbackInterval), nextStartOfDay)
    }
}

/// The widget target's date vocabulary.
///
/// **Everything here now forwards to `DateFormatters`.** This enum was originally a hand-rolled
/// copy because `DateFormatters` was main-actor isolated and widget timeline providers run off the
/// main actor — but the T-87 sweep marked that enum `nonisolated`, and `Cadence/Shared/`
/// `DateFormatters.swift` is compiled into `CadenceWidgets` alongside this file. So the workaround
/// outlived its reason, and what was left of it was a second set of date formats that drifted:
/// the labels below were built with `date.formatted(...)`, which follows `Locale.current`, so a
/// widget on a French phone rendered `SAM.` and `15 août` beside the app's English chrome on the
/// same home screen. The pinned formatters are the whole point of that file.
nonisolated enum CadenceWidgetDateSupport {
    /// Calendar-injectable core. The `Calendar.current` convenience below is what the widget
    /// actually calls, but a test host is always Gregorian, so without a seam no assertion here
    /// can tell a correct implementation from one that reads `Calendar.current`'s components.
    ///
    /// The Gregorian forcing that keeps these keys matching the store lives in
    /// `DateFormatters.storageCalendar(inheritingTimeZoneFrom:)`, which documents the Buddhist /
    /// Japanese / Islamic keys a `Calendar.current` read produced. This enum used to re-expose
    /// that as a forwarding member of its own; the collapse in `0e78c5b` left it with no callers,
    /// and T-453 removed it. Reach for `DateFormatters` directly if a widget ever needs it again.
    nonisolated static func dateKey(from date: Date, calendar: Calendar) -> String {
        DateFormatters.dateKey(from: date, calendar: calendar)
    }

    nonisolated static func dateKey(from date: Date) -> String {
        dateKey(from: date, calendar: .current)
    }

    /// `"SAT"`. Pinned to `en_US_POSIX` via `DateFormatters.dayOfWeek`, so it reads the same on
    /// every host — see the note on this enum for what following the host looked like.
    nonisolated static func weekdayLabel(from date: Date) -> String {
        DateFormatters.dayOfWeek.string(from: date).uppercased()
    }

    /// `"15"`. Pinned too, and the numerals are the reason: `DateFormatters.dayNumber` documents
    /// that an unpinned `"d"` renders Arabic-Indic digits under an `ar` host.
    nonisolated static func dayNumberLabel(from date: Date) -> String {
        DateFormatters.dayNumber.string(from: date)
    }

    /// Cadence's single due-date vocabulary: `nil` (no due date at all), "Due today",
    /// "Due tomorrow", "Overdue Aug 2", "Due Aug 14".
    ///
    /// This is the one implementation — `CadenceFocusSupport.dueLabel(forDueDateKey:todayKey:)`
    /// forwards here. It lives in this enum rather than beside the focus helper because that is
    /// where the widget target's callers already look for it; the `nonisolated` marks are kept
    /// explicit for the same reason, since widget timeline providers run off the main actor.
    ///
    /// Returns `nil` — never a generic stand-in string — when the task has no due date, so a task
    /// due later can never render identically to one with no deadline at all. An overdue task
    /// names its date instead of saying a bare "Overdue"; the date is the part the reader needs.
    ///
    /// The widget copy used to name near dates by weekday ("Due Fri") and guard that with a
    /// six-day cutoff, because weekday names repeat at seven days. Both are gone with the weekday
    /// names: the only relative word left is "tomorrow", which is an exact one-day offset and so
    /// needs no window.
    nonisolated static func dueLabel(for dueDate: String, todayKey: String) -> String? {
        let key = dueDate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        if key == todayKey { return "Due today" }

        let day = dayLabel(fromKey: key)
        if key < todayKey { return "Overdue \(day)" }

        if let today = parsedDate(fromKey: todayKey),
           let date = parsedDate(fromKey: key),
           Calendar.current.dateComponents([.day], from: today, to: date).day == 1 {
            return "Due tomorrow"
        }
        return "Due \(day)"
    }

    /// "Aug 14" for a `yyyy-MM-dd` key, falling back to the raw key when it cannot be parsed.
    /// Literally `DateFormatters.shortDateString(from:)` — the app and the widget say the date the
    /// same way because they now say it with the same formatter.
    nonisolated static func dayLabel(fromKey key: String) -> String {
        DateFormatters.shortDateString(from: key)
    }

    /// Resolves a `yyyy-MM-dd` key to midnight in the current calendar's time zone.
    nonisolated static func parsedDate(fromKey key: String) -> Date? {
        DateFormatters.date(from: key, in: .current)
    }
}

// MARK: - T-1366: what one widget generation cost, and whether it finished

/// The parts of a widget generation this instrument times separately.
///
/// **A stage is absent from a record when the path that produced it does not separate that stage,
/// and absent is not zero.** That is the same distinction `NoteMigrationReport.noteTableScanned`
/// exists to make one file over: a `0` in an `Int` field reads identically whether the number was
/// measured or never computed, and a reader that prints it without asking first is reporting a
/// number nobody took.
///
/// **All four widget kinds now separate all three stages** ([[T-1403]]): each support type's
/// store-facing `snapshot` takes `probe:` and closes `fetch` and `derive` around its own fetch, and
/// each provider closes `containerOpen`. Habit and Milestone were the two that did not, because
/// their support types were outside [[T-1366]]'s file ownership. **The absent-is-not-zero rule is
/// unchanged and is what makes the widening visible**: `probe:` defaults to `nil`, so a caller that
/// passes none still produces a record with no `fetch` and no `derive` in `measuredStages` and a
/// `nil` `rowsFetched` — not a record claiming a fetch that cost nothing and materialised no rows.
nonisolated enum CadenceWidgetStage: String, Hashable, CaseIterable {
    case containerOpen
    case fetch
    case derive
}

/// How a generation ended. **`empty` and `refused` are different answers and are stored apart.**
///
/// Before this, they were not: all four providers catch an open or fetch failure and return their
/// `unavailableSnapshot()`, which renders the same "open Cadence once" chrome whether the store
/// held no work or could not be read at all — and nothing outlived the process to say which. The
/// audit's silent case is exactly this pair: a widget that looks successfully stale and a refresh
/// that arrived late are indistinguishable from outside.
nonisolated enum CadenceWidgetGenerationOutcome: String, Hashable {
    /// The provider built an entry with rows in it.
    case ready
    /// The provider ran to completion and there was nothing to draw. A **result**, not a failure.
    case empty
    /// The provider could not run. A **failure**, never a result.
    case refused
}

/// One generation's measured cost, small enough to live in the app group and carry no user text.
///
/// **Content-free by construction, not by review.** Every field here is a duration, a count, a
/// timestamp, or a refusal reason built by `CadenceWidgetGenerationLedger.refusalReason(for:)` out
/// of an error's type name and `NSError` domain/code. No title, note body, tag or identifier
/// reaches it, which is why it is safe for the widget process to leave behind in shared storage.
nonisolated struct CadenceWidgetGenerationRecord: Hashable {
    let kind: String
    let outcome: CadenceWidgetGenerationOutcome
    /// Non-`nil` exactly when `outcome` is `refused`.
    let refusalReason: String?
    /// Seconds per stage this path actually separated. Never carries a stage it did not measure.
    let stageDurations: [CadenceWidgetStage: TimeInterval]
    /// Seconds from the first instruction of the provider's body to the record being built.
    let totalDuration: TimeInterval
    /// Rows the store materialised, or `nil` where the path has no row instrument at all.
    let rowsFetched: Int?
    /// Rows the entry draws, which is the visible prefix and not the population it was ranked from.
    let renderedCount: Int
    /// Physical footprint in bytes at the end of the generation, or `nil` when the kernel refused
    /// to answer. Never `0`: see `CadenceProcessFootprint.currentBytes()`.
    let footprintBytes: Int?
    /// When this generation ran.
    let generatedAt: Date
    /// The instant the snapshot says its data came from — **the thing a next-reload date cannot
    /// tell you.** `nil` for a refusal, whose snapshot has no source.
    let sourceSnapshotAt: Date?

    /// **An instrument with nothing in it refuses to be a record.**
    ///
    /// A successful generation that measured no stage is a reader that returned nothing, and
    /// reporting it as a clean sweep of zeroes is the failure this whole ticket is against. A
    /// refusal is allowed to have measured no stage — the container open can throw before any
    /// stage finishes — but it must then say why it refused.
    init?(
        kind: String,
        outcome: CadenceWidgetGenerationOutcome,
        refusalReason: String?,
        stageDurations: [CadenceWidgetStage: TimeInterval],
        totalDuration: TimeInterval,
        rowsFetched: Int?,
        renderedCount: Int,
        footprintBytes: Int?,
        generatedAt: Date,
        sourceSnapshotAt: Date?
    ) {
        guard !kind.isEmpty, totalDuration.isFinite, totalDuration >= 0, renderedCount >= 0 else { return nil }
        guard stageDurations.values.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        switch outcome {
        case .refused:
            guard let refusalReason, !refusalReason.isEmpty else { return nil }
            self.refusalReason = refusalReason
        case .ready, .empty:
            guard !stageDurations.isEmpty, refusalReason == nil else { return nil }
            self.refusalReason = nil
        }
        self.kind = kind
        self.outcome = outcome
        self.stageDurations = stageDurations
        self.totalDuration = totalDuration
        self.rowsFetched = rowsFetched
        self.renderedCount = renderedCount
        self.footprintBytes = footprintBytes
        self.generatedAt = generatedAt
        self.sourceSnapshotAt = sourceSnapshotAt
    }

    /// The stages this record is entitled to speak about. Anything outside it was not measured.
    var measuredStages: Set<CadenceWidgetStage> {
        Set(stageDurations.keys)
    }

    /// Seconds the measured stages account for. Never more than `totalDuration`.
    var accountedDuration: TimeInterval {
        stageDurations.values.reduce(0, +)
    }
}

/// Why the ledger has no number, said out loud instead of returned as zeroes.
nonisolated enum CadenceWidgetLedgerSilence: String, Hashable {
    /// Nobody opted the instrument in, so nothing was ever written.
    case instrumentDisabled
    /// The instrument is on and this kind has not generated since the state was cleared.
    case nothingRecorded
    /// Something is stored under the key and it is not a record this reader can believe.
    case recordUnreadable
}

/// A reading, or a refusal to give one. There is no third answer and no empty report.
nonisolated enum CadenceWidgetLedgerReading: Hashable {
    case recorded(CadenceWidgetGenerationRecord)
    case silent(CadenceWidgetLedgerSilence)

    var record: CadenceWidgetGenerationRecord? {
        switch self {
        case let .recorded(record): return record
        case .silent: return nil
        }
    }

    var silence: CadenceWidgetLedgerSilence? {
        switch self {
        case .recorded: return nil
        case let .silent(silence): return silence
        }
    }
}

/// The durable half of the widget instrument: three slots per widget kind in the app group.
///
/// **Three and not one, because the last generation is the wrong question.** The audit's silent
/// pair needs the last *successful* generation kept beside the last *refusal*: a widget whose last
/// success is hours old and whose last refusal is seconds old is failing to refresh, and a widget
/// whose last success is hours old with no refusal behind it was never asked. One slot holding
/// whichever happened most recently cannot separate those, and `.after(date)` — the only thing the
/// providers record today — is a *request* for a timeline opportunity, not evidence one arrived.
///
/// Opt-in: with `enabledDefaultsKey` unset, `CadenceWidgetGenerationProbe` still times its stages
/// in memory (three integer subtractions) but takes no footprint reading and writes nothing at all,
/// and every reader below answers `.silent(.instrumentDisabled)`.
nonisolated enum CadenceWidgetGenerationLedger {
    static let enabledDefaultsKey = "cadence.instrument.widgetCost.enabled"
    static let lastGenerationKeyPrefix = "cadence.instrument.widgetCost.lastGeneration."
    static let lastSuccessKeyPrefix = "cadence.instrument.widgetCost.lastSuccess."
    static let lastRefusalKeyPrefix = "cadence.instrument.widgetCost.lastRefusal."

    /// Every widget kind that writes here, so a reader can sweep without a second hand-list.
    static let instrumentedKinds = [
        CadenceWidgetRefreshCenter.todayWidgetKind,
        CadenceWidgetRefreshCenter.calendarWidgetKind,
        CadenceWidgetRefreshCenter.habitWidgetKind,
        CadenceWidgetRefreshCenter.milestoneWidgetKind,
    ]

    static func isEnabled(userDefaults: UserDefaults? = nil) -> Bool {
        sharedDefaults(userDefaults).bool(forKey: enabledDefaultsKey)
    }

    static func setEnabled(_ enabled: Bool, userDefaults: UserDefaults? = nil) {
        let defaults = sharedDefaults(userDefaults)
        if enabled {
            defaults.set(true, forKey: enabledDefaultsKey)
        } else {
            defaults.removeObject(forKey: enabledDefaultsKey)
        }
    }

    /// The most recent generation of `kind`, whatever it ended as.
    static func lastGeneration(kind: String, userDefaults: UserDefaults? = nil) -> CadenceWidgetLedgerReading {
        read(prefix: lastGenerationKeyPrefix, kind: kind, userDefaults: userDefaults)
    }

    /// The most recent generation of `kind` that produced an entry — `ready` or `empty`.
    static func lastSuccess(kind: String, userDefaults: UserDefaults? = nil) -> CadenceWidgetLedgerReading {
        read(prefix: lastSuccessKeyPrefix, kind: kind, userDefaults: userDefaults)
    }

    /// The most recent generation of `kind` that could not run.
    static func lastRefusal(kind: String, userDefaults: UserDefaults? = nil) -> CadenceWidgetLedgerReading {
        read(prefix: lastRefusalKeyPrefix, kind: kind, userDefaults: userDefaults)
    }

    static func record(_ record: CadenceWidgetGenerationRecord, userDefaults: UserDefaults? = nil) {
        let defaults = sharedDefaults(userDefaults)
        guard defaults.bool(forKey: enabledDefaultsKey) else { return }
        let payload = record.storagePayload
        defaults.set(payload, forKey: lastGenerationKeyPrefix + record.kind)
        switch record.outcome {
        case .ready, .empty:
            defaults.set(payload, forKey: lastSuccessKeyPrefix + record.kind)
        case .refused:
            defaults.set(payload, forKey: lastRefusalKeyPrefix + record.kind)
        }
    }

    static func clearStoredState(userDefaults: UserDefaults? = nil) {
        let defaults = sharedDefaults(userDefaults)
        for kind in instrumentedKinds {
            defaults.removeObject(forKey: lastGenerationKeyPrefix + kind)
            defaults.removeObject(forKey: lastSuccessKeyPrefix + kind)
            defaults.removeObject(forKey: lastRefusalKeyPrefix + kind)
        }
    }

    /// A refusal reason that **cannot** carry user text, because it is built only from an error's
    /// type name and its `NSError` domain and code. `localizedDescription` is not used: SwiftData's
    /// own sentence is one fixed string for every cause, and the Cocoa errors underneath it name
    /// file paths.
    static func refusalReason(for error: Error) -> String {
        let bridged = error as NSError
        return "\(type(of: error))/\(bridged.domain)/\(bridged.code)"
    }

    private static func read(
        prefix: String,
        kind: String,
        userDefaults: UserDefaults?
    ) -> CadenceWidgetLedgerReading {
        let defaults = sharedDefaults(userDefaults)
        guard defaults.bool(forKey: enabledDefaultsKey) else { return .silent(.instrumentDisabled) }
        guard let payload = defaults.dictionary(forKey: prefix + kind) else { return .silent(.nothingRecorded) }
        guard let record = CadenceWidgetGenerationRecord(storagePayload: payload) else {
            return .silent(.recordUnreadable)
        }
        return .recorded(record)
    }

    private static func sharedDefaults(_ defaults: UserDefaults?) -> UserDefaults {
        if let defaults {
            return defaults
        }
        if let sharedDefaults = UserDefaults(suiteName: CadenceStoreSupport.appGroupIdentifier) {
            return sharedDefaults
        }
        return .standard
    }
}

extension CadenceWidgetGenerationRecord {
    nonisolated fileprivate var storagePayload: [String: Any] {
        var payload: [String: Any] = [
            "kind": kind,
            "outcome": outcome.rawValue,
            "stages": Dictionary(uniqueKeysWithValues: stageDurations.map { ($0.key.rawValue, $0.value) }),
            "total": totalDuration,
            "rendered": renderedCount,
            "generatedAt": generatedAt.timeIntervalSince1970,
        ]
        if let refusalReason { payload["refusalReason"] = refusalReason }
        if let rowsFetched { payload["rows"] = rowsFetched }
        if let footprintBytes { payload["footprint"] = footprintBytes }
        if let sourceSnapshotAt { payload["sourceSnapshotAt"] = sourceSnapshotAt.timeIntervalSince1970 }
        return payload
    }

    /// Decodes, or refuses. Every guard here is the storage-side half of the initializer's rule:
    /// a payload that has lost its stages, its outcome or its timestamp is not a quiet zero.
    nonisolated fileprivate init?(storagePayload payload: [String: Any]) {
        guard let kind = payload["kind"] as? String,
              let rawOutcome = payload["outcome"] as? String,
              let outcome = CadenceWidgetGenerationOutcome(rawValue: rawOutcome),
              let total = (payload["total"] as? NSNumber)?.doubleValue,
              let rendered = (payload["rendered"] as? NSNumber)?.intValue,
              let generatedAt = (payload["generatedAt"] as? NSNumber)?.doubleValue,
              generatedAt > 0
        else { return nil }

        var stages: [CadenceWidgetStage: TimeInterval] = [:]
        for (rawStage, rawValue) in (payload["stages"] as? [String: Any] ?? [:]) {
            guard let stage = CadenceWidgetStage(rawValue: rawStage),
                  let seconds = (rawValue as? NSNumber)?.doubleValue
            else { return nil }
            stages[stage] = seconds
        }

        let sourceSnapshotAt = (payload["sourceSnapshotAt"] as? NSNumber)?.doubleValue
        self.init(
            kind: kind,
            outcome: outcome,
            refusalReason: payload["refusalReason"] as? String,
            stageDurations: stages,
            totalDuration: total,
            rowsFetched: (payload["rows"] as? NSNumber)?.intValue,
            renderedCount: rendered,
            footprintBytes: (payload["footprint"] as? NSNumber)?.intValue,
            generatedAt: Date(timeIntervalSince1970: generatedAt),
            sourceSnapshotAt: sourceSnapshotAt.map(Date.init(timeIntervalSince1970:))
        )
    }
}

/// The live half: one of these per generation, driven by the provider that owns the catch.
///
/// A reference type so the support types can take it as `probe: CadenceWidgetGenerationProbe? = nil`
/// and stay source-compatible with every existing caller — an `inout` parameter cannot be defaulted,
/// and `WidgetSupportTests` calls all four `snapshot` entry points.
nonisolated final class CadenceWidgetGenerationProbe {
    let kind: String
    private let userDefaults: UserDefaults?
    private let isEnabled: Bool
    private let nanoseconds: () -> UInt64
    private let wallClock: () -> Date
    private let footprint: () -> Int?
    private let started: UInt64
    private var lastMark: UInt64
    private var stageDurations: [CadenceWidgetStage: TimeInterval] = [:]
    private var rowsFetched: Int?

    init(
        kind: String,
        userDefaults: UserDefaults? = nil,
        nanoseconds: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
        wallClock: @escaping () -> Date = Date.init,
        footprint: @escaping () -> Int? = CadenceProcessFootprint.currentBytes
    ) {
        self.kind = kind
        self.userDefaults = userDefaults
        self.isEnabled = CadenceWidgetGenerationLedger.isEnabled(userDefaults: userDefaults)
        self.nanoseconds = nanoseconds
        self.wallClock = wallClock
        self.footprint = footprint
        let now = nanoseconds()
        self.started = now
        self.lastMark = now
    }

    /// Closes `stage` at whatever the clock says now, and opens the next one.
    func finished(_ stage: CadenceWidgetStage, rows: Int? = nil) {
        let now = nanoseconds()
        stageDurations[stage] = Self.seconds(from: lastMark, to: now)
        lastMark = now
        if let rows {
            rowsFetched = (rowsFetched ?? 0) + rows
        }
    }

    /// Records a generation that produced an entry. Returns the record it wrote, or `nil` when the
    /// instrument is off or the reading would have been empty.
    @discardableResult
    func recordGeneration(
        outcome: CadenceWidgetGenerationOutcome,
        renderedCount: Int,
        sourceSnapshotAt: Date?
    ) -> CadenceWidgetGenerationRecord? {
        guard outcome != .refused else { return nil }
        return commit(
            outcome: outcome,
            refusalReason: nil,
            renderedCount: renderedCount,
            sourceSnapshotAt: sourceSnapshotAt
        )
    }

    /// Records a generation that could not run. **Stored apart from an empty result**, and the
    /// reason goes through `CadenceWidgetGenerationLedger.refusalReason(for:)` so it cannot carry
    /// note or task text.
    @discardableResult
    func recordRefusal(_ error: Error) -> CadenceWidgetGenerationRecord? {
        commit(
            outcome: .refused,
            refusalReason: CadenceWidgetGenerationLedger.refusalReason(for: error),
            renderedCount: 0,
            sourceSnapshotAt: nil
        )
    }

    private func commit(
        outcome: CadenceWidgetGenerationOutcome,
        refusalReason: String?,
        renderedCount: Int,
        sourceSnapshotAt: Date?
    ) -> CadenceWidgetGenerationRecord? {
        guard isEnabled else { return nil }
        let record = CadenceWidgetGenerationRecord(
            kind: kind,
            outcome: outcome,
            refusalReason: refusalReason,
            stageDurations: stageDurations,
            totalDuration: Self.seconds(from: started, to: nanoseconds()),
            rowsFetched: rowsFetched,
            renderedCount: renderedCount,
            footprintBytes: footprint(),
            generatedAt: wallClock(),
            sourceSnapshotAt: sourceSnapshotAt
        )
        guard let record else { return nil }
        CadenceWidgetGenerationLedger.record(record, userDefaults: userDefaults)
        return record
    }

    private static func seconds(from start: UInt64, to end: UInt64) -> TimeInterval {
        guard end > start else { return 0 }
        return TimeInterval(end - start) / 1_000_000_000
    }
}

/// This process's physical memory footprint, or nothing.
///
/// **Never `0`.** A zero footprint is not a measurement any live process can produce, so returning
/// one would be the instrument reporting a clean sweep where it had failed to read — the shape
/// every guard in this repository is written against. A kernel that will not answer gets `nil`, and
/// `CadenceWidgetGenerationRecord.footprintBytes` carries the `nil` through to the reader.
nonisolated enum CadenceProcessFootprint {
    nonisolated static func currentBytes() -> Int? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), reboundPointer, &count)
            }
        }
        guard status == KERN_SUCCESS, info.phys_footprint > 0 else { return nil }
        return Int(info.phys_footprint)
    }
}
