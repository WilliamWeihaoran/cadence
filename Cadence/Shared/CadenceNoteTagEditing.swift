import Foundation
import SwiftData

extension TagSupport {
    /// **[[T-8761]] — the tags a tag picker lists, on both platforms.** Active tags only, one per
    /// slug, in `uniqueBySlug`'s order.
    ///
    /// It was spelled `uniqueBySlug(allTags.filter { !$0.isArchived })` inside each popover —
    /// macOS's `TagPickerPopover` and iOS's `iOSTaskTagPickerPopover` — which is two copies of one
    /// rule about what a note's (or a task's) tag control may offer. The iOS note chrome now
    /// presents the iOS popover, so a phone and a Mac open on the same note must list the same
    /// tags, and one function is what makes that true rather than coincidental.
    /// `CadenceNoteTagEditingTests` holds both popovers to it.
    static func pickerChoices(from allTags: [Tag]) -> [Tag] {
        uniqueBySlug(allTags.filter { !$0.isArchived })
    }
}

/// **[[T-8761]] — the iOS note chrome's tag writes.** `iOSNoteTagControl` (the Notes header at
/// regular width, the editor's format row at compact) edits a note's tags through these, and they
/// are `TagSupport.setTagsCommittingInsertions(... writeFrontmatter: true)` — the door macOS's
/// `NoteEditorPane.noteTagsBinding` uses — so a tag picked on the phone lands in `note.tags` and in
/// the frontmatter block exactly as one picked on the Mac does, mint committed first and nothing
/// written on a refusal.
///
/// Here rather than in the iOS view so the behaviour can be pinned: `CadenceTests` runs on macOS and
/// cannot reach `Cadence/iOS/`.
enum CadenceNoteTagEditing {
    /// Replaces the note's picked tags with `tags`. Inline `#tags` in the body are folded back in by
    /// `setTagsCommittingInsertions`, the same as on the Mac, so a tag the prose still mentions
    /// cannot be removed from chrome alone.
    ///
    /// - Returns: Whether the write happened. `false` means the store refused a tag this had to
    ///   mint, and the note is untouched.
    @discardableResult
    static func setTags(
        _ tags: [Tag],
        on note: Note,
        in context: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Bool {
        TagSupport.setTagsCommittingInsertions(
            named: TagSupport.sorted(tags).map(\.name),
            on: note,
            in: context,
            writeFrontmatter: true,
            commit: commit
        )
    }

    /// A chip's `x`: the note's tags without `tag`, matched by id.
    @discardableResult
    static func remove(
        _ tag: Tag,
        from note: Note,
        in context: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Bool {
        let remaining = (note.tags ?? []).filter { $0.id != tag.id }
        return setTags(remaining, on: note, in: context, commit: commit)
    }
}
