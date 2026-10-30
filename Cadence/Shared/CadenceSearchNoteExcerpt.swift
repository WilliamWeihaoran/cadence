import Foundation

/// **The body excerpt under a note's search result row, on both platforms** ([[T-8763]]).
///
/// iOS Search drew this line and Cmd+K did not, so a note found by a word in its text gave the Mac
/// user no sign why it matched. The rule is one call: resolve task embeds to their live titles (the
/// same text the row was matched on), flatten the markdown, cut it at `limit` characters. Both
/// `iOSSearchView.noteResult` and `GlobalSearchIndexSupport.noteResult` read it here, so the two
/// cannot drift apart again by one of them changing the limit or skipping the embed resolution.
///
/// Only the excerpt is shared. The rest of the row — which metadata a task row carries, how the
/// sections are cut — is the owner's call under [[T-8763]] and deliberately not decided here.
enum CadenceSearchNoteExcerpt {
    /// Characters of flattened body text. The row truncates to one line anyway; the cap keeps the
    /// string bounded for long notes.
    static let limit = 120

    static func text(for note: Note, taskTitles: [UUID: String]) -> String {
        CadenceMarkdownPresentationSupport.plainPreviewText(
            from: MarkdownTaskEmbedTitleCache.resolving(note.content, titles: taskTitles),
            limit: limit
        )
    }
}
