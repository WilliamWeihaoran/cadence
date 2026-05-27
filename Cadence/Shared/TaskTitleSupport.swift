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
        guard title.hasSuffix("~") else { return nil }
        let prefix = String(title.dropLast())
        return prefix.isEmpty || prefix.hasSuffix(" ") ? prefix : nil
    }
}
