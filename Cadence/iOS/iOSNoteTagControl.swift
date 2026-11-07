#if os(iOS)
import SwiftData
import SwiftUI

/// **[[T-8761]] — the note's tags, in the iOS note chrome.** macOS draws `TagPickerControl` beside
/// the note's title; until this the phone and the iPad drew nothing, so a note's tags could be added
/// only by typing `#` blind and could not be seen or removed at all.
///
/// It sits where the template menu sits, on the same gate: in the Notes header (and a list's Notes
/// control row) where the layout has two columns, and in the editor's format row everywhere else —
/// `iOSNotesView.showsHeaderTemplateMenu` gives the reason, and a note does not gain or lose chrome
/// depending on which column it was reached from.
///
/// **A touch twin, not the Mac control moved.** The catalogue is `iOSTaskTagPickerPopover`, the
/// popover a task's tags already use on iOS, and its list is `TagSupport.pickerChoices(from:)` —
/// the same function macOS's `TagPickerPopover` lists from, so both platforms offer one note the
/// same tags. Every write goes through `CadenceNoteTagEditing`, which is
/// `TagSupport.setTagsCommittingInsertions(... writeFrontmatter: true)`: the Mac's door.
///
/// **Focus is dropped before anything is written.** `iOSMarkdownEditingSurface` ignores external
/// writes to its text while it holds focus and later commits its own draft over them — the reason
/// `iOSNotesView.apply(_:to:)` drops focus before a template. A tag write rewrites the frontmatter
/// in `note.content`, so the same rule holds: opening the picker resigns the editor, and a chip's
/// `x` tapped mid-typing resigns it and writes a turn later.
struct iOSNoteTagControl: View {
    enum Placement {
        /// Right-aligned in a header row: chips, then the trigger, so the trigger's frame does not
        /// move when a chip is added — a popover anchored to a control that has just relocated
        /// gets repositioned by UIKit (the reason `iOSTaskTagStrip` leads with its `+`).
        case header
        /// Left-aligned in the format row's scroller: the trigger leads, for the same reason.
        case formatRow
    }

    let note: Note
    @Binding var isEditorFocused: Bool
    var placement: Placement = .header
    /// Where a refusal is said — always the host's, never this control's own (T-9542). Each chip
    /// row below is `.fixedSize()` so a chip never truncates, and a fixed-size container proposes no
    /// width: a sentence drawn inside it took its one-line ideal width, about 300pt, and in an iPad
    /// header that block shoved the date title aside. Every host draws the sentence on a full-width
    /// line under the strip that holds this control, where it wraps: the format row's surface
    /// under the format row, `iOSNotesView` under its header, `iOSListNotesView` under its
    /// control row.
    let onFailure: (String?) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var typographyScaling
    @Query(sort: \Tag.order) private var allTags: [Tag]
    @State private var isPickerPresented = false
    @State private var newTagName = ""
    /// The popover writes its binding and *then* asks `onCommit` whether the store took it; this
    /// carries the setter's answer across that gap.
    @State private var lastWrite = iOSNoteTagWriteOutcome()

    private var selectedTags: [Tag] {
        TagSupport.sorted(note.tags ?? [])
    }

    private var stripSpacing: CGFloat {
        CadenceTagChipStyle.editableStripSpacing(for: .regular, at: dynamicTypeSize, scaling: typographyScaling)
    }

    /// **[[T-12292]]: the chips fold to fit the width they are offered; they never widen the host.**
    /// Until this the whole control was `.fixedSize()` with a fixed chip limit, so it reported one
    /// width whatever it was offered — on a portrait iPad three tags made the Notes header wider
    /// than the window and the two-column shell was centred on the overflow. Now only each
    /// *candidate* row is fixed-size (a chip still never truncates), and `ViewThatFits` picks the
    /// widest count in `CadenceTagStripCollapse.candidateLimits` that fits — down to the `+N` badge
    /// alone. The same rule macOS's `AdaptiveSelectedTagStrip` draws from. The popover lists every
    /// tag with a tick, so a folded tag is still one tap from being removed.
    var body: some View {
        HStack(spacing: stripSpacing) {
            if placement == .formatRow { trigger }
            chips
            if placement == .header { trigger }
        }
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: note.id) { _, _ in report(nil) }
    }

    @ViewBuilder
    private var chips: some View {
        let tags = selectedTags
        if !tags.isEmpty {
            ViewThatFits(in: .horizontal) {
                ForEach(CadenceTagStripCollapse.candidateLimits(tagCount: tags.count), id: \.self) { limit in
                    chipRow(tags, limit: limit)
                }
            }
        }
    }

    private func chipRow(_ tags: [Tag], limit: Int) -> some View {
        HStack(spacing: stripSpacing) {
            ForEach(tags.prefix(limit)) { tag in
                CadenceTagChip(tag: tag) {
                    remove(tag)
                }
            }
            if tags.count > limit {
                CadenceTagOverflowBadge(count: tags.count - limit)
                    .accessibilityLabel(
                        tags.dropFirst(limit).map { CadenceTagChipStyle.accessibilityLabel(for: $0) }
                            .joined(separator: ", ")
                    )
            }
        }
        .fixedSize()
    }

    private var trigger: some View {
        Button {
            isEditorFocused = false
            isPickerPresented = true
        } label: {
            iOSIconTile(systemImage: "tag", color: Theme.muted, size: 34, iconSize: 13)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel("Edit tags")
        .accessibilityValue(selectedTags.isEmpty ? "No tags" : "\(selectedTags.count)")
        .popover(isPresented: $isPickerPresented) {
            iOSTaskTagPickerPopover(
                selectedTags: Binding(
                    get: { TagSupport.sorted(note.tags ?? []) },
                    set: { tags in
                        lastWrite.succeeded = CadenceNoteTagEditing.setTags(tags, on: note, in: modelContext)
                        if lastWrite.succeeded { report(nil) }
                    }
                ),
                allTags: allTags,
                newTagName: $newTagName,
                // Nothing to restore on a refusal: `setTagsCommittingInsertions` puts the note back
                // itself when its commit is refused, so the binding already reads what the store holds.
                onCommit: { _ in lastWrite.succeeded },
                onDismissRefusal: { report($0) }
            )
        }
    }

    private func remove(_ tag: Tag) {
        guard isEditorFocused else {
            commitRemoval(of: tag)
            return
        }
        isEditorFocused = false
        DispatchQueue.main.async {
            commitRemoval(of: tag)
        }
    }

    private func commitRemoval(of tag: Tag) {
        if CadenceNoteTagEditing.remove(tag, from: note, in: modelContext) {
            report(nil)
        } else {
            report(CadencePendingChangePersistence.editFailureNotice)
        }
    }

    private func report(_ notice: String?) {
        onFailure(notice)
    }
}

/// See `iOSNoteTagControl.lastWrite`.
@MainActor
final class iOSNoteTagWriteOutcome {
    var succeeded = true
}
#endif
