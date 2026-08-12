import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

enum CadenceWidgetRefreshCenter {
    nonisolated static let todayWidgetKind = "CadenceTodayTasksWidget"
    nonisolated static let habitWidgetKind = "CadenceHabitCheckInWidget"
    nonisolated static let milestoneWidgetKind = "CadenceMilestoneMomentumWidget"
    nonisolated static let calendarWidgetKind = "CadenceCalendarSnapshotWidget"
    private nonisolated static let reloadTimestampDefaultsKey = "cadence.widgets.lastReloadAt"
    private nonisolated static let recentlyCompletedTasksDefaultsKey = "cadence.widgets.today.recentlyCompletedTasks"
    private nonisolated static let recentlyChangedHabitsDefaultsKey = "cadence.widgets.habits.recentlyChangedHabits"
    private nonisolated static let completionSuppressionInterval: TimeInterval = 90
    private nonisolated static let defaultReloadInterval: TimeInterval = 15

    nonisolated static func reloadAllWidgets(
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

    // There is no `reloadTodayWidgets`. It existed as a pure forwarder to `reloadAllWidgets` with
    // no production caller, which advertised a per-widget-kind reload this type does not have:
    // every reload path goes through `reloadAllWidgets`.

    nonisolated static func markTaskCompleted(
        _ taskID: UUID,
        now: Date = Date(),
        userDefaults: UserDefaults? = nil
    ) {
        var timestamps = loadRecentlyCompletedTaskTimestamps(userDefaults: userDefaults)
        timestamps[taskID.uuidString] = now.timeIntervalSince1970
        storeRecentlyCompletedTaskTimestamps(timestamps, userDefaults: userDefaults)
    }

    nonisolated static func suppressedTaskIDs(
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

    nonisolated static func markHabitCompletion(
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

    nonisolated static func recentHabitCompletionStates(
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

    nonisolated static func clearStoredState(userDefaults: UserDefaults? = nil) {
        let defaults = sharedDefaults(userDefaults)
        defaults.removeObject(forKey: reloadTimestampDefaultsKey)
        defaults.removeObject(forKey: recentlyCompletedTasksDefaultsKey)
        defaults.removeObject(forKey: recentlyChangedHabitsDefaultsKey)
    }

    private nonisolated static func sharedDefaults(_ defaults: UserDefaults?) -> UserDefaults {
        if let defaults {
            return defaults
        }
        if let sharedDefaults = UserDefaults(suiteName: CadenceStoreSupport.appGroupIdentifier) {
            return sharedDefaults
        }
        return .standard
    }

    private nonisolated static func loadRecentlyCompletedTaskTimestamps(userDefaults: UserDefaults?) -> [String: TimeInterval] {
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

    private nonisolated static func storeRecentlyCompletedTaskTimestamps(
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

    private nonisolated static func loadRecentlyChangedHabitStates(userDefaults: UserDefaults?) -> [String: HabitCompletionState] {
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

    private nonisolated static func storeRecentlyChangedHabitStates(
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
