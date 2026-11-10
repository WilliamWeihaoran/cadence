#if os(macOS)
import SwiftUI

// MARK: - Header & Search

struct ListNotesHeaderView: View {
    let onNewNote: () -> Void
    let onNewNoteInFolder: () -> Void

    var body: some View {
        HStack {
            Text("Notes")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.muted)
            Spacer()
            Menu {
                Button("New Note", action: onNewNote)
                Button("New Note in Folder…", action: onNewNoteInFolder)
            } label: {
                // [[T-9531]]: a 28x26 target with one hover plate. The label was the bare 12pt
                // glyph under `.menuStyle(.borderlessButton)`, measured on the accessibility tree
                // at 33x14pt (glyph plus indicator) -- that style builds an AppKit pop-up button
                // that ignores the label's frame, so a frame alone does nothing. `.button` with
                // `.plain` draws the SwiftUI label as it is, frame and content shape included.
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                    .frame(width: 28, height: 26)
                    .contentShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .fixedSize()
            .cadenceHoverHighlight(cornerRadius: Theme.radiusControlCompact, fillColor: Theme.blue.opacity(0.08), strokeColor: Theme.blue.opacity(0.16))
            .cadenceControlLabel("New note")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

struct ListNotesSearchField: View {
    @Binding var searchText: String
    var hasTagFilters: Bool
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dim)
            TextField("Search notes", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
                .focused($isSearchFocused)
            // [[T-9971]]: iOS's list Notes search (`iOSListNotesView.filterRow`) clears from the
            // shared button; the Mac field had none, so a typed query could only be deleted by hand.
            CadenceSearchFieldClearButton(text: $searchText, glyphSize: 11, focus: $isSearchFocused)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.bg.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, hasTagFilters ? 6 : 10)
    }
}

// MARK: - Collapsible Section

// `CollapsibleNoteSection` is shared now: `Shared/CadenceListNotesSections.swift`, which iOS's
// list Notes tab draws too ([[T-15433]]).

// MARK: - List Note Row + Menu

/// One row of the folder-grouped list-notes column, with the affordances that are macOS's own:
/// click to open, right-click for the copy/move/delete menu.
///
/// The **grouping** is not here — `NoteFolderGroupList` in `Shared/CadenceNoteFolderSupport.swift`
/// draws the headings and the runs on both platforms, and this is the row it is handed. This used
/// to be `ListNoteFolderGroupView`, which owned the heading, the ordering *and* the row menu; the
/// first two are the parts iOS would have had to copy to show a Mac-made folder at all.
struct ListNoteFolderRow: View {
    let note: Note
    let isSelected: Bool
    let folderNames: [String]
    let onSelect: (Note) -> Void
    let onCopyLink: (Note) -> Void
    let onMoveToFolder: (String) -> Void
    let onNewFolder: () -> Void
    let onDelete: (Note) -> Void

    var body: some View {
        ListNoteRow(note: note, isSelected: isSelected, onOpen: { onSelect(note) })
            .onTapGesture {
                onSelect(note)
            }
            .contextMenu {
                // [[T-10166]]: glyphed, as the Delete under it and iOS's item are.
                Button {
                    onCopyLink(note)
                } label: {
                    Label(CadenceNoteClipboard.copyLinkTitle, systemImage: CadenceNoteClipboard.copyLinkSystemImage)
                }
                NoteFolderMoveMenu(
                    folderNames: folderNames,
                    move: onMoveToFolder,
                    newFolder: onNewFolder
                )
                Button(role: .destructive) {
                    onDelete(note)
                } label: {
                    Label(CadenceNoteRowMenuCopy.deleteTitle, systemImage: CadenceNoteRowMenuCopy.deleteSystemImage)
                }
                .cadenceDestructiveMenuRow()
            }
    }
}

// MARK: - Row Button

/// A note-list row as a control ([[T-7068]]): the rows were a tap gesture on a plain stack, so
/// VoiceOver found two loose texts, no button, and no way to open the note. `iOSNotesView`
/// already hosts the same rows in a `Button`; this is the Mac's.
///
/// `.plain` so the button adds no bezel and no padding: the row keeps its own full-width frame,
/// `contentShape` and hover fill, which is the hit area the tap gesture had. A row's
/// `.contextMenu` goes on this, outside, so the right-click target is the whole button too.
struct NoteListRowButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action, label: label)
            .buttonStyle(.plain)
    }
}

// MARK: - Event / Task Note Section Rows

struct ListEventNoteSectionRows: View {
    let notes: [Note]
    let selectedNoteID: UUID?
    let onSelect: (Note) -> Void

    var body: some View {
        ForEach(notes) { note in
            // No month header above this section, so the row spells its own date out.
            NoteListRowButton(action: { onSelect(note) }) {
                MeetingNoteListRow(note: note, isSelected: selectedNoteID == note.id, showsDate: true)
            }
        }
    }
}

struct ListTaskNoteSectionRows: View {
    let tasks: [AppTask]
    /// `ListNotesView`'s observed day ([[T-5012]]).
    let todayKey: String
    let selectedTaskID: UUID?
    let onSelect: (AppTask) -> Void

    var body: some View {
        ForEach(tasks) { task in
            NoteListRowButton(action: { onSelect(task) }) {
                TaskNoteListRow(task: task, isSelected: selectedTaskID == task.id, todayKey: todayKey)
            }
        }
    }
}

// MARK: - Empty States

struct ListNotesEmptyState: View {
    let hasAnyNotes: Bool
    let hasAnyFilteredMatches: Bool

    var body: some View {
        if !hasAnyNotes {
            Spacer()
            EmptyStateView(
                message: CadenceEmptyStateCopy.listNotesTitle,
                subtitle: CadenceEmptyStateCopy.listNotesSubtitle,
                icon: "doc.text"
            )
            Spacer()
        } else if !hasAnyFilteredMatches {
            Spacer()
            EmptyStateView(
                message: CadenceEmptyStateCopy.listNotesNoMatchesTitle,
                subtitle: CadenceEmptyStateCopy.listNotesNoMatchesSubtitle,
                icon: "magnifyingglass"
            )
            Spacer()
        }
    }
}

struct ListNotesEditorPlaceholder: View {
    var body: some View {
        ZStack {
            Theme.bg
            VStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 32))
                    .foregroundStyle(Theme.dim)
                Text(CadenceEmptyStateCopy.selectNoteTitle)
                    .foregroundStyle(Theme.dim)
            }
        }
    }
}
#endif
