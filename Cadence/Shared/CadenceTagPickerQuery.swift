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

extension TagSupport {
    /// `pickerQuery`'s `createName`, for a catalogue held as slugs rather than `Tag` rows
    /// ([[T-14472]]): the note editor's `#` picker works from `MarkdownTagSuggestion` values, which
    /// keep a tag's slug and archived flag but not the model. The same three clauses as
    /// `creationDecision`'s `.creatable` -- a non-empty display name, a slug no tag (active **or
    /// archived**) carries, and at least one letter or digit -- and
    /// `CadenceTagPickerQueryTests` pins the two answering alike over one store.
    ///
    /// - Parameter existingSlugs: every tag's slug, archived and active.
    nonisolated static func creatableName(for candidate: String, existingSlugs: some Sequence<String>) -> String? {
        let display = displayName(for: candidate)
        guard !display.isEmpty else { return nil }
        let candidateSlug = slug(for: display)
        guard !existingSlugs.contains(candidateSlug) else { return nil }
        guard display.rangeOfCharacter(from: .alphanumerics) != nil else { return nil }
        return display
    }
}

/// **[[T-12772]] — what the iOS popover's field commits on `+`, Return and dismiss.**
///
/// `iOSTaskTagPickerPopover.addTag()` used to hand every non-blank name to
/// `TagSupport.committedTag`, whose slug index holds archived rows too — so typing an archived
/// tag's name attached a chip for a tag every picker hides, still archived, while the list right
/// above offered `Unarchive "<name>"` for the same text. The field now asks the same
/// `pickerQuery` the list does: an archived match is un-archived (keeper decision, [[T-12780]]),
/// not dropped as the Mac's Return drops it, because the dismiss-add ([[T-5175]]) would otherwise
/// throw away what was typed without a word.
nonisolated enum TagPickerFieldCommit {
    /// Blank, or nothing left after `displayName(for:)`: the field does nothing.
    case nothing
    /// The archived tag the Unarchive row names; the popover's `unarchive(_:)` path.
    case unarchive(Tag)
    /// Resolve (pick or mint) this display name through `TagSupport.committedTag`.
    case resolve(name: String)

    /// Whether the field would act at all. The iOS footer `+` is enabled by this, so it goes
    /// disabled exactly when the field would do nothing ([[T-13501]]).
    var commits: Bool {
        if case .nothing = self { return false }
        return true
    }
}

extension TagSupport {
    /// The field's commit for `query`, decided by `creationDecision` -- the decision `pickerQuery`
    /// draws the list from -- so the field and the list above it cannot disagree. `allTags` is
    /// every tag in the store, archived and active.
    ///
    /// **[[T-13501]].** A name `creationDecision` calls `.unusableName` (non-empty but with no
    /// letter or digit, such as `--`, whose slug falls back to `tag`) is `.nothing`: the list draws
    /// `No matching tags` and no Create row for it, and the field used to mint and attach it anyway
    /// on `+`, Return and the dismiss-add. An active tag carrying the slug still resolves to it.
    static func pickerFieldCommit(_ query: String, in allTags: [Tag]) -> TagPickerFieldCommit {
        let name = displayName(for: query)
        guard !name.isEmpty else { return .nothing }
        let decision = creationDecision(for: query, in: allTags)
        if let archived = decision.archivedMatch {
            return .unarchive(archived)
        }
        if case .unusableName = decision {
            return .nothing
        }
        return .resolve(name: name)
    }
}
