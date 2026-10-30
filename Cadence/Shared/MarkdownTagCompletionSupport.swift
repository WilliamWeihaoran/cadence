import Foundation
import SwiftData

// The `#` tag picker's logic, shared by the macOS popover (`MarkdownTagPickerController`) and the
// iOS suggestion strip (`iOSMarkdownTagCompletionStrip`) ([[T-8761]]). Only the presentation
// differs between them -- a caret-anchored popover under a pointer, a strip above the keyboard on
// touch -- so which tags a query offers, when a Create row appears, and what a choice writes all
// live here, once ([[T-8201]]).

struct MarkdownTagSuggestion: Identifiable, Hashable {
    let name: String
    let slug: String
    let desc: String
    let colorHex: String
    let isArchived: Bool

    var id: String { slug }

    static func tag(_ tag: Tag) -> MarkdownTagSuggestion {
        MarkdownTagSuggestion(
            name: tag.name,
            slug: tag.slug,
            desc: tag.desc,
            colorHex: tag.colorHex,
            isArchived: tag.isArchived
        )
    }

    /// Every tag the picker may offer, one per slug.
    static func suggestions(from tags: [Tag]) -> [MarkdownTagSuggestion] {
        TagSupport.uniqueBySlug(tags).map { MarkdownTagSuggestion.tag($0) }
    }
}

struct MarkdownTagCompletionContext {
    let range: NSRange
    let query: String
    let cursorLocation: Int
}

enum MarkdownTagCompletionTokenSupport {
    static func token(in text: NSString, cursor: Int) -> MarkdownTagCompletionContext? {
        let safeCursor = min(max(cursor, 0), text.length)
        let lineRange = text.lineRange(for: NSRange(location: max(0, safeCursor - 1), length: 0))
        guard safeCursor >= lineRange.location else { return nil }

        var queryStart = safeCursor
        while queryStart > lineRange.location {
            let previous = text.character(at: queryStart - 1)
            if isTagBodyCharacter(previous) {
                queryStart -= 1
            } else {
                break
            }
        }

        let hashLocation = queryStart - 1
        guard hashLocation >= lineRange.location,
              hashLocation < text.length,
              text.character(at: hashLocation) == 35 else { return nil }

        if hashLocation > lineRange.location {
            let beforeHash = text.character(at: hashLocation - 1)
            guard beforeHash != 35, !isTagBodyCharacter(beforeHash) else { return nil }
        }

        let queryRange = NSRange(location: hashLocation + 1, length: safeCursor - hashLocation - 1)
        let query = text.substring(with: queryRange)
        guard query.count <= 64 else { return nil }

        return MarkdownTagCompletionContext(
            range: NSRange(location: hashLocation, length: safeCursor - hashLocation),
            query: query,
            cursorLocation: safeCursor
        )
    }

    /// The token under a caret, or nil while a range is selected: a selection is not a `#` being
    /// typed, on either platform.
    static func context(in text: String, selection: NSRange) -> MarkdownTagCompletionContext? {
        guard selection.length == 0 else { return nil }
        let nsText = text as NSString
        let safeCursor = min(max(selection.location, 0), nsText.length)
        return token(in: nsText, cursor: safeCursor)
    }

    /// What choosing a tag writes over the `#query` token.
    static func replacement(for suggestion: MarkdownTagSuggestion) -> String {
        "#\(suggestion.slug)"
    }

    private static func isTagBodyCharacter(_ character: unichar) -> Bool {
        (character >= 48 && character <= 57) ||
        (character >= 65 && character <= 90) ||
        (character >= 97 && character <= 122) ||
        character == 45 ||
        character == 95
    }
}

enum MarkdownTagPickerChoice: Hashable {
    case existing(MarkdownTagSuggestion)
    case create(String)

    /// The rows a `#query` offers: up to eight matching tags (archived ones only once a query is
    /// typed), else one Create row when the query has something to name a tag with. Empty means
    /// the picker should not show at all.
    static func choices(query rawQuery: String, suggestions: [MarkdownTagSuggestion]) -> [MarkdownTagPickerChoice] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let querySlug = TagSupport.slug(for: query)
        let matches = suggestions
            .filter { suggestion in
                if query.isEmpty {
                    return !suggestion.isArchived
                }
                return suggestion.name.localizedCaseInsensitiveContains(query) ||
                    suggestion.slug.localizedCaseInsensitiveContains(querySlug)
            }
            .prefix(8)
            .map(MarkdownTagPickerChoice.existing)

        var choices = Array(matches)
        if choices.isEmpty,
           !query.isEmpty,
           TagSupport.displayName(for: query).rangeOfCharacter(from: .alphanumerics) != nil {
            choices.append(.create(TagSupport.displayName(for: query)))
        }
        return choices
    }

    /// The tag a choice resolves to. An archived tag is restored and a Create row mints one, both
    /// through `create` (which un-archives an existing slug); nil means the store refused it and
    /// nothing should be written into the text.
    func resolve(create: (String) -> MarkdownTagSuggestion?) -> MarkdownTagSuggestion? {
        switch self {
        case .existing(let existing):
            if existing.isArchived, let restored = create(existing.name) {
                return restored
            }
            return existing
        case .create(let name):
            return create(name)
        }
    }
}

enum MarkdownInlineTagCommit {
    /// Finds or mints the tag named `name`, un-archives it, and commits -- what both platforms'
    /// `#` pickers run for a Create row or an archived tag. Nil when the store refused.
    @MainActor
    static func commit(named name: String, in modelContext: ModelContext) -> MarkdownTagSuggestion? {
        guard let tag = TagSupport.committedTag(named: name, in: modelContext) else { return nil }
        let wasArchived = tag.isArchived
        let previousUpdatedAt = tag.updatedAt
        tag.isArchived = false
        tag.updatedAt = Date()
        do {
            try CadencePendingChangePersistence.commitEdit(in: modelContext, undo: {
                tag.isArchived = wasArchived
                tag.updatedAt = previousUpdatedAt
            })
        } catch {
            return nil
        }
        return .tag(tag)
    }
}
