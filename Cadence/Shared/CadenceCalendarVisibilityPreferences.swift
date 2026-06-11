import Foundation

enum CalendarVisibilityPreferences {
    static let hiddenCalendarIDsKey = "calendar.hiddenCalendarIDs.v1"

    static func hiddenCalendarIDs(from rawValue: String = UserDefaults.standard.string(forKey: hiddenCalendarIDsKey) ?? "") -> Set<String> {
        Set(rawValue.split(separator: "\n").map(String.init).filter { !$0.isEmpty })
    }

    static func rawHiddenCalendarIDs(from ids: Set<String>) -> String {
        ids.sorted().joined(separator: "\n")
    }

    static func isHidden(_ calendarID: String, rawValue: String = UserDefaults.standard.string(forKey: hiddenCalendarIDsKey) ?? "") -> Bool {
        hiddenCalendarIDs(from: rawValue).contains(calendarID)
    }

    static func isActive(_ calendarID: String, rawValue: String = UserDefaults.standard.string(forKey: hiddenCalendarIDsKey) ?? "") -> Bool {
        !isHidden(calendarID, rawValue: rawValue)
    }
}
