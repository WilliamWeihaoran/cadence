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

/// **The fields a note's search row is scored on, in Cmd+K and iOS Search alike** ([[T-18597]]).
///
/// Cmd+K draws and scores a list document's line as `List • Marketing`; iOS Search draws the bare
/// `Marketing` and scored only that, so `list` -- or `list marketing` -- found Marketing's
/// documents on the Mac and none of them on the phone. Every other kind's kind word (`Daily`,
/// `Weekly`, `Notepad`) is scored on both, so the list document's is too: the scored line is the
/// Mac's on both platforms, while each platform keeps drawing its own (`drawnSubtitle`). The order
/// -- title, body, subtitle, tags, storage keys -- is the one both scorers already used.
enum CadenceSearchNoteFields {
    /// `List • <list>`, the line Cmd+K draws for a filed list document.
    static func listDocumentSubtitle(container: String) -> String {
        "List • \(container)"
    }

    /// The subtitle a note is scored on: a filed list document's `List • <list>`, else what the
    /// row draws. A list note filed under no list keeps its drawn line (iOS's `List note`).
    static func scoredSubtitle(for note: Note, drawnSubtitle: String) -> String {
        guard note.kind == .list, let container = NoteReferencePanelSupport.listContainerName(note) else {
            return drawnSubtitle
        }
        return listDocumentSubtitle(container: container)
    }

    static func fields(for note: Note, drawnSubtitle: String, taskTitles: [UUID: String]) -> [String] {
        [
            NoteReferencePanelSupport.searchTitle(note),
            CadenceSearchNoteText.body(of: note, taskTitles: taskTitles),
            scoredSubtitle(for: note, drawnSubtitle: drawnSubtitle),
            CadenceSearchTagSupport.text(for: note.sortedTags),
        ] + NoteReferencePanelSupport.searchKeyFields(note)
    }
}
