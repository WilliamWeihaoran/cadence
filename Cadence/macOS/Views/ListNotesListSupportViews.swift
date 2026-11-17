#if os(macOS)
import SwiftUI
import SwiftData

// `ListNoteFolderGroup` was here — a macOS-only struct carrying the `""`-is-root and
// `"__root__"`-is-its-id halves of the folder convention. It is `CadenceNoteFolderGroup` in
// `Shared/CadenceNoteFolderSupport.swift` now, with the convention written down beside it, because
// a folder made on a Mac was invisible on iOS and this type was one of the four places that knew
// why.

struct NoteFolderSheetRequest: Identifiable {
    enum Mode {
        case newNote
        case moveNote(UUID)
    }

    let id = UUID()
    let mode: Mode

    var title: String {
        switch mode {
        case .newNote: return "New Folder Note"
        case .moveNote: return "Move to Folder"
        }
    }

    var actionTitle: String {
        switch mode {
        case .newNote: return "Create Note"
        case .moveNote: return "Move"
        }
    }
}

struct NoteFolderSheet: View {
    let request: NoteFolderSheetRequest
    /// The folders this list's notes are already filed in, offered as rows under the field as iOS's
    /// sheet offers them ([[T-12751]]): without them, a new note bound for an existing folder needed
    /// its name retyped exactly, and a typo made a second folder.
    var existingFolders: [String] = []
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var folderPath = ""

    /// What the typed string actually becomes. Create is gated on **this**, not on the raw field:
    /// `CadenceNoteFolderPath.normalized` drops empty components, so `"//"` and `" / "` are
    /// non-empty text that name no folder at all, and enabling Create on them files the note at the
    /// root — a "New Folder" that silently makes no folder. iOS's sheet has always gated on the
    /// normalized value; this is the same spelling.
    private var normalizedFolderPath: String {
        CadenceNoteFolderPath.normalized(folderPath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.text)

            VStack(alignment: .leading, spacing: 6) {
                Text(NoteFolderSheetCopy.fieldLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                TextField(NoteFolderSheetCopy.placeholder, text: $folderPath)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                // [[T-12751]]: the sentence iOS's sheet has always shown under this field.
                Text(NoteFolderSheetCopy.nestingHint)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }

            if !existingFolders.isEmpty {
                existingFolderList
            }

            // T-7268: Escape cancels and Return confirms; Return is gated by the same `isDisabled`
            // as the click, so a folder path that normalizes to nothing does nothing.
            // [[T-9532]]: the shared action button, so the hit area and the hover wash are the
            // plate. Both buttons were padded and filled BEFORE `.buttonStyle(.cadencePlain)`,
            // which put the plate outside the button: its rim was dead to a click and hover lit
            // a smaller rectangle round the bare word ([[T-9351]]'s shape, modifiers reversed).
            HStack {
                Spacer()
                CadenceActionButton(title: "Cancel", role: .ghost, size: .compact, shortcut: .cancelAction) {
                    dismiss()
                }

                CadenceActionButton(
                    title: request.actionTitle,
                    role: .primary,
                    size: .compact,
                    isDisabled: normalizedFolderPath.isEmpty,
                    shortcut: .defaultAction
                ) {
                    onSave(folderPath)
                    dismiss()
                }
            }
        }
        .padding(18)
        .frame(width: 320)
        .background(Theme.surface)
    }

    /// iOS's "Existing" rows ([[T-12751]]), in the shared row label at pointer height. A click
    /// fills the field, as a tap does there; the commit stays the button below. Scrolls past a
    /// handful so a list with many folders cannot push the buttons off the sheet.
    private var existingFolderList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NoteFolderSheetCopy.existingHeading)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dim)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(existingFolders, id: \.self) { folder in
                        Button {
                            folderPath = folder
                        } label: {
                            NoteFolderExistingRowLabel(
                                folder: folder,
                                isSelected: normalizedFolderPath == folder,
                                fontSize: 13,
                                minHeight: 28
                            )
                        }
                        .buttonStyle(.cadencePlain)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            // A sheet sizes to its content and a ScrollView has none of its own to offer, so the
            // height is stated: every row up to six, then scroll.
            .frame(height: CGFloat(min(existingFolders.count, 6)) * 30)
        }
    }
}

/// macOS's list-note row: `NoteFolderListRow` plus the double-click rename.
///
/// The row itself is shared — one glyph slot, one title, one tag strip, and **one** selection/hover
/// fill at `Theme.radiusControl`. This carried its own copy of that layout, and drew
/// `Theme.blue.opacity(0.15)` *underneath* a `cadenceHoverHighlight` fill and stroke at the same
/// radius: two hover layers for one row, which is the standing violation the shared row exists to
/// end. Escape still leaves the field, from out here — `onExitCommand` is AppKit-only and the
/// shared row has no platform guards. Since [[T-18082]] the field edits a draft: Escape restores
/// the stored name, Return or leaving the field commits it, and a blank name is refused.
///
/// One deliberate change in the move: the tag strip caps at 3 rather than 2. That is
/// `NoteListDayRow`'s figure — the *other* shared note row — so the two rows in the same column
/// stop disagreeing about how many tags a note gets to show.
struct ListNoteRow: View {
    let note: Note
    let isSelected: Bool
    /// [[T-7077]]. The accessibility path to the click `ListNoteFolderRow` puts on this row. Only
    /// the assistive action calls it: the pointer still reaches `onSelect` through that outer tap
    /// gesture, untouched, so single-click open and double-click rename keep their event routing.
    var onOpen: () -> Void = {}
    @Environment(\.modelContext) private var modelContext
    @State private var isEditingTitle = false
    /// [[T-18082]]: what the field edits. The field used to bind `note.title` itself, so every
    /// keystroke was the stored name: Escape "left the field" with the typed text kept, a cleared
    /// field saved as "Untitled", and nothing committed. The draft is seeded when the rename
    /// starts and reaches the note only through `commitRename`.
    @State private var draftTitle = ""
    /// [[T-18082]]: the store refused the rename; the note keeps its old name and this says so.
    @State private var renameFailureNotice: String?

    /// [[T-7077]]. What the row is to assistive tech. A button, selected when it is the open note
    /// — but **not while renaming**: then the row is a container and its `TextField` is the
    /// element in focus, so it must not be folded into a button's label.
    ///
    /// Not a `Button` wrapper, which is what [[T-7068]] did for the other note lists: a `Button`
    /// takes the clicks that the double-click rename and the in-row text field rely on.
    nonisolated static func accessibilityTraits(isEditing: Bool, isSelected: Bool) -> AccessibilityTraits {
        let button: AccessibilityTraits = isEditing ? [] : .isButton
        return button.union(isSelected ? .isSelected : [])
    }

    /// The double-click rename's assistive path.
    nonisolated static let renameActionName = "Rename note"

    /// How a rename ended. A blank draft is refused rather than stored: the row would otherwise
    /// read "Untitled", a name nobody typed.
    nonisolated enum RenameOutcome: Equatable {
        case saved
        case unchanged
        case refusedBlank
    }

    /// [[T-18356]]: why Return did nothing on a blank draft. The refusal keeps the field open so
    /// the name can be typed; this says so, under the row, until the next Return or rename.
    nonisolated static let blankTitleNotice = "A note needs a title."

    /// What the row says after a rename ends. Leaving the field drops a blank draft and closes on
    /// the stored name, so there is nothing to explain; Return on one keeps the field open.
    nonisolated static func renameNotice(after outcome: RenameOutcome, leavingField: Bool) -> String? {
        outcome == .refusedBlank && !leavingField ? blankTitleNotice : nil
    }

    /// [[T-18082]]: the rename's one write. Normalises the draft, refuses a blank one, writes the
    /// title and `updatedAt`, and commits, putting both back if the commit throws — the
    /// `ContextSettingsRow.commitRename` shape. Static, and the commit a parameter, so the refused
    /// path is reachable from a test; the view has no seam.
    ///
    /// [[T-18095]]: the body's first-line `# H1` is rewritten with the title, as `NoteEditorPane`'s
    /// own title field does, so the note's next body commit cannot read the old heading back and
    /// undo the rename. A refused commit puts the body back with the title.
    static func commitRename(
        _ note: Note,
        draft: String,
        in modelContext: ModelContext,
        now: Date = Date(),
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> RenameOutcome {
        guard !CadenceTitleNormalization.isBlank(draft) else { return .refusedBlank }
        let title = CadenceTitleNormalization.normalized(draft)
        guard title != note.title else { return .unchanged }
        let previousTitle = note.title
        let previousUpdatedAt = note.updatedAt
        let previousContent = note.content
        MarkdownNoteTitleSync.rename(note, to: title)
        note.updatedAt = now
        try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit) {
            note.title = previousTitle
            note.content = previousContent
            note.updatedAt = previousUpdatedAt
        }
        return .saved
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            NoteFolderListRow(
                title: note.displayTitle,
                detail: NoteRowText.previewBelowTitleHeading(note),
                tags: note.sortedTags,
                isSelected: isSelected,
                editingTitle: isEditingTitle ? $draftTitle : nil,
                onSubmitTitle: { finishRename(leavingField: false) },
                onTitleFocusLost: { finishRename(leavingField: true) }
            )
            // [[T-18082]]: Escape restores the stored name, through both spellings the Settings
            // context row uses (`onExitCommand` and `onKeyPress(.escape)`, [[T-10033]]).
            .onExitCommand(perform: cancelRename)
            .onKeyPress(.escape) {
                guard isEditingTitle else { return .ignored }
                cancelRename()
                return .handled
            }
            .onTapGesture(count: 2) {
                beginRename()
            }
            .accessibilityElement(children: isEditingTitle ? .contain : .combine)
            .accessibilityAddTraits(Self.accessibilityTraits(isEditing: isEditingTitle, isSelected: isSelected))
            .accessibilityAction { onOpen() }
            .accessibilityAction(named: Self.renameActionName) { beginRename() }

            if let renameFailureNotice {
                CadenceInlineFailureNotice(text: renameFailureNotice)
            }
        }
    }

    /// A double-click inside an open field selects a word; it must not reseed the draft.
    private func beginRename() {
        guard !isEditingTitle else { return }
        draftTitle = note.title
        renameFailureNotice = nil
        isEditingTitle = true
    }

    private func cancelRename() {
        isEditingTitle = false
    }

    /// Return keeps the field open on a refusal, so the draft can be fixed; leaving the field
    /// cannot keep it open, so a blank draft is dropped and a refused commit closes on the stored
    /// name with the notice beneath it.
    private func finishRename(leavingField: Bool) {
        guard isEditingTitle else { return }
        let outcome: RenameOutcome
        do {
            outcome = try Self.commitRename(note, draft: draftTitle, in: modelContext)
        } catch {
            renameFailureNotice = CadencePendingChangePersistence.editFailureNotice
            if leavingField { isEditingTitle = false }
            return
        }
        renameFailureNotice = Self.renameNotice(after: outcome, leavingField: leavingField)
        if outcome == .refusedBlank && !leavingField { return }
        isEditingTitle = false
    }
}
#endif
