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
                iOSLinkedNoteEditorSheet(
                    note: note,
                    referenceNotes: referenceNotes,
                    referenceTasks: referenceTasks
                )
            }
            .sheet(item: $selectedReferenceTask) { task in
                iOSTaskDetailSheet(task: task)
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

struct iOSLinkedNoteEditorSheet: View {
    @Bindable var note: Note
    let referenceNotes: [Note]
    let referenceTasks: [AppTask]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @State private var isEditorFocused = false
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
                            persistNote()
                            isEditorFocused = false
                            dismiss()
                        }
                    }
                }
                .onChange(of: note.content) { _, _ in
                    persistNote()
                }
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The note's kind, in the shared eyebrow style rather than a fourth hand-rolled
            // uppercase caption. It stays because this sheet is reached from a `[[link]]` in some
            // other note — the kind is something the screen does not otherwise say.
            SectionEyebrowLabel(text: subtitle)

            Text(note.displayTitle)
                .font(.system(size: isRegularWidth ? 24 : 22, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: isRegularWidth ? .infinity : nil, alignment: .topLeading)
        .padding(.horizontal, isRegularWidth ? 20 : 18)
        .padding(.vertical, isRegularWidth ? 20 : 14)
        .background(Theme.surface)
    }

    private var editorSurface: some View {
        iOSMarkdownEditingSurface(
            text: $note.content,
            isFocused: $isEditorFocused,
            placeholder: "Start writing...",
            referenceNotes: referenceNotes,
            referenceTasks: referenceTasks,
            editingNote: note,
            onOpenReference: openMarkdownReference
        )
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
}

enum iOSMarkdownReferenceResolver {
    static func note(for target: MarkdownReferenceDisplayTarget, in notes: [Note]) -> Note? {
        if let id = target.referenceID,
           let exact = notes.first(where: { $0.id == id }) {
            return exact
        }

        let title = target.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        return notes.first {
            $0.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(title) == .orderedSame
        }
    }

    static func task(for target: MarkdownReferenceDisplayTarget, in tasks: [AppTask]) -> AppTask? {
        if let id = target.referenceID,
           let exact = tasks.first(where: { $0.id == id }) {
            return exact
        }

        let title = target.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        return tasks.first {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(title) == .orderedSame
        }
    }
}
#endif
