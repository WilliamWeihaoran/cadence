#if os(macOS)
import Foundation

/// Which notes earn a row in a Notes list column.
///
/// Daily and weekly notes are created for you — opening the tab on a day you never wrote on still
/// makes a row — so an unfiltered column is mostly a list of days that say nothing, and the handful
/// you actually wrote on are buried in it. The list is an index of days *with content*; the current
/// day/week is pinned so there is always a way in to writing today.
///
/// Everything here is a pure function of a note's stored text. Nothing is cached: the column is
/// recomputed from the live `@Query`, so a note appears the moment it gains a character and drops
/// out the moment the last one is deleted.
enum NotesListVisibility {
    /// Does this note hold anything the user put there?
    ///
    /// Measured the same way `NoteEditorPane.isNoteBlank` gates its template chips — against the
    /// **body**, after `MarkdownMetadataParser.splitFrontmatter` — because a plain
    /// `content.isEmpty` test misses the auto-seeded `# Title` body and calls a note that says
    /// nothing "written".
    ///
    /// The one place this parts company with the template-chip rule: a **frontmatter block counts
    /// as content**. Frontmatter is rendered at zero height, so a note that has only been *tagged*
    /// looks blank in the editor but carries `---\ntags: [...]\n---`. Blank-bodied is exactly the
    /// state the template chips exist for, so the editor is right to offer them; the list is not,
    /// because dropping the row is the only handle on those tags and would strand them.
    static func hasContent(_ note: Note) -> Bool {
        hasContent(rawContent: note.content, displayTitle: note.displayTitle)
    }

    static func hasContent(rawContent: String, displayTitle: String) -> Bool {
        let split = MarkdownMetadataParser.splitFrontmatter(in: rawContent)
        if !split.frontmatter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return !isBlankBody(split.body, displayTitle: displayTitle)
    }

    /// A body with nothing in it but whitespace, or nothing but the heading the note was seeded
    /// with. Shared with the "looks empty" row styling so the list cannot dim a row it also lists
    /// as written.
    static func isBlankBody(_ body: String, displayTitle: String) -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "# \(displayTitle)"
    }

    /// The body a row should preview: frontmatter stripped, so a tagged-but-unwritten note reads as
    /// empty rather than previewing its own `---` fence.
    static func previewBody(_ note: Note) -> String {
        MarkdownMetadataParser.splitFrontmatter(in: note.content).body
    }

    /// Filters an already-sorted list, keeping anything `isPinned` claims regardless of content.
    static func listed(_ notes: [Note], pinning isPinned: (Note) -> Bool) -> [Note] {
        notes.filter { isPinned($0) || hasContent($0) }
    }

    /// Daily tab: today is always listed, even blank — it is the way in to writing today's note.
    static func dailyNotes(_ notes: [Note], todayKey: String) -> [Note] {
        listed(notes) { $0.dateKey == todayKey }
    }

    /// Weekly tab: same rule one period up, pinning the current week.
    static func weeklyNotes(_ notes: [Note], currentWeekKey: String) -> [Note] {
        listed(notes) { $0.weekKey == currentWeekKey }
    }
}
#endif
