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
    private static let defaultReloadInterval: TimeInterval = 15

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
        let cutoff = now.timeIntervalSince1970 - completionSuppressionInterval
        let timestamps = loadRecentlyCompletedTaskTimestamps(userDefaults: userDefaults)
        let filtered = timestamps.filter { $0.value >= cutoff }

        if filtered.count != timestamps.count {
            storeRecentlyCompletedTaskTimestamps(filtered, userDefaults: userDefaults)
        }

        return Set(filtered.keys.compactMap(UUID.init(uuidString:)))
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
            isDoneToday: isDoneToday
        )
        storeRecentlyChangedHabitStates(states, userDefaults: userDefaults)
    }

    static func recentHabitCompletionStates(
        now: Date = Date(),
        userDefaults: UserDefaults? = nil
    ) -> [UUID: Bool] {
        let cutoff = now.timeIntervalSince1970 - completionSuppressionInterval
        let states = loadRecentlyChangedHabitStates(userDefaults: userDefaults)
        let filtered = states.filter { $0.value.timestamp >= cutoff }

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
                        "isDoneToday": value.isDoneToday,
                    ] as [String: Any]
                )
            }
        )
        defaults.set(payload, forKey: recentlyChangedHabitsDefaultsKey)
    }
}
