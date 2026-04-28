import Foundation

enum CadenceMCPServiceSupport {
    static func normalizedRequiredText(_ value: String, emptyError: Error) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw emptyError }
        return trimmed
    }

    static func validatedOptionalDate(_ dateKey: String?) throws -> String? {
        guard let dateKey else { return nil }
        let trimmed = dateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        _ = try parsedDate(trimmed)
        return trimmed
    }

    static func resolvedDateKey(_ dateKey: String?) throws -> String {
        guard let dateKey else { return DateFormatters.todayKey() }
        let trimmed = dateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return DateFormatters.todayKey() }
        _ = try parsedDate(trimmed)
        return trimmed
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

enum CadenceResolvedContainer {
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
