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
    static let deleteConfirmationTitle = "Delete Link?"

    /// **[[T-9973]]: the add-link form's commit, one label on both platforms.** The Mac's
    /// `AddLinkBar` said "Save" beside Cancel while iOS's `iOSAddLinkForm` said "Save Link" with no
    /// Cancel beside it, so its label has to carry the object; carrying it costs the Mac nothing.
    static let saveActionTitle = "Save Link"

    static func deleteConfirmationMessage(title: String) -> String {
        "This will permanently delete \"\(title)\"."
    }

    /// The confirmation for `link`, naming it as its row does ([[T-17122]]). Both Links tabs passed
    /// `link.title` raw, so a link stored with a blank title -- an import, an MCP write, sync from
    /// an older build, the rows [[T-12793]] taught both rows to draw by their URL -- was confirmed
    /// as `delete ""`, naming nothing, under a row that read as its URL.
    static func deleteConfirmationMessage(for link: SavedLink) -> String {
        deleteConfirmationMessage(title: CadenceTitleNormalization.display(link.title, fallback: link.url))
    }

    /// Shown when the insert could not be committed. The link is gone again by then, so the
    /// sentence is about the save rather than about the row.
    static let saveFailureNotice = "Couldn't save this link."

    /// Shown when the delete could not be committed. The row is back in the list by then.
    static let deleteFailureNotice = "Couldn't delete this link."

    /// Commits a link the caller has just built and configured. Inserting and committing are one
    /// step so that no caller can do the first and forget the second.
    /// The default commit saves normally; injecting a refusal lets tests exercise the undo.
    static func insert(
        _ link: SavedLink,
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        modelContext.insert(link)
        try CadencePendingChangePersistence.commitInsert(of: link, in: modelContext, commit: commit)
    }

    /// Writes an edited title and URL onto a link the store already holds, and commits
    /// ([[T-7259]]). Returns `false` without writing anything when the typed URL is blank, the
    /// same guard the add form's Save already applies.
    ///
    /// The typed values go through the add path's own rules -- `CadenceSavedLinkURL.normalized`
    /// for the URL and the URL as the title's fallback ([[T-509]]) -- so an edited link cannot be
    /// stored in a shape a new one could not. A refused commit puts both fields back, so the row
    /// keeps showing what the store still holds while the form keeps what was typed.
    static func update(
        _ link: SavedLink,
        typedTitle: String,
        typedURL: String,
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> Bool {
        guard let url = CadenceSavedLinkURL.normalized(typedURL) else { return false }
        let title = CadenceTitleNormalization.display(
            CadenceTitleNormalization.normalized(typedTitle),
            fallback: url
        )
        let previousTitle = link.title
        let previousURL = link.url
        link.title = title
        link.url = url
        try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit) {
            link.title = previousTitle
            link.url = previousURL
        }
        return true
    }

    /// The edit form's Save, one rule for both Links tabs ([[T-7259]]): writes `form`'s draft
    /// onto the link it was opened on and returns the notice the tab shows, `nil` for none.
    ///
    /// - A landed edit closes the form, exactly as a landed add does.
    /// - A link gone while the form was open (deleted here, or by sync) closes it too: there is
    ///   nothing to write onto, and quietly inserting a new link instead would resurrect a delete.
    /// - A blank URL writes nothing and keeps the form open; Save is disabled then anyway.
    /// - A refused commit keeps the form open on what was typed and names the refusal.
    static func saveEdit(
        _ form: inout SavedLinkAddForm,
        among links: [SavedLink],
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> String? {
        guard let editingID = form.editingLinkID else { return nil }
        guard let link = links.first(where: { $0.id == editingID }) else {
            form.cancel()
            return nil
        }
        do {
            guard try update(link, typedTitle: form.title, typedURL: form.url, in: modelContext, commit: commit) else {
                return nil
            }
        } catch {
            return saveFailureNotice
        }
        form.cancel()
        return nil
    }

    /// Deletes a link and commits it. A failed commit rolls the delete back, because the
    /// alternative — leaving the deletion pending and unreported — is the bug this file is here
    /// to remove.
    /// The default commit saves normally; injecting a refusal lets tests exercise the rollback.
    static func delete(
        _ link: SavedLink,
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        modelContext.delete(link)
        try CadencePendingChangePersistence.commitDelete(in: modelContext, commit: commit)
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
nonisolated enum CadenceSavedLinkURL {
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

// MARK: - Add Link Form State

/// A Links tab's add form: whether it is open and what has been typed into it — **on both
/// platforms** ([[T-10056]]).
///
/// Closing it is one operation however it is closed — the form's Cancel, the header button, or a
/// successful save — and every one of them discards the draft (T-7256). That was the Mac's alone
/// until [[T-10056]]: iOS's header button read "Cancel" and only hid the form, so tapping
/// "Add Link" again brought back the abandoned title and URL — the exact defect T-7256 fixed on
/// the Mac. Moved here from `LinksView.swift` so both tabs close through the one `cancel()`.
///
/// **It is the edit form too ([[T-7259]]).** A saved link used to be fixable only by deleting and
/// re-adding it, which also sent it to the bottom. `beginEditing` opens this same form prefilled,
/// and `editingLinkID` is what tells the save to write onto that link instead of inserting one.
nonisolated struct SavedLinkAddForm: Equatable {
    var isOpen = false
    var title = ""
    var url = ""
    /// The link being edited, or `nil` while the form adds a new one.
    var editingLinkID: UUID? = nil

    var isEditing: Bool { editingLinkID != nil }

    /// Opens the form on an existing link. A title that is only the URL fallback ([[T-509]]) opens
    /// blank, so a corrected URL becomes the title again rather than leaving the old URL behind as
    /// one; any other title opens as stored.
    mutating func beginEditing(id: UUID, title: String, url: String) {
        isOpen = true
        editingLinkID = id
        self.title = title == url ? "" : title
        self.url = url
    }

    /// The header button's tap. Returns `true` when it closed the form, so the caller clears the
    /// failure notice exactly as the form's own Cancel does.
    @discardableResult
    mutating func toggle() -> Bool {
        if isOpen {
            cancel()
            return true
        }
        isOpen = true
        return false
    }

    /// A link was deleted from the tab ([[T-17124]]). When it is the one the form is editing,
    /// the form closes: left open it went on showing the deleted link's title and URL under an
    /// enabled Save that, by `saveEdit`'s rule for a vanished link, closed it and wrote nothing.
    mutating func linkWasDeleted(id: UUID) {
        guard editingLinkID == id else { return }
        cancel()
    }

    mutating func cancel() {
        isOpen = false
        title = ""
        url = ""
        editingLinkID = nil
    }

    /// The header button's visible word, on both platforms ([[T-7257]]). The Mac header was a
    /// muted "Saved Links" title beside a bare "+", restating the Links tab the reader had just
    /// selected; it now draws iOS's leading labelled button instead, from this one spelling.
    var headerTitle: String { isOpen ? "Cancel" : "Add Link" }
    var headerSymbol: String { isOpen ? "xmark" : "plus" }
    var headerLabel: String {
        guard isOpen else { return "Add link" }
        return isEditing ? "Cancel editing this link" : "Cancel adding a link"
    }
}

// MARK: - Link List

/// The rows a Links tab draws for one list, in the order both tabs draw them ([[T-17123]]).
///
/// Both tabs filtered a `@Query(sort: \SavedLink.order)` and stopped there, so two links holding
/// one `order` -- two devices each adding a link before sync met, an archive import, an MCP write
/// beside an app write -- came back in whatever order the store handed them over, and could swap
/// between renders. `list_links` already broke the tie by title then id
/// (`CadenceMCPOrdering.precedes`); the tabs now read that same total order, so the app and an
/// agent reading the list see one sequence.
enum CadenceSavedLinkList {
    static func links(area: Area?, project: Project?, among allLinks: [SavedLink]) -> [SavedLink] {
        let own: [SavedLink]
        if let area {
            own = allLinks.filter { $0.area?.id == area.id }
        } else if let project {
            own = allLinks.filter { $0.project?.id == project.id }
        } else {
            own = []
        }
        return own.sorted(by: CadenceMCPOrdering.precedes)
    }
}

// MARK: - Link Row Menu

/// The words of a saved link's row menu, for the Mac's right-click and iOS's long-press
/// ([[T-10057]]).
///
/// The Mac row has offered Open Link, Copy Link and Delete since [[T-7258]]; an iOS row offered a
/// tap to open and a swipe to delete, and no way at all to copy a saved URL. A long-press is the
/// touch spelling of the right-click ([[T-8531]], [[T-8201]]), so iOS now carries the same three
/// items in the same order, named once here.
nonisolated enum CadenceSavedLinkRowMenu {
    static let openTitle = "Open Link"
    static let copyTitle = "Copy Link"
    /// [[T-7259]]: opens the Links tab's form on this link, prefilled, on both platforms.
    static let editTitle = "Edit Link"
    static let deleteTitle = "Delete"

    /// Each item's glyph, named once beside its words ([[T-10165]]). iOS's long-press drew these
    /// three from the day it gained the menu; the Mac's right-click drew Open Link and Copy Link
    /// as bare words above a glyphed Delete, so one menu was two vocabularies on one platform and
    /// a second vocabulary across the pair -- pure UI, no input behind it ([[T-8201]]).
    static let openSystemImage = "arrow.up.right"
    static let copySystemImage = "doc.on.doc"
    static let editSystemImage = "pencil"
    static let deleteSystemImage = "trash"
}
