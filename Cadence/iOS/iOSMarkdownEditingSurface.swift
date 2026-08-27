#if os(iOS)
import PhotosUI
import SwiftData
import SwiftUI

/// The note editor. One mode: the live, editable preview.
///
/// It used to be three — `Live`, `Edit` (raw markdown) and `Preview` (read-only) — behind a
/// three-icon segmented control repeated in a dozen editor headers, with the choice persisted
/// app-wide under `ios.notes.editorMode`. Two of those modes were the same text with its styling
/// turned off or its editability turned off, and the picker was the only way to discover that; the
/// editor now just renders live-styled text you can type into. `CadenceNotesEditorPreferences`
/// clears the stored selection at launch.
struct iOSMarkdownEditingSurface: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MarkdownImageAsset.createdAt) private var imageAssets: [MarkdownImageAsset]
    @Binding var text: String
    @Binding var isFocused: Bool
    let placeholder: String
    var referenceNotes: [Note] = []
    var referenceTasks: [AppTask] = []
    /// The note being edited, when the host is editing a `Note` rather than some other body of
    /// markdown (a task's notes field, a template, an event draft). Set it and the editor grows the
    /// reference panel above its toolbar; leave it nil and it cannot, because "what points at this"
    /// has no subject.
    ///
    /// It is a separate parameter rather than something inferred from `text` and `referenceNotes`
    /// on purpose: hosts pass *all* notes, including the one being edited, so the only way to pick
    /// self out of that array would be to match content — and two blank notes are indistinguishable
    /// that way. Guessing wrong shows one note the backlinks of another.
    var editingNote: Note? = nil
    var onOpenReference: ((MarkdownReferenceDisplayTarget) -> Void)? = nil
    var allowsEmbeddedTaskCreation = true
    var embeddedTaskArea: Area? = nil
    var embeddedTaskProject: Project? = nil
    /// Passed straight through to `iOSMarkdownFormatToolbar`; see the note there for why the
    /// template menu belongs in the format row rather than a page header.
    var templateKind: NoteKind? = nil
    var applyTemplate: ((NoteTemplate) -> Void)? = nil
    @State private var draftText = ""
    @State private var hasLoadedDraft = false
    @State private var pendingCommitWorkItem: DispatchWorkItem?
    @State private var referencePickerKind: iOSMarkdownReferencePickerKind?
    @State private var selectedRange = NSRange(location: 0, length: 0)
    @State private var isImagePickerPresented = false
    @State private var selectedImageItems: [PhotosPickerItem] = []
    @State private var recentEmbeddedTasks: [UUID: AppTask] = [:]
    @State private var selectedEmbeddedTask: AppTask?
    /// Held rather than computed in `body`. Backlinks run a regex over *every* other note's content,
    /// so recomputing them on each body pass would put that scan behind every keystroke; macOS holds
    /// its equivalent in `NoteEditorPane.derivedState` for the same reason. Refreshed when the
    /// committed text changes — the editor's own 2.5s commit debounce is the throttle.
    @State private var referenceContents = NoteReferencePanelContents()

    // No word/line count bar under the editor. It was a permanent strip across the foot of every
    // note reporting a number nobody was writing towards — the editor's last piece of chrome that
    // described the note instead of holding it.
    var body: some View {
        editorSurface
        .background(Theme.surface)
        .onAppear(perform: loadDraftIfNeeded)
        .onAppear(perform: refreshReferenceContents)
        .onDisappear(perform: commitDraftImmediately)
        .onChange(of: text) { _, newValue in
            guard !isFocused, newValue != draftText else { return }
            draftText = newValue
        }
        // Its own observer rather than a line inside the one above: that one returns early while the
        // editor holds focus, and the references still have to catch up when focus is released and
        // the buffer commits.
        .onChange(of: text) { _, _ in refreshReferenceContents() }
        .onChange(of: editingNote?.id) { _, _ in refreshReferenceContents() }
        .onChange(of: referenceNotes.count) { _, _ in refreshReferenceContents() }
        .onChange(of: referenceTasks.count) { _, _ in refreshReferenceContents() }
        .onChange(of: isFocused) { _, focused in
            if focused {
                loadDraftIfNeeded()
            } else {
                commitDraftImmediately()
            }
        }
        .sheet(item: $referencePickerKind) { kind in
            iOSMarkdownReferencePickerSheet(
                kind: kind,
                notes: referenceNotes,
                tasks: referenceTasks
            ) { markdown in
                insertReferenceMarkdown(markdown)
            }
        }
        .sheet(item: $selectedEmbeddedTask, onDismiss: reconcileEmbeddedTaskReferenceTitles) { task in
            iOSTaskDetailSheet(task: task)
        }
        .photosPicker(
            isPresented: $isImagePickerPresented,
            selection: $selectedImageItems,
            maxSelectionCount: 8,
            matching: .images
        )
        .onChange(of: selectedImageItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                await insertPickedImages(items)
            }
        }
    }

    private var editorSurface: some View {
        let createEmbeddedTask: ((String) -> String?)? = allowsEmbeddedTaskCreation
            ? { title in createEmbeddedTaskReference(title: title) }
            : nil

        return VStack(spacing: 0) {
            // Above the format toolbar, which is where macOS puts it: header, then what the note is
            // connected to, then the tools, then the note.
            //
            // Hidden while the editor has focus, which is the one place this differs from macOS.
            // With a keyboard up there is room for a single row of chrome above the editor, and that
            // row belongs to the `[[` and `/` strips below the toolbar — typing affordances beat a
            // navigation affordance for the space, and up to three reference strips plus a toolbar
            // plus a keyboard leaves the note itself a sliver.
            if !isFocused {
                iOSNoteReferencePanel(
                    contents: referenceContents,
                    openNote: openReferencedNote,
                    openTask: { task in openEmbeddedTask(id: task.id) }
                )
            }

            iOSMarkdownFormatToolbar(
                apply: { command in applyToolbarCommand(command) },
                chooseImages: { chooseImages() },
                templateKind: templateKind,
                applyTemplate: applyTemplate
            )

            if let context = referenceCompletionContext {
                iOSMarkdownReferenceCompletionStrip(
                    context: context,
                    choices: referenceCompletionChoices(for: context)
                ) { markdown in
                    applyReferenceCompletion(markdown, context: context)
                }

                Divider().background(Theme.borderSubtle)
            } else if let context = slashCommandContext {
                iOSMarkdownSlashCommandStrip(
                    context: context,
                    commands: slashCommandChoices(for: context)
                ) { command in
                    applySlashCommand(command, context: context)
                }

                Divider().background(Theme.borderSubtle)
            }

            // One hairline colour for every rule in the editor. These three were 0.52, 0.62 and
            // 0.65 of `borderSubtle`: three different hairlines stacked within 60pt of each other,
            // each hand-tuned in isolation.
            Divider().background(Theme.borderSubtle)

            ZStack(alignment: .topLeading) {
                if draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isFocused {
                    iOSMarkdownEmptyPrompt(placeholder: placeholder)
                }

                iOSMarkdownEditor(
                    text: Binding(
                        get: { draftText },
                        set: { updateDraft($0) }
                    ),
                    isFocused: $isFocused,
                    selectedRange: $selectedRange,
                    imageAssets: imageAssets,
                    taskEmbeds: taskEmbedInfos,
                    onToggleChecklistLine: { lineIndex in
                        toggleChecklistItem(at: lineIndex)
                    },
                    onToggleEmbeddedTask: { taskID in
                        toggleEmbeddedTask(id: taskID)
                    },
                    onToggleEmbeddedSubtask: { taskID, subtaskID in
                        toggleEmbeddedSubtask(taskID: taskID, subtaskID: subtaskID)
                    },
                    onCreateEmbeddedTask: createEmbeddedTask,
                    onOpenEmbeddedTask: { taskID in
                        openEmbeddedTask(id: taskID)
                    },
                    onOpenReference: onOpenReference,
                    onCreatePastedImages: createPastedImageAssets,
                    onResizeImage: resizeImageAsset
                )
                .background(Color.clear)
            }
        }
        .background(Theme.surface)
    }

    private var taskEmbedInfos: [UUID: MarkdownTaskEmbedRenderInfo] {
        let tasks = referenceTasks + recentEmbeddedTasks.values.filter { recentTask in
            !referenceTasks.contains(where: { $0.id == recentTask.id })
        }
        return Dictionary(uniqueKeysWithValues: tasks.map { task in
            (task.id, MarkdownTaskEmbedRenderInfo.task(task))
        })
    }

    private var referenceCompletionContext: MarkdownReferenceCompletionContext? {
        guard isFocused else { return nil }
        return MarkdownReferenceCompletionSupport.context(in: draftText, selection: selectedRange)
    }

    private var slashCommandContext: MarkdownSlashCommandContext? {
        guard isFocused else { return nil }
        return MarkdownSlashCommandTokenSupport.context(in: draftText, selection: selectedRange)
    }

    private func referenceCompletionChoices(for context: MarkdownReferenceCompletionContext) -> [iOSMarkdownReferenceCompletionChoice] {
        switch context.kind {
        case .note:
            return MarkdownReferenceCompletionSupport
                .candidateNotes(from: referenceNotes, query: context.query)
                .prefix(6)
                .map { note in
                    iOSMarkdownReferenceCompletionChoice(
                        id: "note-\(note.id.uuidString)",
                        title: note.displayTitle,
                        subtitle: NoteReferencePanelSupport.noteKindLabel(note.kind),
                        systemImage: "doc.text",
                        tint: Theme.blue,
                        markdown: NoteReferenceParser.noteReferenceMarkdown(for: note)
                    )
                }
        case .task:
            return MarkdownReferenceCompletionSupport
                .candidateTasks(from: referenceTasks, query: context.query)
                .prefix(6)
                .map { task in
                    let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let subtitle = task.containerName.trimmingCharacters(in: .whitespacesAndNewlines)
                    return iOSMarkdownReferenceCompletionChoice(
                        id: "task-\(task.id.uuidString)",
                        title: title.isEmpty ? "Untitled Task" : title,
                        subtitle: subtitle.isEmpty ? (task.isDone ? "Completed" : "Task") : subtitle,
                        systemImage: task.isDone ? "checkmark.circle.fill" : "checkmark.circle",
                        tint: task.isDone ? Theme.green : Theme.blue,
                        markdown: NoteReferenceParser.taskReferenceMarkdown(for: task)
                    )
                }
        }
    }

    private func applyReferenceCompletion(_ markdown: String, context: MarkdownReferenceCompletionContext) {
        applyCommandToDraft(.replaceMarkdown(
            location: context.range.location,
            length: context.range.length,
            markdown: markdown
        ))
    }

    private func slashCommandChoices(for context: MarkdownSlashCommandContext) -> [MarkdownSlashCommand] {
        MarkdownSlashCommand.all
            .filter { command in
                return context.query.isEmpty ||
                    command.id.localizedCaseInsensitiveContains(context.query) ||
                    command.title.localizedCaseInsensitiveContains(context.query)
            }
            .prefix(8)
            .map { $0 }
    }

    private func applySlashCommand(_ command: MarkdownSlashCommand, context: MarkdownSlashCommandContext) {
        let mutation = MarkdownSlashCommandMutationSupport.mutation(for: command, context: context)
        let replacementCommand = MarkdownFormatCommand.replaceMarkdownWithCaret(
            location: mutation.replacementRange.location,
            length: mutation.replacementRange.length,
            markdown: mutation.replacement,
            caretOffset: mutation.selection.location - mutation.replacementRange.location
        )

        switch mutation.followUp {
        case .none:
            applyCommandToDraft(replacementCommand)
        case .chooseImage:
            applyCommandToDraft(replacementCommand, refocusEditor: false)
            chooseImages()
        }
    }

    private func chooseImages() {
        commitDraftImmediately()
        isFocused = false
        selectedImageItems = []
        isImagePickerPresented = true
    }

    @MainActor
    private func insertPickedImages(_ items: [PhotosPickerItem]) async {
        defer { selectedImageItems = [] }
        var insertedAssets: [MarkdownImageAsset] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let asset = MarkdownImageAssetService.createAsset(fromImageData: data, in: modelContext) else {
                continue
            }
            insertedAssets.append(asset)
        }
        guard !insertedAssets.isEmpty else { return }
        try? modelContext.save()

        let markdown = insertedAssets
            .map { MarkdownImageAssetService.markdown(for: $0) }
            .joined(separator: "\n\n")
        applyCommandToDraft(.insertMarkdown(markdown))
    }

    /// Persists a drag-resize. Same call the macOS editor makes from its mouse drag, so there is
    /// one clamp and one write path; width is the only dimension stored and the height follows from
    /// the pixel aspect wherever the image is drawn.
    private func resizeImageAsset(id: UUID, width: CGFloat) {
        MarkdownImageAssetService.setDisplayWidth(width, for: id, in: imageAssets)
        try? modelContext.save()
    }

    private func createPastedImageAssets(_ images: [UIImage]) -> [MarkdownImageAsset] {
        let assets = images.compactMap { image in
            MarkdownImageAssetService.createAsset(from: image, in: modelContext)
        }
        if !assets.isEmpty {
            try? modelContext.save()
        }
        return assets
    }

    private func toggleChecklistItem(at lineIndex: Int) {
        guard let toggled = MarkdownChecklistSupport.toggledText(draftText, lineIndex: lineIndex) else { return }
        updateDraft(toggled)
        commitDraftImmediately()
    }

    private func toggleEmbeddedTask(id: UUID) -> MarkdownTaskEmbedRenderInfo? {
        guard let task = embeddedTask(id: id) else { return nil }
        CadenceTaskMutationSupport.toggleCompletion(task, modelContext: modelContext)
        return MarkdownTaskEmbedRenderInfo.task(task)
    }

    private func toggleEmbeddedSubtask(taskID: UUID, subtaskID: UUID) -> MarkdownTaskEmbedRenderInfo? {
        guard let task = embeddedTask(id: taskID),
              let subtask = (task.subtasks ?? []).first(where: { $0.id == subtaskID }) else {
            return nil
        }
        subtask.isDone.toggle()
        try? modelContext.save()
        return MarkdownTaskEmbedRenderInfo.task(task)
    }

    /// Bring the note's `[[task:UUID|Title]]` source back in line with the tasks it points at.
    ///
    /// A task embed's title lives in two places: on the task, which is what the card is drawn from,
    /// and inside the note's own reference text. Renaming a task in the detail sheet only writes the
    /// first, so the card relabels itself immediately while the markdown underneath keeps the old
    /// title — invisible until the note is exported, searched, or the task is deleted and the
    /// reference has to render itself from its own stale text.
    ///
    /// Run on the sheet's dismissal rather than on every keystroke in it: the note text is a
    /// document the user is also editing, and rewriting it mid-rename would interleave with their
    /// own typing. `MarkdownTaskEmbedParser` owns which runs to rewrite and what a title may look
    /// like inside a reference — the same rules the Mac's inline rename uses.
    private func reconcileEmbeddedTaskReferenceTitles() {
        guard let reconciled = MarkdownTaskEmbedParser.reconcilingReferenceTitles(
            in: draftText,
            titles: taskEmbedInfos.mapValues(\.title),
            fallback: MarkdownTaskEmbedRenderInfo.untitledTaskTitle
        ) else { return }
        updateDraft(reconciled)
        commitDraftImmediately()
    }

    private func refreshReferenceContents() {
        guard let editingNote else {
            referenceContents = NoteReferencePanelContents()
            return
        }
        referenceContents = NoteReferencePanelSupport.contents(
            for: editingNote,
            content: text,
            notes: referenceNotes,
            tasks: referenceTasks
        )
    }

    /// Opens a panel chip through the same presenter a `[[link]]` tapped in the body goes through —
    /// the host's `iOSMarkdownReferenceSheets`, one of the four `.sheet(item:)` presenters that
    /// deliberately keep their own presentation because they present from inside a sheet. A panel
    /// chip is the same navigation as the link it stands for, so it must not be a second route.
    private func openReferencedNote(_ note: Note) {
        commitDraftImmediately()
        isFocused = false
        onOpenReference?(
            MarkdownReferenceDisplayTarget(kind: .note, referenceID: note.id, title: note.displayTitle)
        )
    }

    private func embeddedTask(id: UUID) -> AppTask? {
        referenceTasks.first(where: { $0.id == id }) ?? recentEmbeddedTasks[id]
    }

    private func openEmbeddedTask(id: UUID) {
        guard let task = embeddedTask(id: id) else {
            onOpenReference?(
                MarkdownReferenceDisplayTarget(kind: .task, referenceID: id, title: "")
            )
            return
        }
        commitDraftImmediately()
        isFocused = false
        selectedEmbeddedTask = task
    }

    private func createEmbeddedTaskReference(title: String) -> String? {
        let container: TaskContainerSelection
        let areas: [Area]
        let projects: [Project]
        if let embeddedTaskArea {
            container = .area(embeddedTaskArea.id)
            areas = [embeddedTaskArea]
            projects = []
        } else if let embeddedTaskProject {
            container = .project(embeddedTaskProject.id)
            areas = []
            projects = [embeddedTaskProject]
        } else {
            container = .inbox
            areas = []
            projects = []
        }

        let draft = TaskCreationDraft(
            title: title,
            notes: "",
            priority: .none,
            container: container,
            sectionName: TaskSectionDefaults.defaultName,
            dueDateKey: "",
            scheduledDateKey: "",
            subtaskTitles: [],
            tags: []
        )
        // T-364: commit first, hand the markdown back second. `iOSMarkdownEditor` replaces the
        // typed line with this string exactly when it is non-nil, so a refused commit has to
        // return nil — otherwise the draft keeps a `[[task:UUID|Title]]` for a task the store
        // never took. The registration below is success bookkeeping and waits with it.
        let created: AppTask?
        do {
            created = try TaskCreationService(areas: areas, projects: projects)
                .createTask(from: draft, into: modelContext)
        } catch {
            return nil
        }
        guard let task = created else { return nil }

        recentEmbeddedTasks[task.id] = task
        return NoteReferenceParser.taskReferenceMarkdown(for: task)
    }

    private func applyToolbarCommand(_ command: MarkdownFormatCommand) {
        switch command {
        case .noteLink where !referenceNotes.isEmpty:
            commitDraftImmediately()
            isFocused = false
            referencePickerKind = .note
        case .taskReference where !referenceTasks.isEmpty:
            commitDraftImmediately()
            isFocused = false
            referencePickerKind = .task
        default:
            applyCommandToDraft(command)
        }
    }

    private func insertReferenceMarkdown(_ markdown: String) {
        applyCommandToDraft(.insertMarkdown(markdown))
    }

    private func applyCommandToDraft(_ command: MarkdownFormatCommand, refocusEditor: Bool = true) {
        let mutation = MarkdownFormatCommandSupport.apply(
            command,
            text: draftText,
            selection: selectedRange
        )
        updateDraft(mutation.text)
        selectedRange = mutation.selection
        // No `mode = .live` here any more. It used to run after *every* toolbar command and every
        // slash command, which quietly moved a user who was in `Edit` into `Live` and persisted the
        // switch app-wide. With one mode there is nothing to set.
        isFocused = refocusEditor
    }

    private func loadDraftIfNeeded() {
        guard !hasLoadedDraft else { return }
        draftText = text
        hasLoadedDraft = true
    }

    private func updateDraft(_ nextText: String) {
        if !hasLoadedDraft {
            hasLoadedDraft = true
        }
        draftText = nextText
        scheduleCommit(nextText)
    }

    private func scheduleCommit(_ nextText: String) {
        pendingCommitWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            if text != nextText {
                text = nextText
            }
        }
        pendingCommitWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: workItem)
    }

    private func commitDraftImmediately() {
        pendingCommitWorkItem?.cancel()
        pendingCommitWorkItem = nil
        guard hasLoadedDraft, text != draftText else { return }
        text = draftText
    }
}

#endif
