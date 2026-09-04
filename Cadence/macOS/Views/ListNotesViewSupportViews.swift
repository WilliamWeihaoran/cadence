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
                Button("New Note in Folder...", action: onNewNoteInFolder)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.blue)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .cadenceControlLabel("New note")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

struct ListNotesSearchField: View {
    @Binding var searchText: String
    var hasTagFilters: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dim)
            TextField("Search notes", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
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

struct CollapsibleNoteSection<Content: View>: View {
    let title: String
    let count: Int
    @Binding var isCollapsed: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                isCollapsed.toggle()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .frame(width: 12)
                    // `Theme.muted` rather than the eyebrow's default `Theme.dim`: this header is
                    // a *control* — the whole row toggles the section — so it sits a step brighter
                    // than the inert eyebrows around it.
                    SectionEyebrowLabel(text: title, tint: Theme.muted)
                    Spacer()
                    Text("\(count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.surfaceElevated.opacity(0.75))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.cadencePlain)
            .cadenceHoverHighlight(
                cornerRadius: Theme.radiusControlCompact,
                fillColor: Theme.surfaceElevated.opacity(0.55),
                strokeColor: Theme.borderSubtle.opacity(0.8)
            )

            if !isCollapsed {
                content
            }
        }
    }
}

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
        ListNoteRow(note: note, isSelected: isSelected)
            .onTapGesture {
                onSelect(note)
            }
            .contextMenu {
                Button("Copy Note Link") {
                    onCopyLink(note)
                }
                NoteFolderMoveMenu(
                    folderNames: folderNames,
                    move: onMoveToFolder,
                    newFolder: onNewFolder
                )
                Button(role: .destructive) {
                    onDelete(note)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
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
            MeetingNoteListRow(note: note, isSelected: selectedNoteID == note.id, showsDate: true)
                .onTapGesture {
                    onSelect(note)
                }
        }
    }
}

struct ListTaskNoteSectionRows: View {
    let tasks: [AppTask]
    let selectedTaskID: UUID?
    let onSelect: (AppTask) -> Void

    var body: some View {
        ForEach(tasks) { task in
            TaskNoteListRow(task: task, isSelected: selectedTaskID == task.id)
                .onTapGesture {
                    onSelect(task)
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
                message: "No matches",
                subtitle: "Try a different search",
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
