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
    @State private var todayNote: Note?
    @State private var weekNote: Note?
    @State private var permanentNote: Note?
    @State private var selectedMeetingNote: Note?
    @State private var selectedReferenceNote: Note?
    @State private var selectedReferenceTask: AppTask?
    // Deliberately `@State`, not `@FocusState`. The editor's first responder is a `UITextView`
    // inside a `UIViewRepresentable`; nothing here is ever attached with `.focused(...)`, so a
    // `@FocusState` had no view to move focus to and could not report focus back either. The
    // editor's own `isFocused` binding is what drives — and observes — the text view.
    @State private var isEditorFocused = false
    /// Which day the Daily and Weekly tabs are showing. Deliberately **not** persisted: a stored
    /// day would reopen the app on whatever date you last browsed to, which for a daily note is a
    /// trap — you would write today's entry into a week-old page. It resets to today every launch,
    /// and `scenePhase` re-reads from it rather than resetting it, so a session that is browsing
    /// stays where it is.
    @State private var selectedDayKey = DateFormatters.todayKey()

    private var isCompactWidth: Bool {
        horizontalSizeClass == .compact
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
    private var showsHeaderTemplateMenu: Bool {
        !isCompactWidth
    }

    var body: some View {
        VStack(spacing: 0) {
            notesHeader

            Divider().background(Theme.borderSubtle)

            if activeTab == .events {
                // The index is the only place on this screen that shows note *text*, so the title
                // index is built here rather than in `body` — the other three tabs are editors and
                // would pay for a map nothing reads. See `MarkdownTaskEmbedTitleCache`.
                iOSMeetingNotesList(
                    notes: meetingNotes,
                    taskTitles: MarkdownTaskEmbedTitleCache.titles(for: allTasks)
                ) { note in
                    selectedMeetingNote = note
                }
            } else {
                coreEditor
            }
        }
        .background(Theme.surface.ignoresSafeArea())
        .iOSHidesCompactNavigationBar()
        .onAppear(perform: loadNotes)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            loadNotes()
        }
        .onChange(of: activeTab) { _, _ in
            isEditorFocused = false
        }
        // Dropping focus first is the same rule `apply(_:to:)` spells out: the editing surface
        // ignores external writes to its text binding while focused, and swapping to another day's
        // note is exactly such a write. Without this, jumping dates with the caret in the editor
        // would show the old day's text over the new day's note.
        .onChange(of: selectedDayKey) { _, _ in
            isEditorFocused = false
            loadNotes()
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
            // Regular width only — see `showsHeaderTemplateMenu`. At compact width it rides in the
            // editor's format row instead.
            if showsHeaderTemplateMenu, let coreTab = activeTab.coreTab, let note = selectedNote {
                iOSNoteTemplateMenu(kind: coreTab.noteKind, compact: true) { template in
                    apply(template, to: note)
                }
            }
        }
        .frame(height: useStandardHeaderHeight ? iOSNotesHeaderStandardHeight : nil, alignment: .top)
        .background(Theme.surface)
    }

    @ViewBuilder
    private var coreEditor: some View {
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
            ProgressView()
                .tint(Theme.blue)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// `nil` on Event Notes, the one tab that is a list rather than a single standing note.
    private var selectedNote: Note? {
        guard let coreTab = activeTab.coreTab else { return nil }
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
        let snapshot = CadenceCoreNoteSupport.loadOrCreateCoreNotes(in: modelContext, dayKey: selectedDayKey)
        todayNote = snapshot.today
        weekNote = snapshot.week
        permanentNote = snapshot.notepad
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

/// The Event Notes list.
///
/// It was a column of shadowed elevated cards; the note list is an *index*, and macOS rewrote its
/// equivalent (`NoteListDayRow`) into flat rows for exactly that reason — a dozen cards fill the
/// screen where a dozen index entries do not. These are the same rows: a day-number column on the
/// left so the numbers line up, whatever the note says beside it, and one press fill at one
/// radius.
private struct iOSMeetingNotesList: View {
    let notes: [Note]
    /// Live task titles for the rows' excerpts, built once by the caller. See
    /// `iOSMeetingNoteRow.preview`.
    let taskTitles: [UUID: String]
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
                                iOSMeetingNoteRow(note: note, taskTitles: taskTitles)
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
    /// Passed in rather than derived here: an index draws one map for all of its rows, and a
    /// `@Query` per row would rebuild it once per row instead. See `preview`.
    let taskTitles: [UUID: String]

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

    /// The excerpt is taken from the note's text with every `[[task:UUID|Title]]` title replaced by
    /// the task's current one — the title in the text is a cache, not the record, so a row that
    /// excerpted the raw string named tasks by whatever they were called when they were embedded.
    /// This covers both spellings at once: a standalone embed, which `plainPreviewText` excerpts
    /// through its `.taskEmbed` branch, and an inline reference, which it excerpts as link text
    /// through `MarkdownReferenceDisplaySupport`.
    private var preview: String {
        let resolved = MarkdownTaskEmbedTitleCache.resolving(note.content, titles: taskTitles)
        let preview = CadenceMarkdownPresentationSupport.plainPreviewText(from: resolved, limit: 140)
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
