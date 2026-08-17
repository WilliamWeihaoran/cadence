import CoreGraphics
import Foundation
import SwiftData

nonisolated struct MarkdownTaskEmbedSubtaskRenderInfo: Hashable {
    let id: UUID
    let title: String
    let isDone: Bool
    let order: Int
}

nonisolated struct MarkdownTaskEmbedRenderInfo: Hashable {
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

nonisolated struct MarkdownTaskEmbedLayoutInfo: Hashable {
    let task: MarkdownTaskEmbedRenderInfo
}

nonisolated enum MarkdownTaskEmbedField: Hashable {
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

nonisolated struct MarkdownTaskEmbedReference: Hashable {
    let id: UUID
    let title: String
    let range: NSRange
}

nonisolated enum MarkdownTaskEmbedParser {
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

    /// `markdown` with every task reference retitled from `titles`, or nil when nothing changed.
    ///
    /// The many-tasks spelling of `replacingReferenceTitles`, and the reason that one has a
    /// production caller at all. A task's title lives both on the task and inside the note's
    /// `[[task:UUID|Title]]` text; renaming it anywhere other than in the note — the task detail
    /// sheet, which is now the *only* way to rename an embed on iOS — writes the task and leaves the
    /// note behind. This is the sweep back: hand it the note and the titles the embeds currently
    /// render with, and every reference to a task in `titles` is brought back into agreement.
    ///
    /// Driven by the references actually present in the text rather than by `titles`, so passing a
    /// whole note's worth of candidate tasks costs one regex per *embedded* task, not per candidate.
    /// A reference to a task that is not in `titles` — deleted, or outside the caller's scope — is
    /// left exactly as it is: its stale title is the only name that reference has left.
    nonisolated static func reconcilingReferenceTitles(
        in markdown: String,
        titles: [UUID: String],
        fallback: String
    ) -> String? {
        var result = markdown
        var reconciled: Set<UUID> = []
        for reference in NoteReferenceParser.taskReferences(in: markdown) {
            guard let id = reference.taskID,
                  reconciled.insert(id).inserted,
                  let title = titles[id],
                  let rewritten = replacingReferenceTitles(
                    of: id,
                    in: result,
                    with: title,
                    fallback: fallback
                  ) else { continue }
            result = rewritten
        }
        return result == markdown ? nil : result
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

/// The read side of `[[task:UUID|Title]]`: the title stored beside the id is a **cache**, and the
/// task is the record.
///
/// The title is written into the note text once, when the embed is created, and every rename that
/// does not happen inside that note leaves the copy stale — a `TaskDetailPopover` opened from a
/// task row, a timeline block, a kanban card or the month grid, an MCP write, or a rename merged in
/// from another device. Reconciling on rename was considered and rejected: it means an unindexed
/// `contains` scan over every `Note` on each title commit, and the inspector's title field is a
/// direct binding with no commit boundary, so it would run per keystroke.
///
/// So nothing sweeps, and instead every reader that puts an embed title in front of a user resolves
/// it here first — export, note-content search, the iOS note-index row excerpts, and the card
/// renderer (which already does it, by looking the id up in its `taskEmbeds` map). The stored string
/// survives only as the name of a task that no longer exists, which is exactly what
/// `MarkdownTaskEmbedRenderInfo.missing(reference:)` already uses it for. Drift then cannot reach
/// the user, and cross-device renames are covered for free because nothing has to be rewritten.
///
/// **Resolution is on the text, not on one renderer's model, and that is what makes it complete.**
/// `[[task:UUID|Title]]` has two spellings — a standalone line, drawn as a card, and an inline
/// reference in a sentence, drawn as a link — and they are rendered by different code
/// (`MarkdownTaskEmbedRenderInfo` against `MarkdownReferenceDisplaySupport`), so a fix applied to
/// either one covers half the cases. Rewriting the string ahead of both covers them together: an
/// excerpt taken through `CadenceMarkdownPresentationSupport.plainPreviewText` reads the live title
/// in its `.taskEmbed` branch *and* in its inline-link runs, from this one call.
nonisolated enum MarkdownTaskEmbedTitleCache {
    /// `markdown` with every embed title replaced by the current title of the task it references.
    ///
    /// A reference whose id is not in `titles` is left exactly as it is: the cached title is the
    /// only name that reference has left. Returns a string either way — the nil-means-unchanged
    /// contract of `MarkdownTaskEmbedParser.reconcilingReferenceTitles` is the right shape for a
    /// writer deciding whether to save, and the wrong one for a reader that needs text regardless.
    nonisolated static func resolving(
        _ markdown: String,
        titles: [UUID: String],
        fallback: String = MarkdownTaskEmbedRenderInfo.untitledTaskTitle
    ) -> String {
        // Cheap gate first: note-content search runs this over every note on every keystroke, and
        // most notes embed nothing at all.
        guard !titles.isEmpty,
              markdown.range(of: "[[task:", options: [.caseInsensitive]) != nil else {
            return markdown
        }
        return MarkdownTaskEmbedParser.reconcilingReferenceTitles(
            in: markdown,
            titles: titles,
            fallback: fallback
        ) ?? markdown
    }

    /// Live titles keyed by task id, for `resolving(_:titles:)`.
    ///
    /// Build this once per query rather than per note — a search pass resolves many notes against
    /// the same task set.
    static func titles(for tasks: [AppTask]) -> [UUID: String] {
        Dictionary(tasks.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
    }

    static func resolving(_ markdown: String, tasks: [AppTask]) -> String {
        resolving(markdown, titles: titles(for: tasks))
    }

    /// The tasks `markdown` embeds, fetched by the ids in its references.
    ///
    /// For callers with no task query in scope — note export is the one — so a one-off read does
    /// not have to observe every task in the store just to name a handful of them.
    static func embeddedTasks(in markdown: String, modelContext: ModelContext) -> [AppTask] {
        let ids = Array(Set(NoteReferenceParser.taskReferences(in: markdown).compactMap(\.taskID)))
        guard !ids.isEmpty else { return [] }
        let descriptor = FetchDescriptor<AppTask>(predicate: #Predicate { ids.contains($0.id) })
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}
