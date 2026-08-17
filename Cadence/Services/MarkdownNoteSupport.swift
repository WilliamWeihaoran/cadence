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

    /// Whether an override is stored is decided by the template it would actually produce, not by
    /// the raw text typed into the editor.
    ///
    /// An empty title or subtitle falls back to the default in `resolved(_:with:)`, so clearing
    /// either field asks for the default back. Comparing the raw values instead recorded an
    /// override of `""` that read as customized while displaying the original text everywhere —
    /// the blue dot, the "Customized" chip and an enabled "Reset Template" for a template that
    /// looked untouched. An empty *body* is a real edit and keeps its override; `resolved` has no
    /// fallback for it.
    static func setOverride(for id: String, title: String, subtitle: String, body: String, in raw: String) -> String {
        var overrides = overrides(from: raw)
        guard let defaultTemplate = defaultTemplates.first(where: { $0.id == id }) else { return raw }
        let normalized = NoteTemplateOverride(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            subtitle: subtitle.trimmingCharacters(in: .whitespacesAndNewlines),
            body: body
        )
        if resolved(defaultTemplate, with: normalized) == defaultTemplate {
            overrides.removeValue(forKey: id)
        } else {
            overrides[id] = normalized
        }
        return rawOverrides(from: overrides)
    }

    /// The template an override actually produces. `merged(_:with:)` and `setOverride` both go
    /// through this, so "what the user sees" and "does this count as customized" cannot drift.
    static func resolved(_ template: NoteTemplate, with override: NoteTemplateOverride) -> NoteTemplate {
        NoteTemplate(
            id: template.id,
            title: override.title.isEmpty ? template.title : override.title,
            subtitle: override.subtitle.isEmpty ? template.subtitle : override.subtitle,
            body: override.body
        )
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
            return resolved(template, with: override)
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

/// How a table column's cells are aligned, as declared by the colons in its delimiter cell.
///
/// Spelled `leading`/`trailing` rather than left/right because every renderer downstream is
/// SwiftUI or UIKit, and these values are handed straight to one.
enum MarkdownTableAlignment: String, Hashable {
    case leading
    case center
    case trailing
}

struct MarkdownTableRowStyle: Hashable {
    let lineIndex: Int
    let columnCount: Int
    let isHeader: Bool
    let isDelimiter: Bool
    /// One entry per column, always `columnCount` long. Columns the delimiter row did not reach
    /// are `.leading`.
    let alignments: [MarkdownTableAlignment]
}

enum MarkdownTableParser {
    nonisolated static func rowStyles(in content: String) -> [Int: MarkdownTableRowStyle] {
        let lines = MarkdownSourceLines.texts(in: content)
        guard lines.count >= 2 else { return [:] }

        var result: [Int: MarkdownTableRowStyle] = [:]
        var index = 0
        while index < lines.count - 1 {
            guard isTableContentLine(lines[index]),
                  let delimiter = delimiterInfo(lines[index + 1]) else {
                index += 1
                continue
            }

            // **Column count is the wider of the header row and the delimiter row, not the
            // delimiter row alone.**
            //
            // GFM's answer to a mismatch is that the block is not a table at all; Cadence's used to
            // be that the header is truncated to the delimiter's width, which silently deletes a
            // named column from a note the user can see the source of. Neither is right for a live
            // editor — the first makes a table vanish while you are still typing its delimiter row,
            // the second lies about the note's contents. Widening keeps every header cell on screen
            // and shows the missing delimiter as a column with no alignment, which is visible and
            // recoverable.
            let headerCellCount = MarkdownBlockSupport.tableRowCells(in: lines[index]).count
            let columnCount = max(delimiter.columnCount, headerCellCount)
            let alignments = delimiter.alignments
                + Array(repeating: .leading, count: max(0, columnCount - delimiter.alignments.count))

            result[index] = MarkdownTableRowStyle(
                lineIndex: index,
                columnCount: columnCount,
                isHeader: true,
                isDelimiter: false,
                alignments: alignments
            )
            result[index + 1] = MarkdownTableRowStyle(
                lineIndex: index + 1,
                columnCount: columnCount,
                isHeader: false,
                isDelimiter: true,
                alignments: alignments
            )

            var rowIndex = index + 2
            while rowIndex < lines.count, isTableContentLine(lines[rowIndex]) {
                result[rowIndex] = MarkdownTableRowStyle(
                    lineIndex: rowIndex,
                    columnCount: columnCount,
                    isHeader: false,
                    isDelimiter: false,
                    alignments: alignments
                )
                rowIndex += 1
            }
            index = rowIndex
        }

        return result
    }

    /// A row is table content when it holds at least two unescaped `|` and something other than
    /// whitespace between them.
    ///
    /// Two pipes rather than GFM's one, deliberately. This predicate also decides where a table
    /// *ends*, with no second gate behind it — accepting a single pipe would let the first line of
    /// ordinary prose after a table ("Ship it | maybe") be swallowed as a row. The cost is that
    /// the delimiter-less `a | b` spelling of a table is not recognised; the pipe-bounded spelling
    /// is what every Cadence affordance writes.
    nonisolated private static func isTableContentLine(_ line: String) -> Bool {
        let trimmed = MarkdownSourceLines.classificationText(of: line)
        let cells = MarkdownBlockSupport.splitTableRow(trimmed)
        return cells.count >= 3 && cells.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    nonisolated private static func delimiterInfo(_ line: String) -> (columnCount: Int, alignments: [MarkdownTableAlignment])? {
        let cells = MarkdownBlockSupport.tableRowCells(in: line)
        guard !cells.isEmpty else { return nil }

        var alignments: [MarkdownTableAlignment] = []
        for cell in cells {
            guard let alignment = alignment(ofDelimiterCell: cell) else { return nil }
            alignments.append(alignment)
        }
        return (cells.count, alignments)
    }

    /// `---` / `:---` / `---:` / `:---:`, and the one- and two-dash spellings of each.
    ///
    /// The old rule demanded three or more characters, which rejects `|-|-|` and `|:-|` — both
    /// legal GFM, and both what a hand-typed or generator-written table often looks like. The rule
    /// now is GFM's: at least one `-`, nothing but `-` and `:`, and colons only at the ends.
    nonisolated private static func alignment(ofDelimiterCell cell: String) -> MarkdownTableAlignment? {
        let compact = cell.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty, compact.contains("-") else { return nil }

        let leading = compact.hasPrefix(":")
        let trailing = compact.hasSuffix(":")
        let dashes = compact.dropFirst(leading ? 1 : 0).dropLast(trailing && compact.count > 1 ? 1 : 0)
        guard !dashes.isEmpty, dashes.allSatisfy({ $0 == "-" }) else { return nil }

        switch (leading, trailing) {
        case (true, true): return .center
        case (false, true): return .trailing
        default: return .leading
        }
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
