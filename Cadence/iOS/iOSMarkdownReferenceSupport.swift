#if os(iOS)
import SwiftData
import SwiftUI

struct iOSMarkdownReferenceSheetModifier: ViewModifier {
    @Binding var selectedReferenceNote: Note?
    @Binding var selectedReferenceTask: AppTask?
    // No note or task arrays ([[T-9761]]): since [[T-9663]] the linked note opens in
    // `iOSNoteEditorCover`, which queries its own.

    func body(content: Content) -> some View {
        content
            .sheet(item: $selectedReferenceNote) { note in
                // [[T-9663]]: a note reached from a `[[link]]` opens in the Notes tab's editor,
                // chrome and all, not in a thinner sheet of its own.
                iOSHeldNoteSheet(note: note) { selectedReferenceNote = nil } content: { note in
                    iOSNoteEditorCover(reachedFrom: note)
                }
                .cadenceFixedTypography()
            }
            .sheet(item: $selectedReferenceTask) { task in
                iOSTaskInspectorSheet(task: task) { selectedReferenceTask = nil }
            }
    }
}

extension View {
    func iOSMarkdownReferenceSheets(
        selectedNote: Binding<Note?>,
        selectedTask: Binding<AppTask?>
    ) -> some View {
        modifier(iOSMarkdownReferenceSheetModifier(
            selectedReferenceNote: selectedNote,
            selectedReferenceTask: selectedTask
        ))
    }
}

/// [[T-7540]]. **The note half of the guard `iOSTaskInspectorSheet` gives a task.** Every route that
/// holds a `Note` in a `.sheet(item:)` or `.fullScreenCover(item:)` keeps a strong reference to the
/// model, so a delete landing from outside the editor — a CloudKit import of a delete made on the
/// Mac, or a data reset — left the editor drawing a committed-deleted note: `isDeleted` reads
/// `false` again after the save, `modelContext` is `nil`, the property snapshot stays readable, and
/// typing went into a model with no context and was lost silently.
///
/// `CadenceDetailPanelPresentation.resolveHeldSubject` is the measured rule for exactly that, so
/// this asks it rather than re-deciding. One wrapper reused by every note presenter beats a check
/// per presenter, and it is generic over the editor because the note routes present four different
/// editors. Like the task guard, it closes on the next re-render rather than instantly — neither
/// signal is observable — and it can never *open* onto a note that is already gone.
struct iOSHeldNoteSheet<Content: View>: View {
    let note: Note
    let close: () -> Void
    @ViewBuilder let content: (Note) -> Content

    var body: some View {
        switch CadenceDetailPanelPresentation.resolveHeldSubject(heldModel: note) {
        case .stay:
            content(note)
        case .close:
            // Nothing to draw and nothing to bind to. `onAppear` rather than a synchronous clear:
            // the selection cannot be written during the body evaluation that reads it.
            Color.clear.onAppear(perform: close)
        }
    }
}

/// Tap navigation for a `[[…]]` reference the user touched.
///
/// It answers the same question `NoteReferenceResolver` does and must answer it the same way, so it
/// switches on `MarkdownReferenceDisplayTarget.resolution`: a tap on a reference whose note was
/// deleted opens **nothing**, rather than opening a different note that happens to share the
/// label (T-348). A title-only reference still resolves by title.
enum iOSMarkdownReferenceResolver {
    static func note(for target: MarkdownReferenceDisplayTarget, in notes: [Note]) -> Note? {
        switch target.resolution {
        case .identified(let id):
            return notes.first { $0.id == id }
        case .titleOnly:
            let title = target.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return notes.first {
                $0.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(title) == .orderedSame
            }
        }
    }

    static func task(for target: MarkdownReferenceDisplayTarget, in tasks: [AppTask]) -> AppTask? {
        switch target.resolution {
        case .identified(let id):
            return tasks.first { $0.id == id }
        case .titleOnly:
            let title = target.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return tasks.first {
                $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(title) == .orderedSame
            }
        }
    }
}
#endif
