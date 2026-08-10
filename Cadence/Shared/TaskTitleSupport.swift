import Foundation

enum TaskTitleSupport {
    static let defaultDisplayTitle = "Untitled Task"
    static let defaultCompactDisplayTitle = "Untitled"

    static func normalized(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isEmpty(_ title: String) -> Bool {
        normalized(title).isEmpty
    }

    static func displayTitle(_ title: String, fallback: String = defaultDisplayTitle) -> String {
        let trimmed = normalized(title)
        return trimmed.isEmpty ? fallback : trimmed
    }

    static func containerShortcut(in title: String) -> TaskTitleInlineShortcut? {
        trailingInlineShortcut(in: title, marker: "~")
    }

    static func tagShortcut(in title: String) -> TaskTitleInlineShortcut? {
        trailingInlineShortcut(in: title, marker: "#")
    }

    static func priorityShortcut(in title: String) -> TaskTitlePriorityShortcut? {
        var cleanedTitle = normalized(title)
        var bangCounts: [Int] = []

        if let leadingCount = leadingBangCount(in: cleanedTitle) {
            bangCounts.append(leadingCount)
            cleanedTitle = normalized(String(cleanedTitle.dropFirst(leadingCount)))
        }

        if let trailingCount = trailingBangCount(in: cleanedTitle) {
            bangCounts.append(trailingCount)
            cleanedTitle = normalized(String(cleanedTitle.dropLast(trailingCount)))
        }

        guard let bangCount = bangCounts.max() else { return nil }
        return TaskTitlePriorityShortcut(
            title: cleanedTitle,
            priority: priority(forBangCount: bangCount)
        )
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
        guard let shortcut = priorityShortcut(in: title) else {
            return normalized(title)
        }
        priority = shortcut.priority
        return shortcut.title
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

    private static func priority(forBangCount count: Int) -> TaskPriority {
        switch count {
        case 1: return .low
        case 2: return .medium
        default: return .high
        }
    }

    private static func leadingBangCount(in title: String) -> Int? {
        let count = title.prefix { $0 == "!" }.count
        return count > 0 ? count : nil
    }

    private static func trailingBangCount(in title: String) -> Int? {
        let count = title.reversed().prefix { $0 == "!" }.count
        return count > 0 ? count : nil
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

struct TaskTitlePriorityShortcut: Equatable {
    let title: String
    let priority: TaskPriority
}

struct TaskTitlePriorityShortcutSegments: Equatable {
    enum Placement: Equatable {
        case leading
        case trailing
    }

    let title: String
    let marker: String
    let priority: TaskPriority
    let placement: Placement
}

struct TaskTitleInlineShortcut: Equatable {
    let prefix: String
    let query: String
}
