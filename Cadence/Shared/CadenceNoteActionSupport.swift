import Foundation
import SwiftData
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// The two note-row actions that were macOS-only until T-226: deleting a note, and copying a link
/// to it.
///
/// **Why the delete lives here rather than in each platform's view.** `modelContext.delete(note)`
/// is not the whole operation. A note's body can reference `MarkdownImageAsset` rows, which are a
/// separate model with `.externalStorage` bytes and no relationship to the note at all — nothing
/// cascades to them, so a delete that stops at the note leaks every image that note was the last
/// reader of, permanently and invisibly. macOS got that second step right in both of its two
/// `deleteNote` sites; it got it right by having been written twice, which is the shape that
/// eventually drifts. `ModelContext.deleteNote` is now the one spelling, and the sweep cannot be
/// forgotten by a third caller.
///
/// This is the `CadenceListDeleteHelpers` / `CadenceNoteFolderSupport` arrangement again: the
/// mutation is shared, and each platform supplies only its own confirmation chrome.

// MARK: - Deleting

extension ModelContext {
    /// Deletes one note and reclaims the images only it referenced.
    ///
    /// Deliberately does **not** save. macOS's two call sites rely on autosave and iOS's modifier
    /// saves explicitly, exactly as `iOSListDeletionModifier` does around the list cascades — so
    /// putting a save in here would change macOS's behaviour to buy nothing.
    ///
    /// Nothing detaches `tags`, `area` or `project` by hand: `Tag.notes` declares
    /// `@Relationship(inverse: \Note.tags)` and `Area`/`Project` own the note, so SwiftData
    /// nullifies all three. A tag is a first-class user object and must survive the notes filed
    /// under it — `CadenceNoteActionSupportTests` pins that it does.
    func deleteNote(_ note: Note) {
        // Read before the delete: `id` is readable on a deleted-but-unsaved model, but the sweep's
        // exclusion set is the whole reason the images go, and it must not depend on that.
        let noteID = note.id
        delete(note)
        deleteUnreferencedMarkdownImageAssets(excludingNoteIDs: [noteID])
    }
}

/// What deleting one note costs, counted before the fact.
///
/// The same job `CadenceListDeletionSummary` does for a list, and the same rule: **it may not
/// over-promise.** A confirmation that claims an image is about to go when another note still
/// references it teaches the user that the numbers on this screen are decorative. So `images`
/// counts the assets that both exist *and* are referenced by no surviving note — the exact set
/// `deleteUnreferencedMarkdownImageAssets` will collect — rather than the image references in the
/// note's own body, which is the number a naive count would produce and is larger.
///
/// The other two counts are on the screen precisely because they are **not** losses. Tags survive,
/// and backlinks are other people's notes, which survive with a link that stops resolving. Saying
/// so is the informative half: a note is a small enough object that "what goes with it" would
/// otherwise read as one line.
struct CadenceNoteDeletionSummary: Equatable, Sendable {
    /// Whitespace-separated tokens in the note's body — the typed content that is actually
    /// unrecoverable.
    var words = 0
    /// Image assets this delete will reclaim. See the note above on why this is not a reference
    /// count.
    var images = 0
    /// Tags on the note. **Not** deleted; reported so the confirmation can say so.
    var tags = 0
    /// Other notes whose body links to this one. Not deleted either; their links go dangling.
    var backlinks = 0

    /// True when there is nothing to lose but the row itself — a note created and never written
    /// in. Published rather than inferred from `lostItemLines.isEmpty` for the reason
    /// `CadenceListDeletionSummary.isEmpty` is: the empty case gets a sentence, not an empty list.
    var isEmpty: Bool {
        words == 0 && images == 0
    }

    /// One line per non-zero loss. Zero-count kinds are omitted rather than shown as "0 images".
    var lostItemLines: [String] {
        [
            Self.line(words, "word", "words"),
            Self.line(images, "embedded image", "embedded images")
        ].compactMap { $0 }
    }

    /// What the delete leaves alone, when there is anything to say. `nil` rather than an empty
    /// string so the confirmation can drop the row entirely.
    var retainedLine: String? {
        guard tags > 0 else { return nil }
        return tags == 1
            ? "1 tag stays — deleting a note never deletes a tag."
            : "\(tags) tags stay — deleting a note never deletes a tag."
    }

    /// What this delete breaks elsewhere. macOS's dialog cannot say this; it is the one respect in
    /// which the mobile confirmation is deliberately more informative, the same way the list
    /// confirmation's counts are.
    var brokenLinkLine: String? {
        guard backlinks > 0 else { return nil }
        return backlinks == 1
            ? "1 other note links to this one. That link will stop resolving."
            : "\(backlinks) other notes link to this one. Those links will stop resolving."
    }

    private static func line(_ count: Int, _ singular: String, _ plural: String) -> String? {
        guard count > 0 else { return nil }
        return "\(count) \(count == 1 ? singular : plural)"
    }

    /// The call-site API: counts against the whole store, so `images` matches what the sweep in
    /// `deleteNote` will actually collect.
    static func forNote(_ note: Note, in modelContext: ModelContext) -> Self {
        let allNotes = (try? modelContext.fetch(FetchDescriptor<Note>())) ?? []
        let assetIDs = Set(((try? modelContext.fetch(FetchDescriptor<MarkdownImageAsset>())) ?? []).map(\.id))
        return forNote(note, allNotes: allNotes, existingImageAssetIDs: assetIDs)
    }

    /// The same arithmetic with the store reads hoisted out, so it can be exercised directly.
    static func forNote(_ note: Note, allNotes: [Note], existingImageAssetIDs: Set<UUID>) -> Self {
        let survivors = allNotes.filter { $0.id != note.id }
        let stillReferenced = survivors.reduce(into: Set<UUID>()) { result, other in
            result.formUnion(MarkdownImageAssetService.referencedIDs(in: other.content))
        }
        let reclaimed = MarkdownImageAssetService.referencedIDs(in: note.content)
            .intersection(existingImageAssetIDs)
            .subtracting(stillReferenced)

        var summary = Self()
        summary.words = wordCount(note.content)
        summary.images = reclaimed.count
        summary.tags = (note.tags ?? []).count
        // Through `NoteReferencePanelSupport`, not `NoteReferenceResolver.backlinks` directly, for
        // the reason that file states: the panel support is the *one* entry point resolution goes
        // through, and `CadenceNoteReferencePanelSurfaceTests` pins that the resolver itself has
        // exactly three callers. It resolves the other two directions too, which is why `tasks` is
        // empty — a task reference is not a backlink, and nothing here reads that half. The wrapper
        // also keys on `displayTitle` rather than `title`, which is the better question for a dated
        // note: `[[2026-08-21]]` is a link a user can reasonably have written.
        summary.backlinks = NoteReferencePanelSupport.contents(
            for: note,
            content: note.content,
            notes: survivors,
            tasks: []
        ).backlinks.count
        return summary
    }

    private static func wordCount(_ content: String) -> Int {
        content.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}

// MARK: - Copying a link

/// Putting `[[Note Title]]` on the clipboard.
///
/// One helper for both platforms because the *format* is the part that can drift, and the two
/// pasteboards are the part that genuinely cannot be shared. macOS's `NoteActionSupport` forwards
/// here rather than keeping its own copy, the way it already forwards `appendSummary` to
/// `CadenceAINoteSummary`.
enum CadenceNoteClipboard {
    static func copyMarkdownLink(to note: Note) {
        let markdown = NoteReferenceParser.noteReferenceMarkdown(for: note)
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = markdown
        #endif
    }
}
