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
    /// Where a refusal is said. `nil` draws it under the control, which a header row has room
    /// for; the format row is a fixed-height strip, so the surface draws it under the strip.
    var onFailure: ((String?) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var typographyScaling
    @Query(sort: \Tag.order) private var allTags: [Tag]
    @State private var isPickerPresented = false
    @State private var newTagName = ""
    @State private var failureNotice: String?
    /// The popover writes its binding and *then* asks `onCommit` whether the store took it; this
    /// carries the setter's answer across that gap.
    @State private var lastWrite = iOSNoteTagWriteOutcome()

    private var selectedTags: [Tag] {
        TagSupport.sorted(note.tags ?? [])
    }

    /// The chips this row draws before it folds the rest into `+N`. The popover lists every tag
    /// with a tick, so a folded tag is still one tap from being removed.
    private var chipLimit: Int {
        placement == .header ? 2 : 3
    }

    var body: some View {
        VStack(alignment: placement == .header ? .trailing : .leading, spacing: 3) {
            HStack(spacing: CadenceTagChipStyle.editableStripSpacing(
                for: .regular, at: dynamicTypeSize, scaling: typographyScaling
            )) {
                if placement == .formatRow { trigger }
                chips
                if placement == .header { trigger }
            }
            if onFailure == nil, let failureNotice {
                CadenceInlineFailureNotice(text: failureNotice)
            }
        }
        .fixedSize()
        .onChange(of: note.id) { _, _ in report(nil) }
    }

    @ViewBuilder
    private var chips: some View {
        let tags = selectedTags
        ForEach(tags.prefix(chipLimit)) { tag in
            CadenceTagChip(tag: tag) {
                remove(tag)
            }
        }
        if tags.count > chipLimit {
            CadenceTagOverflowBadge(count: tags.count - chipLimit)
                .accessibilityLabel(
                    tags.dropFirst(chipLimit).map { CadenceTagChipStyle.accessibilityLabel(for: $0) }
                        .joined(separator: ", ")
                )
        }
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
                // Nothing to restore on a refusal: `setTagsCommittingInsertions` writes nothing
                // until its mint has committed, so the binding already reads what the store holds.
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
        if let onFailure {
            onFailure(notice)
        } else {
            failureNotice = notice
        }
    }
}

/// See `iOSNoteTagControl.lastWrite`.
@MainActor
final class iOSNoteTagWriteOutcome {
    var succeeded = true
}
#endif
