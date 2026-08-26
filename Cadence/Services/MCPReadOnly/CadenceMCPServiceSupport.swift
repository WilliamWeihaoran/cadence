import Foundation

nonisolated enum CadenceMCPServiceSupport {
    static func normalizedRequiredText(_ value: String, emptyError: Error) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw emptyError }
        return trimmed
    }

    /// The canonical `yyyy-MM-dd` spelling of an externally supplied date, or `invalidDate`.
    ///
    /// **MCP is the only door through which a date enters Cadence from outside**, so it is the only
    /// place a non-canonical key can be written with nobody watching. These three helpers used to
    /// validate by parsing and then return the *raw* text, which let `"2026-8-20"` through as
    /// typed — a key that parses, displays fine, and loses every string comparison it should win
    /// (`"2026-8-20" < "2026-08-25"` is `false`). See `DateFormatters.normalizedDateKey` for what is
    /// normalized versus rejected and why.
    static func normalizedDateKey(_ dateKey: String) throws -> String {
        guard let normalized = DateFormatters.normalizedDateKey(dateKey) else {
            throw CadenceReadError.invalidDate(dateKey)
        }
        return normalized
    }

    static func validatedOptionalDate(_ dateKey: String?) throws -> String? {
        guard let dateKey else { return nil }
        let trimmed = dateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return try normalizedDateKey(trimmed)
    }

    static func resolvedDateKey(_ dateKey: String?) throws -> String {
        guard let dateKey else { return DateFormatters.todayKey() }
        let trimmed = dateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return DateFormatters.todayKey() }
        return try normalizedDateKey(trimmed)
    }

    static func weekKey(for dateKey: String) throws -> String {
        DateFormatters.weekKey(from: try parsedDate(dateKey))
    }

    static func parsedDate(_ dateKey: String) throws -> Date {
        guard let date = DateFormatters.date(from: dateKey) else {
            throw CadenceReadError.invalidDate(dateKey)
        }
        return date
    }

    static func uuid(from id: String) throws -> UUID {
        guard let uuid = UUID(uuidString: id) else {
            throw CadenceReadError.invalidIdentifier(id)
        }
        return uuid
    }

    static func normalizeContainerKind(_ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized == "area" || normalized == "project" else {
            throw CadenceReadError.invalidContainerKind(value)
        }
        return normalized
    }

    static func resolvedContainerFilter(kind: String?, id: String?) throws -> (kind: String, id: UUID)? {
        let normalizedKind = kind?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedID = id?.trimmingCharacters(in: .whitespacesAndNewlines)

        switch (normalizedKind?.isEmpty == false ? normalizedKind : nil, normalizedID?.isEmpty == false ? normalizedID : nil) {
        case (.none, .none):
            return nil
        case (.some(let kind), .some(let id)):
            return (try normalizeContainerKind(kind), try uuid(from: id))
        default:
            throw CadenceReadError.incompleteContainerFilter
        }
    }

    static func cappedLimit(_ limit: Int) -> Int {
        min(max(limit, 0), 200)
    }

    static func excerpt(_ text: String, maxLength: Int = 240) -> String {
        let cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > maxLength else { return cleaned }
        return String(cleaned.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func resolvedTitle(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    static func normalizedSectionName(_ value: String?, container: CadenceResolvedContainer?) -> String {
        let requested = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let container else { return TaskSectionDefaults.defaultName }
        let available = container.sectionNames
        if !requested.isEmpty, let match = available.first(where: { $0.caseInsensitiveCompare(requested) == .orderedSame }) {
            return match
        }
        return available.first ?? TaskSectionDefaults.defaultName
    }

    static func normalizedSubtaskTitles(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func append(_ text: String, separator: String, to content: inout String) {
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            content = text
        } else {
            content += separator + text
        }
    }
}

nonisolated enum CadenceResolvedContainer {
    case area(Area)
    case project(Project)

    var sectionNames: [String] {
        switch self {
        case .area(let area):
            return area.sectionNames
        case .project(let project):
            return project.sectionNames
        }
    }
}
