#if os(iOS)
import EventKit
import SwiftData
import SwiftUI

struct iOSNotesPanel: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @State private var todayNote: Note?
    @State private var weekNote: Note?
    @State private var permanentNote: Note?
    @State private var selectedReferenceNote: Note?
    @State private var selectedReferenceTask: AppTask?
    @AppStorage("ios.notes.activeCoreTab") private var activeTabRaw = CadenceCoreNoteTab.today.rawValue
    @AppStorage(iOSMarkdownEditorPreferences.modeKey) private var editorModeRaw = iOSMarkdownEditorPreferences.defaultMode.rawValue
    @AppStorage(iOSMarkdownEditorPreferences.didMigrateLiveDefaultKey) private var didMigrateLiveEditorDefault = false
    @FocusState private var isEditorFocused: Bool
    var useStandardHeaderHeight = false

    private var activeTab: CadenceCoreNoteTab {
        get { CadenceCoreNoteTab(rawValue: activeTabRaw) ?? .today }
        set { activeTabRaw = newValue.rawValue }
    }

    private var editorMode: iOSMarkdownEditorMode {
        get { iOSMarkdownEditorMode(rawValue: editorModeRaw) ?? iOSMarkdownEditorPreferences.defaultMode }
        set { editorModeRaw = newValue.rawValue }
    }

    private var editorModeBinding: Binding<iOSMarkdownEditorMode> {
        Binding(
            get: { editorMode },
            set: { editorModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            notesHeader

            Divider().background(Theme.borderSubtle)

            if let note = selectedNote {
                iOSMarkdownEditingSurface(
                    text: Binding(
                        get: { note.content },
                        set: { update(note, content: $0) }
                    ),
                    isFocused: Binding(
                        get: { isEditorFocused },
                        set: { isEditorFocused = $0 }
                    ),
                    mode: editorModeBinding,
                    placeholder: "Start writing...",
                    referenceNotes: allNotes,
                    referenceTasks: allTasks,
                    onOpenReference: openMarkdownReference
                )
                .id(note.id)
            } else {
                ProgressView()
                    .tint(Theme.blue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.surface)
        .onAppear {
            migrateLiveEditorDefaultIfNeeded()
            loadNotes()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            loadNotes()
        }
        .onChange(of: activeTab) { _, _ in
            isEditorFocused = false
        }
        .iOSMarkdownReferenceSheets(
            selectedNote: $selectedReferenceNote,
            selectedTask: $selectedReferenceTask,
            referenceNotes: allNotes,
            referenceTasks: allTasks
        )
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
    private var notesHeader: some View {
        if useStandardHeaderHeight {
            regularNotesHeader
        } else {
            compactNotesHeader
        }
    }

    private var regularNotesHeader: some View {
        GeometryReader { proxy in
            regularNotesHeaderContent(isNarrow: proxy.size.width < 320)
        }
        .frame(height: 124, alignment: .top)
        .background(Theme.surface)
    }

    private func regularNotesHeaderContent(isNarrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Notes")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .textCase(.uppercase)
                        .kerning(0.8)

                    Text(activeTab.rawValue)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    if !isNarrow {
                        Text(activeTab.subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.dim)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                iOSMarkdownModePicker(mode: editorModeBinding, compact: isNarrow)
            }

            HStack(spacing: 8) {
                ForEach(CadenceCoreNoteTab.allCases) { tab in
                    iOSNotePanelTabButton(
                        title: tab.compactTitle,
                        isSelected: activeTab == tab
                    ) { activeTabRaw = tab.rawValue }
                }

                Spacer(minLength: 8)

                if let note = selectedNote {
                    iOSNoteTemplateMenu(kind: activeTab.noteKind, compact: true) { template in
                        apply(template, to: note)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var compactNotesHeader: some View {
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
                    ) { activeTabRaw = tab.rawValue }
                }
                Spacer()

                iOSMarkdownModePicker(mode: editorModeBinding, compact: true)
                    .padding(.trailing, 8)

                if let note = selectedNote {
                    iOSNoteTemplateMenu(kind: activeTab.noteKind) { template in
                        apply(template, to: note)
                    }
                    .padding(.trailing, 12)
                }
            }
            .padding(.horizontal, 12)
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

    private func migrateLiveEditorDefaultIfNeeded() {
        guard !didMigrateLiveEditorDefault else { return }
        if editorModeRaw == iOSMarkdownEditorMode.edit.rawValue {
            editorModeRaw = iOSMarkdownEditorPreferences.defaultMode.rawValue
        }
        didMigrateLiveEditorDefault = true
    }

    private func update(_ note: Note, content: String) {
        CadenceCoreNoteSupport.update(note, content: content, in: modelContext)
    }

    private func apply(_ template: NoteTemplate, to note: Note) {
        CadenceNoteTemplateInsertionSupport.apply(template, to: note, in: modelContext)
    }

    private func openMarkdownReference(_ target: MarkdownReferenceDisplayTarget) {
        switch target.kind {
        case .note:
            selectedReferenceNote = iOSMarkdownReferenceResolver.note(for: target, in: allNotes)
        case .task:
            selectedReferenceTask = iOSMarkdownReferenceResolver.task(for: target, in: allTasks)
        }
    }
}

struct iOSCompactNotesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(iOSCalendarManager.self) private var calendarManager
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @State private var activePage: iOSCompactNotesPage = .today
    @State private var todayNote: Note?
    @State private var weekNote: Note?
    @State private var permanentNote: Note?
    @State private var selectedMeetingNote: Note?
    @State private var selectedReferenceNote: Note?
    @State private var selectedReferenceTask: AppTask?
    @AppStorage(iOSMarkdownEditorPreferences.modeKey) private var editorModeRaw = iOSMarkdownEditorPreferences.defaultMode.rawValue
    @AppStorage(iOSMarkdownEditorPreferences.didMigrateLiveDefaultKey) private var didMigrateLiveEditorDefault = false
    @FocusState private var isEditorFocused: Bool

    private var editorMode: iOSMarkdownEditorMode {
        get { iOSMarkdownEditorMode(rawValue: editorModeRaw) ?? iOSMarkdownEditorPreferences.defaultMode }
        set { editorModeRaw = newValue.rawValue }
    }

    private var editorModeBinding: Binding<iOSMarkdownEditorMode> {
        Binding(
            get: { editorMode },
            set: { editorModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            compactHeader
            pageTabRow

            if let coreTab = activePage.coreTab {
                HStack {
                    iOSMarkdownModePicker(mode: editorModeBinding)

                    Spacer()

                    if let note = selectedCoreNote {
                        iOSNoteTemplateMenu(kind: coreTab.noteKind) { template in
                            apply(template, to: note)
                        }
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
        .onAppear {
            migrateLiveEditorDefaultIfNeeded()
            loadNotes()
        }
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
        .iOSMarkdownReferenceSheets(
            selectedNote: $selectedReferenceNote,
            selectedTask: $selectedReferenceTask,
            referenceNotes: allNotes,
            referenceTasks: allTasks
        )
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
            iOSMarkdownEditingSurface(
                text: Binding(
                    get: { note.content },
                    set: { update(note, content: $0) }
                ),
                isFocused: Binding(
                    get: { isEditorFocused },
                    set: { isEditorFocused = $0 }
                ),
                mode: editorModeBinding,
                placeholder: "Start writing...",
                referenceNotes: allNotes,
                referenceTasks: allTasks,
                onOpenReference: openMarkdownReference
            )
            .id(note.id)
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

    // Matches macOS NotesView's tab treatment: left-aligned text tabs with a blue underline on
    // the selected tab, instead of a native `.pickerStyle(.segmented)` control stretched into
    // four equal-width boxes (which looked like generic system chrome, not part of the app).
    private var pageTabRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                ForEach(iOSCompactNotesPage.allCases) { page in
                    Button {
                        activePage = page
                    } label: {
                        Text(page.compactTitle)
                            .font(.system(size: 15, weight: activePage == page ? .semibold : .medium))
                            .foregroundStyle(activePage == page ? Theme.text : Theme.dim)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .overlay(alignment: .bottom) {
                                if activePage == page {
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(Theme.blue)
                                        .frame(height: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)

            Divider().background(Theme.borderSubtle)
        }
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

    private func migrateLiveEditorDefaultIfNeeded() {
        guard !didMigrateLiveEditorDefault else { return }
        if editorModeRaw == iOSMarkdownEditorMode.edit.rawValue {
            editorModeRaw = iOSMarkdownEditorPreferences.defaultMode.rawValue
        }
        didMigrateLiveEditorDefault = true
    }

    private func update(_ note: Note, content: String) {
        CadenceCoreNoteSupport.update(note, content: content, in: modelContext)
    }

    private func apply(_ template: NoteTemplate, to note: Note) {
        CadenceNoteTemplateInsertionSupport.apply(template, to: note, in: modelContext)
    }

    private func openMarkdownReference(_ target: MarkdownReferenceDisplayTarget) {
        switch target.kind {
        case .note:
            selectedReferenceNote = iOSMarkdownReferenceResolver.note(for: target, in: allNotes)
        case .task:
            selectedReferenceTask = iOSMarkdownReferenceResolver.task(for: target, in: allTasks)
        }
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
        let preview = CadenceMarkdownPresentationSupport.plainPreviewText(from: note.content, limit: 140)
        return preview.isEmpty ? "Empty note" : preview
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.purple)
                .frame(width: 34, height: 34)
                .background(Theme.purple.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))

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
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceCard(background: Theme.surfaceElevated, cornerRadius: Theme.radiusCard, shadowRadius: 10, shadowY: 4)
    }
}

struct iOSNoteTemplateMenu: View {
    let kind: NoteKind
    var compact = false
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
            templateLabel
        }
        .disabled(templates.isEmpty)
        .opacity(templates.isEmpty ? 0.5 : 1)
    }

    @ViewBuilder
    private var templateLabel: some View {
        if compact {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.blue)
                .frame(width: 34, height: 34)
                .background(Theme.blue.opacity(0.11))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else {
            Label("Template", systemImage: "doc.badge.plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.blue)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Theme.blue.opacity(0.11))
                .clipShape(Capsule())
        }
    }
}

private struct iOSNotePanelTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? Theme.text : Theme.dim)
                .frame(minWidth: 62, minHeight: 32)
                .padding(.horizontal, 8)
                .background(isSelected ? Theme.blue.opacity(0.16) : Theme.surfaceElevated.opacity(0.24))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSelected ? Theme.blue.opacity(0.28) : Theme.borderSubtle.opacity(0.28), lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
#endif
