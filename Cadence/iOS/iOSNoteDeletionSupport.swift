#if os(iOS)
import SwiftData
import SwiftUI

/// The one place iOS deletes a note, and the one confirmation in front of it.
///
/// **T-226: iOS could not delete a note at all.** `modelContext.delete` under `Cadence/iOS/`
/// reached `SavedLink`, `Subtask`, tasks, bundles, goals, habits, areas, projects and contexts —
/// never `Note`. That was survivable while the platform showed one note per list; `676ff3b` gave it
/// a full note-management column that creates, files and moves notes, whose row menu carried only
/// Move, and the gap became structural: every note ever made on the device was permanent.
///
/// The shape is `iOSListDeletionSupport`'s, deliberately, down to the modifier: a surface that
/// offers a delete sets a binding and nothing else, so there is exactly one call to
/// `ModelContext.deleteNote` in this folder and exactly one sheet that can reach it.
extension View {
    /// Attaches the note-delete confirmation and the one delete call site.
    ///
    /// `Note?` rather than a wrapper target — `iOSListDeletionTarget` exists because a list delete
    /// has three kinds and the sheet needs each one's name, icon and colour; a note delete has one
    /// kind, and the note is its own identity.
    func iOSNoteDeletion(note: Binding<Note?>) -> some View {
        modifier(iOSNoteDeletionModifier(note: note))
    }
}

private struct iOSNoteDeletionModifier: ViewModifier {
    @Binding var note: Note?
    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content.sheet(item: $note) { note in
            iOSNoteDeleteConfirmationSheet(
                note: note,
                summary: CadenceNoteDeletionSummary.forNote(note, in: modelContext)
            ) {
                try perform(note)
            }
        }
    }

    /// The shared delete, called and not re-implemented. `ModelContext.deleteNote` is what also
    /// reclaims the image assets the note was the last reader of — see `CadenceNoteActionSupport`.
    ///
    /// **T-320: it throws, and the confirmation waits for it.** `deleteNote` only marks the note
    /// and its orphaned image assets deleted in the context; the commit is what makes the deletion
    /// real, and swallowing its failure was how a sheet came to close over a note that is still
    /// there. `commitDelete` rolls the whole marking back on a throw — the note *and* the assets —
    /// so the caller can say so with nothing half-removed behind it.
    private func perform(_ note: Note) throws {
        modelContext.deleteNote(note)
        try CadencePendingChangePersistence.commitDelete(in: modelContext)
    }
}

/// The destructive menu row, so no call site can spell the title or the glyph differently.
struct iOSNoteDeleteMenuButton: View {
    let note: Note
    let request: (Note) -> Void

    var body: some View {
        Button(role: .destructive) {
            request(note)
        } label: {
            Label("Delete Note", systemImage: "trash")
        }
    }
}

/// macOS's `Copy Note Link`, which was also macOS-only, and is the same one line of shared
/// formatting on both platforms — see `CadenceNoteClipboard`.
struct iOSNoteCopyLinkButton: View {
    let note: Note

    var body: some View {
        Button {
            CadenceNoteClipboard.copyMarkdownLink(to: note)
        } label: {
            Label("Copy Note Link", systemImage: "link")
        }
    }
}

/// The confirmation. One view for iPhone and iPad — they differ in the width it is handed, not in
/// what it says or how it is armed.
///
/// **Why a modal sheet and not a `confirmationDialog`.** The same reason
/// `iOSListDeleteConfirmationSheet` gives, and it is worth restating because the wrong answer is
/// the *literal* translation: macOS gates this behind a window-modal dialog, and the direct iOS
/// equivalent is a bottom action sheet — one thumb-reachable tap landing under the finger that
/// just long-pressed the row, which is strictly weaker than the desktop bar for something
/// unrecoverable. So the row's menu only *presents*, and the button that deletes exists only
/// inside a modal with Cancel in the navigation bar.
///
/// **Why it is shorter than the list confirmation.** A note is one object, not a cascade: there is
/// no nested tree to enumerate, and padding this out to the list sheet's three sections would be
/// ceremony for its own sake — the failure mode the task warned about in the other direction. So
/// it is one card. What that card says is not shorter, though: the two lines below the title are
/// the note's own word count and the images this delete reclaims, and the two below *those* are
/// the things it does **not** take (tags, and other notes' links to this one), because for an
/// object this small the reassurance is as load-bearing as the warning.
struct iOSNoteDeleteConfirmationSheet: View {
    let note: Note
    let summary: CadenceNoteDeletionSummary
    /// Throwing, and that is the contract (T-320). This sheet used to call `dismiss()` and *then*
    /// `onConfirm()`: it closed before the delete had been attempted, let alone committed, so
    /// there was no moment at which a failure could have been reported even if the delete had
    /// bothered to report one. Now it waits for the result, and closes only on success.
    let onConfirm: () throws -> Void

    @Environment(\.dismiss) private var dismiss

    /// Set when the delete threw. The sheet stays open holding it: this is a confirmation, so the
    /// only place the answer belongs is the screen that asked the question.
    @State private var failureNotice: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    iOSSettingsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            warningRow

                            iOSRowDivider()

                            noteRow

                            iOSRowDivider()

                            lostLines

                            if let unknownImpactLine = summary.unknownImpactLine {
                                unknownImpactRow(unknownImpactLine)
                            }

                            if summary.retainedLine != nil || summary.brokenLinkLine != nil {
                                iOSRowDivider()
                                keptLines
                            }

                            if let failureNotice {
                                iOSRowDivider()

                                Text(failureNotice)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.red)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                    iOSActionButton(
                        title: "Delete Note",
                        systemImage: "trash.fill",
                        role: .destructive,
                        size: .regular,
                        fullWidth: true,
                        action: confirm
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Delete Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .tint(Theme.blue)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    /// Attempt, then decide. The dismissal is the report of success and nothing else.
    private func confirm() {
        do {
            try onConfirm()
            failureNotice = nil
            dismiss()
        } catch {
            failureNotice = CadenceNoteDeletionSummary.deleteFailureNotice
        }
    }

    private var warningRow: some View {
        HStack(alignment: .top, spacing: iOSSettingsMetrics.glyphLabelSpacing) {
            iOSIconTile(
                systemImage: "exclamationmark.triangle.fill",
                color: Theme.red,
                size: 34,
                iconSize: 16
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("This cannot be undone")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)

                Text("Cadence syncs through your private iCloud database, so this deletion reaches your other devices.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.subdued)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    /// Which note this is: its title, and its folder when it has one.
    ///
    /// **The folder line is back** (T-233). It came off because reading `note.folderPath` failed
    /// `CadenceNoteFolderSurfaceTests.onlyTheSharedFilingHelperWritesAFolderPath`, a test named for
    /// writes whose needle counted reads too; that assertion is an assignment scan now and the read
    /// was never the thing worth banning. It is read off `summary.folder` rather than the note, so
    /// the `""`-is-root convention is applied by the one type that owns it.
    ///
    /// It is a second line under the title rather than a breadcrumb beside it because the title is
    /// allowed two lines, and because the folder is the disambiguator — it earns its own line only
    /// when the title has not already answered the question. Absent at the root: see
    /// `CadenceNoteDeletionSummary.folder`.
    private var noteRow: some View {
        HStack(spacing: iOSSettingsMetrics.glyphLabelSpacing) {
            iOSIconTile(
                systemImage: "doc.text",
                color: Theme.blue,
                size: iOSSettingsMetrics.glyphSlot,
                iconSize: 15
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(note.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)

                if let folder = summary.folder {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 10, weight: .semibold))

                        Text(folder)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .foregroundStyle(Theme.subdued)
                }
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var lostLines: some View {
        if summary.isEmpty {
            Text("Nothing has been written in this note yet.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.subdued)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(summary.lostItemLines, id: \.self) { line in
                    HStack(spacing: 8) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.red)

                        Text(line)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.text)

                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    /// The one-sided doubt, said out loud (T-298).
    ///
    /// **Not a second failure notice, and the distinction is the point.** `failureNotice` — the
    /// red line this card already draws, in the spelling `CadenceInlineFailureNotice` documents
    /// for plain surfaces — is for "the thing you just asked for did not happen", after a refused
    /// delete. This line is the opposite tense: nothing has been attempted yet, and what it
    /// qualifies is the *arithmetic*, not the outcome. Two red paragraphs in one card would read
    /// as two failures, so this one is amber.
    ///
    /// It is above the kept-lines block, not among it: those lines say what this delete leaves
    /// alone, which is exactly the reassurance this line is warning may be incomplete.
    private func unknownImpactRow(_ line: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.amber)

            Text(line)
                .font(.system(size: 12))
                .foregroundStyle(Theme.subdued)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private var keptLines: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let retainedLine = summary.retainedLine {
                Text(retainedLine)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.subdued)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let brokenLinkLine = summary.brokenLinkLine {
                Text(brokenLinkLine)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.subdued)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
#endif
