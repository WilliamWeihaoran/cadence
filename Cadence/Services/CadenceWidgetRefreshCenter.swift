import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

enum CadenceWidgetRefreshCenter {
    nonisolated static let todayWidgetKind = "CadenceTodayTasksWidget"
    private nonisolated static let reloadTimestampDefaultsKey = "cadence.widgets.today.lastReloadAt"
    private nonisolated static let recentlyCompletedTasksDefaultsKey = "cadence.widgets.today.recentlyCompletedTasks"
    private nonisolated static let completionSuppressionInterval: TimeInterval = 90
    private nonisolated static let defaultReloadInterval: TimeInterval = 15

    nonisolated static func reloadTodayWidgets(
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
        WidgetCenter.shared.reloadTimelines(ofKind: todayWidgetKind)
        #endif
    }

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

    private nonisolated static func sharedDefaults(_ defaults: UserDefaults?) -> UserDefaults {
        if let defaults {
            return defaults
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
}
