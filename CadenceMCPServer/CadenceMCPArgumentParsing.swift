import Foundation
import MCP

enum ToolArgumentError: Error, LocalizedError {
    case invalid(String)
    case missing(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message):
            return message
        case .missing(let key):
            return "Missing required argument: \(key)"
        }
    }
}

extension Dictionary where Key == String, Value == MCP.Value {
    func string(_ key: String) -> String? {
        self[key]?.stringValue
    }

    func requiredString(_ key: String) throws -> String {
        guard let value = string(key), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolArgumentError.missing(key)
        }
        return value
    }

    func bool(_ key: String) -> Bool? {
        self[key]?.boolValue
    }

    func int(_ key: String) -> Int? {
        if let intValue = self[key]?.intValue {
            return intValue
        }
        if let doubleValue = self[key]?.doubleValue {
            return Int(doubleValue)
        }
        if let stringValue = self[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           let intValue = Int(stringValue) {
            return intValue
        }
        return nil
    }

    func dateKey(_ key: String) throws -> String? {
        guard let raw = string(key)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if DateFormatters.date(from: raw) != nil { return raw }
        let normalized = raw.lowercased()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let resolved: Date?

        switch normalized {
        case "today":
            resolved = today
        case "tomorrow":
            resolved = calendar.date(byAdding: .day, value: 1, to: today)
        case "yesterday":
            resolved = calendar.date(byAdding: .day, value: -1, to: today)
        default:
            if let match = Self.parseRelativeDay(normalized, calendar: calendar, today: today) {
                resolved = match
            } else {
                resolved = nil
            }
        }

        guard let resolved else {
            throw ToolArgumentError.invalid("Invalid \(key): \(raw). Expected yyyy-MM-dd, today, tomorrow, yesterday, or in N days.")
        }
        return DateFormatters.dateKey(from: resolved)
    }

    func durationMinutes(_ key: String) throws -> Int? {
        guard let value = self[key] else { return nil }
        if let intValue = value.intValue { return intValue }
        if let doubleValue = value.doubleValue { return Int(doubleValue) }
        guard let raw = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let intValue = Int(raw) { return intValue }
        if let parsed = Self.parseDuration(raw) { return parsed }
        throw ToolArgumentError.invalid("Invalid \(key): \(raw). Expected minutes, 30m, 1h, 1.5h, or three hours.")
    }

    func minuteOfDay(_ key: String) throws -> Int? {
        guard let value = self[key] else { return nil }
        if let intValue = value.intValue { return intValue }
        if let doubleValue = value.doubleValue { return Int(doubleValue) }
        guard let raw = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let intValue = Int(raw) { return intValue }
        if let parsed = Self.parseMinuteOfDay(raw) { return parsed }
        throw ToolArgumentError.invalid("Invalid \(key): \(raw). Expected minutes from midnight or a time like 4 PM.")
    }

    func stringArray(_ key: String) -> [String]? {
        guard case .array(let values)? = self[key] else { return nil }
        return values.compactMap(\.stringValue)
    }

    private static func parseRelativeDay(_ value: String, calendar: Calendar, today: Date) -> Date? {
        let patterns = [
            #"^in\s+(\d+)\s+days?$"#,
            #"^\+(\d+)\s+days?$"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
                  let range = Range(match.range(at: 1), in: value),
                  let days = Int(value[range]) else {
                continue
            }
            return calendar.date(byAdding: .day, value: days, to: today)
        }

        guard let regex = try? NSRegularExpression(pattern: #"^(\d+)\s+days?\s+ago$"#),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value),
              let days = Int(value[range]) else {
            return nil
        }
        return calendar.date(byAdding: .day, value: -days, to: today)
    }

    private static func parseDuration(_ value: String) -> Int? {
        let spaced = value
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let compact = spaced.replacingOccurrences(of: " ", with: "")

        if let regex = try? NSRegularExpression(pattern: #"^(\d+)(?:m|min|mins|minute|minutes)$"#),
           let match = regex.firstMatch(in: compact, range: NSRange(compact.startIndex..., in: compact)),
           let range = Range(match.range(at: 1), in: compact),
           let minutes = Int(compact[range]) {
            return minutes
        }

        if let regex = try? NSRegularExpression(pattern: #"^(\d+(?:\.\d+)?)(?:h|hr|hrs|hour|hours)$"#),
           let match = regex.firstMatch(in: compact, range: NSRange(compact.startIndex..., in: compact)),
           let range = Range(match.range(at: 1), in: compact),
           let hours = Double(compact[range]) {
            return Int((hours * 60).rounded())
        }

        if let wordDuration = parseWordDuration(spaced) {
            return wordDuration
        }

        return nil
    }

    private static func parseWordDuration(_ value: String) -> Int? {
        let numberWords: [String: Double] = [
            "a": 1,
            "an": 1,
            "one": 1,
            "two": 2,
            "three": 3,
            "four": 4,
            "five": 5,
            "six": 6,
            "seven": 7,
            "eight": 8,
            "nine": 9,
            "ten": 10,
            "eleven": 11,
            "twelve": 12,
        ]
        let units = #"hours?|hrs?|h|minutes?|mins?|m"#
        let pattern = #"^(a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)(?: and a half)?\s+(\#(units))$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let amountRange = Range(match.range(at: 1), in: value),
              let unitRange = Range(match.range(at: 2), in: value),
              var amount = numberWords[String(value[amountRange])] else {
            return nil
        }

        if value.contains(" and a half") {
            amount += 0.5
        }

        let unit = value[unitRange]
        if unit.hasPrefix("h") {
            return Int((amount * 60).rounded())
        }
        return Int(amount.rounded())
    }

    private static func parseMinuteOfDay(_ value: String) -> Int? {
        let normalized = value
            .lowercased()
            .replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(\d{1,2})(?::(\d{2}))?\s*(am|pm)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
              let hourRange = Range(match.range(at: 1), in: normalized),
              let hour = Int(normalized[hourRange]) else {
            return nil
        }

        let minute: Int
        if let minuteRange = Range(match.range(at: 2), in: normalized) {
            guard let parsedMinute = Int(normalized[minuteRange]) else { return nil }
            minute = parsedMinute
        } else {
            minute = 0
        }

        guard (1...12).contains(hour), (0...59).contains(minute),
              let meridiemRange = Range(match.range(at: 3), in: normalized) else {
            return nil
        }

        let meridiem = normalized[meridiemRange]
        var resolvedHour = hour % 12
        if meridiem == "pm" { resolvedHour += 12 }
        return resolvedHour * 60 + minute
    }
}
