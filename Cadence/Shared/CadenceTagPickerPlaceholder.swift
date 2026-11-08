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

    /// **[[T-13321]]: the `.offerDefaultTags` row's words and glyph, drawn by all three pickers** --
    /// the Mac's `TagPickerPlaceholderRow`, the phone's `iOSTaskTagPickerPopover` and its capture
    /// strip. The iOS popover alone drew the offer as bare blue text with no glyph, beside its own
    /// Create and Unarchive rows that draw glyph + label as the Mac's do; no input constraint
    /// answers that difference ([[T-8201]]).
    static let offerDefaultTagsTitle = "Add Default Tags"
    static let offerDefaultTagsSystemImage = "tag.fill"
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

    /// The active tags whose drawn name starts with `query`, or whose slug starts with the query's
    /// slug. An empty query matches every one.
    ///
    /// **The slug half is [[T-13963]].** `#day-job` against an existing `Day Job` matched no drawn
    /// name, so the strip offered `Create “day-job”` -- and the create resolved the slug straight
    /// back to `Day Job`. Now the query's slug finds it, and `canCreateSuggestedTag` declines the
    /// Create. A query with no letter or digit has no slug of its own (`slug(for:)` falls back to
    /// `tag`), so it matches on the drawn name alone.
    static func tagSuggestions(from allTags: [Tag], query: String) -> [Tag] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let querySlug = trimmed.rangeOfCharacter(from: .alphanumerics) == nil ? nil : TagSupport.slug(for: trimmed)
        return activeSuggestionTags(allTags).filter { tag in
            if matchesQuery(suggestionTitle(for: tag), query: query) { return true }
            guard let querySlug else { return false }
            return tag.slug.hasPrefix(querySlug)
        }
    }

    /// Whether the strip offers `Create “query”`: something usable is typed and **no tag in the
    /// store, active or archived, carries its slug** -- `TagSupport.creationDecision`, the rule
    /// every other tag entry point reads.
    ///
    /// **[[T-13963]].** This compared the query against the strip's own drawn matches, which
    /// `activeSuggestionTags` had already stripped of archived tags, and by drawn name rather than
    /// slug. So an archived tag's name offered `Create “work”`, and the create's
    /// `TagSupport.committedTag` resolved the slug to the archived row and attached it, still
    /// archived -- a tag every picker hides. An archived match is offered as Unarchive instead
    /// (`archivedSuggestedTag`); an active one is already among the matches to pick.
    ///
    /// - Parameter allTags: every tag in the store, archived and active.
    static func canCreateSuggestedTag(query: String, allTags: [Tag]) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        return TagSupport.creationDecision(for: trimmed, in: allTags).isCreatable
    }

    /// The archived tag carrying the query's slug, which the strip offers as `Unarchive "<name>"`
    /// in place of a Create -- the same row the Mac tag picker and the phone's tag popover draw for
    /// the same text ([[T-13963]]). `nil` when nothing is typed.
    static func archivedSuggestedTag(query: String, allTags: [Tag]) -> Tag? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return TagSupport.creationDecision(for: trimmed, in: allTags).archivedMatch
    }

    /// What the `#` strip draws in place of rows. `hasActiveTags` is read off the **catalogue**,
    /// not off `matches` — reading the filtered list is how an empty store came to say
    /// `No tag matches “”`.
    static func tagSuggestionPlaceholder(allTags: [Tag], query: String) -> TagPickerPlaceholder {
        let matches = tagSuggestions(from: allTags, query: query)
        return TagPickerPlaceholder.resolve(
            hasActiveTags: !activeSuggestionTags(allTags).isEmpty,
            matchCount: matches.count,
            canCreate: canCreateSuggestedTag(query: query, allTags: allTags),
            canRestore: archivedSuggestedTag(query: query, allTags: allTags) != nil
        )
    }
}
