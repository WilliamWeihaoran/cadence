import CoreGraphics
import Foundation

struct MarkdownTaskEmbedSubtaskRenderInfo: Hashable {
    let id: UUID
    let title: String
    let isDone: Bool
    let order: Int
}

struct MarkdownTaskEmbedRenderInfo: Hashable {
    static let untitledTaskTitle = TaskTitleSupport.defaultDisplayTitle
    static let compactCardHeight: CGFloat = 68
    static let subtaskCardHeight: CGFloat = 96
    static let lineHeightPadding: CGFloat = 12
    static let maxCardWidth: CGFloat = 640

    let id: UUID
    let title: String
    let statusRaw: String
    let priorityRaw: String
    let sectionName: String
    let containerName: String
    let containerColorHex: String
    let dueDate: String
    let scheduledDate: String
    let scheduledStartMin: Int
    let estimatedMinutes: Int
    let actualMinutes: Int
    let recurrenceRaw: String
    let isDone: Bool
    let isCancelled: Bool
    let isMissing: Bool
    let subtasks: [MarkdownTaskEmbedSubtaskRenderInfo]

    var subtaskTotalCount: Int {
        subtasks.count
    }

    var completedSubtaskCount: Int {
        subtasks.filter(\.isDone).count
    }

    var visibleSubtasks: [MarkdownTaskEmbedSubtaskRenderInfo] {
        Array(subtasks.prefix(3))
    }

    var hiddenSubtaskCount: Int {
        max(0, subtasks.count - visibleSubtasks.count)
    }

    var hasSubtasks: Bool {
        !subtasks.isEmpty
    }

    var cardHeight: CGFloat {
        hasSubtasks ? Self.subtaskCardHeight : Self.compactCardHeight
    }

    var paragraphLineHeight: CGFloat {
        cardHeight + Self.lineHeightPadding
    }

    static func task(_ task: AppTask) -> MarkdownTaskEmbedRenderInfo {
        let subtaskInfos = (task.subtasks ?? [])
            .sorted {
                if $0.order == $1.order {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.order < $1.order
            }
            .map {
                MarkdownTaskEmbedSubtaskRenderInfo(
                    id: $0.id,
                    title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    isDone: $0.isDone,
                    order: $0.order
                )
            }

        return MarkdownTaskEmbedRenderInfo(
            id: task.id,
            title: TaskTitleSupport.displayTitle(task.title, fallback: untitledTaskTitle),
            statusRaw: task.statusRaw,
            priorityRaw: task.priorityRaw,
            sectionName: task.resolvedSectionName,
            containerName: task.containerName,
            containerColorHex: task.containerColor,
            dueDate: task.dueDate,
            scheduledDate: task.scheduledDate,
            scheduledStartMin: task.scheduledStartMin,
            estimatedMinutes: task.estimatedMinutes,
            actualMinutes: task.actualMinutes,
            recurrenceRaw: task.recurrenceRaw,
            isDone: task.isDone,
            isCancelled: task.isCancelled,
            isMissing: false,
            subtasks: subtaskInfos
        )
    }

    static func missing(reference: MarkdownTaskEmbedReference) -> MarkdownTaskEmbedRenderInfo {
        let title = reference.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return MarkdownTaskEmbedRenderInfo(
            id: reference.id,
            title: title.isEmpty ? "Missing Task" : title,
            statusRaw: TaskStatus.cancelled.rawValue,
            priorityRaw: TaskPriority.none.rawValue,
            sectionName: "",
            containerName: "",
            containerColorHex: TaskSectionDefaults.defaultColorHex,
            dueDate: "",
            scheduledDate: "",
            scheduledStartMin: -1,
            estimatedMinutes: 0,
            actualMinutes: 0,
            recurrenceRaw: TaskRecurrenceRule.none.rawValue,
            isDone: false,
            isCancelled: false,
            isMissing: true,
            subtasks: []
        )
    }
}

struct MarkdownTaskEmbedLayoutInfo: Hashable {
    let task: MarkdownTaskEmbedRenderInfo
}

enum MarkdownTaskEmbedField: Hashable {
    case title
    case status
    case priority
    case container
    case section
    case scheduledDate
    case dueDate
    case estimate
    case recurrence
}

struct MarkdownTaskEmbedReference: Hashable {
    let id: UUID
    let title: String
    let range: NSRange
}

enum MarkdownTaskEmbedParser {
    nonisolated static func draftTitle(in line: String) -> String? {
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        let patterns = [
            #"^\s*\(\s*\)\s+(.+)$"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: line, range: fullRange),
                  match.numberOfRanges > 1,
                  match.range(at: 1).location != NSNotFound else { continue }

            let title = nsLine.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { return title }
        }
        return nil
    }

    /// True for a bare `( )` / `()` draft line — the marker typed, no title yet.
    ///
    /// The companion to `draftTitle`, which needs a title to match. Together they are what Return
    /// consults: `( ) Buy milk` creates a task called "Buy milk", a bare marker creates an untitled
    /// one, and neither is created before Return. The marker used to create an untitled task the
    /// instant its trailing space landed, which is what made the title untypeable — the finished
    /// embed collapses to a fully hidden `[[task:UUID|Title]]` run with a card drawn over it, so
    /// there is nowhere visible to put the caret afterwards. Resolving the title first means it is
    /// typed in plain text at the caret.
    ///
    /// The untitled placeholder itself is deliberately not returned from here: it lives on
    /// `MarkdownTaskEmbedRenderInfo`, which is main-actor isolated, and this parser is `nonisolated`.
    nonisolated static func isUntitledDraftLine(_ line: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"^\s*\(\s*\)\s*$"#) else { return false }
        let nsLine = line as NSString
        return regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) != nil
    }

    nonisolated static func standaloneTaskReference(in line: String, lineStart: Int = 0) -> MarkdownTaskEmbedReference? {
        guard let regex = try? NSRegularExpression(pattern: #"^\s*\[\[task:([0-9A-Fa-f-]{36})\|([^\]\n]+)\]\]\s*$"#) else {
            return nil
        }
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: line, range: fullRange),
              match.numberOfRanges >= 3,
              match.range(at: 1).location != NSNotFound,
              match.range(at: 2).location != NSNotFound,
              let id = UUID(uuidString: nsLine.substring(with: match.range(at: 1))) else {
            return nil
        }

        let title = nsLine.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
        return MarkdownTaskEmbedReference(
            id: id,
            title: title,
            range: NSRange(location: lineStart + match.range.location, length: match.range.length)
        )
    }

    /// What a task title may look like once it is written back into `[[task:UUID|Title]]`.
    ///
    /// `]`, `|` and a newline each end the reference early, so a task renamed to "Read [ch. 3]"
    /// would otherwise turn the embed into a broken half-reference the parser no longer recognises
    /// — the card would vanish and leave raw brackets behind. Substituted rather than stripped, so
    /// the title still reads as what the user typed.
    nonisolated static func sanitizedReferenceTitle(_ title: String, fallback: String) -> String {
        let sanitized = title
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "|", with: "-")
            .replacingOccurrences(of: "[", with: "(")
            .replacingOccurrences(of: "]", with: ")")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? fallback : sanitized
    }

    /// The title runs of every `[[task:UUID|Title]]` reference to one task, in source order.
    ///
    /// Ranges rather than a rewritten string because the macOS editor mutates an `NSTextStorage`
    /// through `shouldChangeText(in:replacementString:)` — it needs the range, not the result — and
    /// iOS replaces through `UITextView.replace(_:withText:)` for the same undo reason. Apply them
    /// back to front; each replacement shifts everything after it.
    nonisolated static func referenceTitleRanges(of id: UUID, in markdown: String) -> [NSRange] {
        let escapedID = NSRegularExpression.escapedPattern(for: id.uuidString)
        guard let regex = try? NSRegularExpression(
            pattern: #"\[\[task:\#(escapedID)\|([^\]\n]+)\]\]"#,
            options: [.caseInsensitive]
        ) else { return [] }

        let nsMarkdown = markdown as NSString
        return regex
            .matches(in: markdown, range: NSRange(location: 0, length: nsMarkdown.length))
            .compactMap { match in
                guard match.numberOfRanges > 1 else { return nil }
                let range = match.range(at: 1)
                return range.location == NSNotFound ? nil : range
            }
    }

    /// `markdown` with every reference to `id` renamed, or nil when nothing changed.
    ///
    /// The whole-string spelling of `referenceTitleRanges`, for callers holding plain text rather
    /// than a text storage. Nil rather than an unchanged copy so a caller can skip the write.
    nonisolated static func replacingReferenceTitles(
        of id: UUID,
        in markdown: String,
        with title: String,
        fallback: String
    ) -> String? {
        let displayTitle = sanitizedReferenceTitle(title, fallback: fallback)
        let nsMarkdown = markdown as NSString
        let result = NSMutableString(string: markdown)
        var didReplace = false
        for range in referenceTitleRanges(of: id, in: markdown).reversed()
        where nsMarkdown.substring(with: range) != displayTitle {
            result.replaceCharacters(in: range, with: displayTitle)
            didReplace = true
        }
        return didReplace ? (result as String) : nil
    }

    nonisolated static func referenceTitleRange(in markdown: String, lineStart: Int = 0) -> NSRange? {
        guard let regex = try? NSRegularExpression(pattern: #"^\s*\[\[task:[0-9A-Fa-f-]{36}\|([^\]\n]+)\]\]\s*$"#) else {
            return nil
        }
        let nsMarkdown = markdown as NSString
        let match = regex.firstMatch(in: markdown, range: NSRange(location: 0, length: nsMarkdown.length))
        guard let match, match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound else {
            return nil
        }
        return NSRange(location: lineStart + match.range(at: 1).location, length: match.range(at: 1).length)
    }

    // There is no legacy-checklist marker helper here any more. `legacyChecklistMarkerRange` and
    // its sibling `isLegacyChecklistMarkerCharacter` both lost their last production caller when
    // `CadenceTextView.legacyChecklistMarkerHit` became `checklistMarkerHit`, which asks
    // `MarkdownChecklistSupport.lineInfo(in:)` for the range *and* the spelling — so legacy
    // glyphs and GitHub `- [x] ` syntax are hit-tested through one path instead of two.
}
