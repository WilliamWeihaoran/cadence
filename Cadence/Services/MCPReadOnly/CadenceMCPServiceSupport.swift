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

    /// The container's own spelling of a requested section, or `sectionNotFound`.
    ///
    /// **An absent section name and a wrong one are two different requests, and the first-section
    /// fallback is only the right answer to the first.** This used to answer both with
    /// `available.first`, so `Backlogg` for `Backlog` filed the task into whichever column happened
    /// to sort first and `create_task` reported success. A UI can get away with that because the
    /// user watches the row land; MCP is an API whose caller sees only the word "success", so the
    /// redirect is invisible exactly where nobody can catch it.
    ///
    /// Rejecting rather than reporting the redirect back is deliberate: `resolveContainer` already
    /// throws `containerNotFound` for a list id that matches nothing, and a section that matches
    /// nothing is the same class of mistake one level down. A `requestedSectionName` field in the
    /// response would still be a success the caller has to notice, and the caller who mistypes the
    /// name is the same one who will not read the extra field.
    ///
    /// An inbox task has no columns at all, so it accepts no name but `Default` — the name
    /// `AppTask.resolvedSectionName` gives it anyway.
    static func normalizedSectionName(_ value: String?, container: CadenceResolvedContainer?) throws -> String {
        let requested = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let container else {
            guard !requested.isEmpty,
                  requested.caseInsensitiveCompare(TaskSectionDefaults.defaultName) != .orderedSame
            else { return TaskSectionDefaults.defaultName }
            throw CadenceWriteError.sectionNotFound(requested, [])
        }
        let available = container.sectionNames
        guard !requested.isEmpty else { return available.first ?? TaskSectionDefaults.defaultName }
        guard let match = available.first(where: { $0.caseInsensitiveCompare(requested) == .orderedSame }) else {
            throw CadenceWriteError.sectionNotFound(requested, available)
        }
        return match
    }

    /// The tags the caller asked for, or `tagsUnavailable`.
    ///
    /// `TagSupport.resolveTags` answers `nil` — not `[]` — when the tag table could not be read,
    /// and it is `TagSupport.setTags` that turns that `nil` into a bare `return`. In a view the
    /// unchanged chips are on screen; on this path the only reader is an agent, and `update_task`
    /// counts a non-nil `tagNames` as a real requested change, so a tag-only update saved nothing
    /// and audited success. Resolve through here *before* the mutation so a failed read is the
    /// caller's answer instead of a silent no-op.
    static func requiredTags(_ resolved: [Tag]?) throws -> [Tag] {
        guard let resolved else { throw CadenceWriteError.tagsUnavailable }
        return resolved
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
