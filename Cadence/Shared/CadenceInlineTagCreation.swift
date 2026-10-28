import Foundation
import SwiftData

/// **`TagSupport`'s app-only commit surface** — creating a tag from an inline picker (T-631),
/// syncing a note's markdown tags (T-651), and seeding the defaults (T-653).
///
/// Separate from `TagSupport.swift` for one reason, and it is a target boundary rather than a
/// taste: that file compiles into `CadenceWidgets` too, and `CadencePendingChangePersistence` does
/// not. A widget draws tags and never makes or seeds one, so the commit belongs on the app side of
/// the line and this is where the line is.
extension TagSupport {

    /// The sentence the **attachment** half of an inline create-and-select may say ([[T-1110]]).
    ///
    /// `iOSTaskTagPickerPopover.addTag` is two commits and not one. The mint goes through
    /// `committedTag` below and is durable the moment it returns — deliberately, since T-631: the
    /// moment the tag exists is the moment the user asked for it. Attaching it to the task is a
    /// *second* commit, through the popover's `onCommit`, and its refusal used to be reported with
    /// `CadencePendingChangePersistence.editFailureNotice`, whose second sentence is "Nothing was
    /// changed". On this path something was: the tag is in the catalogue, and the popover is still
    /// open over a live tag list, so the row is on screen while the notice under it denies it.
    ///
    /// **Both clauses are true whichever branch `committedTag` took.** It returns non-`nil` only
    /// for a tag the store holds — one it minted and committed, or one that already existed — so
    /// "it's in your tag list" is not a guess about provenance. It deliberately does not say the
    /// tag was *created*: `committedTag` does not report that, and a sentence that inferred it
    /// would be the same overclaim in the other direction. The second clause promises exactly what
    /// `iOSTaskTagStrip.commitTags(restoring:)` actually undoes, and nothing wider.
    static let attachmentFailureNotice =
        "Couldn't add this tag to the task. It's in your tag list, but the task's tags weren't changed."

    /// `resolveTags`, **plus the commit for the rows it had to mint** (T-631).
    ///
    /// Every inline "create tag" affordance in the app called `resolveTags` from a view's ambient
    /// `@Environment(\.modelContext)` and committed nothing. The new `Tag` therefore sat *pending*
    /// in the app's single `ModelContext`: cancelling the sheet did not undo it, because no
    /// composer rolls back and `TaskCreationService.createTask` un-inserts `[task] + subtasks` and
    /// not the tag. It landed later, from whatever unrelated screen saved next — which is how a
    /// tag typed into a sheet the user then dismissed turned up in Settings › Tags minutes
    /// afterwards, from another window.
    ///
    /// So the moment the tag exists is now the moment the user asked for it, which is what
    /// `SettingsTagsSection.createTag` and `iOSSettingsTagsSection.createTag` already did for the
    /// same act on the same model.
    ///
    /// **Only the rows this call minted are handed to `commitInsert`.** A refused commit un-inserts
    /// exactly those and leaves the tags that already existed — and any unrelated pending work in
    /// the shared context — alone. `rollback()` is not available here for the reason
    /// `CadencePendingChangePersistence.commitEdit` documents at length.
    ///
    /// **`nil` and `throws` are different answers on purpose.** `nil` is `resolveTags`' own
    /// "the tag table could not be read, so nothing was created"; a throw is "the tag was made and
    /// the store refused it, and it has been taken back out". Both leave the caller with no tag,
    /// and the caller says so rather than selecting a chip for a row that does not exist.
    ///
    /// - Parameter commit: See `CadencePendingChangePersistence.commitInsert(of:in:commit:)`; it is
    ///   forwarded so the undo path stays reachable from a test.
    static func resolveTagsCommittingInsertions(
        named names: [String],
        in context: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> [Tag]? {
        guard let resolution = resolution(named: names, in: context) else { return nil }
        guard !resolution.inserted.isEmpty else { return resolution.tags }
        try CadencePendingChangePersistence.commitInsert(
            of: resolution.inserted,
            in: context,
            commit: commit
        )
        return resolution.tags
    }

    /// The inline pickers' spelling of `resolveTagsCommittingInsertions(named:in:commit:)`: one
    /// name in, one committed `Tag` or `nil` out.
    ///
    /// **Why the throw is turned into a value here and not six times over.** `onCreateTag` is a
    /// non-throwing closure stored on a `View`, so every one of the six surfaces that offers
    /// "create tag" would otherwise write the same `do`/`catch` around the same call — and six
    /// copies of one sentence is how a repo ends up with six answers to one question, which is
    /// what T-631 found when it counted them.
    ///
    /// The two failures it merges are one event to a caller: the tag table could not be read, or
    /// the store refused the insert and it has been taken back out. Either way there is no tag,
    /// nothing is left pending, and the surface must say so rather than draw a chip for a row that
    /// does not exist. What it must *not* do is fall back to `Tag(name:)` — an object the store was
    /// never asked about — which is what four of the six did.
    ///
    /// - Parameter commit: See `CadencePendingChangePersistence.commitInsert(of:in:commit:)`; it is
    ///   forwarded so a test can reach the `nil` a refused commit produces.
    static func committedTag(
        named name: String,
        in context: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Tag? {
        do {
            return try resolveTagsCommittingInsertions(named: [name], in: context, commit: commit)?.first
        } catch {
            return nil
        }
    }

    /// `syncNoteTagsFromMarkdown`, **plus the commit for the rows it had to mint** (T-651).
    ///
    /// The same shape as `committedTag`, one call site over: `CadenceCoreNoteSupport.update` calls
    /// this one frame down, and `resolveTags` mints a `Tag` for a name typed into the note's
    /// frontmatter that no existing row matches. That insert used to ride along inside `update`'s
    /// own swallowed `save()`, so an editor that fails to save the note body — a full disk, a
    /// refused CloudKit write — still left the new tag pending for whatever unrelated screen saves
    /// next, the same T-631 symptom this file exists to close.
    ///
    /// **Only the rows this call minted are committed**, exactly as `resolveTagsCommittingInsertions`
    /// documents; a refused commit un-inserts those and nothing else, and the note's own tag
    /// assignment is left untouched so `update`'s later save still has the field edit to write.
    /// A failure here reads as "did not sync" rather than surfacing on its own — `update` has one
    /// swallowed save for the note body already, and giving the tag sync a second, independent
    /// failure path would ask every one of its nine callers to draw a distinction none of them has
    /// a control to show.
    ///
    /// - Parameter commit: See `CadencePendingChangePersistence.commitInsert(of:in:commit:)`.
    @discardableResult
    static func syncNoteTagsFromMarkdownCommittingInsertions(
        _ note: Note,
        in context: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Bool {
        let tagNames = MarkdownMetadataParser.metadata(in: note.content).tags
        guard let resolution = resolution(named: tagNames, in: context) else { return false }
        guard tagSlugs(note.tags ?? []) != tagSlugs(resolution.tags) else { return false }
        if !resolution.inserted.isEmpty {
            do {
                try CadencePendingChangePersistence.commitInsert(
                    of: resolution.inserted,
                    in: context,
                    commit: commit
                )
            } catch {
                return false
            }
        }
        note.tags = resolution.tags
        note.updatedAt = Date()
        // [[T-7882]]: what the PREVIOUS sync of this note minted and this one dropped is a
        // half-typed `#pro` of `#project`; remove it before recording this sync's own mints.
        removeProvisionalMintsDropped(by: note, keeping: resolution.tags, in: context, commit: commit)
        TagProvisionalMints.shared.record(resolution.inserted, for: note.id)
        return true
    }

    /// **[[T-7882]].** An editor commits a note's body while the user is still typing — iOS after a
    /// 2.5 s pause, macOS after 15 s, either on a focus loss — and the sync above mints a `Tag` for
    /// every inline `#name` in it, so a caret inside `#pro` of `#project` mints `pro`, and the
    /// finished word's commit used to leave that row behind for ever, in every tag picker and in
    /// CloudKit.
    ///
    /// So a tag minted by one sync of a note is provisional until the next sync that CHANGES the
    /// note's tags (one that changes nothing returns above and leaves it provisional). If that
    /// sync no longer names it and nothing else holds it — no other note, no task — and nobody has
    /// recoloured, renamed, described or archived it since, it was a half-word and is deleted.
    /// Anything else keeps it: a tag that already existed was never provisional, a tag that
    /// survives that sync stops being provisional, and the sync after it never looks. The
    /// finished token of any commit, a quit's or a disappear's included, is minted as before.
    ///
    /// The delete is committed with `commitTypedContent`'s rule, not `commitDelete`'s: the context
    /// holds the body being typed, and a rollback would take it. A refusal leaves the delete pending
    /// beside that body, for the editor's next flush.
    private static func removeProvisionalMintsDropped(
        by note: Note,
        keeping tags: [Tag],
        in context: ModelContext,
        commit: (ModelContext) throws -> Void
    ) {
        let kept = Set(tags.map(\.id))
        let orphans = TagProvisionalMints.shared.take(for: note.id).compactMap { mint -> Tag? in
            guard !kept.contains(mint.id) else { return nil }
            let id = mint.id
            guard let tag = try? context.fetch(FetchDescriptor<Tag>(predicate: #Predicate { $0.id == id })).first,
                  mint.matches(tag),
                  (tag.notes ?? []).allSatisfy({ $0.id == note.id }),
                  (tag.tasks ?? []).isEmpty else { return nil }
            return tag
        }
        guard !orphans.isEmpty else { return }
        for tag in orphans { context.delete(tag) }
        CadencePendingChangePersistence.commitTypedContent(in: context, commit: commit)
    }

    /// `TagSupport.setTags(named:on:in:writeFrontmatter:)` for a `Note`, plus the commit for the
    /// rows it had to mint — `NoteEditorPane.noteTagsBinding`'s own door onto the same T-631 shape
    /// (T-762), and the reason it needed a separate function rather than reusing
    /// `syncNoteTagsFromMarkdownCommittingInsertions` above: that one only ever *reads* the tag
    /// names out of the frontmatter it already has; this one is the picker's write path, so it also
    /// has to fold the picked names back into the frontmatter block, the same as `setTags` does.
    ///
    /// **Nothing is written until the mint is safely committed.** `note.tags`, the frontmatter
    /// rewrite and `note.updatedAt` all happen *after* `commitInsert` returns — never before — so a
    /// refusal has nothing to undo: the picker's binding still reads the tags the store actually
    /// holds, and the chip the user tapped simply does not light up. That is the answer T-497 gave
    /// for an in-place field edit, reached here by construction instead of by a rollback that would
    /// have had to fight whatever the user has since typed in `note.content`. It is a materially
    /// different answer to the one `CadencePendingChangePersistence.commitEdit`'s doc argues
    /// `rollback()` is wrong for, because there is no "restore the old value" step at all — only a
    /// "do not take the new one yet" one, and there is nothing under a live caret to lose either
    /// way, since the frontmatter block is never rendered.
    ///
    /// - Parameter commit: See `CadencePendingChangePersistence.commitInsert(of:in:commit:)`.
    @discardableResult
    static func setTagsCommittingInsertions(
        named names: [String],
        on note: Note,
        in context: ModelContext,
        writeFrontmatter: Bool,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Bool {
        let resolvedNames = writeFrontmatter ? names + MarkdownMetadataParser.inlineTagNames(in: note.content) : names
        guard let resolution = resolution(named: resolvedNames, in: context) else { return false }
        if !resolution.inserted.isEmpty {
            do {
                try CadencePendingChangePersistence.commitInsert(
                    of: resolution.inserted,
                    in: context,
                    commit: commit
                )
            } catch {
                return false
            }
        }
        note.tags = resolution.tags
        if writeFrontmatter {
            note.content = MarkdownMetadataParser.content(note.content, replacingFrontmatterTags: names)
        }
        note.updatedAt = Date()
        return true
    }

    /// `seedDefaultTags`, **committed** (T-653).
    ///
    /// `seedDefaultTags(in:saveChanges:)` is handed its `ModelContext`, and its default
    /// `saveChanges: true` was a `try? context.save()` behind a flag — written for a launch-time
    /// caller [[T-528]] removed. What is left calling it with that default are four "Add Defaults"
    /// buttons, each pressed by a person watching the screen for the empty state to fill in, so a
    /// refused commit here is not a launch quietly repeating the seed; it is a control the user
    /// just pressed, reporting done over a store that said no.
    ///
    /// **A cascade, not an insert-only commit.** `seedDefaultTags` runs `deduplicateTags` first,
    /// which both deletes a duplicate into its canonical and can reorder an existing tag in place —
    /// so "the rows this call minted" is the wrong unit of work here, unlike
    /// `resolveTagsCommittingInsertions`. `commitDelete(in:commit:)` is the shelf answer for a
    /// commit that may hold inserts, deletes and edits together: on a refusal it rolls the whole
    /// context back, which is what a half-seeded, half-merged tag table left over from a refused
    /// commit would otherwise look like.
    ///
    /// - Parameter commit: See `CadencePendingChangePersistence.commitInsert(of:in:commit:)`.
    @discardableResult
    static func seedDefaultTagsCommitting(
        in context: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> Bool {
        let changed = seedDefaultTags(in: context, saveChanges: false)
        guard changed else { return false }
        try CadencePendingChangePersistence.commitDelete(in: context, commit: commit)
        return changed
    }
}

/// **[[T-7882]].** The tags each note's last tag sync minted, as they were minted, until the next
/// sync of that note takes them (`TagSupport.syncNoteTagsFromMarkdownCommittingInsertions`).
///
/// In memory only, on purpose: an orphan needs the finished word's commit to drop the half-word,
/// and that commit happens in the same session as the half-word's — after a relaunch the note
/// still reads `#pro`, so the tag is the user's. Locked rather than actor-bound because
/// `TagSupport` is `nonisolated`.
nonisolated final class TagProvisionalMints: @unchecked Sendable {
    struct Mint: Equatable {
        let id: UUID
        let name: String
        let colorHex: String
        let desc: String
        let isArchived: Bool

        init(_ tag: Tag) {
            id = tag.id
            name = tag.name
            colorHex = tag.colorHex
            desc = tag.desc
            isArchived = tag.isArchived
        }

        /// Nobody has edited the row since it was minted.
        func matches(_ tag: Tag) -> Bool {
            self == Mint(tag)
        }
    }

    static let shared = TagProvisionalMints()

    private let lock = NSLock()
    private var mintsByNoteID: [UUID: [Mint]] = [:]

    /// Replaces the note's provisional set with what its latest sync minted.
    func record(_ tags: [Tag], for noteID: UUID) {
        let mints = tags.map(Mint.init)
        lock.lock()
        defer { lock.unlock() }
        mintsByNoteID[noteID] = mints.isEmpty ? nil : mints
    }

    /// The note's provisional set, removed: only the next sync of the note may act on it.
    func take(for noteID: UUID) -> [Mint] {
        lock.lock()
        defer { lock.unlock() }
        return mintsByNoteID.removeValue(forKey: noteID) ?? []
    }
}
