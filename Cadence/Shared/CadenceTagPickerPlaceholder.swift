import Foundation

/// What a tag picker draws **where its rows would go**, when it has no rows to draw.
///
/// Both macOS pickers — `TagPickerPopover` and `TaskTitleInlineTagPicker` — reached one bare
/// `"No tags"` for two unrelated situations, and it was the wrong sentence in each (T-532):
///
/// - **The catalogue is empty.** After [T-528] the default tags are seeded only when someone asks,
///   so a brand-new store's first `#` picker is genuinely empty and the user's only routes to the
///   default set were typing each name or finding Settings > Tags. iOS already answers this in the
///   same place: `iOSTaskTagPickerPopover` offers **Add Default Tags** whenever its catalogue is
///   empty. This is macOS reaching parity with it.
/// - **A query matched nothing.** Here tags exist, so "No tags" was simply false. The house
///   spelling for a list narrowed to nothing is "No matching …" — `GoalsView` and `HabitsView`
///   both draw it.
///
/// Held as a value the pickers *resolve* rather than a condition each spells out, because the
/// bare `"No tags"` was already two copies that had to stay in step and did not.
///
/// **Shared since [[T-9231]].** It lived in `macOS/Views/TagPickerSupportViews.swift`, so the iOS
/// capture sheet's `#` suggestion strip could not ask it and spelled its own condition — keyed off
/// the *filtered* list, the exact mistake this type exists to stop. On a store with no tags, typing
/// `#` drew `No tag matches “”`, quoting an empty query back at the user, where the Mac's title
/// field offers Add Default Tags. The strip now resolves through
/// `CadenceTaskComposerSupport.tagSuggestionPlaceholder(allTags:query:)` below.
nonisolated enum TagPickerPlaceholder: Equatable {
    /// The picker is drawing rows of its own — tags, a create row, or a restore row. Nothing here.
    case none
    /// No unarchived tag exists at all. Offer the default set.
    case offerDefaultTags
    /// Tags exist; this query reaches none of them and offers no other row.
    case noMatches

    /// - Parameters:
    ///   - hasActiveTags: whether the store holds **any** unarchived tag, not whether this query
    ///     found one. That distinction is the whole point: the two callers previously keyed the
    ///     placeholder off the *filtered* list, which cannot tell an empty store from a narrow
    ///     query.
    ///   - matchCount: rows the picker is about to draw for the current query.
    ///   - canCreate: whether a create row is about to be drawn.
    ///   - canRestore: whether a restore row is about to be drawn. `TaskTitleInlineTagPicker` has
    ///     no restore affordance and leaves this at its default; `TagPickerPopover` used to draw
    ///     "Restore \"bug\"" and "No tags" one above the other, which contradicted itself.
    static func resolve(
        hasActiveTags: Bool,
        matchCount: Int,
        canCreate: Bool,
        canRestore: Bool = false
    ) -> TagPickerPlaceholder {
        guard matchCount == 0, !canCreate, !canRestore else { return .none }
        return hasActiveTags ? .noMatches : .offerDefaultTags
    }
}

// MARK: - The iOS capture sheet's `#` strip

/// The decisions behind `iOSTaskComposerMarkerSuggestions`' tag half, here rather than in the view
/// because everything under `Cadence/iOS/` is invisible to `CadenceTests` ([[T-9231]]).
extension CadenceTaskComposerSupport {
    /// The catalogue a `#` strip picks from: unarchived, one tag per slug.
    static func activeSuggestionTags(_ allTags: [Tag]) -> [Tag] {
        TagSupport.uniqueBySlug(allTags.filter { !$0.isArchived })
    }

    /// The name a suggestion chip draws for `tag`, and the one a query is matched against.
    static func suggestionTitle(for tag: Tag) -> String {
        tag.name.isEmpty ? tag.slug : tag.name
    }

    /// The active tags whose drawn name starts with `query`. An empty query matches every one.
    static func tagSuggestions(from allTags: [Tag], query: String) -> [Tag] {
        activeSuggestionTags(allTags).filter { matchesQuery(suggestionTitle(for: $0), query: query) }
    }

    /// Whether the strip offers `Create “query”`: there is something typed, and no drawn
    /// suggestion already carries exactly that name.
    static func canCreateSuggestedTag(query: String, matches: [Tag]) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        return !matches.contains { suggestionTitle(for: $0).caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    /// What the `#` strip draws in place of rows. `hasActiveTags` is read off the **catalogue**,
    /// not off `matches` — reading the filtered list is how an empty store came to say
    /// `No tag matches “”`.
    static func tagSuggestionPlaceholder(allTags: [Tag], query: String) -> TagPickerPlaceholder {
        let matches = tagSuggestions(from: allTags, query: query)
        return TagPickerPlaceholder.resolve(
            hasActiveTags: !activeSuggestionTags(allTags).isEmpty,
            matchCount: matches.count,
            canCreate: canCreateSuggestedTag(query: query, matches: matches)
        )
    }
}
