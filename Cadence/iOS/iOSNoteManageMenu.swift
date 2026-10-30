#if os(iOS)
import SwiftData
import SwiftUI

/// The open note's Move Note and Delete Note, in the editor chrome ([[T-8762]]).
///
/// The Mac's `NoteActionMenu` carries both in the Actions popover above every note it edits: Move
/// Note for a list note whenever a list exists, Delete Note wherever the host passes `onDelete`.
/// iOS had neither in its editor chrome — no list-to-list move anywhere, and delete only from a
/// row's long-press — and neither gap answers a hardware constraint ([[T-8201]]). This is the same
/// two actions in the touch idiom the AI and export controls beside it already use: a `Menu`
/// behind a quiet 34pt tile.
///
/// **Nothing is re-implemented here.** The move is `NoteActionSupport.move`, the helper the Mac
/// popover calls; whether to offer it and what each destination is called are
/// `CadenceNoteMoveDestinations`, which the Mac reads too; and Delete is
/// `iOSNoteDeleteMenuButton`, which only *requests* — the host's `iOSNoteDeletion` modifier owns
/// the confirmation and the one delete call.
struct iOSNoteManageMenu: View {
    let note: Note
    /// Where a refused move is reported. A menu closes on tap whatever the store answers, so the
    /// notice cannot live in the menu the way the Mac's lives on its still-open Move page; the
    /// host draws it beside the note instead. A host that passes `nil` offers no move — it has
    /// nowhere to say a refusal.
    var moveFailureNotice: Binding<String?>?
    /// Set by a host that offers a delete for this note, exactly as the Mac host's `onDelete`.
    var onDelete: ((Note) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]

    private var offersMove: Bool {
        moveFailureNotice != nil
            && CadenceNoteMoveDestinations.offersMove(
                kind: note.kind,
                hasAreas: !areas.isEmpty,
                hasProjects: !projects.isEmpty
            )
    }

    var body: some View {
        // Absent rather than empty: a `Menu` with nothing in it still draws its tile.
        if offersMove || onDelete != nil {
            Menu {
                if offersMove {
                    moveMenu
                }
                if let onDelete {
                    Divider()
                    iOSNoteDeleteMenuButton(note: note, request: onDelete)
                }
            } label: {
                label
            }
        }
    }

    /// The Mac's Move page, destination for destination: No List, then the areas, then the
    /// projects, the current one checked.
    private var moveMenu: some View {
        Menu {
            destinationButton(
                title: CadenceNoteMoveDestinations.noListTitle,
                isCurrent: CadenceNoteMoveDestinations.isUnfiled(note)
            ) {
                try NoteActionSupport.move(note, toArea: nil, modelContext: modelContext)
            }

            if !areas.isEmpty {
                Section("Areas") {
                    ForEach(areas) { area in
                        destinationButton(
                            title: CadenceNoteMoveDestinations.title(for: area),
                            isCurrent: note.area?.id == area.id
                        ) {
                            try NoteActionSupport.move(note, toArea: area, modelContext: modelContext)
                        }
                    }
                }
            }

            if !projects.isEmpty {
                Section("Projects") {
                    ForEach(projects) { project in
                        destinationButton(
                            title: CadenceNoteMoveDestinations.title(for: project),
                            isCurrent: note.project?.id == project.id
                        ) {
                            try NoteActionSupport.move(note, toProject: project, modelContext: modelContext)
                        }
                    }
                }
            }
        } label: {
            Label("Move Note", systemImage: "tray.full")
        }
    }

    private func destinationButton(
        title: String,
        isCurrent: Bool,
        move: @escaping () throws -> Void
    ) -> some View {
        Button {
            moveNote(move)
        } label: {
            if isCurrent {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    /// The Mac popover's `moveNote`, minus the dismissal a menu does for itself: the refusal is
    /// the shared notice, and a success clears it.
    private func moveNote(_ apply: () throws -> Void) {
        do {
            try apply()
        } catch {
            moveFailureNotice?.wrappedValue = CadencePendingChangePersistence.editFailureNotice
            return
        }
        moveFailureNotice?.wrappedValue = nil
    }

    /// The same quiet tile and 44pt hit area as the template, AI and export controls in the same
    /// row — one kind of control.
    private var label: some View {
        iOSIconTile(systemImage: "ellipsis", color: Theme.muted, size: 34, iconSize: 13)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("Note actions")
    }
}
#endif
