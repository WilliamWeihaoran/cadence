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
        // exclusion set is the whole reason the images go, and it must not depend on that. The
        // body is read here for the same reason and one stronger — it is the *candidate set*
        // (T-620), so a stale or emptied read would silently widen or narrow what gets collected.
        let noteID = note.id
        let doomedMarkdown = note.content
        delete(note)
        deleteUnreferencedMarkdownImageAssets(
            referencedByDeletedMarkdown: [doomedMarkdown],
            excludingNoteIDs: [noteID]
        )
    }
}

/// What deleting one note costs, counted before the fact.
///
/// The same job `CadenceListDeletionSummary` does for a list, and the same rule: **it may not
/// over-promise.** A confirmation that claims an image is about to go when another note still
/// references it teaches the user that the numbers on this screen are decorative. So `images`
/// counts the assets that both exist *and* are referenced by no surviving markdown — rather than
/// the image references in the note's own body, which is the number a naive count would produce
/// and is larger.
///
/// **`images` is exactly `deleteUnreferencedMarkdownImageAssets`'s collection restricted to the
/// assets this note references, and it is computed from the same source (T-423).** This comment
/// used to claim the two sets were identical, full stop. Two things were wrong with that. The
/// sweep also collected assets *nobody* references — orphans already in the store — which are not
/// this delete's cost and are deliberately excluded here. **T-620 closed that gap from the other
/// side**: the sweep is now a candidate-set delete restricted to the assets the doomed markdown
/// referenced, which is exactly the restriction below, so the two sets have stopped differing in
/// that direction. This summary is still the narrower statement of the same rule and keeps its own
/// restriction rather than relying on the sweep's. And the claim silently stopped holding
/// even in the restricted sense when T-411 widened "referenced" from `Note.content` to the seven
/// fields in `CadenceMarkdownSourceInventory`, while this summary went on asking the surviving
/// *notes* only: an image also pasted into a task's notes was reported as about to be reclaimed
/// when the sweep would keep it. Both halves now read the store through
/// `CadenceMarkdownSourceInventory.liveMarkdownTexts(in:excludingNoteIDs:)` with the same
/// exclusion set, so widening the field list again moves them together.
/// `CadenceNoteDeletionSurfaceTests.theImageCountMatchesWhatTheSweepActuallyCollects` pins the
/// agreement against the real sweep rather than against a restatement of it.
///
/// The other two counts are on the screen precisely because they are **not** losses. Tags survive,
/// and backlinks are other people's notes, which survive with a link that stops resolving. Saying
/// so is the informative half: a note is a small enough object that "what goes with it" would
/// otherwise read as one line.
struct CadenceNoteDeletionSummary: Equatable, Sendable {
    /// Shown **inside** the still-open confirmation when the delete could not be committed
    /// (T-320). Its second sentence is the one the user needs: the rollback put the note back, so
    /// nothing has been lost while they decide whether to try again.
    static let deleteFailureNotice = "Couldn't delete this note. Nothing was removed."

    /// Shown **before** the delete, when a store read behind the counts failed (T-298).
    ///
    /// It names the direction of the doubt rather than just admitting one, because the doubt is
    /// one-sided: every count a failed fetch can move, it moves *down*. There is no wording of
    /// "something went wrong" that stops a user reading "0 embedded images" as "no images".
    static let unknownImpactNotice =
        "Couldn't check everything this delete touches. It may remove more than the counts below show."

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
    /// The note's folder, normalized and ready to print, or `nil` when it sits at the root.
    ///
    /// **Identity, not a count** — the only field here that is not arithmetic, and it is here
    /// rather than read off the note in the view for two reasons. It keeps the `folderPath` read
    /// beside the normalizer that gives the string meaning (`""`, `"/"` and `"  "` are all the
    /// root, and a raw value can arrive from a merge or from CloudKit), and it makes the line
    /// testable from the macOS-built test target instead of only by a source scan.
    ///
    /// Why show it at all: a note's title and its folder are the only two things distinguishing
    /// one row in a list-notes column from another, and until [[T-223]] every list note on iOS
    /// read "Untitled" — so the confirmation for "delete this one" could name neither. It stays
    /// worth showing after that fix, because two notes in one list may legitimately share a title
    /// while living in different folders, and because notes written before the fix keep their old
    /// title until the next edit. `nil` at the root rather than the word "Notes": "Notes" is the
    /// heading a folder-less run of rows *lacks*, and printing it here would read as a folder the
    /// user never made.
    var folder: String?

    /// True when a store read behind `images` or `backlinks` failed, so those two counts are
    /// floors rather than totals.
    ///
    /// **A failed fetch is not an empty store, and this summary used to say it was.** Both reads
    /// in `forNote(_:in:)` were `(try? …) ?? []`, so a store hiccup produced a confirmation
    /// reading "0 embedded images" and no broken-link line — the smallest possible account of the
    /// delete, presented as fact, on the screen where the user says yes. That is the one direction
    /// a wrong number must not go: `CadenceNoteDeletionSummary`'s standing rule is that it may not
    /// *over*-promise what survives, and collapsing a failure to zero does exactly that.
    ///
    /// The rule is already settled twice in this codebase and is followed rather than re-argued.
    /// `HabitNotificationReconcileSupport.reconcileInput` returns `nil` when either fetch failed
    /// because reconcile reads an empty desired set as "cancel everything", and
    /// `MarkdownTaskEmbedSupport.storeHoldsTask` returns `Bool?` so a failed read keeps the cached
    /// task — a store hiccup is not evidence of a deletion. Same distinction, third site.
    ///
    /// It is a flag beside the counts rather than `Int?` counts because `words`, `tags` and
    /// `folder` are read off the note itself and stay exact. Making all four optional to express
    /// the uncertainty of two would lose that.
    var hasUnknownImpact = false

    /// The unknown-impact sentence, or `nil` when the counts are complete.
    var unknownImpactLine: String? {
        hasUnknownImpact ? Self.unknownImpactNotice : nil
    }

    /// True when there is nothing to lose but the row itself — a note created and never written
    /// in. Published rather than inferred from `lostItemLines.isEmpty` for the reason
    /// `CadenceListDeletionSummary.isEmpty` is: the empty case gets a sentence, not an empty list.
    ///
    /// **Never true while the impact is unknown**, whatever the counts say. "Nothing has been
    /// written in this note yet." is the strongest claim on this screen, and a note with no words
    /// and an unread image table is exactly the case where it would be false and reassuring at the
    /// same time.
    var isEmpty: Bool {
        words == 0 && images == 0 && !hasUnknownImpact
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
        // The `?? []` that used to be on both of these is the whole of T-298. `try?` already
        // erases *why* the read failed; coercing the `nil` as well erases *that* it failed, and
        // what is left is indistinguishable from an empty store.
        let allNotes = try? modelContext.fetch(FetchDescriptor<Note>())
        let assetIDs = (try? modelContext.fetch(FetchDescriptor<MarkdownImageAsset>()))
            .map { Set($0.map(\.id)) }
        // The same call `deleteUnreferencedMarkdownImageAssets` makes, with the same exclusion set
        // — the note is still live here and already gone there, and `excludingNoteIDs` is what
        // makes the two agree anyway. Its `nil` means the same thing as the two above: a fetch
        // failed, so the survivor set is not a survivor set.
        let survivingMarkdown = CadenceMarkdownSourceInventory.liveMarkdownTexts(
            in: modelContext,
            excludingNoteIDs: [note.id]
        )
        return forNote(
            note,
            allNotes: allNotes,
            survivingMarkdownTexts: survivingMarkdown,
            existingImageAssetIDs: assetIDs
        )
    }

    /// The same arithmetic with the store reads hoisted out, so it can be exercised directly.
    ///
    /// **`nil` means the fetch failed; `[]` means the store is empty.** The two produce the same
    /// arithmetic — there is nothing else to compute from — and differ in `hasUnknownImpact`,
    /// which is what the confirmation needs in order to stop presenting a floor as a total. Same
    /// signature shape as `HabitNotificationReconcileSupport.reconcileInput`, for the same reason.
    ///
    /// `allNotes` still answers the backlink question — that one really is about notes. `images`
    /// is answered from `survivingMarkdownTexts`, which is every markdown-bearing field in the
    /// store minus this note's, because that is the set the sweep asks about (T-423).
    static func forNote(
        _ note: Note,
        allNotes: [Note]?,
        survivingMarkdownTexts: [String]?,
        existingImageAssetIDs: Set<UUID>?
    ) -> Self {
        let survivors = (allNotes ?? []).filter { $0.id != note.id }
        let stillReferenced = (survivingMarkdownTexts ?? []).reduce(into: Set<UUID>()) { result, text in
            result.formUnion(MarkdownImageAssetService.referencedIDs(in: text))
        }
        let reclaimed = MarkdownImageAssetService.referencedIDs(in: note.content)
            .intersection(existingImageAssetIDs ?? [])
            .subtracting(stillReferenced)

        var summary = Self()
        // Any failure taints both derived counts, not one each. A missing note table drops the
        // backlink count; a missing markdown read leaves `stillReferenced` empty, which moves
        // `images` in the other direction; a missing asset table empties the intersection. Naming
        // which fetch failed would be a distinction the confirmation has no way to act on. Note
        // that both wrong directions here over-state the *loss*, never the survival — which is the
        // one direction this summary's standing rule forbids.
        summary.hasUnknownImpact =
            allNotes == nil || survivingMarkdownTexts == nil || existingImageAssetIDs == nil
        summary.words = wordCount(note.content)
        summary.images = reclaimed.count
        summary.tags = (note.tags ?? []).count
        summary.folder = CadenceNoteFolderPath.isRoot(note.folderPath)
            ? nil
            : CadenceNoteFolderPath.displayName(for: note.folderPath)
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
