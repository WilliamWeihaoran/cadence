#if os(macOS)
import SwiftUI
import SwiftData

struct NotesView: View {
    @Query(sort: \DailyNote.date, order: .reverse) private var allNotes: [DailyNote]
    @Environment(\.modelContext) private var modelContext

    @State private var selectedNoteID: UUID? = nil

    private var todayKey: String { DateFormatters.todayKey() }

    private var selectedNote: DailyNote? {
        allNotes.first { $0.id == selectedNoteID }
    }

    var body: some View {
        HSplitView {
            // Left: list of notes
            VStack(spacing: 0) {
                HStack {
                    Text("Notes")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 14)

                Divider().background(Theme.borderSubtle)

                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(allNotes) { note in
                            NoteListRow(note: note, isSelected: selectedNoteID == note.id)
                                .onTapGesture { selectedNoteID = note.id }
                        }
                    }
                    .padding(8)
                }

                if allNotes.isEmpty {
                    Spacer()
                    EmptyStateView(
                        message: "No notes yet",
                        subtitle: "Notes are created automatically each day",
                        icon: "doc.text"
                    )
                    Spacer()
                }
            }
            .frame(minWidth: 200, idealWidth: 240)
            .background(Theme.surface)

            // Right: editor
            if let note = selectedNote {
                NoteEditorPane(note: note)
            } else {
                ZStack {
                    Theme.bg
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 32))
                            .foregroundStyle(Theme.dim)
                        Text("Select a note")
                            .foregroundStyle(Theme.dim)
                    }
                }
            }
        }
        .background(Theme.bg)
        .onAppear { loadOrCreateToday() }
    }

    private func loadOrCreateToday() {
        let key = todayKey
        if let existing = allNotes.first(where: { $0.date == key }) {
            selectedNoteID = existing.id
        } else {
            let note = DailyNote(date: key)
            modelContext.insert(note)
            selectedNoteID = note.id
        }
    }
}

// MARK: - Note List Row

private struct NoteListRow: View {
    let note: DailyNote
    let isSelected: Bool

    private var formattedDate: String {
        guard let date = DateFormatters.date(from: note.date) else { return note.date }
        return DateFormatters.longDate.string(from: date)
    }

    private var preview: String {
        let lines = note.content.components(separatedBy: "\n")
        return lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? "Empty note"
    }

    private var isToday: Bool {
        note.date == DateFormatters.todayKey()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(isToday ? "Today" : formattedDate)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isToday ? Theme.blue : Theme.muted)
                Spacer()
            }
            Text(preview)
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Theme.blue.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }
}

// MARK: - Note Editor Pane

private struct NoteEditorPane: View {
    @Bindable var note: DailyNote

    private var formattedDate: String {
        guard let date = DateFormatters.date(from: note.date) else { return note.date }
        return DateFormatters.longDate.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 2) {
                Text("Notes".uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .kerning(0.8)
                Text(formattedDate)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider().background(Theme.borderSubtle)

            MarkdownEditorView(text: $note.content)
                .onChange(of: note.content) {
                    note.updatedAt = Date()
                }
        }
        .background(Theme.surface)
    }
}
#endif
