#if os(macOS)
import SwiftUI
import SwiftData

struct NotesView: View {
    enum NotesPage: String, CaseIterable {
        case daily  = "Daily"
        case weekly = "Weekly"
    }

    @State private var page: NotesPage = .daily

    var body: some View {
        VStack(spacing: 0) {
            // Page selector
            HStack(spacing: 0) {
                ForEach(NotesPage.allCases, id: \.self) { p in
                    Button {
                        page = p
                    } label: {
                        Text(p.rawValue)
                            .font(.system(size: 13, weight: page == p ? .semibold : .regular))
                            .foregroundStyle(page == p ? Theme.text : Theme.dim)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .overlay(alignment: .bottom) {
                                if page == p {
                                    Rectangle().fill(Theme.blue).frame(height: 2)
                                }
                            }
                    }
                    .buttonStyle(.cadencePlain)
                }
                Spacer()
            }
            .background(Theme.surface)

            Divider().background(Theme.borderSubtle)

            Group {
                switch page {
                case .daily:  DailyNotesPage()
                case .weekly: WeeklyNotesPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg)
    }
}

// MARK: - Daily Notes Page

private struct DailyNotesPage: View {
    @Query(sort: \DailyNote.date, order: .reverse) private var allNotes: [DailyNote]
    @Environment(\.modelContext) private var modelContext

    @State private var selectedNoteID: UUID? = nil

    private var selectedNote: DailyNote? {
        allNotes.first { $0.id == selectedNoteID }
    }

    var body: some View {
        HSplitView {
            // Left: list
            VStack(spacing: 0) {
                HStack {
                    Text("Daily Notes")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

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
                    EmptyStateView(message: "No notes yet",
                                   subtitle: "Notes are created automatically each day",
                                   icon: "doc.text")
                    Spacer()
                }
            }
            .frame(minWidth: 200, idealWidth: 240)
            .background(Theme.surface)

            // Right: editor
            if let note = selectedNote {
                DailyNoteEditorPane(note: note)
            } else {
                noteEditorPlaceholder
            }
        }
        .onAppear { loadOrCreateToday() }
    }

    private var noteEditorPlaceholder: some View {
        ZStack {
            Theme.bg
            VStack(spacing: 8) {
                Image(systemName: "doc.text").font(.system(size: 32)).foregroundStyle(Theme.dim)
                Text("Select a note").foregroundStyle(Theme.dim)
            }
        }
    }

    private func loadOrCreateToday() {
        let key = DateFormatters.todayKey()
        if let existing = allNotes.first(where: { $0.date == key }) {
            selectedNoteID = existing.id
        } else {
            let note = DailyNote(date: key)
            modelContext.insert(note)
            selectedNoteID = note.id
        }
    }
}

// MARK: - Weekly Notes Page

private struct WeeklyNotesPage: View {
    @Query(sort: \WeeklyNote.weekKey, order: .reverse) private var allNotes: [WeeklyNote]
    @Environment(\.modelContext) private var modelContext

    @State private var selectedNoteID: UUID? = nil

    private var selectedNote: WeeklyNote? {
        allNotes.first { $0.id == selectedNoteID }
    }

    var body: some View {
        HSplitView {
            // Left: list
            VStack(spacing: 0) {
                HStack {
                    Text("Weekly Notes")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

                Divider().background(Theme.borderSubtle)

                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(allNotes) { note in
                            WeeklyNoteListRow(note: note, isSelected: selectedNoteID == note.id)
                                .onTapGesture { selectedNoteID = note.id }
                        }
                    }
                    .padding(8)
                }

                if allNotes.isEmpty {
                    Spacer()
                    EmptyStateView(message: "No weekly notes yet",
                                   subtitle: "Weekly notes are created automatically",
                                   icon: "doc.text")
                    Spacer()
                }
            }
            .frame(minWidth: 200, idealWidth: 240)
            .background(Theme.surface)

            // Right: editor
            if let note = selectedNote {
                WeeklyNoteEditorPane(note: note)
            } else {
                ZStack {
                    Theme.bg
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text").font(.system(size: 32)).foregroundStyle(Theme.dim)
                        Text("Select a week").foregroundStyle(Theme.dim)
                    }
                }
            }
        }
        .onAppear { loadOrCreateThisWeek() }
    }

    private func loadOrCreateThisWeek() {
        let key = DateFormatters.currentWeekKey()
        if let existing = allNotes.first(where: { $0.weekKey == key }) {
            selectedNoteID = existing.id
        } else {
            let note = WeeklyNote(weekKey: key)
            modelContext.insert(note)
            selectedNoteID = note.id
        }
    }
}

// MARK: - Daily Note List Row

struct NoteListRow: View {
    let note: DailyNote
    let isSelected: Bool

    private var formattedDate: String {
        guard let date = DateFormatters.date(from: note.date) else { return note.date }
        return DateFormatters.longDate.string(from: date)
    }
    private var preview: String {
        note.content.components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? "Empty note"
    }
    private var isToday: Bool { note.date == DateFormatters.todayKey() }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(isToday ? "Today" : formattedDate)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isToday ? Theme.blue : Theme.muted)
            Text(preview)
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Theme.blue.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .cadenceHoverHighlight(
            cornerRadius: 6,
            fillColor: Theme.blue.opacity(isSelected ? 0.14 : 0.06),
            strokeColor: Theme.blue.opacity(isSelected ? 0.22 : 0.12)
        )
    }
}

// MARK: - Weekly Note List Row

private struct WeeklyNoteListRow: View {
    let note: WeeklyNote
    let isSelected: Bool

    private var isThisWeek: Bool { note.weekKey == DateFormatters.currentWeekKey() }
    private var label: String { isThisWeek ? "This Week" : DateFormatters.weekLabel(from: note.weekKey) }
    private var preview: String {
        note.content.components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? "Empty note"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isThisWeek ? Theme.blue : Theme.muted)
            Text(preview)
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Theme.blue.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .cadenceHoverHighlight(
            cornerRadius: 6,
            fillColor: Theme.blue.opacity(isSelected ? 0.14 : 0.06),
            strokeColor: Theme.blue.opacity(isSelected ? 0.22 : 0.12)
        )
    }
}

// MARK: - Daily Note Editor Pane

private struct DailyNoteEditorPane: View {
    @Bindable var note: DailyNote

    private var formattedDate: String {
        guard let date = DateFormatters.date(from: note.date) else { return note.date }
        return DateFormatters.longDate.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Daily".uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim).kerning(0.8)
                Text(formattedDate)
                    .font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 12)
            Divider().background(Theme.borderSubtle)
            MarkdownEditorView(text: $note.content)
                .onChange(of: note.content) { note.updatedAt = Date() }
        }
        .background(Theme.surface)
    }
}

// MARK: - Weekly Note Editor Pane

private struct WeeklyNoteEditorPane: View {
    @Bindable var note: WeeklyNote

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Weekly".uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim).kerning(0.8)
                Text(DateFormatters.weekLabel(from: note.weekKey))
                    .font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 12)
            Divider().background(Theme.borderSubtle)
            MarkdownEditorView(text: $note.content)
                .onChange(of: note.content) { note.updatedAt = Date() }
        }
        .background(Theme.surface)
    }
}
#endif
