#if os(iOS)
import EventKit
import SwiftData
import SwiftUI

struct iOSNotesPanel: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var activeTab: CadenceCoreNoteTab = .today
    @State private var todayNote: Note?
    @State private var weekNote: Note?
    @State private var permanentNote: Note?
    @FocusState private var isEditorFocused: Bool
    var useStandardHeaderHeight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                iOSPanelHeader(
                    eyebrow: "Notes",
                    title: activeTab.rawValue
                )

                HStack(spacing: 0) {
                    ForEach(CadenceCoreNoteTab.allCases) { tab in
                        iOSNotePanelTabButton(
                            title: tab.rawValue,
                            isSelected: activeTab == tab
                        ) {
                            activeTab = tab
                        }
                    }
                    Spacer()

                    if let note = selectedNote {
                        iOSNoteTemplateMenu(kind: activeTab.noteKind) { template in
                            apply(template, to: note)
                        }
                        .padding(.trailing, 12)
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(height: useStandardHeaderHeight ? iOSPanelHeaderHeight : nil, alignment: .top)

            Divider().background(Theme.borderSubtle)

            if let note = selectedNote {
                ZStack(alignment: .topLeading) {
                    if note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isEditorFocused {
                        Text("Start writing...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.dim.opacity(0.6))
                            .padding(.horizontal, 17)
                            .padding(.vertical, 16)
                    }

                    iOSMarkdownEditor(text: Binding(
                        get: { note.content },
                        set: { update(note, content: $0) }
                    ), isFocused: Binding(
                        get: { isEditorFocused },
                        set: { isEditorFocused = $0 }
                    ))
                    .background(Color.clear)
                }
                .background(Theme.surface)
            } else {
                ProgressView()
                    .tint(Theme.blue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.surface)
        .onAppear(perform: loadNotes)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            loadNotes()
        }
        .onChange(of: activeTab) { _, _ in
            isEditorFocused = false
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isEditorFocused = false
                }
            }
        }
    }

    private var selectedNote: Note? {
        notesSnapshot.note(for: activeTab)
    }

    private var notesSnapshot: CadenceCoreNoteState {
        CadenceCoreNoteState(today: todayNote, week: weekNote, notepad: permanentNote)
    }

    private func loadNotes() {
        let snapshot = CadenceCoreNoteSupport.loadOrCreateCoreNotes(in: modelContext)
        todayNote = snapshot.today
        weekNote = snapshot.week
        permanentNote = snapshot.notepad
    }

    private func update(_ note: Note, content: String) {
        CadenceCoreNoteSupport.update(note, content: content, in: modelContext)
    }

    private func apply(_ template: NoteTemplate, to note: Note) {
        CadenceNoteTemplateInsertionSupport.apply(template, to: note, in: modelContext)
    }
}

struct iOSCompactNotesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(iOSCalendarManager.self) private var calendarManager
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @State private var activePage: iOSCompactNotesPage = .today
    @State private var todayNote: Note?
    @State private var weekNote: Note?
    @State private var permanentNote: Note?
    @State private var selectedMeetingNote: Note?
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            compactHeader

            Picker("Note", selection: $activePage) {
                ForEach(iOSCompactNotesPage.allCases) { page in
                    Text(page.compactTitle).tag(page)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            if let note = selectedCoreNote, let coreTab = activePage.coreTab {
                HStack {
                    Spacer()
                    iOSNoteTemplateMenu(kind: coreTab.noteKind) { template in
                        apply(template, to: note)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }

            Divider().background(Theme.borderSubtle)

            if activePage == .meetings {
                iOSMeetingNotesList(notes: meetingNotes) { note in
                    selectedMeetingNote = note
                }
            } else {
                coreEditor
            }
        }
        .background(Theme.surface.ignoresSafeArea())
        .onAppear(perform: loadNotes)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            loadNotes()
        }
        .onChange(of: activePage) { _, _ in
            isEditorFocused = false
        }
        .sheet(item: $selectedMeetingNote) { note in
            let event = calendarManager.event(withIdentifier: note.calendarEventID)
            iOSEventNoteEditorSheet(
                note: note,
                eventTitle: event.map { iOSCalendarEventSupport.title(for: $0) } ?? note.displayTitle,
                event: event
            )
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isEditorFocused = false
                }
            }
        }
    }

    @ViewBuilder
    private var coreEditor: some View {
        if let note = selectedCoreNote {
            ZStack(alignment: .topLeading) {
                if note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isEditorFocused {
                    Text("Start writing...")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.dim.opacity(0.62))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 20)
                }

                iOSMarkdownEditor(text: Binding(
                    get: { note.content },
                    set: { update(note, content: $0) }
                ), isFocused: Binding(
                    get: { isEditorFocused },
                    set: { isEditorFocused = $0 }
                ))
            }
        } else {
            ProgressView()
                .tint(Theme.blue)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var compactHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.blue)
                .frame(width: 42, height: 42)
                .background(Theme.blue.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Notes")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                Text(activePage.subtitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var selectedCoreNote: Note? {
        guard let coreTab = activePage.coreTab else { return nil }
        return notesSnapshot.note(for: coreTab)
    }

    private var meetingNotes: [Note] {
        allNotes
            .filter { $0.kind == .meeting }
            .sorted { lhs, rhs in
                if lhs.eventDateKey != rhs.eventDateKey {
                    if lhs.eventDateKey.isEmpty { return false }
                    if rhs.eventDateKey.isEmpty { return true }
                    return lhs.eventDateKey > rhs.eventDateKey
                }
                if lhs.eventStartMin != rhs.eventStartMin {
                    return lhs.eventStartMin < rhs.eventStartMin
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    private var notesSnapshot: CadenceCoreNoteState {
        CadenceCoreNoteState(today: todayNote, week: weekNote, notepad: permanentNote)
    }

    private func loadNotes() {
        let snapshot = CadenceCoreNoteSupport.loadOrCreateCoreNotes(in: modelContext)
        todayNote = snapshot.today
        weekNote = snapshot.week
        permanentNote = snapshot.notepad
    }

    private func update(_ note: Note, content: String) {
        CadenceCoreNoteSupport.update(note, content: content, in: modelContext)
    }

    private func apply(_ template: NoteTemplate, to note: Note) {
        CadenceNoteTemplateInsertionSupport.apply(template, to: note, in: modelContext)
    }
}

private enum iOSCompactNotesPage: String, CaseIterable, Identifiable {
    case today
    case week
    case meetings
    case notepad

    var id: Self { self }

    var compactTitle: String {
        switch self {
        case .today: return "Today"
        case .week: return "Week"
        case .meetings: return "Meetings"
        case .notepad: return "Notepad"
        }
    }

    var subtitle: String {
        switch self {
        case .today:
            return CadenceCoreNoteTab.today.subtitle
        case .week:
            return CadenceCoreNoteTab.week.subtitle
        case .meetings:
            return "Notes linked to calendar events"
        case .notepad:
            return CadenceCoreNoteTab.notepad.subtitle
        }
    }

    var coreTab: CadenceCoreNoteTab? {
        switch self {
        case .today:
            return .today
        case .week:
            return .week
        case .meetings:
            return nil
        case .notepad:
            return .notepad
        }
    }
}

private struct iOSMeetingNotesList: View {
    let notes: [Note]
    let open: (Note) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if notes.isEmpty {
                    iOSEmptyPanel(
                        systemImage: "doc.text",
                        title: "No meeting notes yet",
                        subtitle: "Create one from a calendar event."
                    )
                    .padding(.top, 56)
                } else {
                    ForEach(notes) { note in
                        Button {
                            open(note)
                        } label: {
                            iOSMeetingNoteRow(note: note)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.surface)
    }
}

private struct iOSMeetingNoteRow: View {
    let note: Note

    private var detail: String {
        if let date = DateFormatters.date(from: note.eventDateKey) {
            if note.eventStartMin >= 0, note.eventEndMin >= 0 {
                return "\(DateFormatters.shortDate.string(from: date)) · \(TimeFormatters.timeRange(startMin: note.eventStartMin, endMin: note.eventEndMin))"
            }
            return DateFormatters.shortDate.string(from: date)
        }
        return "Updated \(DateFormatters.shortDate.string(from: note.updatedAt))"
    }

    private var preview: String {
        note.content.components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? "Empty note"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.purple)
                .frame(width: 34, height: 34)
                .background(Theme.purple.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(note.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                Text(preview)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.dim.opacity(0.7))
                .padding(.top, 9)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.55), lineWidth: 1)
        }
    }
}

struct iOSNoteTemplateMenu: View {
    let kind: NoteKind
    let apply: (NoteTemplate) -> Void
    @AppStorage(NoteTemplateLibrary.storageKey) private var noteTemplateOverridesRaw = ""

    private var templates: [NoteTemplate] {
        NoteTemplateLibrary.templates(for: kind, overridesRaw: noteTemplateOverridesRaw)
    }

    var body: some View {
        Menu {
            ForEach(templates) { template in
                Button {
                    apply(template)
                } label: {
                    Label(template.title, systemImage: "doc.text")
                }
            }
        } label: {
            Label("Template", systemImage: "doc.badge.plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.blue)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Theme.blue.opacity(0.11))
                .clipShape(Capsule())
        }
        .disabled(templates.isEmpty)
        .opacity(templates.isEmpty ? 0.5 : 1)
    }
}

private struct iOSNotePanelTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Theme.blue : Theme.dim)
                .frame(minWidth: 78, minHeight: 30)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
                .overlay(alignment: .bottom) {
                    if isSelected {
                        Rectangle()
                            .fill(Theme.blue.opacity(0.8))
                            .frame(height: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}
#endif
