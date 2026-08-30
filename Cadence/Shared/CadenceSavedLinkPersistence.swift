import Foundation
import SwiftData

/// The two writes a saved-link list makes, with the commit that has to follow them.
///
/// **Why this exists (T-327).** `modelContext.delete(link)` on its own only marks the row deleted
/// in memory; the store is not touched until something saves. macOS's `LinksView` did exactly that
/// — deleted with no explicit save, and inserted with no explicit save either — and relied on
/// SwiftData's autosave to flush eventually. If the app quits or crashes before that flush, the
/// user's delete is simply undone: the link they removed is back on next launch. A delete that
/// restores itself is worse than one that fails loudly, because nothing about it looks like a
/// failure.
///
/// Both operations therefore commit here, and both undo their own pending change when the commit
/// throws, so the view never ends up showing a row state the store does not hold:
/// - a link that could not be inserted is removed again (the shape
///   `CadenceTaskMutationSupport.insertTask` already uses), and
/// - a delete that could not be committed is rolled back, which puts the row back in the list
///   rather than leaving it hidden and undeleted.
///
/// **Neither rule is link-shaped**, which T-319 and T-320 made concrete when two more surfaces
/// needed the same two sentences. Both now live once in `CadencePendingChangePersistence`, generic
/// over `PersistentModel`; what stays here is the part that really is about links — the two
/// notices the macOS list shows.
enum CadenceSavedLinkPersistence {
    /// Shown when the insert could not be committed. The link is gone again by then, so the
    /// sentence is about the save rather than about the row.
    static let saveFailureNotice = "Couldn't save this link."

    /// Shown when the delete could not be committed. The row is back in the list by then.
    static let deleteFailureNotice = "Couldn't delete this link."

    /// Commits a link the caller has just built and configured. Inserting and committing are one
    /// step so that no caller can do the first and forget the second.
    static func insert(_ link: SavedLink, in modelContext: ModelContext) throws {
        modelContext.insert(link)
        try CadencePendingChangePersistence.commitInsert(of: link, in: modelContext)
    }

    /// Deletes a link and commits it. A failed commit rolls the delete back, because the
    /// alternative — leaving the deletion pending and unreported — is the bug this file is here
    /// to remove.
    static func delete(_ link: SavedLink, in modelContext: ModelContext) throws {
        modelContext.delete(link)
        try CadencePendingChangePersistence.commitDelete(in: modelContext)
    }
}

/// What a saved link stores, from what the user typed into the URL field.
///
/// **Why this is shared (T-509).** macOS and iOS each hand-rolled the same three lines — trim,
/// then `hasPrefix("http://") || hasPrefix("https://")`, then prepend `https://` — and both got
/// the same detail wrong, because `hasPrefix` is case-sensitive and a URI scheme is not. A user
/// who pasted `HTTPS://example.com` out of an address bar matched neither prefix, so the "fix"
/// prepended a second scheme and stored `https://HTTPS://example.com`: a string `URL(string:)`
/// still accepts and nothing can open. Two copies, one defect, twice — [[T-374]]'s shape, and the
/// reason the rule now has exactly one declaration.
///
/// What it deliberately does **not** do is re-case the scheme the user typed. `HTTP://example.com`
/// is a valid URL and stays as it is; rewriting it would be a second guess stacked on the first,
/// and the defect here was guessing, not casing.
enum CadenceSavedLinkURL {
    /// The schemes a typed link may already carry. Anything else — including a scheme this list
    /// does not know, like `ftp://` — is treated as scheme-less and gets `https://`, which is what
    /// both platforms already did.
    static let recognisedSchemes = ["http://", "https://"]

    /// The default for a link typed without one. Not `http://`: a link the user did not
    /// scheme should not be downgraded to cleartext on their behalf.
    static let assumedScheme = "https://"

    /// The stored URL for `raw`, or `nil` when the field is empty once trimmed — which is the
    /// `guard !url.isEmpty else { return }` both call sites already wrote, folded in here so the
    /// blank case cannot be spelled two ways either.
    static func normalized(_ raw: String) -> String? {
        let trimmed = CadenceTitleNormalization.normalized(raw)
        guard !trimmed.isEmpty else { return nil }
        guard !hasRecognisedScheme(trimmed) else { return trimmed }
        return assumedScheme + trimmed
    }

    /// `.anchored` is what makes this a prefix test rather than a search; `.caseInsensitive` is the
    /// whole ticket.
    static func hasRecognisedScheme(_ value: String) -> Bool {
        recognisedSchemes.contains { scheme in
            value.range(of: scheme, options: [.caseInsensitive, .anchored]) != nil
        }
    }
}
