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

    static func titleBeforeContainerShortcut(in title: String) -> String? {
        trailingInlineShortcut(in: title, marker: "~")?.prefix
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

struct TaskTitleInlineShortcut: Equatable {
    let prefix: String
    let query: String
}
