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

/// **The note text a search query is matched against, on every note search** ([[T-16325]]).
///
/// The body only: the frontmatter block is cut off first. Tagging a note through its tag control
/// writes `---` / `tags: ["work"]` / `---` above the text (`TagSupport.setTagsCommittingInsertions`),
/// and the editor, the Notes list and the excerpt all hide that block -- but Cmd+K, iOS Search and
/// a list's Notes-tab field matched the raw `content`, so typing `tags` listed every tagged note
/// with nothing on its row saying why, and a quote mark or a colon in the list field matched them
/// all. A tag is still found by its name and slug through `CadenceSearchTagSupport.text(for:)`,
/// which every one of those searches also scores, so nothing that was findable for a reason the
/// user can see is lost.
///
/// Task embeds are read under the task's live title, as before (`MarkdownTaskEmbedTitleCache`).
enum CadenceSearchNoteText {
    static func body(of note: Note, taskTitles: [UUID: String]) -> String {
        MarkdownTaskEmbedTitleCache.resolving(
            MarkdownMetadataParser.splitFrontmatter(in: note.content).body,
            titles: taskTitles
        )
    }
}
