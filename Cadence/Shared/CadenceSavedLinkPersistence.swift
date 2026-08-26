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
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(link)
            throw error
        }
    }

    /// Deletes a link and commits it. A failed commit rolls the delete back, because the
    /// alternative — leaving the deletion pending and unreported — is the bug this file is here
    /// to remove.
    static func delete(_ link: SavedLink, in modelContext: ModelContext) throws {
        modelContext.delete(link)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
