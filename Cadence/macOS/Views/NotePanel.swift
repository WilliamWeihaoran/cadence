#if os(macOS)
import SwiftUI
import SwiftData

struct NotePanel: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(HoveredTaskManager.self) private var hoveredTaskManager
    @Environment(HoveredEditableManager.self) private var hoveredEditableManager
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    /// [[T-5180]]: what `[[note]]` links in the core notes resolve against — the same query and
    /// order the Notes page and the task inspector's notes box ([[T-5061]]) use.
    @Query(sort: \Note.updatedAt, order: .reverse) private var referenceNotes: [Note]
    var useStandardHeaderHeight = false

    @State private var activeTab: CadenceCoreNoteTab = .today
    @State private var todayNote:  Note?
    @State private var weekNote:   Note?
    @State private var permNote:   Note?
    @State private var notesContext: ModelContext?
    /// [[T-6721]]: the live-card embed handlers, the popovers' state and the refused-edit notice
    /// are the shared `TaskNotesEmbedHandlers`; this panel's policy is in `embedScope`.
    @State private var embeds = TaskNotesEmbedHandlers(hoverIDPrefix: "note-embed-task-")
    @State private var editorContent = ""
    @State private var loadedNoteID: UUID?
    @State private var pendingFallbackContentSyncTask: Task<Void, Never>?
    /// [[T-7810]]: when the oldest edit the pending fallback commit carries was made; only
    /// meaningful while `pendingFallbackContentSyncTask` is non-nil.
    @State private var fallbackContentWindowStart: Date?
    /// [[T-7891]]: the note whose body a ceiling commit wrote without its tag sync; the next true
    /// flush point owes that sync even if the body has not changed since.
    @State private var tagSyncDeferredNoteID: UUID?
    /// [[T-7811]]: this editor's key in `MarkdownEditorTerminationFlush`.
    @State private var terminationFlushID = UUID()
    /// Tabs whose note failed to load or create on the last `loadOrCreate()` (T-849). A tab in
    /// here has a `nil` note that is never going to become non-nil on its own — unlike the `nil`
    /// every tab starts in before the first load lands, which `ProgressView()` still correctly
    /// describes.
    @State private var failedNoteTabs: Set<CadenceCoreNoteTab> = []
    /// [[T-7983]]: the day the Today and This Week tabs are resolved against. Every other pane on
    /// Mac Today observes the day; this one resolved its notes only on appear, activation and a
    /// tab switch, so a page left open overnight kept editing — and saving into — yesterday's
    /// daily note (and last week's, once the week turned) while the task column moved on.
    @State private var observedDay = CadenceObservedDay()

    /// The context this panel's notes are loaded into and written back through.
    ///
    /// `refreshFromStore()` replaces `notesContext` wholesale, so the environment's context is
    /// only the fallback for the frames before `loadOrCreate()` runs. Writing through
    /// `modelContext` once `notesContext` exists would update a `Note` the panel is not showing;
    /// writing through a `notesContext` that has already been discarded loses the edit outright,
    /// and SwiftData reports neither. One spelling, one place.
    private var currentNotesContext: ModelContext {
        notesContext ?? modelContext
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    // The column's one name. It read `NOTES / <active tab>` — the column named
                    // once in the eyebrow, then the tab strip's own answer restated in the title,
                    // with the strip eight lines below already drawing that word lit. See
                    // `PanelHeader` (T-602). The strip answers "which note"; this answers "which
                    // column"; neither question is now answered twice.
                    PanelHeader(title: "Notes")
                    Spacer()
                    if let activeNote {
                        NoteActionMenu(note: activeNote, onAppendSummary: { summary in
                            appendSummary(summary, to: activeNote)
                        })
                        .padding(.top, 12)
                        .padding(.trailing, 12)
                    }
                }

                HStack(spacing: 0) {
                    ForEach(CadenceCoreNoteTab.allCases) { tab in
                        NotePanelTabButton(tab: tab, isSelected: activeTab == tab) {
                            selectTab(tab)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
            }
            .frame(height: useStandardHeaderHeight ? todayPanelHeaderHeight : nil, alignment: .top)
            .zIndex(50)

            Divider().background(Theme.borderSubtle)

            // Content
            Group {
                switch activeTab {
                case .today:
                    noteOrPlaceholder(todayNote, tab: .today)
                case .week:
                    noteOrPlaceholder(weekNote, tab: .week)
                case .notepad:
                    noteOrPlaceholder(permNote, tab: .notepad)
                }
            }
            .zIndex(0)

            // Under the editor rather than over the card: the card is drawn by the text view, so
            // there is nothing in SwiftUI's tree to attach a notice to at the point of the refusal.
            if let embeddedTaskFailureNotice = embeds.embeddedTaskFailureNotice {
                CadenceInlineFailureNotice(text: embeddedTaskFailureNotice) { embeds.embeddedTaskFailureNotice = nil }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
        .background(Theme.surface)
        .onAppear { loadOrCreate() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            flushPendingEditorContent()
            refreshFromStore()
        }
        .onChange(of: activeTab) { _, _ in
            refreshFromStore()
        }
        // [[T-7983]]: midnight. `refreshFromStore()` flushes the editor's pending text into the
        // note it was typed into — yesterday's, still the loaded one — before it reloads the three
        // notes against the new day's key.
        .cadenceTracksDayChanges($observedDay)
        .onChange(of: observedDay) { _, _ in
            refreshFromStore()
        }
        .onDisappear {
            flushPendingEditorContent()
            MarkdownEditorTerminationFlush.shared.unregister(terminationFlushID)
            pendingFallbackContentSyncTask?.cancel()
            pendingFallbackContentSyncTask = nil
        }
    }

    private var activeNote: Note? {
        notesSnapshot.note(for: activeTab)
    }

    private var notesSnapshot: CadenceCoreNoteState {
        CadenceCoreNoteState(today: todayNote, week: weekNote, notepad: permNote)
    }

    /// The one tab's content: the loaded note, an explicit failure if this tab's load failed
    /// (T-849), or the spinner for the ordinary case of "still loading".
    ///
    /// **A failed tab must not blank the panel.** The three notes load independently — one
    /// `try?` each in `CadenceCoreNoteSupport.loadOrCreateCoreNotes` — so a failure here says
    /// nothing about the other two tabs, which is why this switches on `tab` alone rather than
    /// gating the whole `Group` on one shared success flag.
    @ViewBuilder
    private func noteOrPlaceholder(_ note: Note?, tab: CadenceCoreNoteTab) -> some View {
        if let note {
            noteEditor(for: note)
        } else if failedNoteTabs.contains(tab) {
            noteLoadFailureView(for: tab)
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// **Distinguishable from "still loading" (T-849).** A `nil` note used to draw the same
    /// `ProgressView()` whether the fetch had not finished yet or had already failed and was
    /// never going to finish — the second case looked identical to the first forever, with
    /// nothing on screen saying so. `dailyNote`/`weeklyNote`/`permanentNote` all `throws` rather
    /// than returning `nil` for "not found" (they create it instead), so a `nil` reaching here
    /// is always a genuine failure, never an empty state.
    private func noteLoadFailureView(for tab: CadenceCoreNoteTab) -> some View {
        VStack(spacing: 10) {
            CadenceInlineFailureNotice(text: "Couldn't load this note.")
            // [[T-9453]]: the shared action button, not a bare label whose hover wash is the word.
            CadenceActionButton(title: "Try Again", role: .secondary, size: .compact) { loadOrCreate() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    /// The core notes' embed policy ([[T-6721]]): a card created here goes to the Inbox, default
    /// section.
    private var embedScope: TaskNotesEmbedScope {
        TaskNotesEmbedScope(
            referenceTasks: allTasks,
            embedTarget: .coreNotes,
            modelContext: modelContext
        )
    }

    @ViewBuilder
    private func noteEditor(for note: Note) -> some View {
        let embedScope = self.embedScope
        let embedCallbacks = embeds.callbacks(
            in: embedScope,
            hoveredTaskManager: hoveredTaskManager,
            hoveredEditableManager: hoveredEditableManager
        )
        MarkdownEditor(
            text: coreNoteContentBinding(for: note),
            // [[T-8583]]: the `[[` completion offers every note but this one, as `NoteEditorPane`
            // and iOS ([[T-8582]]) do. `openNoteReference` still resolves against the whole query.
            referenceNotes: MarkdownReferenceCompletionSupport.linkableNotes(referenceNotes, excludingNoteID: note.id),
            referenceTasks: allTasks,
            onOpenNoteReference: openNoteReference,
            onOpenTaskReference: embedCallbacks.openTaskReference,
            onCreateEmbeddedTask: embedCallbacks.createEmbeddedTask,
            onToggleEmbeddedTask: embedCallbacks.toggleEmbeddedTask,
            onToggleEmbeddedSubtask: embedCallbacks.toggleEmbeddedSubtask,
            onRenameEmbeddedTask: embedCallbacks.renameEmbeddedTask,
            onOpenEmbeddedTask: embedCallbacks.openEmbeddedTask,
            onEditEmbeddedTask: embedCallbacks.editEmbeddedTask,
            onHoverEmbeddedTask: embedCallbacks.hoverEmbeddedTask,
            onEditingChanged: handleEditorFocusChange,
            onTextViewChanged: embedCallbacks.textViewChanged
        )
        .taskNotesEmbedPopovers(embeds, scope: embedScope)
        .onAppear {
            loadEditorStateIfNeeded(for: note)
        }
        // T-9171: an outside write to this note (sync, MCP, another editor) reaches the buffer.
        .onChange(of: note.content) { priorContent, storeContent in
            adoptStoreContentIfIdle(storeContent, priorStoreContent: priorContent, for: note)
        }
    }

    /// [[T-9171]]: adopt an outside change to `note.content` unless typing is still pending —
    /// `MarkdownEditorStoreAdoption` holds the rule. A commit still armed when this adopts carries
    /// nothing the store lacked (see `commitHoldsTyping`), and its captured text is the pre-change
    /// body, so it is cancelled; a tag sync a ceiling commit deferred ([[T-7891]]) stays owed and is
    /// re-armed against the adopted body.
    private func adoptStoreContentIfIdle(_ storeContent: String, priorStoreContent: String, for note: Note) {
        guard let adopted = MarkdownEditorStoreAdoption.adoptedBuffer(
            storeText: storeContent,
            buffer: editorContent,
            bufferIsLoaded: loadedNoteID == note.id,
            commitIsPending: MarkdownEditorStoreAdoption.commitHoldsTyping(
                commitIsPending: pendingFallbackContentSyncTask != nil,
                buffer: editorContent,
                priorStoreText: priorStoreContent
            )
        ) else { return }
        pendingFallbackContentSyncTask?.cancel()
        pendingFallbackContentSyncTask = nil
        editorContent = adopted
        if tagSyncDeferredNoteID == note.id { scheduleFallbackContentSync(for: adopted, noteID: note.id) }
    }

    private func loadOrCreate() {
        // Deliberately *not* `currentNotesContext`. This is the one site that wants a brand new
        // private context when there isn't one yet, rather than the environment's — the panel's
        // notes must live in a context it can discard and rebuild without disturbing the rest of
        // the window.
        let context = notesContext ?? makeNotesContext()
        notesContext = context

        let snapshot = CadenceCoreNoteSupport.loadOrCreateCoreNotes(
            in: context,
            dayKey: observedDay.todayKey
        )
        todayNote = snapshot.today
        weekNote = snapshot.week
        permNote = snapshot.notepad
        failedNoteTabs = snapshot.failedTabs
    }

    private func refreshFromStore() {
        // The flush has to come first: it moves the editor's in-flight text into the context so
        // the save below can see it. Then `CadenceModelContextRefresh` saves before it swaps —
        // the same contract `macOSRootView.refreshAppData()` relies on.
        flushPendingEditorContent()
        notesContext = CadenceModelContextRefresh.replacement(for: currentNotesContext)
        todayNote = nil
        weekNote = nil
        permNote = nil
        loadOrCreate()
    }

    private func makeNotesContext() -> ModelContext {
        ModelContext(modelContext.container)
    }

    private func selectTab(_ tab: CadenceCoreNoteTab) {
        guard activeTab != tab else { return }
        flushPendingEditorContent()
        activeTab = tab
    }

    private func coreNoteContentBinding(for note: Note) -> Binding<String> {
        Binding(
            get: { loadedNoteID == note.id ? editorContent : note.content },
            set: { updateEditorContent($0, for: note) }
        )
    }

    private func loadEditorStateIfNeeded(for note: Note, force: Bool = false) {
        guard force || loadedNoteID != note.id else { return }
        pendingFallbackContentSyncTask?.cancel()
        pendingFallbackContentSyncTask = nil
        loadedNoteID = note.id
        editorContent = note.content
    }

    private func updateEditorContent(_ content: String, for note: Note) {
        if loadedNoteID != note.id {
            loadedNoteID = note.id
            editorContent = note.content
        }
        guard editorContent != content else { return }
        editorContent = content
        scheduleFallbackContentSync(for: content, noteID: note.id)
    }

    private func scheduleFallbackContentSync(for content: String, noteID: UUID) {
        // T-7810: re-armed on every keystroke, but never later than the ceiling after the
        // first uncommitted one, so continuous typing still reaches the store.
        let schedule = MarkdownEditorSyncTiming.fallbackContentCommitSchedule(
            pendingWindowStart: pendingFallbackContentSyncTask == nil ? nil : fallbackContentWindowStart,
            now: Date()
        )
        fallbackContentWindowStart = schedule.windowStart
        pendingFallbackContentSyncTask?.cancel()
        // T-7811: something is pending now; a quit drains it through this editor's flush.
        // Gated on the pending task: once a load or flush clears it, this closure's captured
        // note/task may no longer be the one the buffer holds, and must write nothing.
        MarkdownEditorTerminationFlush.shared.register(terminationFlushID) {
            guard pendingFallbackContentSyncTask != nil else { return }
            flushPendingEditorContent()
        }
        pendingFallbackContentSyncTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: schedule.delay)
            guard !Task.isCancelled, loadedNoteID == noteID else { return }
            // T-7891: a commit the ceiling cut short fires mid-typing, so it must not mint the
            // half-typed `#tag` under the caret; it writes the body and defers the tag sync.
            let syncsTags = MarkdownEditorSyncTiming.fallbackCommitSyncsTags(delay: schedule.delay)
            persistEditorContentIfNeeded(content, noteID: noteID, syncTags: syncsTags)
            pendingFallbackContentSyncTask = nil
            // The deferred sync gets a true idle commit of its own, so a pause still mints it.
            if tagSyncDeferredNoteID == noteID { scheduleFallbackContentSync(for: content, noteID: noteID) }
        }
    }

    private func flushPendingEditorContent() {
        pendingFallbackContentSyncTask?.cancel()
        pendingFallbackContentSyncTask = nil
        guard let loadedNoteID else { return }
        persistEditorContentIfNeeded(editorContent, noteID: loadedNoteID)
    }

    private func handleEditorFocusChange(_ isFocused: Bool) {
        guard !isFocused else { return }
        flushPendingEditorContent()
    }

    private func persistEditorContentIfNeeded(_ content: String, noteID: UUID, syncTags: Bool = true) {
        guard let note = notesSnapshot.note(for: activeTab), note.id == noteID else { return }
        // T-7891: an unchanged body still goes through when a ceiling commit deferred its tag sync.
        guard note.content != content || (syncTags && tagSyncDeferredNoteID == noteID) else { return }
        CadenceCoreNoteSupport.update(note, content: content, in: currentNotesContext, syncTags: syncTags)
        tagSyncDeferredNoteID = syncTags ? nil : noteID
    }

    /// [[T-5180]]: a `[[note]]` link opens the note where the rest of the Mac app opens it — the
    /// route [[T-5061]] gave the task inspector. A `.list` note opens its list's Notes tab.
    private func openNoteReference(id: UUID?, title: String) {
        guard let note = TaskNoteLinkRouting.note(id: id, title: title, in: referenceNotes) else { return }
        TaskNoteLinkRouting.open(note)
    }

    private func appendSummary(_ summary: String, to note: Note) {
        flushPendingEditorContent()
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSummary.isEmpty else { return }
        let separator = note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
        let content = "\(note.content)\(separator)## AI Summary\n\n\(trimmedSummary)"
        CadenceCoreNoteSupport.update(note, content: content, in: currentNotesContext)
        if loadedNoteID == note.id {
            editorContent = content
        }
    }
}

// MARK: - Tab Button

private struct NotePanelTabButton: View {
    let tab: CadenceCoreNoteTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(tab.rawValue)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Theme.blue : Theme.dim)
                .frame(minWidth: 78, minHeight: 30)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
                .overlay(alignment: .bottom) {
                    if isSelected {
                        Rectangle().fill(Theme.blue.opacity(0.8)).frame(height: 1)
                    }
                }
        }
        .buttonStyle(.cadencePlain)
    }
}
#endif
