#if os(iOS)
import EventKit
import SwiftData
import SwiftUI

/// Fixed height for the notes pane's header when it has to line up with the panes beside it on
/// iPad — the panel title block plus the tab row under it. Replaces a bare `124` that was sized
/// around a subtitle line the header no longer carries.
/// Tall enough for the header block plus a 44pt tab row.
///
/// This was 112, which is under the content's own minimum (~120: a 66pt `iOSPanelHeader` at
/// regular width, a `minHeight: 44` tab row, and 10pt of bottom padding). `.frame(height:)` does
/// not clip, so the tab row was drawn across the divider below it.
let iOSNotesPanelHeaderHeight: CGFloat = 124

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

    /// One header, both hosts.
    ///
    /// It used to be two near-copies: a bespoke three-line block behind a `GeometryReader` for the
    /// iPad pane — eyebrow, tab name, and a subtitle spelling out the tab you had just tapped —
    /// and `iOSPanelHeader` plus a differently-styled tab row for the compact one. They are the
    /// same header: a panel title with the tab bar under it, exactly like macOS's `NotePanel`.
    /// `useStandardHeaderHeight` now only decides whether it is pinned to a fixed height so it
    /// lines up with the panes beside it on iPad.
    ///
    /// The subtitle is gone under the standing rule: a header does not describe the page you are
    /// already looking at, and "Everything you wrote today" under a tab labelled *Today* is a
    /// label for nobody.
    private var notesHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                iOSPanelHeader(eyebrow: "Notes", title: activeTab.rawValue)

                if let note = selectedNote {
                    iOSNoteTemplateMenu(kind: activeTab.noteKind, compact: true) { template in
                        apply(template, to: note)
                    }
                    .padding(.top, 10)
                    .padding(.trailing, 16)
                }
            }

            HStack(spacing: iOSNotesTabMetrics.spacing) {
                ForEach(CadenceCoreNoteTab.allCases) { tab in
                    iOSQuietTabButton(
                        title: tab.compactTitle,
                        isSelected: activeTab == tab
                    ) { activeTabRaw = tab.rawValue }
                }

                Spacer(minLength: 8)

                iOSMarkdownModePicker(mode: editorModeBinding, compact: true)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .frame(height: useStandardHeaderHeight ? iOSNotesPanelHeaderHeight : nil, alignment: .top)
        .background(Theme.surface)
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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
            // On iPhone this is a pushed screen with its navigation bar hidden, so the header
            // carries the back control. On iPad the same view is the root of its own stack (the
            // bar is already hidden there) and there is nothing to go back to.
            iOSPanelHeader(
                eyebrow: "Notes",
                title: activePage.compactTitle,
                onBack: isCompactWidth ? { dismiss() } : nil
            )

            pageTabRow

            if let coreTab = activePage.coreTab {
                HStack(spacing: 8) {
                    iOSMarkdownModePicker(mode: editorModeBinding, compact: true)

                    Spacer(minLength: 8)

                    if let note = selectedCoreNote {
                        iOSNoteTemplateMenu(kind: coreTab.noteKind, compact: true) { template in
                            apply(template, to: note)
                        }
                    }
                }
                .padding(.horizontal, 12)
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
        .iOSHidesCompactNavigationBar()
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

    /// The same tab bar the iPad pane uses. It was a bespoke blue-underline bar — the exact idiom
    /// macOS's `NotesView` deleted, on the grounds that blue is reserved for things that are
    /// actually selected or actionable and a tab bar is neither special nor worth a second idiom.
    /// Four tabs do not fit across a phone, so the row scrolls rather than truncating its labels.
    private var pageTabRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: iOSNotesTabMetrics.spacing) {
                ForEach(iOSCompactNotesPage.allCases) { page in
                    iOSQuietTabButton(
                        title: page.compactTitle,
                        isSelected: activePage == page
                    ) { activePage = page }
                }
            }
            .padding(.horizontal, 12)
        }
        .scrollIndicators(.hidden)
        .padding(.bottom, 8)
    }

    private var selectedCoreNote: Note? {
        guard let coreTab = activePage.coreTab else { return nil }
        return notesSnapshot.note(for: coreTab)
    }

    private var isCompactWidth: Bool {
        horizontalSizeClass == .compact
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
        case .meetings: return "Event Notes"
        case .notepad: return "Notepad"
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

/// The Event Notes list.
///
/// It was a column of shadowed elevated cards; the note list is an *index*, and macOS rewrote its
/// equivalent (`NoteListDayRow`) into flat rows for exactly that reason — a dozen cards fill the
/// screen where a dozen index entries do not. These are the same rows: a day-number column on the
/// left so the numbers line up, whatever the note says beside it, and one press fill at one
/// radius.
private struct iOSMeetingNotesList: View {
    let notes: [Note]
    let open: (Note) -> Void

    var body: some View {
        Group {
            if notes.isEmpty {
                iOSEmptyPanel(
                    systemImage: "doc.text",
                    title: "No meeting notes yet",
                    subtitle: "Create one from a calendar event."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(notes) { note in
                            Button {
                                open(note)
                            } label: {
                                iOSMeetingNoteRow(note: note)
                            }
                            .buttonStyle(.iosPressable)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
    }
}

private struct iOSMeetingNoteRow: View {
    let note: Note

    /// The event's own day, falling back to the last edit so a note with no metadata still files
    /// under a number rather than dropping out of the column.
    private var dayLabel: String {
        let date = DateFormatters.date(from: note.eventDateKey) ?? note.updatedAt
        return DateFormatters.dayNumber.string(from: date)
    }

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
        HStack(alignment: .firstTextBaseline, spacing: iOSNoteListRowMetrics.dayNumberSpacing) {
            Text(dayLabel)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.muted)
                .frame(width: iOSNoteListRowMetrics.dayNumberWidth, alignment: .trailing)

            VStack(alignment: .leading, spacing: 4) {
                Text(note.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.subdued)
                    .lineLimit(1)
                Text(preview)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}

enum iOSNoteListRowMetrics {
    /// Fixed leading slot for the day number, so one- and two-digit days line up as a column
    /// instead of ragging against the title beside them.
    static let dayNumberWidth: CGFloat = 22
    static let dayNumberSpacing: CGFloat = 14
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

    /// One label at both sizes. It was a blue capsule (or a blue tile at radius 9) for an action
    /// that is not the note's primary one — macOS's equivalent header control is a quiet neutral
    /// glyph, and blue there is reserved for the thing you actually came to do. `compact` now only
    /// changes the tile's size, not its idiom.
    private var templateLabel: some View {
        iOSIconTile(
            systemImage: "doc.badge.plus",
            color: Theme.muted,
            size: compact ? 34 : 38,
            iconSize: 13
        )
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel("Apply template")
    }
}

enum iOSNotesTabMetrics {
    /// Cluster spacing for a row of tabs. Deliberately tight, like macOS's
    /// `CadenceQuietPillMetrics.clusterSpacing`: the selected tab's fill is what separates them,
    /// so a wide gap would read as unrelated buttons rather than one control.
    static let spacing: CGFloat = 2
    /// Touch floor.
    static let height: CGFloat = 44
}

/// The iOS translation of macOS's `CadenceQuietTabButton`.
///
/// Text only — no icon, no accent underline, no segmented trough. The selected tab is carried by a
/// neutral `Theme.surfaceHighlight` fill plus a brighter label, and there is exactly one fill
/// layer at one radius. It is deliberately *not* `iOSSegmentedPill`: the mode picker sitting in
/// the same header is a segmented control, and a tab bar that looked identical to it would say the
/// two do the same kind of job.
///
/// Lives here because Notes is the surface that needed it; it belongs in `iOSDesignSystem.swift`
/// alongside `iOSSegmentedPill` once the other iOS tab bars adopt it.
struct iOSQuietTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)

        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Theme.text : Theme.dim)
                // The label sits in a fixed-height frame, so a wrap would overflow the pill rather
                // than grow it. Under compression this must truncate, never wrap.
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minWidth: iOSNotesTabMetrics.height, minHeight: iOSNotesTabMetrics.height)
                .background(shape.fill(isSelected ? Theme.surfaceHighlight : Color.clear))
                .contentShape(shape)
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
#endif
