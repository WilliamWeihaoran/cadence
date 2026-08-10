import Foundation

struct NoteTemplate: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let body: String
}

struct NoteTemplateOverride: Codable, Equatable {
    var title: String
    var subtitle: String
    var body: String
}

enum NoteTemplateLibrary {
    static let storageKey = "noteTemplateOverrides"

    static func templates(for kind: NoteKind, overridesRaw: String? = nil) -> [NoteTemplate] {
        let overrides = overrides(from: overridesRaw ?? UserDefaults.standard.string(forKey: storageKey) ?? "")
        switch kind {
        case .daily:
            return merged([dailyPlan, dailyReview], with: overrides)
        case .weekly:
            return merged([weeklyReview, projectBrief, decisionLog], with: overrides)
        case .meeting:
            return merged([meetingNotes, decisionLog], with: overrides)
        case .permanent, .list:
            return merged([projectBrief, researchNote, decisionLog, checklist], with: overrides)
        }
    }

    static func editableTemplates(overridesRaw: String) -> [NoteTemplate] {
        merged(defaultTemplates, with: overrides(from: overridesRaw))
    }

    static func overrides(from raw: String) -> [String: NoteTemplateOverride] {
        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: NoteTemplateOverride].self, from: data) else {
            return [:]
        }
        return decoded
    }

    static func rawOverrides(from overrides: [String: NoteTemplateOverride]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(overrides),
              let raw = String(data: data, encoding: .utf8) else {
            return ""
        }
        return raw
    }

    static func setOverride(for id: String, title: String, subtitle: String, body: String, in raw: String) -> String {
        var overrides = overrides(from: raw)
        guard let defaultTemplate = defaultTemplates.first(where: { $0.id == id }) else { return raw }
        let normalized = NoteTemplateOverride(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            subtitle: subtitle.trimmingCharacters(in: .whitespacesAndNewlines),
            body: body
        )
        if normalized.title == defaultTemplate.title,
           normalized.subtitle == defaultTemplate.subtitle,
           normalized.body == defaultTemplate.body {
            overrides.removeValue(forKey: id)
        } else {
            overrides[id] = normalized
        }
        return rawOverrides(from: overrides)
    }

    static func resetOverride(for id: String, in raw: String) -> String {
        var overrides = overrides(from: raw)
        overrides.removeValue(forKey: id)
        return rawOverrides(from: overrides)
    }

    static func isCustomized(_ template: NoteTemplate, overridesRaw: String) -> Bool {
        overrides(from: overridesRaw)[template.id] != nil
    }

    static func defaultTemplate(id: String) -> NoteTemplate? {
        defaultTemplates.first { $0.id == id }
    }

    static func noteKinds(containing template: NoteTemplate) -> [NoteKind] {
        NoteKind.allCases.filter { kind in
            defaultTemplates(for: kind).contains { $0.id == template.id }
        }
    }

    private static var defaultTemplates: [NoteTemplate] {
        [dailyPlan, dailyReview, weeklyReview, meetingNotes, projectBrief, researchNote, decisionLog, checklist]
    }

    private static func defaultTemplates(for kind: NoteKind) -> [NoteTemplate] {
        switch kind {
        case .daily:
            return [dailyPlan, dailyReview]
        case .weekly:
            return [weeklyReview, projectBrief, decisionLog]
        case .meeting:
            return [meetingNotes, decisionLog]
        case .permanent, .list:
            return [projectBrief, researchNote, decisionLog, checklist]
        }
    }

    private static func merged(_ templates: [NoteTemplate], with overrides: [String: NoteTemplateOverride]) -> [NoteTemplate] {
        templates.map { template in
            guard let override = overrides[template.id] else { return template }
            return NoteTemplate(
                id: template.id,
                title: override.title.isEmpty ? template.title : override.title,
                subtitle: override.subtitle.isEmpty ? template.subtitle : override.subtitle,
                body: override.body
            )
        }
    }

    private static let dailyPlan = NoteTemplate(
        id: "daily-plan",
        title: "Daily Plan",
        subtitle: "Priorities, schedule, and notes",
        body: """
        ---
        tags: [daily]
        status: active
        ---

        # Daily Plan

        ## Priorities
        ○ 

        ## Schedule Notes

        ## End-of-day Review

        """
    )

    private static let dailyReview = NoteTemplate(
        id: "daily-review",
        title: "Daily Review",
        subtitle: "Wins, friction, next steps",
        body: """
        # Daily Review

        ## Wins

        ## Friction

        ## Carry Forward
        ○ 

        """
    )

    private static let weeklyReview = NoteTemplate(
        id: "weekly-review",
        title: "Weekly Review",
        subtitle: "Outcomes, decisions, and next week",
        body: """
        ---
        tags: [weekly-review]
        status: active
        ---

        # Weekly Review

        ## Outcomes

        ## Decisions

        ## Risks

        ## Next Week
        ○ 

        """
    )

    private static let meetingNotes = NoteTemplate(
        id: "meeting-notes",
        title: "Meeting Notes",
        subtitle: "Agenda, decisions, action items",
        body: """
        # Meeting Notes

        ## Agenda

        ## Notes

        ## Decisions

        ## Action Items
        ○ 

        """
    )

    private static let projectBrief = NoteTemplate(
        id: "project-brief",
        title: "Project Brief",
        subtitle: "Goal, scope, milestones",
        body: """
        ---
        tags: [project]
        status: active
        ---

        # Project Brief

        ## Goal

        ## Scope

        ## Milestones
        | Milestone | Date |
        | --- | --- |
        |  |  |

        ## Open Questions

        """
    )

    private static let researchNote = NoteTemplate(
        id: "research-note",
        title: "Research Note",
        subtitle: "Sources, observations, synthesis",
        body: """
        ---
        tags: [research]
        status: draft
        ---

        # Research Note

        ## Question

        ## Sources

        ## Observations

        ## Synthesis

        """
    )

    private static let decisionLog = NoteTemplate(
        id: "decision-log",
        title: "Decision Log",
        subtitle: "Context, options, decision",
        body: """
        # Decision

        ## Context

        ## Options

        ## Decision

        ## Follow-up
        ○ 

        """
    )

    private static let checklist = NoteTemplate(
        id: "checklist",
        title: "Checklist",
        subtitle: "Simple reusable checklist",
        body: """
        # Checklist

        ○ 
        ○ 
        ○ 

        """
    )
}

extension NoteKind {
    var templateDisplayName: String {
        switch self {
        case .daily:
            return "Daily"
        case .weekly:
            return "Weekly"
        case .permanent:
            return "Permanent"
        case .list:
            return "List"
        case .meeting:
            return "Event"
        }
    }
}

struct MarkdownTableRowStyle: Hashable {
    let lineIndex: Int
    let columnCount: Int
    let isHeader: Bool
    let isDelimiter: Bool
}

enum MarkdownTableParser {
    nonisolated static func rowStyles(in content: String) -> [Int: MarkdownTableRowStyle] {
        let lines = content.components(separatedBy: "\n")
        guard lines.count >= 2 else { return [:] }

        var result: [Int: MarkdownTableRowStyle] = [:]
        var index = 0
        while index < lines.count - 1 {
            guard isTableContentLine(lines[index]),
                  let columnCount = delimiterColumnCount(lines[index + 1]) else {
                index += 1
                continue
            }

            result[index] = MarkdownTableRowStyle(lineIndex: index, columnCount: columnCount, isHeader: true, isDelimiter: false)
            result[index + 1] = MarkdownTableRowStyle(lineIndex: index + 1, columnCount: columnCount, isHeader: false, isDelimiter: true)

            var rowIndex = index + 2
            while rowIndex < lines.count, isTableContentLine(lines[rowIndex]) {
                result[rowIndex] = MarkdownTableRowStyle(lineIndex: rowIndex, columnCount: columnCount, isHeader: false, isDelimiter: false)
                rowIndex += 1
            }
            index = rowIndex
        }

        return result
    }

    nonisolated private static func isTableContentLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return false }
        let cells = trimmed.split(separator: "|", omittingEmptySubsequences: false)
        return cells.count >= 3 && cells.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    nonisolated private static func delimiterColumnCount(_ line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return nil }
        let cells = trimmed.split(separator: "|", omittingEmptySubsequences: false)
        let contentCells = cells.dropFirst(trimmed.hasPrefix("|") ? 1 : 0).dropLast(trimmed.hasSuffix("|") ? 1 : 0)
        guard !contentCells.isEmpty else { return nil }
        let isDelimiter = contentCells.allSatisfy { cell in
            let compact = cell.trimmingCharacters(in: .whitespaces)
            guard compact.count >= 3 else { return false }
            return compact.allSatisfy { $0 == "-" || $0 == ":" }
        }
        return isDelimiter ? contentCells.count : nil
    }
}

enum NoteUnlinkedMentionResolver {
    static func unlinkedMentions(for note: Note, in notes: [Note]) -> [Note] {
        unlinkedMentions(noteID: note.id, content: note.content, in: notes)
    }

    static func unlinkedMentions(noteID: UUID, content: String, in notes: [Note]) -> [Note] {
        let references = NoteReferenceParser.noteReferences(in: content)
        let linkedIDs = Set(references.compactMap(\.noteID))
        let linkedTitles = Set(references.map { $0.fallbackTitle.lowercased() })

        return notes.filter { candidate in
            guard candidate.id != noteID, !linkedIDs.contains(candidate.id) else { return false }
            let title = candidate.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard title.count >= 3, !linkedTitles.contains(title.lowercased()) else { return false }
            return containsLoosePhrase(title, in: content)
        }
    }

    private static func containsLoosePhrase(_ phrase: String, in content: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        let pattern = #"(?i)(?<![\p{L}\p{N}_])"# + escaped + #"(?![\p{L}\p{N}_])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        return regex.firstMatch(in: content, range: NSRange(location: 0, length: (content as NSString).length)) != nil
    }
}
