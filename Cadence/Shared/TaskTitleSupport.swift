import Foundation

nonisolated enum TaskTitleSupport {
    // The labels themselves live in `CadenceTitleNormalization`, in `Models/`, because that is the
    // only place `CadenceMCPServer` can see them — see T-499. What is left here is the app-facing
    // name, which every macOS and iOS call site already reads.
    static let defaultDisplayTitle = CadenceTitleNormalization.defaultTaskTitle
    static let defaultCompactDisplayTitle = CadenceTitleNormalization.defaultCompactTitle

    // The trim rule itself lives in `CadenceTitleNormalization`, shared with event titles and
    // the list/context/habit name forms. Task titles are not a special case of it; they are the
    // same case, plus the shortcut parsing below.
    //
    // The shortcut parsing itself now lives in `TaskTitleShortcutParsing`, in `Models/`, because
    // that is the only place `CadenceWidgets` can see it — see T-354. What is left here is the
    // app-facing name for it, plus the marker/segment helpers only the editors use.

    static func normalized(_ title: String) -> String {
        CadenceTitleNormalization.normalized(title)
    }

    static func isEmpty(_ title: String) -> Bool {
        CadenceTitleNormalization.isBlank(title)
    }

    static func displayTitle(_ title: String, fallback: String = defaultDisplayTitle) -> String {
        CadenceTitleNormalization.display(title, fallback: fallback)
    }

    static func containerShortcut(in title: String) -> TaskTitleInlineShortcut? {
        trailingInlineShortcut(in: title, marker: "~")
    }

    static func tagShortcut(in title: String) -> TaskTitleInlineShortcut? {
        trailingInlineShortcut(in: title, marker: "#")
    }

    /// **[[T-13961]].** Where a `~`/`#` the user sent back to the title with Escape or
    /// backspace-at-empty begins: the title up to and including the marker.
    static func declinedInlineShortcutAnchor(prefix: String, marker: Character) -> String {
        prefix + String(marker)
    }

    /// **[[T-13961]].** Whether `title` still ends in the shortcut token the user declined at
    /// `anchor`, and so must stay literal text rather than reopen its panel.
    ///
    /// Restoring the literal writes `#query` back into the title, and the title field's change
    /// handler read that write as a freshly typed `#` and reopened the panel at once — so Escape
    /// and backspace-at-empty, the two documented ways out, put the user straight back in, and
    /// `Fix #42` could not be typed at all. The token stays declined while the user keeps
    /// typing into it; a space starts a new token, and deleting back past the marker ends it.
    static func isDeclinedInlineShortcut(in title: String, anchor: String?) -> Bool {
        guard let anchor, !anchor.isEmpty, title.hasPrefix(anchor) else { return false }
        return !title.dropFirst(anchor.count).contains(where: \.isWhitespace)
    }

    static func priorityShortcut(in title: String) -> TaskTitlePriorityShortcut? {
        TaskTitleShortcutParsing.priorityShortcut(in: title)
    }

    static func priorityMark(for priority: TaskPriority) -> String {
        switch priority {
        case .none: return "•"
        case .low: return "!"
        case .medium: return "!!"
        case .high: return "!!!"
        }
    }

    static func titleApplyingPriorityShortcut(
        _ title: String,
        priority: inout TaskPriority
    ) -> String {
        TaskTitleShortcutParsing.titleApplyingPriorityShortcut(title, priority: &priority)
    }

    /// The title split the way the field previews it: the mark at each end, and the title between.
    ///
    /// **[[T-16586]].** Both ends are read here exactly as `priorityShortcut` reads them — leading
    /// first, then trailing on what is left — and the title between is `priorityShortcut`'s own
    /// cleaned title. This used to return the leading mark only, so `!! ship it !!!` previewed a
    /// coloured `!!` and then `ship it !!!` as plain text, while the task was created high and
    /// titled `ship it`.
    static func priorityShortcutSegments(in title: String) -> TaskTitlePriorityShortcutSegments? {
        let normalizedTitle = normalized(title)
        guard let shortcut = priorityShortcut(in: normalizedTitle) else { return nil }

        let leadingCount = leadingBangCount(in: normalizedTitle) ?? 0
        let afterLeading = normalized(String(normalizedTitle.dropFirst(leadingCount)))
        let trailingCount = trailingBangCount(in: afterLeading) ?? 0

        return TaskTitlePriorityShortcutSegments(
            leadingMarker: String(repeating: "!", count: leadingCount),
            title: shortcut.title,
            trailingMarker: String(repeating: "!", count: trailingCount),
            priority: shortcut.priority
        )
    }

    private static func leadingBangCount(in title: String) -> Int? {
        TaskTitleShortcutParsing.leadingBangCount(in: title)
    }

    private static func trailingBangCount(in title: String) -> Int? {
        TaskTitleShortcutParsing.trailingBangCount(in: title)
    }

    private static func trailingInlineShortcut(in title: String, marker: Character) -> TaskTitleInlineShortcut? {
        guard !title.isEmpty else { return nil }
        let tokenStart = title.lastIndex(where: { $0.isWhitespace }).map { title.index(after: $0) } ?? title.startIndex
        guard tokenStart < title.endIndex, title[tokenStart] == marker else { return nil }
        let queryStart = title.index(after: tokenStart)
        return TaskTitleInlineShortcut(
            prefix: String(title[..<tokenStart]),
            query: String(title[queryStart...])
        )
    }
}

/// A mark is empty when that end carries none; at least one is not. Both are drawn in `priority`'s
/// colour, the priority the task is created with (the louder mark wins).
nonisolated struct TaskTitlePriorityShortcutSegments: Equatable {
    let leadingMarker: String
    let title: String
    let trailingMarker: String
    let priority: TaskPriority
}

nonisolated struct TaskTitleInlineShortcut: Equatable {
    let prefix: String
    let query: String
}
