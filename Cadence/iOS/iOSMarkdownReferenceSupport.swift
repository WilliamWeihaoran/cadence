#if os(iOS)
import SwiftData
import SwiftUI

struct iOSMarkdownReferenceSheetModifier: ViewModifier {
    @Binding var selectedReferenceNote: Note?
    @Binding var selectedReferenceTask: AppTask?
    let referenceNotes: [Note]
    let referenceTasks: [AppTask]

    func body(content: Content) -> some View {
        content
            .sheet(item: $selectedReferenceNote) { note in
                iOSHeldNoteSheet(note: note) { selectedReferenceNote = nil } content: { note in
                    iOSLinkedNoteEditorSheet(
                        note: note,
                        referenceNotes: referenceNotes,
                        referenceTasks: referenceTasks
                    )
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
        selectedTask: Binding<AppTask?>,
        referenceNotes: [Note],
        referenceTasks: [AppTask]
    ) -> some View {
        modifier(iOSMarkdownReferenceSheetModifier(
            selectedReferenceNote: selectedNote,
            selectedReferenceTask: selectedTask,
            referenceNotes: referenceNotes,
            referenceTasks: referenceTasks
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

struct iOSLinkedNoteEditorSheet: View {
    @Bindable var note: Note
    let referenceNotes: [Note]
    let referenceTasks: [AppTask]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @State private var isEditorFocused = false
    /// The well's held-back typing, flushed before Done saves the note ([[T-5170]]).
    @State private var editorFlush = iOSMarkdownEditorFlush()
    /// Set when Done could not flush the note. See `flushBeforeDismissing()`.
    @State private var saveFailureNotice: String?
    @State private var selectedReferenceNote: Note?
    @State private var selectedReferenceTask: AppTask?

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    /// The shared spelling, not a fifth copy of this switch. It said "Linked note" for `.list`
    /// while the reference panel's chip for the same note said "List note" — one note, two names,
    /// on two surfaces a tap apart.
    private var subtitle: String {
        NoteReferencePanelSupport.noteKindLabel(note.kind)
    }

    var body: some View {
        NavigationStack {
            editorLayout
                .background(Theme.surface.ignoresSafeArea())
                .navigationTitle(note.displayTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            // [[T-5170]]: the well's tail reaches `note.content` before the save.
                            editorFlush.flush()
                            guard flushBeforeDismissing() else { return }
                            isEditorFocused = false
                            dismiss()
                        }
                    }
                }
                .onChange(of: note.content) { _, _ in
                    persistNote()
                }
                // [[T-5190]]: a swipe skips Done, so the well's held tail is written here.
                .onDisappear(perform: persistTypedTailOnDismissal)
        }
        .iOSMarkdownReferenceSheets(
            selectedNote: $selectedReferenceNote,
            selectedTask: $selectedReferenceTask,
            referenceNotes: referenceNotes,
            referenceTasks: referenceTasks
        )
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var editorLayout: some View {
        if isRegularWidth {
            HStack(spacing: 0) {
                header
                    .frame(width: 320, alignment: .topLeading)

                Divider().background(Theme.borderSubtle)

                editorSurface
            }
        } else {
            VStack(spacing: 0) {
                header

                Divider().background(Theme.borderSubtle)

                editorSurface
            }
        }
    }

    // The eyebrow carries the note's kind, which is worth a row here because this sheet is reached
    // from a `[[link]]` inside some other note and the kind is something the screen does not
    // otherwise say. Everything else about the block is `iOSNoteEditorSheetHeader`'s, shared with
    // `iOSEventNoteEditorSheet` (T-281).
    private var header: some View {
        iOSNoteEditorSheetHeader(eyebrow: subtitle, title: note.displayTitle)
    }

    /// The notice sits here rather than in `editorLayout`, because the layout is drawn twice — the
    /// header is beside the editor at regular width and above it at compact — and a notice attached
    /// to either branch would be missing from the other.
    private var editorSurface: some View {
        VStack(spacing: 0) {
            if let saveFailureNotice {
                CadenceInlineFailureNotice(text: saveFailureNotice)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }

            iOSMarkdownEditingSurface(
                text: $note.content,
                isFocused: $isEditorFocused,
                placeholder: "Start writing…",
                referenceNotes: referenceNotes,
                referenceTasks: referenceTasks,
                editingNote: note,
                onOpenReference: openMarkdownReference,
                flush: editorFlush
            )
        }
    }

    private func openMarkdownReference(_ target: MarkdownReferenceDisplayTarget) {
        switch target.kind {
        case .note:
            selectedReferenceNote = iOSMarkdownReferenceResolver.note(for: target, in: referenceNotes)
        case .task:
            selectedReferenceTask = iOSMarkdownReferenceResolver.task(for: target, in: referenceTasks)
        }
    }

    private func persistNote() {
        note.updatedAt = Date()
        try? modelContext.save()
    }

    /// **[[T-5190]].** A swipe-dismiss skips Done, and the surface's own `onDisappear` writes the
    /// held tail after this sheet stops answering `.onChange(of: note.content)`. Flush it, then
    /// commit whatever is still pending; nothing pending, nothing written.
    private func persistTypedTailOnDismissal() {
        editorFlush.flush()
        guard modelContext.hasChanges else { return }
        persistNote()
    }

    /// **T-497.** `body` used to call `persistNote()` and dismiss unconditionally, so a refused
    /// write closed the sheet on a note the store had not taken — the swallow one frame down and
    /// the claim one frame up. The caret is still in this editor, so nothing is restored: the sheet
    /// stays open, the text stays where it is, and the sentence says so. See
    /// `CadenceInPlaceEditFlush`.
    private func flushBeforeDismissing() -> Bool {
        note.updatedAt = Date()
        guard CadenceInPlaceEditFlush.flush(in: modelContext) else {
            saveFailureNotice = CadenceInPlaceEditFlush.failureNotice
            return false
        }
        saveFailureNotice = nil
        return true
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
