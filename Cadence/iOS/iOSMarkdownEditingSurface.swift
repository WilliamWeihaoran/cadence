#if os(iOS)
import PhotosUI
import SwiftData
import SwiftUI

enum iOSMarkdownEditorMode: String, CaseIterable, Identifiable {
    case live = "Live"
    case edit = "Edit"
    case preview = "Preview"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .live: return "rectangle.split.2x1"
        case .edit: return "pencil"
        case .preview: return "doc.richtext"
        }
    }
}

enum iOSMarkdownEditorPreferences {
    static let modeKey = "ios.notes.editorMode"
    static let didMigrateLiveDefaultKey = "ios.notes.didMigrateLiveEditorDefault"
    static let defaultMode = iOSMarkdownEditorMode.live

    static func mode(from rawValue: String) -> iOSMarkdownEditorMode {
        iOSMarkdownEditorMode(rawValue: rawValue) ?? defaultMode
    }

    static func binding(for rawValue: Binding<String>) -> Binding<iOSMarkdownEditorMode> {
        Binding(
            get: { mode(from: rawValue.wrappedValue) },
            set: { rawValue.wrappedValue = $0.rawValue }
        )
    }
}

struct iOSMarkdownModePicker: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var mode: iOSMarkdownEditorMode
    var compact = false

    private var showsLabels: Bool {
        horizontalSizeClass == .regular && !compact
    }

    var body: some View {
        // Same grouped-capsule control at every width — showsLabels only adds text next to the
        // icon when there's room. Previously the regular-width case used a native
        // `.pickerStyle(.segmented)`, which looked like a different, disconnected control (a
        // plain system tab bar) from the custom capsule used everywhere else in the app.
        HStack(spacing: 2) {
            ForEach(iOSMarkdownEditorMode.allCases) { candidate in
                Button {
                    mode = candidate
                } label: {
                    modeLabel(for: candidate)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(candidate.rawValue)
            }
        }
        .padding(2)
        .background(Theme.surfaceElevated.opacity(0.56))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.46), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func modeLabel(for candidate: iOSMarkdownEditorMode) -> some View {
        HStack(spacing: 5) {
            Image(systemName: candidate.systemImage)
                .font(.system(size: compact ? 11 : 12, weight: .semibold))
            if showsLabels {
                Text(candidate.rawValue)
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .foregroundStyle(mode == candidate ? Theme.text : Theme.dim)
        .frame(height: compact ? 30 : 32)
        .frame(minWidth: showsLabels ? nil : (compact ? 32 : 34))
        .padding(.horizontal, showsLabels ? 12 : 0)
        .background(
            RoundedRectangle(cornerRadius: compact ? 6 : 7, style: .continuous)
                .fill(mode == candidate ? Theme.blue.opacity(0.18) : Color.clear)
        )
    }
}

struct iOSMarkdownEditingSurface: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MarkdownImageAsset.createdAt) private var imageAssets: [MarkdownImageAsset]
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var mode: iOSMarkdownEditorMode
    let placeholder: String
    var referenceNotes: [Note] = []
    var referenceTasks: [AppTask] = []
    var onOpenReference: ((MarkdownReferenceDisplayTarget) -> Void)? = nil
    var allowsEmbeddedTaskCreation = true
    var embeddedTaskArea: Area? = nil
    var embeddedTaskProject: Project? = nil
    @State private var draftText = ""
    @State private var hasLoadedDraft = false
    @State private var pendingCommitWorkItem: DispatchWorkItem?
    @State private var referencePickerKind: iOSMarkdownReferencePickerKind?
    @State private var selectedRange = NSRange(location: 0, length: 0)
    @State private var isImagePickerPresented = false
    @State private var selectedImageItems: [PhotosPickerItem] = []
    @State private var recentEmbeddedTasks: [UUID: AppTask] = [:]
    @State private var selectedEmbeddedTask: AppTask?

    var body: some View {
        return VStack(spacing: 0) {
            switch mode {
            case .live:
                editorSurface(hidesMarkdownMarkers: true)
            case .edit:
                editorSurface(hidesMarkdownMarkers: false)
            case .preview:
                renderedPreview
            }

            Divider().background(Theme.borderSubtle.opacity(0.65))

            iOSMarkdownStatusBar(
                wordCount: wordCount,
                lineCount: lineCount,
                mode: mode,
                isRegularWidth: horizontalSizeClass == .regular
            )
        }
        .background(Theme.surface)
        .onAppear(perform: loadDraftIfNeeded)
        .onDisappear(perform: commitDraftImmediately)
        .onChange(of: text) { _, newValue in
            guard !isFocused, newValue != draftText else { return }
            draftText = newValue
        }
        .onChange(of: mode) { _, _ in
            commitDraftImmediately()
        }
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
        .sheet(item: $selectedEmbeddedTask) { task in
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

    private var renderedPreview: some View {
        iOSMarkdownPreview(
            markdown: draftText,
            imageAssets: imageAssets,
            taskEmbeds: taskEmbedInfos,
            onToggleChecklist: { lineIndex in
                toggleChecklistItem(at: lineIndex)
            },
            onToggleEmbeddedTask: { taskID in
                _ = toggleEmbeddedTask(id: taskID)
            },
            onToggleEmbeddedSubtask: { taskID, subtaskID in
                _ = toggleEmbeddedSubtask(taskID: taskID, subtaskID: subtaskID)
            },
            onOpenEmbeddedTask: { taskID in
                openEmbeddedTask(id: taskID)
            },
            onOpenReference: onOpenReference
        )
    }

    private func editorSurface(hidesMarkdownMarkers: Bool) -> some View {
        let createEmbeddedTask: ((String) -> String?)? = allowsEmbeddedTaskCreation
            ? { title in createEmbeddedTaskReference(title: title) }
            : nil

        return VStack(spacing: 0) {
            iOSMarkdownFormatToolbar { command in
                applyToolbarCommand(command)
            } chooseImages: {
                chooseImages()
            }

            if let context = referenceCompletionContext {
                iOSMarkdownReferenceCompletionStrip(
                    context: context,
                    choices: referenceCompletionChoices(for: context)
                ) { markdown in
                    applyReferenceCompletion(markdown, context: context)
                }

                Divider().background(Theme.borderSubtle.opacity(0.52))
            } else if let context = slashCommandContext {
                iOSMarkdownSlashCommandStrip(
                    context: context,
                    commands: slashCommandChoices(for: context)
                ) { command in
                    applySlashCommand(command, context: context)
                }

                Divider().background(Theme.borderSubtle.opacity(0.52))
            }

            Divider().background(Theme.borderSubtle.opacity(0.62))

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
                    hidesMarkdownMarkers: hidesMarkdownMarkers,
                    imageAssets: imageAssets,
                    taskEmbeds: taskEmbedInfos,
                    onToggleChecklistLine: hidesMarkdownMarkers ? { lineIndex in
                        toggleChecklistItem(at: lineIndex)
                    } : nil,
                    onToggleEmbeddedTask: hidesMarkdownMarkers ? { taskID in
                        toggleEmbeddedTask(id: taskID)
                    } : nil,
                    onToggleEmbeddedSubtask: hidesMarkdownMarkers ? { taskID, subtaskID in
                        toggleEmbeddedSubtask(taskID: taskID, subtaskID: subtaskID)
                    } : nil,
                    onCreateEmbeddedTask: createEmbeddedTask,
                    onOpenEmbeddedTask: { taskID in
                        openEmbeddedTask(id: taskID)
                    },
                    onOpenReference: hidesMarkdownMarkers ? onOpenReference : nil,
                    onEditRenderedBlock: hidesMarkdownMarkers ? { range in
                        revealRenderedBlockForEditing(range)
                    } : nil,
                    onCreatePastedImages: createPastedImageAssets
                )
                .background(Color.clear)
            }
        }
        .background(Theme.surface)
    }

    private var wordCount: Int {
        draftText
            .split { $0.isWhitespace || $0.isNewline }
            .count
    }

    private var lineCount: Int {
        max(1, draftText.components(separatedBy: .newlines).count)
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
        guard isFocused, mode != .preview else { return nil }
        return MarkdownReferenceCompletionSupport.context(in: draftText, selection: selectedRange)
    }

    private var slashCommandContext: MarkdownSlashCommandContext? {
        guard isFocused, mode != .preview else { return nil }
        return MarkdownSlashCommandTokenSupport.context(in: draftText, selection: selectedRange)
    }

    private func referenceCompletionChoices(for context: MarkdownReferenceCompletionContext) -> [iOSMarkdownReferenceCompletionChoice] {
        let trimmedQuery = context.query.trimmingCharacters(in: .whitespacesAndNewlines)
        switch context.kind {
        case .note:
            return referenceNotes
                .filter { note in
                    trimmedQuery.isEmpty ||
                        note.displayTitle.localizedCaseInsensitiveContains(trimmedQuery) ||
                        note.content.localizedCaseInsensitiveContains(trimmedQuery)
                }
                .sorted { lhs, rhs in
                    if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                    return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
                }
                .prefix(6)
                .map { note in
                    iOSMarkdownReferenceCompletionChoice(
                        id: "note-\(note.id.uuidString)",
                        title: note.displayTitle,
                        subtitle: note.kind.rawValue.capitalized,
                        systemImage: "doc.text",
                        tint: Theme.blue,
                        markdown: NoteReferenceParser.noteReferenceMarkdown(for: note)
                    )
                }
        case .task:
            return referenceTasks
                .filter { !$0.isCancelled }
                .filter { task in
                    trimmedQuery.isEmpty ||
                        task.title.localizedCaseInsensitiveContains(trimmedQuery) ||
                        task.notes.localizedCaseInsensitiveContains(trimmedQuery) ||
                        task.containerName.localizedCaseInsensitiveContains(trimmedQuery)
                }
                .sorted { lhs, rhs in
                    if lhs.isDone != rhs.isDone { return !lhs.isDone && rhs.isDone }
                    if priorityRank(lhs.priority) != priorityRank(rhs.priority) {
                        return priorityRank(lhs.priority) > priorityRank(rhs.priority)
                    }
                    if lhs.order != rhs.order { return lhs.order < rhs.order }
                    return lhs.createdAt > rhs.createdAt
                }
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

    private func createPastedImageAssets(_ images: [UIImage]) -> [MarkdownImageAsset] {
        let assets = images.compactMap { image in
            MarkdownImageAssetService.createAsset(from: image, in: modelContext)
        }
        if !assets.isEmpty {
            try? modelContext.save()
        }
        return assets
    }

    private func priorityRank(_ priority: TaskPriority) -> Int {
        switch priority {
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        case .none: return 0
        }
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
        guard let task = TaskCreationService(areas: areas, projects: projects)
            .insertTask(from: draft, into: modelContext) else {
            return nil
        }

        recentEmbeddedTasks[task.id] = task
        try? modelContext.save()
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

    private func revealRenderedBlockForEditing(_ range: NSRange) {
        selectedRange = range
        mode = .edit
        isFocused = true
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
        mode = .live
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
