import Foundation

/// **[[T-12744]] — what a tag picker's field makes of what is typed into it, on both platforms.**
///
/// macOS's `TagPickerPopover` spelled this as three private properties (`filteredTags`,
/// `canCreate`, `archivedQueryMatch`) and iOS's `iOSTaskTagPickerPopover` had none of it: its field
/// only created, so a phone with thirty tags scrolled a fixed panel to find one while the Mac
/// narrowed the list as you typed ([[T-8201]]). Both popovers now ask this one function, so a
/// query reaches the same rows, the same Create row and the same Unarchive row on either device.
///
/// Here rather than in either view because `CadenceTests` runs on macOS and cannot reach
/// `Cadence/iOS/`.
nonisolated struct TagPickerQuery {
    /// The active tags (`TagSupport.pickerChoices`) whose name contains the trimmed query, or whose
    /// slug contains the query's slug. Every choice when nothing is typed.
    let matches: [Tag]
    /// The name a Create row offers, or `nil` when it must not draw: blank, no alphanumeric, or a
    /// tag — active **or archived** — already carries that slug.
    let createName: String?
    /// The archived tag carrying the query's slug, offered as an Unarchive row in place of Create.
    let archivedMatch: Tag?
    /// What the picker draws where its rows would go, resolved from the three above and from the
    /// whole catalogue, never the filtered list (T-532).
    let placeholder: TagPickerPlaceholder

    var canCreate: Bool { createName != nil }
}

extension TagSupport {
    /// The one reading of a tag picker's query. `allTags` is every tag in the store, archived and
    /// active — the choices are derived here, so a caller cannot hand in half the question.
    static func pickerQuery(_ query: String, in allTags: [Tag]) -> TagPickerQuery {
        let choices = pickerChoices(from: allTags)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches: [Tag]
        if trimmed.isEmpty {
            matches = choices
        } else {
            let querySlug = slug(for: trimmed)
            matches = choices.filter {
                $0.name.localizedCaseInsensitiveContains(trimmed) ||
                    $0.slug.localizedCaseInsensitiveContains(querySlug)
            }
        }

        // `creationDecision` puts `archived` before `duplicate`, so a slug carried by both an
        // archived and an active tag still offers the Unarchive row, as the Mac picker always did.
        let decision = creationDecision(for: query, in: allTags)
        let createName: String?
        if case let .creatable(displayName, _) = decision {
            createName = displayName
        } else {
            createName = nil
        }
        let archivedMatch = decision.archivedMatch

        return TagPickerQuery(
            matches: matches,
            createName: createName,
            archivedMatch: archivedMatch,
            placeholder: TagPickerPlaceholder.resolve(
                hasActiveTags: !choices.isEmpty,
                matchCount: matches.count,
                canCreate: createName != nil,
                canRestore: archivedMatch != nil
            )
        )
    }
}
