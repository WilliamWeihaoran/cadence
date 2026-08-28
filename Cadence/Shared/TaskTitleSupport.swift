import Foundation

nonisolated enum TaskTitleSupport {
    static let defaultDisplayTitle = "Untitled Task"
    static let defaultCompactDisplayTitle = "Untitled"

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

    static func priorityShortcutSegments(in title: String) -> TaskTitlePriorityShortcutSegments? {
        let normalizedTitle = normalized(title)
        guard let shortcut = priorityShortcut(in: normalizedTitle) else { return nil }

        if let leadingCount = leadingBangCount(in: normalizedTitle) {
            return TaskTitlePriorityShortcutSegments(
                title: normalized(String(normalizedTitle.dropFirst(leadingCount))),
                marker: String(repeating: "!", count: leadingCount),
                priority: shortcut.priority,
                placement: .leading
            )
        }

        if let trailingCount = trailingBangCount(in: normalizedTitle) {
            return TaskTitlePriorityShortcutSegments(
                title: normalized(String(normalizedTitle.dropLast(trailingCount))),
                marker: String(repeating: "!", count: trailingCount),
                priority: shortcut.priority,
                placement: .trailing
            )
        }

        return nil
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

nonisolated struct TaskTitlePriorityShortcutSegments: Equatable {
    enum Placement: Equatable {
        case leading
        case trailing
    }

    let title: String
    let marker: String
    let priority: TaskPriority
    let placement: Placement
}

nonisolated struct TaskTitleInlineShortcut: Equatable {
    let prefix: String
    let query: String
}
