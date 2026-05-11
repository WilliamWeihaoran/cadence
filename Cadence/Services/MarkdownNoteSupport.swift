import Foundation

struct NoteTemplate: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let body: String
}

enum NoteTemplateLibrary {
    static func templates(for kind: NoteKind) -> [NoteTemplate] {
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
        let references = NoteReferenceParser.noteReferences(in: note.content)
        let linkedIDs = Set(references.compactMap(\.noteID))
        let linkedTitles = Set(references.map { $0.fallbackTitle.lowercased() })
        let content = note.content

        return notes.filter { candidate in
            guard candidate.id != note.id, !linkedIDs.contains(candidate.id) else { return false }
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
