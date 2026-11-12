import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

nonisolated enum CadenceWidgetRefreshCenter {
    static let todayWidgetKind = "CadenceTodayTasksWidget"
    static let habitWidgetKind = "CadenceHabitCheckInWidget"
    static let milestoneWidgetKind = "CadenceMilestoneMomentumWidget"
    static let calendarWidgetKind = "CadenceCalendarSnapshotWidget"
    private static let reloadTimestampDefaultsKey = "cadence.widgets.lastReloadAt"
    private static let recentlyCompletedTasksDefaultsKey = "cadence.widgets.today.recentlyCompletedTasks"
    private static let recentlyChangedHabitsDefaultsKey = "cadence.widgets.habits.recentlyChangedHabits"
    private static let completionSuppressionInterval: TimeInterval = 90
    static let defaultReloadInterval: TimeInterval = 15

    static func reloadAllWidgets(
        minimumInterval: TimeInterval = defaultReloadInterval,
        force: Bool = false,
        now: Date = Date(),
        userDefaults: UserDefaults? = nil
    ) {
        #if canImport(WidgetKit)
        let defaults = sharedDefaults(userDefaults)
        let timestamp = now.timeIntervalSince1970
        let lastReloadTimestamp = defaults.double(forKey: reloadTimestampDefaultsKey)
        if !force, lastReloadTimestamp > 0, (timestamp - lastReloadTimestamp) < max(minimumInterval, 0) {
            return
        }

        defaults.set(timestamp, forKey: reloadTimestampDefaultsKey)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// When this type last asked WidgetKit to reload, or `nil` if it has not since the stored
    /// state was cleared.
    ///
    /// The throttle above already writes and reads this timestamp; exposing it is what lets a
    /// caller that *must* have forced a reload — the privacy reset, whose whole promise is that
    /// deleted titles stop being drawn — be checked for having done so, rather than for containing
    /// a line of source that says it did.
    static func lastReloadDate(userDefaults: UserDefaults? = nil) -> Date? {
        let timestamp = sharedDefaults(userDefaults).double(forKey: reloadTimestampDefaultsKey)
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    // There is no `reloadTodayWidgets`. It existed as a pure forwarder to `reloadAllWidgets` with
    // no production caller, which advertised a per-widget-kind reload this type does not have:
    // every reload path goes through `reloadAllWidgets`.

    static func markTaskCompleted(
        _ taskID: UUID,
        now: Date = Date(),
        userDefaults: UserDefaults? = nil
    ) {
        var timestamps = loadRecentlyCompletedTaskTimestamps(userDefaults: userDefaults)
        timestamps[taskID.uuidString] = now.timeIntervalSince1970
        storeRecentlyCompletedTaskTimestamps(timestamps, userDefaults: userDefaults)
    }

    static func suppressedTaskIDs(
        now: Date = Date(),
        userDefaults: UserDefaults? = nil
    ) -> Set<UUID> {
        Set(taskCompletionExpirations(now: now, userDefaults: userDefaults).keys)
    }

    static func taskCompletionExpirations(
        now: Date = Date(),
        userDefaults: UserDefaults? = nil
    ) -> [UUID: Date] {
        let cutoff = now.timeIntervalSince1970 - completionSuppressionInterval
        let timestamps = loadRecentlyCompletedTaskTimestamps(userDefaults: userDefaults)
        let filtered = timestamps.filter { $0.value > cutoff }

        if filtered.count != timestamps.count {
            storeRecentlyCompletedTaskTimestamps(filtered, userDefaults: userDefaults)
        }

        return Dictionary(uniqueKeysWithValues: filtered.compactMap { key, timestamp in
            guard let id = UUID(uuidString: key) else { return nil }
            return (id, Date(timeIntervalSince1970: timestamp + completionSuppressionInterval))
        })
    }

    @discardableResult
    static func clearTaskCompletion(_ taskID: UUID, userDefaults: UserDefaults? = nil) -> Bool {
        var timestamps = loadRecentlyCompletedTaskTimestamps(userDefaults: userDefaults)
        guard timestamps.removeValue(forKey: taskID.uuidString) != nil else { return false }
        storeRecentlyCompletedTaskTimestamps(timestamps, userDefaults: userDefaults)
        return true
    }

    static func markHabitCompletion(
        _ habitID: UUID,
        isDoneToday: Bool,
        now: Date = Date(),
        userDefaults: UserDefaults? = nil
    ) {
        var states = loadRecentlyChangedHabitStates(userDefaults: userDefaults)
        states[habitID.uuidString] = HabitCompletionState(
            timestamp: now.timeIntervalSince1970,
            dateKey: CadenceWidgetDateSupport.dateKey(from: now),
            isDoneToday: isDoneToday
        )
        storeRecentlyChangedHabitStates(states, userDefaults: userDefaults)
    }

    static func recentHabitCompletionStates(
        now: Date = Date(),
        dateKey: String? = nil,
        userDefaults: UserDefaults? = nil
    ) -> [UUID: Bool] {
        let cutoff = now.timeIntervalSince1970 - completionSuppressionInterval
        let states = loadRecentlyChangedHabitStates(userDefaults: userDefaults)
        let currentDateKey = dateKey ?? CadenceWidgetDateSupport.dateKey(from: now)
        let filtered = states.filter { $0.value.timestamp >= cutoff && $0.value.dateKey == currentDateKey }

        if filtered.count != states.count {
            storeRecentlyChangedHabitStates(filtered, userDefaults: userDefaults)
        }

        return Dictionary(
            uniqueKeysWithValues: filtered.compactMap { key, value in
                guard let uuid = UUID(uuidString: key) else { return nil }
                return (uuid, value.isDoneToday)
            }
        )
    }

    static func clearStoredState(userDefaults: UserDefaults? = nil) {
        let defaults = sharedDefaults(userDefaults)
        defaults.removeObject(forKey: reloadTimestampDefaultsKey)
        defaults.removeObject(forKey: recentlyCompletedTasksDefaultsKey)
        defaults.removeObject(forKey: recentlyChangedHabitsDefaultsKey)
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

    private static func loadRecentlyCompletedTaskTimestamps(userDefaults: UserDefaults?) -> [String: TimeInterval] {
        let defaults = sharedDefaults(userDefaults)
        guard let raw = defaults.dictionary(forKey: recentlyCompletedTasksDefaultsKey) else { return [:] }

        var timestamps: [String: TimeInterval] = [:]
        for (key, value) in raw {
            if let number = value as? NSNumber {
                timestamps[key] = number.doubleValue
            } else if let timestamp = value as? Double {
                timestamps[key] = timestamp
            }
        }
        return timestamps
    }

    private static func storeRecentlyCompletedTaskTimestamps(
        _ timestamps: [String: TimeInterval],
        userDefaults: UserDefaults?
    ) {
        let defaults = sharedDefaults(userDefaults)
        if timestamps.isEmpty {
            defaults.removeObject(forKey: recentlyCompletedTasksDefaultsKey)
        } else {
            defaults.set(timestamps, forKey: recentlyCompletedTasksDefaultsKey)
        }
    }

    private struct HabitCompletionState {
        let timestamp: TimeInterval
        let dateKey: String
        let isDoneToday: Bool
    }

    private static func loadRecentlyChangedHabitStates(userDefaults: UserDefaults?) -> [String: HabitCompletionState] {
        let defaults = sharedDefaults(userDefaults)
        guard let raw = defaults.dictionary(forKey: recentlyChangedHabitsDefaultsKey) else { return [:] }

        var states: [String: HabitCompletionState] = [:]
        for (key, value) in raw {
            guard let payload = value as? [String: Any] else { continue }

            let timestamp = (payload["timestamp"] as? NSNumber)?.doubleValue
                ?? (payload["timestamp"] as? Double)
            let isDoneToday = (payload["isDoneToday"] as? NSNumber)?.boolValue
                ?? (payload["isDoneToday"] as? Bool)

            if let timestamp, let isDoneToday {
                states[key] = HabitCompletionState(
                    timestamp: timestamp,
                    dateKey: payload["dateKey"] as? String
                        ?? CadenceWidgetDateSupport.dateKey(from: Date(timeIntervalSince1970: timestamp)),
                    isDoneToday: isDoneToday
                )
            }
        }
        return states
    }

    private static func storeRecentlyChangedHabitStates(
        _ states: [String: HabitCompletionState],
        userDefaults: UserDefaults?
    ) {
        let defaults = sharedDefaults(userDefaults)
        if states.isEmpty {
            defaults.removeObject(forKey: recentlyChangedHabitsDefaultsKey)
            return
        }

        let payload = Dictionary(
            uniqueKeysWithValues: states.map { key, value in
                (
                    key,
                    [
                        "timestamp": value.timestamp,
                        "dateKey": value.dateKey,
                        "isDoneToday": value.isDoneToday,
                    ] as [String: Any]
                )
            }
        )
        defaults.set(payload, forKey: recentlyChangedHabitsDefaultsKey)
    }
}

/// **Reloads the widgets after this process saves, at most once per throttle window, and never
/// drops the last change of a burst** ([[T-17311]]).
///
/// The Mac app had no reload on a write. Its one caller was `NotificationReconcileObserver`'s
/// leaving-active arm, and [[T-1176]] measured that macOS reports leaving active on HIDE, not on
/// blur: a window left open beside the desktop's Today widget never fired it. So ticking off the
/// overdue task left the widget reading "1 overdue" until its own timeline came round -- 15
/// minutes for a ready snapshot, 30 for an empty one. That arm assumed a widget cannot be seen
/// while the app is in front, which is iOS's home screen and not the Mac's desktop or
/// Notification Center: the hardware difference that puts this observer on macOS only.
///
/// `reloadAllWidgets`' own throttle drops any call inside its window, which is right for the
/// scene-phase checkpoint and wrong here: completing two tasks ten seconds apart would reload for
/// the first and drop the second, leaving the widget one change behind for the same 15 minutes.
/// So a save inside the window schedules ONE trailing reload at the window's end instead, and
/// further saves before it fires ride on it.
@MainActor
final class CadenceWidgetStoreChangeReloader {
    typealias Schedule = @MainActor (_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> Void

    private let minimumInterval: TimeInterval
    private let now: () -> Date
    private let lastReload: () -> Date?
    private let reload: () -> Void
    private let schedule: Schedule
    /// Whether a trailing reload is already waiting; a save while it waits needs nothing more.
    private(set) var hasPendingReload = false

    init(
        minimumInterval: TimeInterval = CadenceWidgetRefreshCenter.defaultReloadInterval,
        now: @escaping () -> Date = Date.init,
        lastReload: @escaping () -> Date? = { CadenceWidgetRefreshCenter.lastReloadDate() },
        reload: @escaping () -> Void = { CadenceWidgetRefreshCenter.reloadAllWidgets(force: true) },
        schedule: @escaping Schedule = { delay, work in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                work()
            }
        }
    ) {
        self.minimumInterval = minimumInterval
        self.now = now
        self.lastReload = lastReload
        self.reload = reload
        self.schedule = schedule
    }

    /// One store save happened. Reloads now when the last reload is outside the window (or in the
    /// future -- a clock step back must not stall reloads for its whole size), otherwise makes sure
    /// one reload is scheduled for the window's end.
    func storeDidSave() {
        guard !hasPendingReload else { return }
        let current = now()
        guard let last = lastReload() else {
            reload()
            return
        }
        let elapsed = current.timeIntervalSince(last)
        guard elapsed >= 0, elapsed < minimumInterval else {
            reload()
            return
        }
        hasPendingReload = true
        schedule(minimumInterval - elapsed) { [weak self] in
            guard let self else { return }
            self.hasPendingReload = false
            self.reload()
        }
    }
}
