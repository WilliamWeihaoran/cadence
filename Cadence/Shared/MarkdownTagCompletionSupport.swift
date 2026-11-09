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

    /// `slug` is the tag's stable identity, not the stored column ([[T-14763]]): a row stored
    /// before [[T-14761]] as `"tag"` under the name `工作` is the `工作` tag, and choosing it must
    /// write `#工作`, which resolves back to it, not `#tag`, which is a different tag.
    static func tag(_ tag: Tag) -> MarkdownTagSuggestion {
        MarkdownTagSuggestion(
            name: tag.name,
            slug: TagSupport.stableSlug(storedSlug: tag.slug, name: tag.name),
            desc: tag.desc,
            colorHex: tag.colorHex,
            isArchived: tag.isArchived
        )
    }

    /// Every tag the picker may offer, one per slug.
    static func suggestions(from tags: [Tag]) -> [MarkdownTagSuggestion] {
        // A tag the inline grammar cannot spell is not offered ([[T-14761]]). Since [[T-14763]]
        // the grammar reads every script, so every slug `TagSupport.slug(for:)` produces is
        // spellable and this is a guard, not a rule: it keeps the picker from ever writing a
        // `#mention` no sweep resolves back, should the slug and the grammar drift apart.
        TagSupport.uniqueBySlug(tags)
            .filter { TagSupport.canBeMentionedInline($0) }
            .map { MarkdownTagSuggestion.tag($0) }
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
            let previous = text.rangeOfComposedCharacterSequence(at: queryStart - 1)
            guard previous.location >= lineRange.location,
                  isTagBody(text.substring(with: previous)) else { break }
            queryStart = previous.location
        }

        let hashLocation = queryStart - 1
        guard hashLocation >= lineRange.location,
              hashLocation < text.length,
              text.character(at: hashLocation) == 35 else { return nil }

        if hashLocation > lineRange.location {
            let beforeHash = text.rangeOfComposedCharacterSequence(at: hashLocation - 1)
            let before = text.substring(with: beforeHash)
            guard before != "#", !isTagBody(before) else { return nil }
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

    /// Whether one composed character can sit in a tag body: letters, marks and digits in any
    /// script, `_` and `-` -- `MarkdownMetadataParser.inlineTagPattern`'s body class ([[T-14763]]).
    /// Walked by composed character, not UTF-16 unit, so a letter outside the BMP (`𠀋`) or a
    /// letter carrying a combining mark (U+0915 U+093E) is one step, never half of one.
    private static func isTagBody(_ character: String) -> Bool {
        guard !character.isEmpty else { return false }
        return character.unicodeScalars.allSatisfy { scalar in
            if scalar == "_" || scalar == "-" { return true }
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                 .nonspacingMark, .spacingMark, .enclosingMark,
                 .decimalNumber, .letterNumber, .otherNumber:
                return true
            default:
                return false
            }
        }
    }
}

enum MarkdownTagPickerChoice: Hashable {
    case existing(MarkdownTagSuggestion)
    case create(String)

    /// The rows a `#query` offers, on the task tag pickers' rule (`TagSupport.pickerQuery`,
    /// [[T-14472]]): the tags whose name or slug contains the query (archived ones only once a
    /// query is typed, restored on choice), at most eight; and a Create row whenever no tag --
    /// active or archived -- carries the query's slug, **beside** partial matches rather than only
    /// when there are none. Empty means the picker should not show at all.
    ///
    /// **The first row is what the typed token already says.** The Mac popover's Return and Tab
    /// apply the highlighted row, which starts at the first (`MarkdownTagPickerController`), so the
    /// first row must never rewrite the token into a different tag: `#work` + Return in a store
    /// holding `homework` wrote `#homework` and swallowed the newline. So a tag whose slug IS the
    /// query's ranks first (promoted before the cap, so it cannot fall past the eighth row), and
    /// with no such tag the Create row leads -- Return writes `#work`, exactly as the task
    /// pickers' field Return resolves the typed name rather than the first partial match. A
    /// completion to a longer tag is one arrow-key away, and is the first row on the iOS strip
    /// after the Create chip.
    static func choices(query rawQuery: String, suggestions: [MarkdownTagSuggestion]) -> [MarkdownTagPickerChoice] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let querySlug = TagSupport.slug(for: query)
        let matching = suggestions.filter { suggestion in
            if query.isEmpty {
                return !suggestion.isArchived
            }
            return suggestion.name.localizedCaseInsensitiveContains(query) ||
                suggestion.slug.localizedCaseInsensitiveContains(querySlug)
        }
        guard !query.isEmpty else {
            return matching.prefix(8).map(MarkdownTagPickerChoice.existing)
        }

        let exact = matching.filter { $0.slug == querySlug }
        let ranked = exact + matching.filter { $0.slug != querySlug }
        var choices = ranked.prefix(8).map(MarkdownTagPickerChoice.existing)
        if let createName = TagSupport.creatableName(for: query, existingSlugs: suggestions.map(\.slug)) {
            choices.insert(.create(createName), at: 0)
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
