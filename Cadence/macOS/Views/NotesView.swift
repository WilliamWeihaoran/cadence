#if os(macOS)
import SwiftUI
import SwiftData

struct NotesView: View {
    enum NotesPage: String, CaseIterable {
        case daily  = "Daily"
        case weekly = "Weekly"
        case meeting = "Meeting"
    }

    @Environment(NotesNavigationManager.self) private var notesNavigationManager
    @State private var page: NotesPage = .daily
    @State private var requestedMeetingNoteID: UUID?

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
                case .meeting: MeetingNotesPage(requestedNoteID: $requestedMeetingNoteID)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg)
        .onAppear { applyPendingNavigationIfNeeded() }
        .onChange(of: notesNavigationManager.request?.token) { _, _ in
            applyPendingNavigationIfNeeded()
        }
    }

    private func applyPendingNavigationIfNeeded() {
        guard let request = notesNavigationManager.request else { return }
        page = request.page
        requestedMeetingNoteID = request.eventNoteID
        notesNavigationManager.clear()
    }
}

// MARK: - Daily Notes Page

private struct DailyNotesPage: View {
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Environment(\.modelContext) private var modelContext

    @State private var selectedNoteID: UUID? = nil

    private var notes: [Note] {
        allNotes
            .filter { $0.kind == .daily }
            .sorted { $0.dateKey > $1.dateKey }
    }

    private var selectedNote: Note? {
        notes.first { $0.id == selectedNoteID }
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
                        ForEach(notes) { note in
                            DailyNoteListRow(note: note, isSelected: selectedNoteID == note.id)
                                .onTapGesture { selectedNoteID = note.id }
                        }
                    }
                    .padding(8)
                }

                if notes.isEmpty {
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
                NoteEditorPane(note: note)
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
        if let existing = notes.first(where: { $0.dateKey == key }) {
            selectedNoteID = existing.id
        } else {
            if let note = try? NoteMigrationService.dailyNote(for: key, in: modelContext) {
                selectedNoteID = note.id
            }
        }
    }
}

// MARK: - Weekly Notes Page

private struct WeeklyNotesPage: View {
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Environment(\.modelContext) private var modelContext

    @State private var selectedNoteID: UUID? = nil

    private var notes: [Note] {
        allNotes
            .filter { $0.kind == .weekly }
            .sorted { $0.weekKey > $1.weekKey }
    }

    private var selectedNote: Note? {
        notes.first { $0.id == selectedNoteID }
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
                        ForEach(notes) { note in
                            WeeklyNoteListRow(note: note, isSelected: selectedNoteID == note.id)
                                .onTapGesture { selectedNoteID = note.id }
                        }
                    }
                    .padding(8)
                }

                if notes.isEmpty {
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
                NoteEditorPane(note: note)
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
        if let existing = notes.first(where: { $0.weekKey == key }) {
            selectedNoteID = existing.id
        } else {
            if let note = try? NoteMigrationService.weeklyNote(for: key, in: modelContext) {
                selectedNoteID = note.id
            }
        }
    }
}

// MARK: - Meeting Notes Page

private struct MeetingNotesPage: View {
    @Binding var requestedNoteID: UUID?

    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Environment(\.modelContext) private var modelContext
    @Environment(CalendarManager.self) private var calendarManager

    @State private var selectedNoteID: UUID?

    private var notes: [Note] {
        allNotes.filter { $0.kind == .meeting }
    }

    private var selectedNote: Note? {
        notes.first { $0.id == selectedNoteID }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("Meeting Notes")
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
                        ForEach(notes) { note in
                            MeetingNoteListRow(note: note, isSelected: selectedNoteID == note.id)
                                .onTapGesture {
                                    selectedNoteID = note.id
                                    requestedNoteID = nil
                                }
                        }
                    }
                    .padding(8)
                }

                if notes.isEmpty {
                    Spacer()
                    EmptyStateView(
                        message: "No meeting notes yet",
                        subtitle: "Create one from a calendar event",
                        icon: "doc.text"
                    )
                    Spacer()
                }
            }
            .frame(minWidth: 200, idealWidth: 260)
            .background(Theme.surface)

            if let note = selectedNote {
                NoteEditorPane(note: note)
            } else {
                noteEditorPlaceholder
            }
        }
        .onAppear {
            backfillMetadata()
            applyRequestedSelection()
            if selectedNoteID == nil {
                selectedNoteID = notes.first?.id
            }
        }
        .onChange(of: requestedNoteID) { _, _ in
            applyRequestedSelection()
        }
        .onChange(of: notes.map(\.id)) { _, _ in
            applyRequestedSelection()
            if let selectedNoteID, notes.contains(where: { $0.id == selectedNoteID }) {
                return
            }
            selectedNoteID = notes.first?.id
        }
    }

    private var noteEditorPlaceholder: some View {
        ZStack {
            Theme.bg
            VStack(spacing: 8) {
                Image(systemName: "doc.text").font(.system(size: 32)).foregroundStyle(Theme.dim)
                Text("Select a meeting note").foregroundStyle(Theme.dim)
            }
        }
    }

    private func applyRequestedSelection() {
        guard let requestedNoteID else { return }
        guard notes.contains(where: { $0.id == requestedNoteID }) else { return }
        selectedNoteID = requestedNoteID
        self.requestedNoteID = nil
    }

    private func backfillMetadata() {
        for note in notes where note.calendarID.isEmpty {
            EventNoteSupport.backfillMetadataIfPossible(note, calendarManager: calendarManager)
        }
        if modelContext.hasChanges {
            try? modelContext.save()
        }
    }
}

// MARK: - Daily Note List Row

struct DailyNoteListRow: View {
    let note: Note
    let isSelected: Bool

    private var formattedDate: String {
        guard let date = DateFormatters.date(from: note.dateKey) else { return note.dateKey }
        return DateFormatters.longDate.string(from: date)
    }
    private var preview: String {
        note.content.components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? "Empty note"
    }
    private var isToday: Bool { note.dateKey == DateFormatters.todayKey() }

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
    let note: Note
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

struct MeetingNoteListRow: View {
    let note: Note
    let isSelected: Bool

    private var preview: String {
        note.content.components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? "Empty note"
    }

    private var detail: String {
        if let date = DateFormatters.date(from: note.eventDateKey) {
            if note.eventStartMin >= 0, note.eventEndMin >= 0 {
                return "\(DateFormatters.shortDate.string(from: date)) • \(TimeFormatters.timeRange(startMin: note.eventStartMin, endMin: note.eventEndMin))"
            }
            return DateFormatters.shortDate.string(from: date)
        }
        return "Updated \(DateFormatters.shortDate.string(from: note.updatedAt))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.displayTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
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

// MARK: - Note Editor Pane

struct NoteEditorPane: View {
    @Bindable var note: Note
    var area: Area?
    var project: Project?
    var relatedNotes: [Note] = []
    var relatedTasks: [AppTask] = []
    var onOpenNote: (Note) -> Void = { _ in }
    var onDelete: (() -> Void)?
    var headerDetail: String?
    var headerAccessory: AnyView?
    @Environment(\.modelContext) private var modelContext

    private var titleBinding: Binding<String> {
        Binding(
            get: { note.title },
            set: {
                note.title = $0
                note.updatedAt = Date()
            }
        )
    }

    private var contentBinding: Binding<String> {
        Binding(
            get: { note.content },
            set: {
                note.content = $0
                note.updatedAt = Date()
                syncTitleFromH1IfNeeded()
            }
        )
    }

    private var shouldEditTitle: Bool {
        note.kind == .list || note.kind == .meeting
    }

    private var kindLabel: String {
        switch note.kind {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .permanent: return "Permanent"
        case .list: return "Note"
        case .meeting: return "Meeting"
        }
    }

    private var headerTitle: String {
        switch note.kind {
        case .daily:
            guard let date = DateFormatters.date(from: note.dateKey) else { return note.displayTitle }
            return DateFormatters.longDate.string(from: date)
        case .weekly:
            return DateFormatters.weekLabel(from: note.weekKey)
        default:
            return note.displayTitle
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(kindLabel.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim).kerning(0.8)
                    Spacer()
                    if let headerAccessory {
                        headerAccessory
                    } else {
                        NoteActionMenu(note: note, area: area, project: project, onDelete: onDelete)
                    }
                }
                if shouldEditTitle {
                    TextField("Note title", text: titleBinding)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.text)
                } else {
                    Text(headerTitle)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.text)
                }
                if let headerDetail,
                   !headerDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(headerDetail)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 12)
            Divider().background(Theme.borderSubtle)
            NoteReferenceStrip(
                note: note,
                notes: relatedNotes,
                tasks: relatedTasks,
                onOpenNote: onOpenNote
            )
            MarkdownEditor(text: contentBinding)
        }
        .background(Theme.surface)
    }

    private func syncTitleFromH1IfNeeded() {
        guard note.kind == .list else { return }
        let firstLine = note.content.prefix(while: { $0 != "\n" })
        guard firstLine.hasPrefix("# ") else { return }
        let h1Text = String(firstLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        guard !h1Text.isEmpty, h1Text != note.title else { return }
        note.title = h1Text
        try? modelContext.save()
    }
}

private struct NoteReferenceStrip: View {
    let note: Note
    let notes: [Note]
    let tasks: [AppTask]
    let onOpenNote: (Note) -> Void

    private var linkedNotes: [Note] {
        NoteReferenceResolver.linkedNotes(for: note, in: notes)
    }

    private var linkedTasks: [AppTask] {
        NoteReferenceResolver.linkedTasks(for: note, in: tasks)
    }

    private var backlinks: [Note] {
        NoteReferenceResolver.backlinks(for: note, in: notes)
    }

    var body: some View {
        if linkedNotes.isEmpty && linkedTasks.isEmpty && backlinks.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if !linkedNotes.isEmpty {
                    ReferenceSection(label: "Linked Notes") {
                        ForEach(linkedNotes, id: \.id) { linked in
                            Button {
                                onOpenNote(linked)
                            } label: {
                                ReferenceChip(icon: "doc.text", title: linked.displayTitle, tint: Theme.blue)
                            }
                            .buttonStyle(.cadencePlain)
                        }
                    }
                }

                if !linkedTasks.isEmpty {
                    ReferenceSection(label: "Task References") {
                        ForEach(linkedTasks, id: \.id) { task in
                            ReferenceChip(icon: "checkmark.circle", title: task.title.isEmpty ? "Untitled Task" : task.title, tint: Theme.green)
                        }
                    }
                }

                if !backlinks.isEmpty {
                    ReferenceSection(label: "Backlinks") {
                        ForEach(backlinks, id: \.id) { backlink in
                            Button {
                                onOpenNote(backlink)
                            } label: {
                                ReferenceChip(icon: "arrow.uturn.backward.circle", title: backlink.displayTitle, tint: Theme.amber)
                            }
                            .buttonStyle(.cadencePlain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.surface)
            .overlay(alignment: .bottom) {
                Divider().background(Theme.borderSubtle)
            }
        }
    }
}

private struct ReferenceSection<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .kerning(0.8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { content }
            }
        }
    }
}

private struct ReferenceChip: View {
    let icon: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12))
        .clipShape(Capsule())
    }
}
#endif
