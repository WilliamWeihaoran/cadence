import Foundation

/// The two sentences shown when a context cannot be created or renamed because an active context
/// already carries the same normalized name ([[T-5808]]).
///
/// One copy for both platforms. iOS's context editor had its own pair that called a context a
/// "list" — a different object in this app — while the Mac's create sheet and settings row said
/// "context". The four `duplicateNameNotice` / `duplicateRenameNotice` functions now return these,
/// so the wording cannot drift apart again.
///
/// Both name the context that is in the way, because the clash is on the *normalized* name and the
/// two spellings can differ — "Work" and "work " read as unrelated until the sentence says which
/// row it means.
enum CadenceContextNameClashCopy {
    /// A new context was refused.
    static func notCreated(_ existingName: String) -> String {
        """
        A context named "\(existingName)" already exists. Two contexts with the same name are \
        merged into one the next time Cadence opens, so this one was not created. Pick a different \
        name, or edit the context you already have.
        """
    }

    /// A rename was refused: the context exists, so what did not happen is the rename.
    static func notRenamed(_ existingName: String) -> String {
        """
        A context named "\(existingName)" already exists. Two contexts with the same name are \
        merged into one the next time Cadence opens, so this one was not renamed. Pick a different name.
        """
    }
}
