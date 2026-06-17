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
    @AppStorage(iOSMarkdownEditorPreferences.modeKey) private var editorModeRaw = iOSMarkdownEditorPreferences.defaultMode.rawValue
    @State private var selectedReferenceNote: Note?
    @State private var selectedReferenceTask: AppTask?

    private var editorModeBinding: Binding<iOSMarkdownEditorMode> {
        iOSMarkdownEditorPreferences.binding(for: $editorModeRaw)
    }

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var subtitle: String {
        switch note.kind {
        case .daily: return "Daily note"
        case .weekly: return "Weekly note"
        case .permanent: return "Notepad"
        case .list: return "Linked note"
        case .meeting: return "Meeting note"
        }
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
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            persistNote()
                            isEditorFocused = false
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
            Text(subtitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .textCase(.uppercase)

            Text(note.displayTitle)
                .font(.system(size: isRegularWidth ? 24 : 22, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(2)

            HStack {
                Spacer()
                iOSMarkdownModePicker(mode: editorModeBinding)
            }
            .padding(.top, 6)
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
            mode: editorModeBinding,
            placeholder: "Start writing...",
            referenceNotes: referenceNotes,
            referenceTasks: referenceTasks,
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
