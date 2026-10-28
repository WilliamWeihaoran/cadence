#if os(macOS)
import SwiftUI
import SwiftData

private struct NoteEditorDerivedState {
    var linkedNotes: [Note] = []
    var linkedTasks: [AppTask] = []
    var backlinks: [Note] = []
    var unlinkedMentions: [Note] = []
    var outline: [MarkdownOutlineItem] = []
}

struct NoteEditorPane: View {
    enum HeaderStyle {
        case full
        case compact
    }

    @Bindable var note: Note
    var area: Area?
    var project: Project?
    var relatedNotes: [Note] = []
    var relatedTasks: [AppTask] = []
    var onOpenNote: (Note) -> Void = { _ in }
    var onDelete: (() -> Void)?
    var onPersistContent: (Note, String) -> Void = { _, _ in }
    var headerDetail: String?
    var headerAccessory: AnyView?
    /// **T-5162.** A header accessory that is handed the pane's own summary append, for a host
    /// whose `NoteActionMenu` must not write the note behind the pane's back. The menu's default
    /// append is a bare store write: it skips `onPersistContent` (the event-note sheet's Apple
    /// Calendar mirror) and leaves this pane's buffer stale, so the next flush wrote the old text
    /// back over the summary. Takes precedence over `headerAccessory`.
    var summaryHeaderAccessory: ((_ appendSummary: @escaping (String) -> Void) -> AnyView)?
    var headerStyle: HeaderStyle = .full
    /// **[[T-7336]].** An Escape in the body that the editor declined (`MarkdownEditor.
    /// onUnhandledEscape`). `nil` for the Notes page; the Mac event-note sheet passes its dismissal.
    /// An open task popover or chip editor is closed first, so Escape never dismisses the sheet
    /// out from under one.
    var onUnhandledEscape: (() -> Void)?
    @Environment(\.modelContext) private var modelContext
    @Environment(HoveredTaskManager.self) private var hoveredTaskManager
    @Environment(HoveredEditableManager.self) private var hoveredEditableManager
    @AppStorage(NoteTemplateLibrary.storageKey) private var noteTemplateOverridesRaw = ""
    @Query(sort: \Tag.order) private var tags: [Tag]
    /// [[T-6721]]: the live-card embed handlers, the popovers' state, the refused-edit notice and
    /// the editor's text view are the shared `TaskNotesEmbedHandlers`; this pane's policy is in
    /// `embedScope`.
    @State private var embeds = TaskNotesEmbedHandlers(hoverIDPrefix: "note-embed-task-")
    @State private var editorContent = ""
    @State private var loadedNoteID: UUID?
    @State private var derivedState = NoteEditorDerivedState()
    @State private var pendingDerivedStateTask: Task<Void, Never>?
    @State private var pendingFallbackContentSyncTask: Task<Void, Never>?
    /// [[T-7810]]: when the oldest edit the pending fallback commit carries was made; only
    /// meaningful while `pendingFallbackContentSyncTask` is non-nil.
    @State private var fallbackContentWindowStart: Date?
    /// [[T-7811]]: this editor's key in `MarkdownEditorTerminationFlush`.
    @State private var terminationFlushID = UUID()
    /// Set when the store refused a tag created from the chips. See `createTag(_:)`.
    @State private var tagFailureNotice: String?
    /// The title field's focus, read only so leaving it is a flush point (T-4971).
    @FocusState private var isTitleFieldFocused: Bool

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
            get: { loadedNoteID == note.id ? editorContent : note.content },
            set: { updateEditorContent($0) }
        )
    }

    private var noteTagsBinding: Binding<[Tag]> {
        Binding(
            get: { note.tags ?? [] },
            set: { newTags in
                // Single write path: `setTagsCommittingInsertions` resolves the `Tag` rows, folds
                // in inline `#tags` already in the body, and mirrors the result into the note's
                // frontmatter so the YAML stays in sync with the chips even though the block is
                // never rendered.
                //
                // **Commits the mint now (T-762).** A name typed here that matches no existing
                // `Tag` mints one, and until this ticket that insert rode along on whatever
                // unrelated screen saved next. Nothing below is written unless that commit lands —
                // on a refusal the picker's own binding still reads the tags the store holds, so
                // the tapped chip does not light up, and the notice already shown for a refused
                // inline create (`tagFailureNotice`) says why.
                guard TagSupport.setTagsCommittingInsertions(
                    named: newTags.map(\.name),
                    on: note,
                    in: modelContext,
                    writeFrontmatter: true
                ) else {
                    tagFailureNotice = CadencePendingChangePersistence.editFailureNotice
                    return
                }
                tagFailureNotice = nil
                editorContent = note.content
                loadedNoteID = note.id
                refreshDerivedState(for: note.content)
            }
        )
    }

    private var shouldEditTitle: Bool {
        note.kind == .list || note.kind == .meeting
    }

    private var headerTitle: String {
        switch note.kind {
        case .daily:
            guard let date = DateFormatters.date(from: note.dateKey) else { return note.displayTitle }
            // Year only outside this year ([[T-6432]]): the list's month heading is the only other
            // year on the page, and it scrolls away from the open note.
            return DateFormatters.absoluteLongDay(date, relativeTo: Date())
        case .weekly:
            return DateFormatters.weekLabel(from: note.weekKey, relativeTo: Date())
        default:
            return note.displayTitle
        }
    }

    private var referenceNotes: [Note] {
        relatedNotes.filter { $0.id != note.id }
    }

    private var hasReferenceStripContent: Bool {
        !derivedState.linkedNotes.isEmpty ||
        !derivedState.linkedTasks.isEmpty ||
        !derivedState.backlinks.isEmpty
    }

    private var templates: [NoteTemplate] {
        NoteTemplateLibrary.templates(for: note.kind, overridesRaw: noteTemplateOverridesRaw)
    }

    /// Drives the empty-body placeholder — one of the three routes to a template, and the only one
    /// that shows itself. Same notion of "blank" that `applyTemplate` uses, so the placeholder
    /// disappears exactly when applying one would start appending rather than filling.
    ///
    /// Measured against the body, not the raw content: a note that has only been tagged carries a
    /// frontmatter block the user cannot see, and it should still read as empty.
    private var isNoteBlank: Bool {
        let source = loadedNoteID == note.id ? editorContent : note.content
        return isBlankBody(MarkdownMetadataParser.splitFrontmatter(in: source).body)
    }

    private func isBlankBody(_ body: String) -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "# \(note.displayTitle)"
    }

    /// The note's entire header: one row.
    ///
    /// It used to be four stacked rows — an eyebrow spelling out the tab you were already looking
    /// at, the title, the tag control, and a strip of template chips. The eyebrow is gone because
    /// "DAILY" above a note you opened from the Daily tab is a label for nobody, and the templates
    /// are gone from here permanently: they are a thing you reach for once, at the start of an
    /// empty note, and they had taken a permanent row at the top of every note forever. They live
    /// in the empty body's placeholder, the `/` menu, and the Actions popover now.
    ///
    /// What is left reads left to right as title, then the note's metadata, then what you can do
    /// to it. Below this there is one more row — the format toolbar — and then the note.
    @ViewBuilder
    private var noteHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                if shouldEditTitle {
                    TextField("Note title", text: titleBinding)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.text)
                        // T-4971: the title is typed straight into the model; Return and leaving
                        // the field are its flush points, the same as the body's focus loss.
                        .focused($isTitleFieldFocused)
                        .onSubmit { flushPendingEditorContent() }
                        .onChange(of: isTitleFieldFocused) { _, isFocused in
                            guard !isFocused else { return }
                            flushPendingEditorContent()
                        }
                } else {
                    Text(headerTitle)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                noteTagControl
                headerControls
            }
            // Only the linked-event sheet sets this; the four Notes tabs leave it nil and stay at
            // one row.
            if let headerDetail,
               !headerDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(headerDetail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
    }

    /// Editable chips plus a "+" to add one. This is the note's whole metadata surface —
    /// frontmatter is kept in the file for portability but never rendered, so these chips are the
    /// only place tags are read or written. Writes go through
    /// `TagSupport.setTags(...writeFrontmatter: true)`.
    private var noteTagControl: some View {
        VStack(alignment: .trailing, spacing: 3) {
            TagPickerControl(
                selectedTags: noteTagsBinding,
                allTags: tags,
                onCreateTag: createTag,
                triggerSymbol: "plus"
            )
            // Here rather than in `noteHeader`, because the chips are drawn twice: the full header
            // draws them in its title row and the compact one parks them in the format toolbar. A
            // notice attached to the header would be missing from the list-detail Notes tab, which
            // is the surface most likely to be open when a save is refused.
            if let tagFailureNotice {
                CadenceInlineFailureNotice(text: tagFailureNotice)
            }
        }
        .fixedSize()
    }

    /// Compact surfaces (the list-detail Notes tab) have no header row of their own — a list
    /// note's title is the `# Heading` at the top of its own body. They get the same three
    /// controls in the same order, parked in the format toolbar, so the two read as one component.
    private var toolbarAccessory: AnyView? {
        guard headerStyle == .compact else { return nil }
        return AnyView(
            HStack(spacing: 10) {
                noteTagControl
                headerControls
            }
        )
    }

    private var headerControls: some View {
        HStack(spacing: 8) {
            NoteOutlineJumpButton(outline: derivedState.outline, onJump: jumpToOutline)

            if let summaryHeaderAccessory {
                summaryHeaderAccessory(appendSummary)
            } else if let headerAccessory {
                headerAccessory
            } else {
                // **T-5211.** The pane's own append here too (Notes page, list Notes tab): the
                // menu's default is a bare store write this pane's buffer never sees, so the next
                // flush wrote the pre-summary text back over the accepted summary.
                NoteActionMenu(
                    note: note,
                    area: area,
                    project: project,
                    templates: templates,
                    onApplyTemplate: applyTemplate,
                    onAppendSummary: appendSummary,
                    onDelete: onDelete
                )
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if headerStyle == .full {
                noteHeader
                    .zIndex(50)
                // Hairline under the tag strip: the header (title + tags) is metadata, everything
                // below it is the note.
                Divider().background(Theme.borderSubtle)
            }
            if hasReferenceStripContent {
                NoteReferenceStrip(
                    linkedNotes: derivedState.linkedNotes,
                    linkedTasks: derivedState.linkedTasks,
                    backlinks: derivedState.backlinks,
                    onOpenNote: onOpenNote,
                    onOpenTask: { embeds.linkedTaskForPopover = $0 }
                )
                .zIndex(10)
            }
            let embedScope = self.embedScope
            let embedCallbacks = embeds.callbacks(
                in: embedScope,
                hoveredTaskManager: hoveredTaskManager,
                hoveredEditableManager: hoveredEditableManager
            )
            MarkdownEditor(
                text: contentBinding,
                toolbarAccessory: toolbarAccessory,
                slashTemplates: templates,
                referenceNotes: relatedNotes.filter { $0.id != note.id },
                referenceTasks: relatedTasks,
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
                onTextViewChanged: embedCallbacks.textViewChanged,
                onUnhandledEscape: onUnhandledEscape.map { hostEscape in
                    { [embeds] in
                        if !embeds.closeOpenPopover() { hostEscape() }
                    }
                }
            )
            .zIndex(0)
            .overlay(alignment: .topLeading) {
                NoteEmptyBodyPlaceholder(templates: templates, isVisible: isNoteBlank, onApply: applyTemplate)
            }
            .taskNotesEmbedPopovers(embeds, scope: embedScope)

            // Under the editor rather than over the card: the card is drawn by the text view, so
            // there is nothing in SwiftUI's tree to attach a notice to at the point of the refusal.
            if let embeddedTaskFailureNotice = embeds.embeddedTaskFailureNotice {
                CadenceInlineFailureNotice(text: embeddedTaskFailureNotice) { embeds.embeddedTaskFailureNotice = nil }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .zIndex(5)
            }

            NoteUnlinkedMentionsFooter(mentions: derivedState.unlinkedMentions, onLink: linkMention)
                .zIndex(5)
        }
        .background(Theme.surface)
        .onAppear {
            loadEditorStateIfNeeded(force: true)
            // T-762: commits the mint, silently, the same as every other
            // `syncNoteTagsFromMarkdownCommittingInsertions` caller — there is no button here and
            // no moment the user is watching for a "tag added" confirmation.
            TagSupport.syncNoteTagsFromMarkdownCommittingInsertions(note, in: modelContext)
        }
        .onChange(of: note.id) { _, _ in
            loadEditorStateIfNeeded(force: true)
        }
        .onDisappear {
            flushPendingEditorContent()
            MarkdownEditorTerminationFlush.shared.unregister(terminationFlushID)
            pendingDerivedStateTask?.cancel()
            pendingDerivedStateTask = nil
            pendingFallbackContentSyncTask?.cancel()
            pendingFallbackContentSyncTask = nil
        }
    }

    private func loadEditorStateIfNeeded(force: Bool = false) {
        guard force || loadedNoteID != note.id else { return }
        pendingDerivedStateTask?.cancel()
        pendingDerivedStateTask = nil
        pendingFallbackContentSyncTask?.cancel()
        pendingFallbackContentSyncTask = nil
        loadedNoteID = note.id
        editorContent = note.content
        refreshDerivedState(for: note.content)
    }

    private func updateEditorContent(_ content: String) {
        if loadedNoteID != note.id {
            loadedNoteID = note.id
            editorContent = note.content
        }
        guard editorContent != content else { return }
        editorContent = content
        scheduleDerivedStateRefresh(for: content)
        scheduleFallbackContentSync(for: content)
    }

    private func scheduleDerivedStateRefresh(for content: String) {
        pendingDerivedStateTask?.cancel()
        pendingDerivedStateTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: MarkdownEditorSyncTiming.derivedStateRefreshDelay)
            guard !Task.isCancelled else { return }
            refreshDerivedState(for: content)
            pendingDerivedStateTask = nil
        }
    }

    private func scheduleFallbackContentSync(for content: String) {
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
        // The note this content belongs to, captured now. Fifteen seconds is long enough for the
        // pane to be looking at a different note by the time the task fires.
        let noteID = note.id
        pendingFallbackContentSyncTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: schedule.delay)
            guard !Task.isCancelled else { return }
            persistEditorContentIfNeeded(content, noteID: noteID)
            pendingFallbackContentSyncTask = nil
        }
    }

    private func flushPendingEditorContent() {
        pendingDerivedStateTask?.cancel()
        pendingDerivedStateTask = nil
        pendingFallbackContentSyncTask?.cancel()
        pendingFallbackContentSyncTask = nil
        persistEditorContentIfNeeded(editorContent, noteID: loadedNoteID ?? note.id)
        refreshDerivedState(for: editorContent)
        // T-4971: a title typed with an unchanged body reaches no commit in the persist above, so
        // the flush commits too. A no-op when nothing is pending.
        CadencePendingChangePersistence.commitTypedContent(in: modelContext)
    }

    private func handleEditorFocusChange(_ isFocused: Bool) {
        guard !isFocused else { return }
        flushPendingEditorContent()
    }

    /// Writes the buffer back to the note it came from, and only to that note.
    ///
    /// The guard used to be `note.content != content || loadedNoteID != note.id`, whose second
    /// clause *forced the write through* during a note switch — the one moment `content` belongs
    /// to a different note than `note` does. That is not a harmless mix-up: `MarkdownNoteTitleSync`
    /// would rename the newly-opened note from the previous note's `# Heading`, and
    /// `onPersistContent` is wired to the event-note sheet, which pushes the body into the user's
    /// real Calendar event. `NotePanel` already threads an id through its debounce for this reason.
    private func persistEditorContentIfNeeded(_ content: String, noteID: UUID) {
        guard note.id == noteID else { return }
        guard note.content != content else { return }
        note.content = content
        note.updatedAt = Date()
        // The `# H1` -> `note.title` rule. It was a private method here — a `hasPrefix` and a
        // trim, nothing AppKit-shaped — which is why iOS never had it and every iOS list-note row
        // read "Untitled" (T-223). It is `MarkdownNoteTitleSync` in `Services/` now, called from
        // here and from `CadenceCoreNoteSupport.update`, and from nowhere else.
        MarkdownNoteTitleSync.apply(to: note, content: content)
        // **Commits the mint now (T-762).** This runs a few seconds after the user stops typing,
        // or on a focus change — never on an explicit Save — so a name typed into the frontmatter
        // that mints a `Tag` used to leave that insert pending for whatever unrelated screen saved
        // next. `syncNoteTagsFromMarkdownCommittingInsertions` only assigns `note.tags` once the
        // mint is safely committed; a refusal here reads as "did not sync yet", silently, the same
        // as this call's other nine callers — there is no button to report through and no moment
        // the user is waiting for one.
        TagSupport.syncNoteTagsFromMarkdownCommittingInsertions(note, in: modelContext)
        onPersistContent(note, content)
        loadedNoteID = note.id
        // T-4971: commit at the flush, not per keystroke. See `commitTypedContent`.
        CadencePendingChangePersistence.commitTypedContent(in: modelContext)
    }

    private func refreshDerivedState(for content: String) {
        let relatedReferenceNotes = relatedNotes.filter { $0.id != note.id }
        derivedState = NoteEditorDerivedState(
            linkedNotes: NoteReferenceResolver.linkedNotes(noteID: note.id, content: content, in: relatedNotes),
            linkedTasks: NoteReferenceResolver.linkedTasks(in: content, tasks: relatedTasks),
            backlinks: NoteReferenceResolver.backlinks(noteID: note.id, title: note.displayTitle, in: relatedNotes),
            unlinkedMentions: NoteUnlinkedMentionResolver.unlinkedMentions(
                noteID: note.id,
                content: content,
                in: relatedReferenceNotes
            ),
            outline: MarkdownOutlineParser.items(in: content)
        )
    }

    /// **T-5162.** Flush first, so the summary is appended to what is on screen rather than to a
    /// `note.content` the buffer is about to overwrite; then append through `replaceEditorContent`,
    /// which persists via `onPersistContent` — the host's own commit — and shows the summary here.
    private func appendSummary(_ summary: String) {
        flushPendingEditorContent()
        guard let content = CadenceAINoteSummary.appending(summary, to: note.content) else { return }
        replaceEditorContent(content)
    }

    private func replaceEditorContent(_ content: String) {
        pendingDerivedStateTask?.cancel()
        pendingDerivedStateTask = nil
        pendingFallbackContentSyncTask?.cancel()
        pendingFallbackContentSyncTask = nil
        editorContent = content
        // Synchronous and user-initiated (template apply / mention link), so `note` is the note
        // the content is for.
        persistEditorContentIfNeeded(content, noteID: note.id)
        refreshDerivedState(for: content)
    }

    /// **T-631.** The note's chips reached for the pane's ambient `ModelContext`, inserted a `Tag`
    /// one frame down in `TagSupport.resolveTags`, and committed nothing — so a tag typed here sat
    /// pending until some other screen's save took it, and the chip was drawn regardless.
    ///
    /// `noteTagsBinding` and `persistEditorContentIfNeeded`'s onward call to
    /// `.onAppear`'s tag sync were the other two tag writes on this pane, deliberately left open at
    /// the time this comment was written — **closed by T-762.** All three now commit only the rows
    /// they had to mint, through `TagSupport.setTagsCommittingInsertions`/
    /// `syncNoteTagsFromMarkdownCommittingInsertions`, and none of them needed `rollback()` or a
    /// captured-field undo: every one of them writes `note.tags`/`note.content` only *after* the
    /// mint's commit succeeds, so a refusal simply never reaches the write a caret-under-edit undo
    /// would otherwise have to fight. `persistEditorContentIfNeeded` and `body`'s `.onAppear` stay
    /// silent on a refusal, matching `syncNoteTagsFromMarkdownCommittingInsertions`'s other nine
    /// callers; `noteTagsBinding` is a direct tap on a chip, so it reports through this same
    /// `tagFailureNotice`.
    private func createTag(_ name: String) -> Tag? {
        guard let tag = TagSupport.committedTag(named: name, in: modelContext) else {
            tagFailureNotice = CadencePendingChangePersistence.editFailureNotice
            return nil
        }
        tagFailureNotice = nil
        return tag
    }

    private func openNoteReference(id: UUID?, title: String) {
        if let id, let note = referenceNotes.first(where: { $0.id == id }) {
            onOpenNote(note)
            return
        }

        let targetTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetTitle.isEmpty,
              let note = referenceNotes.first(where: {
                  $0.displayTitle.caseInsensitiveCompare(targetTitle) == .orderedSame
              }) else { return }
        onOpenNote(note)
    }

    /// This pane's embed policy ([[T-6721]]): a card created in a list note goes to that list's
    /// area or project, any other note's to the Inbox, default section either way; the note's
    /// `updatedAt` is bumped inside the creation's commit and put back if it is refused.
    private var embedScope: TaskNotesEmbedScope {
        TaskNotesEmbedScope(
            referenceTasks: relatedTasks,
            embedTarget: .noteEditor(note, area: area, project: project),
            modelContext: modelContext
        )
    }

    private func jumpToOutline(_ item: MarkdownOutlineItem) {
        guard let editorTextView = embeds.editorTextView else { return }
        let safeLocation = min(max(item.location, 0), (editorTextView.string as NSString).length)
        editorTextView.window?.makeFirstResponder(editorTextView)
        editorTextView.setSelectedRange(NSRange(location: safeLocation, length: 0))
        editorTextView.scrollRangeToVisible(NSRange(location: safeLocation, length: 0))
    }

    private func applyTemplate(_ template: NoteTemplate) {
        // Split the frontmatter off first and put it back after. The block is invisible, so
        // rewriting `editorContent` wholesale would silently take the note's tags with it.
        let parts = MarkdownMetadataParser.splitFrontmatter(in: editorContent)
        let trimmedBody = parts.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let newBody = isBlankBody(parts.body) ? template.body : trimmedBody + "\n\n" + template.body
        replaceEditorContent(MarkdownMetadataParser.content(frontmatter: parts.frontmatter, body: newBody))
    }

    private func linkMention(_ mentionedNote: Note) {
        let markdown = NoteReferenceParser.noteReferenceMarkdown(for: mentionedNote)
        let title = mentionedNote.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = NoteUnlinkedMentionResolver.firstLoosePhraseRange(title, in: editorContent) {
            let nsContent = editorContent as NSString
            replaceEditorContent(nsContent.replacingCharacters(in: range, with: markdown))
        } else {
            let separator = editorContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
            replaceEditorContent(editorContent + "\(separator)\(markdown)")
        }
    }
}

#endif
