#if os(iOS)
import EventKit
import SwiftData
import SwiftUI

/// Fixed height for the notes header when it has to line up with the panes beside it on iPad.
///
/// One row: the title, the tab strip and the template control together — 44pt of tab plus 10pt
/// above and 4pt below, so ~58pt of content.
///
/// It was two rows and 120pt. The second held the Live/Edit/Preview picker beside the template
/// menu; when the picker went, a ~54pt band was left carrying one 34pt button at its trailing
/// edge. `.frame(height:)` does not clip, so this must stay at or above the content's own minimum
/// or the row draws across the divider below it — 64 leaves headroom over the measured ~58.
let iOSNotesHeaderStandardHeight: CGFloat = 64

/// **The** iOS Notes surface: the phone's Notes tab, the iPad sidebar's Notes destination, the
/// Today inspector's Notes pane, and every pushed route that lands on Notes.
///
/// It was two views. `iOSNotesPanel` served exactly one host — the iPad Today inspector — and
/// `iOSCompactNotesView` served everything else on *both* shapes, so the split was never phone
/// against iPad; it was one pane against the rest. They had already converged on the same header,
/// tab button and date title, and diverged in the three places shared chrome could not reach:
///
/// - **The tab set.** Three against four: Event Notes existed only on the host that was *not* the
///   pane, so the Today inspector could not reach an event note at all.
/// - **Tab persistence.** `@AppStorage("ios.notes.activeCoreTab")` against plain `@State` — the
///   same strip remembered your tab in one host and forgot it in the other.
/// - **The template-menu gate**, spelled `showsHeaderTemplateMenu` in one and `isCompactWidth` in
///   the other, for one rule.
///
/// The two judgement calls behind the merge, recorded so they are not rediscovered as bugs:
///
/// **Event Notes appears in the Today inspector too.** It is a list of notes rather than a standing
/// note, and the inspector is the narrowest host — but a tab strip that offers different
/// destinations depending on which surface you opened it from is exactly the divergence this merge
/// exists to remove, and the inspector is the one host that already suppresses the title
/// (`showsTitle: false`), which is where the fourth tab's width comes from. The alternative was a
/// `showsEventsTab` flag: a third knob spelling the same host difference the template gate already
/// spelled twice.
///
/// **The tab does not persist.** `@AppStorage` is gone; the key `ios.notes.activeCoreTab` is left
/// orphaned in `UserDefaults` rather than migrated, because it named a three-case enum that no
/// longer describes the strip. Which tab you are on is the same kind of state as `selectedDayKey`
/// — "which note am I looking at" — and that one deliberately resets every launch, because a stored
/// value is a trap. Persisting one and not the other gives you a relaunch that reopens on Weekly
/// with the date snapped back to this week: the header disagreeing with itself. Both reset to
/// Daily, the note that changes every day and the reason you opened this screen. The cost, stated
/// rather than discovered: on the Today inspector, switching to Timeline and back now reopens on
/// Daily instead of the tab you left.
/// **The sidebar came second.** Until this change three of the four tabs had no list at all: Daily,
/// Weekly and Notepad each opened straight into a single standing note, and the only way to reach
/// an older one was the header's date picker. macOS has had a month-grouped index column for all
/// four kinds the whole time. It has it here now too, from the same code — `NotesFoldableListColumn`
/// in `Shared/CadenceNotesListSupport.swift`, the same rows, the same headings, the same fold.
/// What differs is layout and only layout: iPad puts the column beside the editor, iPhone makes it
/// the screen and opens the editor over it.
struct iOSNotesView: View {
    /// Set when this is the Notes tab's root — see `iOSCalendarView.isCompactTabRoot`. It is what
    /// tells the header there is nothing to go back to.
    var isCompactTabRoot = false
    /// Pins the header block to `iOSNotesHeaderStandardHeight` so it lines up with the panes beside
    /// it, the way macOS's `NotePanel` / `TasksPanel` / `SchedulePanel` trio does on Today.
    ///
    /// No iOS caller sets it today: the iPad Today inspector puts `iPadTodayInspectorSwitcher`
    /// above both panels, and that row is what aligns them. It survives as a parameter because it
    /// describes the *host's* layout rather than this view's — the moment a host does place this
    /// beside another panel, the alignment has to come from here.
    var useStandardHeaderHeight = false
    /// Off in Today's two-pane inspector, where `iPadTodayInspectorSwitcher` is the pane's header
    /// and already has "Notes" lit up in it — the same duplication the title itself was fixed for.
    /// The kind tabs stay either way; they are the only thing in this row that is not a restatement.
    var showsTitle = true

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(iOSCalendarManager.self) private var calendarManager
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @State private var activeTab: CadenceMobileNotesTab = .today
    /// Which row is lit in the sidebar, and — at regular width — which note the pane beside it
    /// holds. Resolved against the tab's **unfiltered** notes rather than the listed ones, exactly
    /// as macOS's pages do: a day you jumped to from the date picker but have not written in yet
    /// has no row, and must still stay open in the editor.
    @State private var selectedNoteID: UUID?
    /// Compact width only. The sidebar is the screen there, so the editor is presented over it.
    @State private var presentedNote: Note?
    @State private var selectedMeetingNote: Note?
    /// Set by a notepad row's menu; the `iOSNoteDeletion` modifier owns the confirmation and the
    /// delete.
    @State private var noteToDelete: Note?
    @State private var selectedReferenceNote: Note?
    @State private var selectedReferenceTask: AppTask?
    // Deliberately `@State`, not `@FocusState`. The editor's first responder is a `UITextView`
    // inside a `UIViewRepresentable`; nothing here is ever attached with `.focused(...)`, so a
    // `@FocusState` had no view to move focus to and could not report focus back either. The
    // editor's own `isFocused` binding is what drives — and observes — the text view.
    @State private var isEditorFocused = false
    /// Which day the Daily and Weekly tabs' date picker is pointing at. Deliberately **not**
    /// persisted: a stored day would reopen the app on whatever date you last browsed to, which for
    /// a daily note is a trap — you would write today's entry into a week-old page. It resets to
    /// today every launch, and `scenePhase` re-reads from it rather than resetting it, so a session
    /// that is browsing stays where it is.
    ///
    /// The fold state next to it *is* persisted, and the difference is the point: a collapsed month
    /// cannot mislead you about which note you are writing in. See `CadenceNotesFoldState`.
    @State private var selectedDayKey = DateFormatters.todayKey()

    /// The width this view has actually been handed, which is **not** what the size class says
    /// about it. Zero until the first measurement lands — see `CadenceNotesListMetrics.layout`.
    @State private var hostWidth: CGFloat = 0

    /// The size class only, and deliberately: this is read by the *back control*, which exists
    /// because a pushed compact screen hides its navigation bar, and by the row metrics, which are
    /// a touch tier. Neither is a layout question. Every layout question goes through `notesLayout`.
    private var isCompactWidth: Bool {
        horizontalSizeClass == .compact
    }

    /// One column or two. The size class *and* the width — a regular-width host can still be too
    /// narrow to split, which is what Today's inspector is.
    private var notesLayout: CadenceNotesLayout {
        CadenceNotesListMetrics.layout(isRegularWidth: !isCompactWidth, hostWidth: hostWidth)
    }

    /// The template menu sits in the header where there is room for it, and in the editor's format
    /// row where there is not. The phone's header carries the date, four tabs and a back control on
    /// one 390pt row; the widest thing the date can say is a week range, and it truncated with the
    /// button beside it. The format row is a horizontal scroller, and applying a template is an
    /// insertion like everything else in it.
    ///
    /// One spelling, deliberately. The two views carried this rule twice — as
    /// `horizontalSizeClass == .regular` in one and `!isCompactWidth` in the other — which is how a
    /// gate drifts without anyone changing it.
    ///
    /// It hangs off the *layout* rather than the size class, because the rule is "is there room on
    /// this row", and a 320pt regular-width inspector has less of it than the 390pt phone the note
    /// above measures. In the one-column form the editor is `iOSNoteEditorCover`, whose format row
    /// already carries the template control unconditionally, so the header dropping it moves the
    /// control rather than removing it.
    private var showsHeaderTemplateMenu: Bool {
        notesLayout == .twoColumn
    }

    private var listMetrics: CadenceNotesListMetrics {
        CadenceNotesListMetrics.metrics(isRegularWidth: !isCompactWidth)
    }

    var body: some View {
        VStack(spacing: 0) {
            notesHeader

            Divider().background(Theme.borderSubtle)

            content
        }
        // Measured, not wrapped — the same call `iOSCalendarView` makes and for the same reason. A
        // `GeometryReader` around this `VStack` reads the same width but also becomes the layout
        // container, and this stack holds an editor and a scrolling list that size themselves from
        // what is left over.
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            hostWidth = newWidth
        }
        .background(Theme.surface.ignoresSafeArea())
        .iOSHidesCompactNavigationBar()
        .onAppear {
            loadCoreNotes()
            selectDefaultNote()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            loadCoreNotes()
        }
        .onChange(of: activeTab) { _, _ in
            isEditorFocused = false
            selectDefaultNote()
        }
        // Dropping focus first is the same rule `apply(_:to:)` spells out: the editing surface
        // ignores external writes to its text binding while focused, and swapping to another day's
        // note is exactly such a write. Without this, jumping dates with the caret in the editor
        // would show the old day's text over the new day's note.
        .onChange(of: selectedDayKey) { _, _ in
            isEditorFocused = false
            openNoteForSelectedDay()
        }
        .onChange(of: listedNotes.map(\.id)) { _, _ in
            normalizeSelection()
        }
        .fullScreenCover(item: $presentedNote) { note in
            iOSNoteEditorCover(
                note: note,
                templateKind: activeTab.coreTab?.noteKind,
                title: coverTitle(for: note)
            )
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
        .iOSNoteDeletion(note: $noteToDelete)
    }

    /// One header, every host.
    ///
    /// It used to be an eyebrow reading NOTES over a large title showing the *selected tab*, with
    /// the tab strip immediately below — where the same word was highlighted a second time. The
    /// title described the page you were already on, which is the one thing a page header may not
    /// do, and it cost a whole row to do it. Title and tabs share one row now.
    ///
    /// On a pushed compact screen the navigation bar is hidden, so the header carries the back
    /// control. As the Notes tab's root, and anywhere on iPad, there is nothing to go back to.
    private var notesHeader: some View {
        iOSNotesHeader(
            showsTitle: showsTitle,
            selection: $activeTab,
            onBack: isCompactWidth && !isCompactTabRoot ? { dismiss() } : nil,
            title: {
                iOSNotesDateTitle(tab: activeTab, dayKey: $selectedDayKey)
            }
        ) {
            // Notepad is the one tab whose notes are not manufactured by a date, so it is the one
            // tab that needs a way to say "make another". Same rule as macOS's `NotesListHeader`,
            // which carries a date picker on the dated tabs and a `+` here.
            if activeTab == .notepad {
                iOSNotesHeaderIconButton(systemImage: "plus", label: "New note", action: createNotepadNote)
            }
            // Regular width only — see `showsHeaderTemplateMenu`. At compact width it rides in the
            // editor's format row instead.
            if showsHeaderTemplateMenu, let coreTab = activeTab.coreTab, let note = selectedNote {
                iOSNoteTemplateMenu(kind: coreTab.noteKind, compact: true) { template in
                    apply(template, to: note)
                }
            }
            // AI note actions, gated on the same rule and for the same reason: this row already
            // holds a back control, a date title and four tabs at 390pt. In the one-column form the
            // editor is a cover with its own navigation bar, and the control rides there instead —
            // see `iOSNoteEditorCover`. It renders nothing at all without an API key.
            if showsHeaderTemplateMenu, let note = selectedNote {
                iOSNoteAIActionsMenu(note: note, area: note.area, project: note.project)
            }
        }
        .frame(height: useStandardHeaderHeight ? iOSNotesHeaderStandardHeight : nil, alignment: .top)
        .background(Theme.surface)
    }

    /// One pane or two — the only thing that separates iPhone from iPad here, and the only thing
    /// that separates a wide iPad host from a narrow one.
    ///
    /// **The list is a fixed frame, so whatever is left over is the editor**, and until T-177
    /// nothing checked that anything *was* left over: this branched on the size class with no width
    /// input, and the Today inspector at its 320pt floor drew a 39pt editor. The floor is
    /// `CadenceNotesListMetrics.twoColumnMinimumWidth`, derived from this column and this divider.
    @ViewBuilder
    private var content: some View {
        switch notesLayout {
        case .oneColumn:
            sidebar
        case .twoColumn:
            HStack(spacing: 0) {
                sidebar
                    .frame(width: CadenceNotesListMetrics.regularColumnWidth)

                Divider().background(Theme.borderSubtle)

                editorPane
            }
        }
    }

    /// The month-grouped index column — the same one macOS draws, from the same file.
    @ViewBuilder
    private var sidebar: some View {
        Group {
            if listedNotes.isEmpty {
                iOSEmptyPanel(
                    systemImage: "doc.text",
                    title: emptyStateTitle,
                    subtitle: emptyStateSubtitle
                )
            } else {
                NotesFoldableListColumn(
                    notes: listedNotes,
                    kind: activeTab.noteKind,
                    metrics: listMetrics,
                    dateKey: { listDateKey(for: $0) }
                ) { note in
                    sidebarRow(for: note)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
    }

    /// One row of the index column, with the delete menu on the one tab that can have one.
    ///
    /// **Notepad only, and that is macOS's rule rather than a mobile compromise:** `NotesView`
    /// passes `onDelete` from `NotepadPage` and from nowhere else. A daily, weekly or event note is
    /// manufactured by its date or its calendar event and reappears the moment you look at that
    /// day again, so deleting one is a no-op behind a confirmation. A notepad note is typed from
    /// nothing, and until T-226 nothing on this platform could remove one.
    ///
    /// The menu is attached conditionally rather than emptied conditionally: a `.contextMenu` whose
    /// content resolves to nothing still arms the long-press, so every dated row would answer a
    /// press with a blank panel.
    @ViewBuilder
    private func sidebarRow(for note: Note) -> some View {
        let row = Button {
            open(note)
        } label: {
            listRow(for: note)
        }
        .buttonStyle(.iosPressable)

        if activeTab == .notepad {
            row.contextMenu {
                iOSNoteDeleteMenuButton(note: note) { noteToDelete = $0 }
            }
        } else {
            row
        }
    }

    @ViewBuilder
    private func listRow(for note: Note) -> some View {
        switch activeTab {
        case .today:
            DailyNoteListRow(note: note, isSelected: isSelected(note), metrics: listMetrics)
        case .week:
            WeeklyNoteListRow(note: note, isSelected: isSelected(note), metrics: listMetrics)
        case .notepad:
            NotepadNoteListRow(note: note, isSelected: isSelected(note), metrics: listMetrics)
        case .events:
            // `showsDate: false` for the same reason macOS passes it: the month heading above and
            // the day number beside have already said the date, so the detail line is the time.
            MeetingNoteListRow(note: note, isSelected: isSelected(note), showsDate: false, metrics: listMetrics)
        }
    }

    /// Regular width only. At compact width the editor is presented over the sidebar instead — see
    /// `presentedNote`.
    @ViewBuilder
    private var editorPane: some View {
        if let note = selectedNote {
            iOSMarkdownEditingSurface(
                text: Binding(
                    get: { note.content },
                    set: { update(note, content: $0) }
                ),
                isFocused: $isEditorFocused,
                placeholder: "Start writing...",
                referenceNotes: allNotes,
                referenceTasks: allTasks,
                onOpenReference: openMarkdownReference,
                templateKind: showsHeaderTemplateMenu ? nil : activeTab.coreTab?.noteKind,
                applyTemplate: showsHeaderTemplateMenu ? nil : { apply($0, to: note) }
            )
            .id(note.id)
            // The page-clearance reset this used to carry now lives on the strips themselves, in
            // `iOSMarkdownAccessoryViews` — the defect belonged to them, not to this host, and a
            // second host hit it independently. One mechanism, not one per host.
        } else {
            // Title only, and macOS's exact wording. This is a "nothing selected" state, not an
            // empty list — `NotesEditorPlaceholder` on macOS carries no subtitle for the same
            // reason, and when the column beside it is *also* empty a subtitle here just prints the
            // list's own empty-state line twice.
            iOSEmptyPanel(systemImage: "doc.text", title: placeholderTitle, subtitle: "")
        }
    }

    /// macOS's three placeholders, tab for tab.
    private var placeholderTitle: String {
        switch activeTab {
        case .today, .notepad: return "Select a note"
        case .week: return "Select a week"
        case .events: return "Select a meeting note"
        }
    }

    // MARK: - The tab's notes

    /// Every note of the active kind, unfiltered and in list order. Selection resolves against this
    /// rather than `listedNotes` — see `selectedNoteID`.
    private var notesForActiveTab: [Note] {
        switch activeTab {
        case .today:
            return allNotes.filter { $0.kind == .daily }.sorted { $0.dateKey > $1.dateKey }
        case .week:
            return allNotes.filter { $0.kind == .weekly }.sorted { $0.weekKey > $1.weekKey }
        case .notepad:
            return NotesListVisibility.notepadNotes(allNotes)
        case .events:
            return NotesListVisibility.meetingNotes(allNotes)
        }
    }

    /// What actually gets a row. The filters are `NotesListVisibility`'s, so the phone, the iPad and
    /// the Mac list exactly the same notes — including the pinned current day and week, which are
    /// listed even when blank because they are the way in to writing today.
    private var listedNotes: [Note] {
        switch activeTab {
        case .today:
            return NotesListVisibility.dailyNotes(notesForActiveTab, todayKey: DateFormatters.todayKey())
        case .week:
            return NotesListVisibility.weeklyNotes(notesForActiveTab, currentWeekKey: DateFormatters.currentWeekKey())
        case .notepad, .events:
            // Both are unfiltered by design — see `NotesListVisibility.notepadNotes` and
            // `.meetingNotes`.
            return notesForActiveTab
        }
    }

    /// The `yyyy-MM-dd` key each row files under, per tab. Same four answers macOS's four pages
    /// give, so a month heading holds the same notes on every platform.
    private func listDateKey(for note: Note) -> String {
        switch activeTab {
        case .today: return note.dateKey
        case .week: return NotesListGrouping.weekStartDateKey(forWeekKey: note.weekKey)
        case .notepad: return DateFormatters.dateKey(from: note.createdAt)
        case .events: return NotesListVisibility.meetingDayKey(for: note)
        }
    }

    private var selectedNote: Note? {
        guard let selectedNoteID else { return nil }
        return notesForActiveTab.first { $0.id == selectedNoteID }
    }

    private func isSelected(_ note: Note) -> Bool {
        selectedNoteID == note.id
    }

    /// Same words macOS uses, tab for tab. "Exact same sidebar" is a claim about vocabulary before
    /// it is one about point sizes.
    private var emptyStateTitle: String {
        switch activeTab {
        case .today, .week: return "Nothing written yet"
        case .notepad: return "No notes yet"
        case .events: return "No meeting notes yet"
        }
    }

    private var emptyStateSubtitle: String {
        switch activeTab {
        case .today: return "Days you write on appear here. Pick a date above to open one."
        case .week: return "Weeks you write in appear here. Pick a date above to open one."
        case .notepad: return "Notepad holds notes that belong to no particular day."
        case .events: return "Create one from a calendar event."
        }
    }

    private func coverTitle(for note: Note) -> String {
        switch activeTab {
        case .today, .week:
            return CadenceNoteDateNavigation.title(for: activeTab, dayKey: listDateKey(for: note)) ?? note.displayTitle
        case .notepad, .events:
            return note.displayTitle
        }
    }

    // MARK: - Selection and creation

    /// In the two-column form selecting a row *is* opening it — `editorPane` beside the list is
    /// already showing it. In the one-column form there is no pane, so the editor is presented over
    /// the list. That form is now reachable at regular width too (a host under
    /// `CadenceNotesListMetrics.twoColumnMinimumWidth`), and this guard has to follow the layout
    /// rather than the size class or a tapped row in Today's inspector would set `selectedNoteID`
    /// and show nothing at all.
    private func open(_ note: Note) {
        selectedNoteID = note.id
        guard notesLayout == .oneColumn else { return }
        // One branch, and it is deliberate: an event note is bound to a calendar event, and
        // `iOSEventNoteEditorSheet` is the editor that carries that event's title and refreshes its
        // metadata. The other three kinds have no such attachment and open in the plain editor.
        if activeTab == .events {
            selectedMeetingNote = note
        } else {
            presentedNote = note
        }
    }

    /// Keeps the three standing notes for `selectedDayKey` on disk. Creating a day's note by
    /// browsing to it is deliberate and matches macOS: a blank note is invisible in every list,
    /// because the lists filter to notes with content.
    @discardableResult
    private func loadCoreNotes() -> CadenceCoreNoteState {
        CadenceCoreNoteSupport.loadOrCreateCoreNotes(in: modelContext, dayKey: selectedDayKey)
    }

    /// What a tab lands on when you arrive at it: the note for the day the header is pointing at on
    /// the dated tabs, the newest row otherwise.
    private func selectDefaultNote() {
        if let coreTab = activeTab.coreTab, coreTab != .notepad,
           let note = loadCoreNotes().note(for: coreTab) {
            selectedNoteID = note.id
            return
        }
        selectedNoteID = listedNotes.first?.id
    }

    /// The date picker is this surface's "go to date", the same job macOS's `NotesDateJumpButton`
    /// does — so picking a day opens that day's note rather than only re-filtering the column.
    private func openNoteForSelectedDay() {
        guard let coreTab = activeTab.coreTab, coreTab != .notepad,
              let note = loadCoreNotes().note(for: coreTab) else { return }
        open(note)
    }

    private func normalizeSelection() {
        guard selectedNoteID == nil || !notesForActiveTab.contains(where: { $0.id == selectedNoteID }) else { return }
        selectedNoteID = listedNotes.first?.id
    }

    private func createNotepadNote() {
        guard let note = try? NoteMigrationService.createPermanentNote(in: modelContext) else { return }
        open(note)
    }

    private func update(_ note: Note, content: String) {
        CadenceCoreNoteSupport.update(note, content: content, in: modelContext)
    }

    /// Clearing focus first is load-bearing, not tidiness.
    ///
    /// `iOSMarkdownEditingSurface` ignores external writes to its `text` binding while the editor
    /// is focused — it has to, or the debounced commit would fight the keystrokes it just saved.
    /// A SwiftUI `Menu` does **not** resign the text view's first responder, so picking a template
    /// with the caret in the editor wrote `note.content` into a binding nobody was reading: the
    /// template vanished, and the stale draft then committed back over it. Verified on device —
    /// picking "Daily Plan" with the editor focused produced an empty note and "0 words".
    ///
    /// Dropping focus commits the draft and lets the surface accept the write on the next runloop
    /// turn, so the template lands on top of what the user had actually typed.
    private func apply(_ template: NoteTemplate, to note: Note) {
        guard isEditorFocused else {
            CadenceNoteTemplateInsertionSupport.apply(template, to: note, in: modelContext)
            return
        }

        isEditorFocused = false
        DispatchQueue.main.async {
            CadenceNoteTemplateInsertionSupport.apply(template, to: note, in: modelContext)
        }
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

/// The Notes header's quiet trailing glyph — Notepad's "new note".
///
/// Same tile, size and ink as `iOSNoteTemplateMenu`'s label, because they sit side by side in the
/// same row and are the same kind of control. Blue is reserved for the thing you came to do; making
/// a second note is not it.
private struct iOSNotesHeaderIconButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            iOSIconTile(systemImage: systemImage, color: Theme.muted, size: 34, iconSize: 13)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel(label)
    }
}

/// The editor as a whole screen, for the width that has only one pane.
///
/// iPad shows the same editor as `iOSNotesView.editorPane`, inline beside the sidebar. This is the
/// same surface with a navigation bar around it — the layout difference iPhone and iPad are allowed
/// to have, and not a second editor: both are `iOSMarkdownEditingSurface` over the same binding,
/// committing through `CadenceCoreNoteSupport.update`.
///
/// The template menu rides in the editor's own format row here, because at compact width the header
/// row has no space for it. See `iOSNotesView.showsHeaderTemplateMenu`.
/// The one-column form's editor: the whole screen, over the list column that presented it.
///
/// **Two hosts, deliberately internal.** The Notes tab presents it for a daily/weekly/notepad note,
/// and `iOSListNotesView` presents it for a list note — the same editor, the same format row, the
/// same AI menu, so a note does not gain or lose chrome depending on which column you reached it
/// from. It was `private` while there was one host; a second copy of it would have been a second
/// place the template menu could go missing.
struct iOSNoteEditorCover: View {
    let note: Note
    let templateKind: NoteKind?
    let title: String
    /// The list a task created from inside this note should land in — set when the note is a list
    /// note, so `[[task:` capture from a project's note files into that project.
    var embeddedTaskArea: Area?
    var embeddedTaskProject: Project?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @State private var isEditorFocused = false
    @State private var selectedReferenceNote: Note?
    @State private var selectedReferenceTask: AppTask?

    var body: some View {
        NavigationStack {
            iOSMarkdownEditingSurface(
                text: Binding(
                    get: { note.content },
                    set: { CadenceCoreNoteSupport.update(note, content: $0, in: modelContext) }
                ),
                isFocused: $isEditorFocused,
                placeholder: "Start writing...",
                referenceNotes: allNotes,
                referenceTasks: allTasks,
                onOpenReference: openMarkdownReference,
                embeddedTaskArea: embeddedTaskArea,
                embeddedTaskProject: embeddedTaskProject,
                templateKind: templateKind,
                applyTemplate: templateKind == nil ? nil : { apply($0) }
            )
            .id(note.id)
            .background(Theme.surface.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        isEditorFocused = false
                        dismiss()
                    }
                }

                // The one-column form's AI actions control. The notes header behind this cover has
                // the same control at regular width; here the navigation bar is the row above the
                // editor, so this is the same affordance in the only place it fits. Absent without
                // an API key.
                ToolbarItem(placement: .primaryAction) {
                    iOSNoteAIActionsMenu(note: note, area: note.area, project: note.project)
                }
            }
        }
        .iOSMarkdownReferenceSheets(
            selectedNote: $selectedReferenceNote,
            selectedTask: $selectedReferenceTask,
            referenceNotes: allNotes,
            referenceTasks: allTasks
        )
        .preferredColorScheme(.dark)
    }

    /// Same focus-drop rule as `iOSNotesView.apply(_:to:)`; see the note there.
    private func apply(_ template: NoteTemplate) {
        guard isEditorFocused else {
            CadenceNoteTemplateInsertionSupport.apply(template, to: note, in: modelContext)
            return
        }

        isEditorFocused = false
        DispatchQueue.main.async {
            CadenceNoteTemplateInsertionSupport.apply(template, to: note, in: modelContext)
        }
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

/// The Notes header: back control, the constant word "Notes", and the tab strip, all on one row.
///
/// The title is deliberately *not* the selected tab. It used to be, under an eyebrow that also
/// read NOTES, directly above a strip where the same tab was highlighted again — three ways of
/// saying one thing, over two rows. The strip stays a plain row rather than a scroller: the labels
/// (`CadenceMobileNotesTab.shortLabel`) are budgeted to fit beside the title on the narrowest
/// phone, and a strip that has to be scrolled sideways to find a tab is the problem this replaced.
///
/// The title is now the *date* on the two dated tabs, and it is also the control that changes it —
/// see `iOSNotesDateTitle`. That is the only place it could go: at 390pt this row already holds a
/// back control, a title, four tabs and the template button, so a second button or a second row
/// were both worse than reusing the slot that was spending itself on a word that never changed.
private struct iOSNotesHeader<Title: View, Trailing: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    var showsTitle = true
    /// The strip took its tabs as an array of value types while two hosts offered two different
    /// sets. There is one host and one set now, so it takes the selection directly — an
    /// intermediate model whose only job was to let the sets differ is a fork with the fork
    /// removed.
    @Binding var selection: CadenceMobileNotesTab
    /// Set on a pushed compact screen whose navigation bar is hidden. See
    /// `iOSHidesCompactNavigationBar()`.
    var onBack: (() -> Void)? = nil
    /// The leading title — a date button on Daily and Weekly, the word "Notes" elsewhere.
    @ViewBuilder var title: () -> Title
    /// The template control. It had a row of its own — a ~54pt band holding one 34pt button at the
    /// trailing edge, left behind when the Live/Edit/Preview picker that shared it was removed.
    /// A row existing to hold a single button is the header saying nothing twice as tall.
    @ViewBuilder var trailing: () -> Trailing

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        HStack(spacing: 8) {
            if let onBack {
                iOSHeaderBackButton(action: onBack)
                    .padding(.leading, -8)
                    .padding(.trailing, -4)
            }

            if showsTitle {
                // Same priority as the tab strip, and both above the `Spacer`. Without this the
                // spacer — greedy by nature, and at the default priority the title also had —
                // claimed the slack first and squeezed a title that had 25pt of room going spare:
                // the week range rendered "Aug 17…" on a row that was not actually full.
                title()
                    .layoutPriority(1)

                Spacer(minLength: 8)
            }

            HStack(spacing: iOSNotesTabMetrics.spacing) {
                ForEach(CadenceMobileNotesTab.allCases) { tab in
                    iOSQuietTabButton(
                        title: tab.shortLabel,
                        isSelected: selection == tab,
                        horizontalPadding: isRegularWidth
                            ? iOSNotesTabMetrics.horizontalPadding
                            : iOSNotesTabMetrics.compactHorizontalPadding,
                        action: { selection = tab }
                    )
                }
            }
            // `fixedSize`, not just a layout priority. Each tab is a `.frame(minWidth:)` with no
            // maximum — a flexible view — so an `HStack` will happily hand the strip less than its
            // ideal and let four labels truncate to "To… W… Ev… Pad" while 40pt of the row sat
            // unused in the spacer. Priority alone did not fix that; refusing to compress does.
            //
            // The strip names the destinations and the title names one date, so if the row ever is
            // genuinely over budget the date is the one that may shorten: "Aug 17" going to "Aug…"
            // costs a glance, a tab going to "Eve…" costs the label its meaning.
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)

            // Without the title the strip is the only thing on the row, so it leads rather than
            // hanging off the trailing edge with nothing opposite it.
            if !showsTitle {
                Spacer(minLength: 0)
            }

            trailing()
        }
        .padding(.horizontal, isRegularWidth ? 14 : 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}

/// The Notes header's leading title: the date on Daily and Weekly, the constant word on the two
/// tabs that have no date, and on Daily/Weekly it is also the button that changes the date.
///
/// **This is the whole date-navigation feature on iOS and iPadOS.** Before it, both surfaces went
/// through `CadenceCoreNoteSupport.loadOrCreateCoreNotes`, which hardcoded `todayKey()` — the only
/// way to reach an older daily note was Search, which finds a note only if you had already written
/// something in it. macOS has had a calendar jump the whole time
/// (`NotesView.NotesDateJumpButton`); this is the same capability in the space a phone actually has.
///
/// Picking a day you have never used **creates** that day's note, because `dailyNote(for:)` does.
/// That is deliberate and matches macOS: an empty note for a browsed day is invisible everywhere it
/// would matter, since the note lists filter to notes with content
/// (`NotesListVisibilitySupport`).
///
/// The control itself is `iOSDateJumpTitle`, shared with all four calendar surfaces. What is left
/// here is the Notes-specific half: which tabs have a date at all, what that date reads as, and the
/// constant word the other two fall back to.
struct iOSNotesDateTitle: View {
    let tab: CadenceMobileNotesTab
    /// The constant word to fall back to on a tab with no date.
    var fallback: String = "Notes"
    @Binding var dayKey: String

    private var label: String? {
        CadenceNoteDateNavigation.title(for: tab, dayKey: dayKey)
    }

    /// The picker's selection, as a `Date`. `iOSDateJumpTitle` and `MonthCalendarPanel` speak
    /// `Date`; storage speaks `"yyyy-MM-dd"`. Converting in the binding rather than holding a second
    /// `@State` date is what keeps them from drifting apart — there is one source of truth and it is
    /// the key. The calendar's title binds a `Date` outright, which is why the shared control speaks
    /// that and this call site does the conversion.
    private var selection: Binding<Date> {
        Binding(
            get: { DateFormatters.date(from: dayKey) ?? Date() },
            set: { dayKey = DateFormatters.dateKey(from: $0) }
        )
    }

    var body: some View {
        if let label {
            iOSDateJumpTitle(
                date: selection,
                label: label,
                isAtNow: CadenceNoteDateNavigation.isCurrentPeriod(tab: tab, dayKey: dayKey),
                // `.inline`, not the calendar's `.page`: this title shares a 390pt row with four
                // tabs and sometimes a back control. See `iOSDateJumpTitleMetrics`.
                metrics: .inline,
                // The thing you are returning to on Weekly is a week, not a day.
                nowTitle: tab == .week ? "This week" : "Today",
                accessibilityLabel: tab == .week
                    ? "Week of \(label). Choose a week"
                    : "\(label). Choose a date"
            )
        } else {
            // 17 either way, unlike the date: "Notes" fits at any width, and the two never appear
            // together. `fixedSize` because a constant word has no slack to give the tab strip.
            Text(fallback)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

enum iOSNotesTabMetrics {
    /// Cluster spacing for a row of tabs. Deliberately tight, like macOS's
    /// `CadenceQuietPillMetrics.clusterSpacing`: the selected tab's fill is what separates them,
    /// so a wide gap would read as unrelated buttons rather than one control.
    static let spacing: CGFloat = 2
    /// Touch floor.
    static let height: CGFloat = 44
    /// Default label inset. See `compactHorizontalPadding` for why the phone uses less.
    static let horizontalPadding: CGFloat = 12
    /// The phone's inset. The Notes header carries a date and four tabs on one 390pt row, and the
    /// widest thing the date can say is a week range — `Aug 17–23` beside `Daily Weekly Events
    /// Pad`. At the default 12 the labels truncated. Moving the template menu into the editor's
    /// format row bought most of the shortfall back, but not all of it: at 6 the row lands with
    /// about 12pt to spare, so this stays. The 44pt `minWidth` floor is untouched at any inset, so
    /// the shortest label ("Pad") and every touch target are exactly as wide as before.
    static let compactHorizontalPadding: CGFloat = 6
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
    /// Tightened on the phone, where the Notes header now spends part of its row on the date. At
    /// 12 the four labels truncated to "To… We… Eve… Pad" on a 390pt screen — the strip stopped
    /// naming its own tabs, which is worse than a narrower fill around a label that still reads.
    /// The 44pt `minWidth` below is untouched, so nothing loses its touch target and the shortest
    /// label ("Pad") is exactly as wide as it was.
    var horizontalPadding: CGFloat = iOSNotesTabMetrics.horizontalPadding
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
                .padding(.horizontal, horizontalPadding)
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
