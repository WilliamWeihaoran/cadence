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
                Text("Folder")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                TextField("Planning/Research", text: $folderPath)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.surfaceElevated.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .buttonStyle(.cadencePlain)

                Button(request.actionTitle) {
                    onSave(folderPath)
                    dismiss()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.blue.opacity(normalizedFolderPath.isEmpty ? 0.35 : 0.95))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .buttonStyle(.cadencePlain)
                .disabled(normalizedFolderPath.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 320)
        .background(Theme.surface)
    }
}

struct TaskNoteListRow: View {
    @Bindable var task: AppTask
    let isSelected: Bool

    private var title: String {
        TaskTitleSupport.displayTitle(task.title)
    }

    private var excerpt: String {
        task.notes
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var dueLabel: String? {
        CadenceFocusSupport.dueLabel(forDueDateKey: task.dueDate, todayKey: DateFormatters.todayKey())
    }

    private var isOverdue: Bool {
        task.isOverdue(todayKey: DateFormatters.todayKey())
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(task.isDone ? Theme.green : Theme.dim)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                    .lineLimit(1)
                // A due date always claims the second line first; the excerpt is what gives way
                // when the row runs out of width.
                if dueLabel != nil || !excerpt.isEmpty {
                    HStack(spacing: 6) {
                        if let dueLabel {
                            Text(dueLabel)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(isOverdue ? Theme.red : Theme.muted)
                                .lineLimit(1)
                                .fixedSize()
                                .layoutPriority(1)
                        }
                        if !excerpt.isEmpty {
                            Text(excerpt)
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.dim)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(isSelected ? Theme.blue.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
        .contentShape(Rectangle())
        .cadenceHoverHighlight(
            cornerRadius: Theme.radiusControl,
            fillColor: Theme.blue.opacity(isSelected ? 0.16 : 0.06),
            strokeColor: Theme.blue.opacity(isSelected ? 0.24 : 0.12)
        )
    }
}

/// macOS's list-note row: `NoteFolderListRow` plus the double-click rename.
///
/// The row itself is shared — one glyph slot, one title, one tag strip, and **one** selection/hover
/// fill at `Theme.radiusControl`. This carried its own copy of that layout, and drew
/// `Theme.blue.opacity(0.15)` *underneath* a `cadenceHoverHighlight` fill and stroke at the same
/// radius: two hover layers for one row, which is the standing violation the shared row exists to
/// end. Escape still leaves the field, from out here — `onExitCommand` is AppKit-only and the
/// shared row has no platform guards.
///
/// One deliberate change in the move: the tag strip caps at 3 rather than 2. That is
/// `NoteListDayRow`'s figure — the *other* shared note row — so the two rows in the same column
/// stop disagreeing about how many tags a note gets to show.
struct ListNoteRow: View {
    @Bindable var note: Note
    let isSelected: Bool
    @State private var isEditingTitle = false

    var body: some View {
        NoteFolderListRow(
            title: note.displayTitle,
            detail: NoteRowText.previewBelowTitleHeading(note),
            tags: note.sortedTags,
            isSelected: isSelected,
            editingTitle: isEditingTitle ? $note.title : nil,
            onSubmitTitle: { isEditingTitle = false }
        )
        .onExitCommand { isEditingTitle = false }
        .onTapGesture(count: 2) {
            isEditingTitle = true
        }
    }
}
#endif
