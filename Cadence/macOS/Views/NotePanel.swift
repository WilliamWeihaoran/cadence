#if os(macOS)
import SwiftUI
import SwiftData

struct NotePanel: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allNotes: [DailyNote]
    @State private var todayNote: DailyNote?

    private var todayKey: String { DateFormatters.todayKey() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(eyebrow: "Notes", title: "Today")

            Divider()
                .background(Theme.borderSubtle)

            if let note = todayNote {
                NoteEditor(note: note)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.surface)
        .onAppear { loadOrCreateNote() }
    }

    private func loadOrCreateNote() {
        let key = todayKey
        if let existing = allNotes.first(where: { $0.date == key }) {
            todayNote = existing
        } else {
            let note = DailyNote(date: key)
            modelContext.insert(note)
            todayNote = note
        }
    }
}

// MARK: - Note Editor

private struct NoteEditor: View {
    @Bindable var note: DailyNote

    var body: some View {
        MarkdownEditorView(text: $note.content)
            .onChange(of: note.content) {
                note.updatedAt = Date()
            }
    }
}
#endif
