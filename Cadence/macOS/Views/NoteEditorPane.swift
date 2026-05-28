#if os(macOS)
import SwiftUI
import SwiftData

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
    @Environment(HoveredTaskManager.self) private var hoveredTaskManager
    @Environment(HoveredEditableManager.self) private var hoveredEditableManager
    @Query(sort: \Tag.order) private var tags: [Tag]
    @State private var editorTextView: CadenceTextView?
    @State private var linkedTaskForPopover: AppTask?
    @State private var embeddedTaskEditRequest: TaskEmbedFieldEditRequest?
    @State private var recentEmbeddedTasks: [UUID: AppTask] = [:]
    @State private var isInspectorCollapsed = false

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
                TagSupport.syncNoteTagsFromMarkdown(note, in: modelContext)
            }
        )
    }

    private var noteTagsBinding: Binding<[Tag]> {
        Binding(
            get: { note.tags ?? [] },
            set: { newTags in
                let names = newTags.map(\.name) + MarkdownMetadataParser.inlineTagNames(in: note.content)
                note.tags = TagSupport.resolveTags(named: names, in: modelContext)
                note.content = MarkdownMetadataParser.content(note.content, replacingFrontmatterTags: newTags.map(\.name))
                note.updatedAt = Date()
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

    private var referenceNotes: [Note] {
        relatedNotes.filter { $0.id != note.id }
    }

    private var unlinkedMentions: [Note] {
        NoteUnlinkedMentionResolver.unlinkedMentions(for: note, in: referenceNotes)
    }

    private var hasReferenceStripContent: Bool {
        !NoteReferenceResolver.linkedNotes(for: note, in: relatedNotes).isEmpty ||
        !NoteReferenceResolver.linkedTasks(for: note, in: relatedTasks).isEmpty ||
        !NoteReferenceResolver.backlinks(for: note, in: relatedNotes).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(kindLabel.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim).kerning(0.8)
                    Spacer()
                    HStack(spacing: 8) {
                        Button {
                            isInspectorCollapsed.toggle()
                        } label: {
                            Image(systemName: isInspectorCollapsed ? "rectangle.split.2x1" : "rectangle.split.2x1.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(isInspectorCollapsed ? Theme.muted : Theme.blue)
                                .frame(width: 30, height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 9)
                                        .fill(isInspectorCollapsed ? Theme.surfaceElevated.opacity(0.72) : Theme.blue.opacity(0.14))
                                )
                        }
                        .buttonStyle(.cadencePlain)
                        .help(isInspectorCollapsed ? "Show note sidebar" : "Hide note sidebar")

                        if let headerAccessory {
                            headerAccessory
                        } else {
                            NoteActionMenu(note: note, area: area, project: project, onDelete: onDelete)
                        }
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
                TagPickerControl(
                    selectedTags: noteTagsBinding,
                    allTags: tags,
                    onCreateTag: createTag
                )
            }
            .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 12)
            if hasReferenceStripContent {
                Divider().background(Theme.borderSubtle)
                NoteReferenceStrip(
                    note: note,
                    notes: relatedNotes,
                    tasks: relatedTasks,
                    onOpenNote: onOpenNote
                )
            }
            HSplitView {
                MarkdownEditor(
                    text: contentBinding,
                    referenceNotes: referenceNotes,
                    referenceTasks: relatedTasks,
                    onOpenNoteReference: openNoteReference,
                    onOpenTaskReference: openTaskReference,
                    onCreateEmbeddedTask: createEmbeddedTask,
                    onToggleEmbeddedTask: toggleEmbeddedTask,
                    onToggleEmbeddedSubtask: toggleEmbeddedSubtask,
                    onRenameEmbeddedTask: renameEmbeddedTask,
                    onOpenEmbeddedTask: openEmbeddedTask,
                    onEditEmbeddedTask: editEmbeddedTask,
                    onHoverEmbeddedTask: hoverEmbeddedTask,
                    onTextViewChanged: { editorTextView = $0 }
                )
                .frame(minWidth: 360)

                if !isInspectorCollapsed {
                    NoteMarkdownSidePanel(
                        content: note.content,
                        noteTitle: note.displayTitle,
                        noteKind: note.kind,
                        unlinkedMentions: unlinkedMentions,
                        onJumpToOutline: jumpToOutline,
                        onInsertFrontmatter: insertFrontmatter,
                        onApplyTemplate: applyTemplate,
                        onLinkMention: linkMention
                    )
                    .frame(minWidth: 220, idealWidth: 240, maxWidth: 290)
                }
            }
        }
        .background(Theme.surface)
        .popover(item: $linkedTaskForPopover) { task in
            TaskDetailPopover(task: task)
                .frame(width: 380)
        }
        .popover(item: $embeddedTaskEditRequest) { request in
            if let task = embeddedTask(id: request.taskID) {
                TaskEmbedFieldEditorPopover(task: task, initialField: request.field) {
                    refreshEmbeddedTask(task)
                }
            } else {
                Text("Task no longer exists")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                    .padding()
            }
        }
        .onAppear {
            TagSupport.syncNoteTagsFromMarkdown(note, in: modelContext)
        }
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

    private func createTag(_ name: String) -> Tag {
        TagSupport.resolveTags(named: [name], in: modelContext).first ?? Tag(name: name)
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

    private func openTaskReference(id: UUID?, title: String) {
        if let id, let task = relatedTasks.first(where: { $0.id == id }) {
            linkedTaskForPopover = task
            return
        }

        let targetTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetTitle.isEmpty,
              let task = relatedTasks.first(where: {
                  $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
                      .caseInsensitiveCompare(targetTitle) == .orderedSame
              }) else { return }
        linkedTaskForPopover = task
    }

    private func createEmbeddedTask(title: String) -> MarkdownReferenceSuggestion? {
        let ownerArea = note.kind == .list ? (area ?? note.area) : nil
        let ownerProject = note.kind == .list ? (project ?? note.project) : nil
        let container: TaskContainerSelection
        let areas: [Area]
        let projects: [Project]

        if let ownerArea {
            container = .area(ownerArea.id)
            areas = [ownerArea]
            projects = []
        } else if let ownerProject {
            container = .project(ownerProject.id)
            areas = []
            projects = [ownerProject]
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

        guard let task = TaskCreationService(areas: areas, projects: projects).insertTask(from: draft, into: modelContext) else {
            return nil
        }

        note.updatedAt = Date()
        try? modelContext.save()
        recentEmbeddedTasks[task.id] = task
        editorTextView?.markdownTaskEmbeds[task.id] = MarkdownTaskEmbedRenderInfo.task(task)
        return .task(task)
    }

    private func toggleEmbeddedTask(id: UUID) {
        guard let task = embeddedTask(id: id) else { return }
        if task.isDone {
            TaskWorkflowService.markTodo(task)
        } else {
            TaskWorkflowService.markDone(task, in: modelContext)
        }
        try? modelContext.save()
        editorTextView?.markdownTaskEmbeds[id] = MarkdownTaskEmbedRenderInfo.task(task)
        if let editorTextView {
            MarkdownStylist.apply(to: editorTextView)
            editorTextView.needsDisplay = true
        }
    }

    private func toggleEmbeddedSubtask(taskID: UUID, subtaskID: UUID) {
        guard let task = embeddedTask(id: taskID),
              let subtask = (task.subtasks ?? []).first(where: { $0.id == subtaskID }) else { return }
        subtask.isDone.toggle()
        try? modelContext.save()
        refreshEmbeddedTask(task)
    }

    private func renameEmbeddedTask(id: UUID, title: String) {
        guard let task = embeddedTask(id: id) else { return }
        var priority = task.priority
        task.title = TaskTitleSupport.titleApplyingPriorityShortcut(title, priority: &priority)
        task.priority = priority
        try? modelContext.save()
        refreshEmbeddedTask(task)
    }

    private func openEmbeddedTask(id: UUID) {
        guard let task = embeddedTask(id: id) else { return }
        linkedTaskForPopover = task
    }

    private func editEmbeddedTask(id: UUID, field: MarkdownTaskEmbedField) {
        guard embeddedTask(id: id) != nil else { return }
        embeddedTaskEditRequest = TaskEmbedFieldEditRequest(taskID: id, field: field)
    }

    private func hoverEmbeddedTask(id: UUID, hovering: Bool) {
        guard let task = embeddedTask(id: id) else { return }
        if hovering {
            hoveredTaskManager.beginHovering(task, source: .note)
            hoveredEditableManager.beginHovering(id: embeddedTaskHoverID(id)) {
                openEmbeddedTask(id: id)
            }
        } else {
            hoveredTaskManager.endHovering(task)
            hoveredEditableManager.endHovering(id: embeddedTaskHoverID(id))
            refreshEmbeddedTask(task)
        }
    }

    private func embeddedTaskHoverID(_ id: UUID) -> String {
        "note-embed-task-\(id.uuidString)"
    }

    private func refreshEmbeddedTask(_ task: AppTask) {
        editorTextView?.markdownTaskEmbeds[task.id] = MarkdownTaskEmbedRenderInfo.task(task)
        editorTextView?.replaceEmbeddedTaskReferenceTitle(id: task.id, title: task.title)
        if let editorTextView {
            MarkdownStylist.apply(to: editorTextView)
            editorTextView.needsDisplay = true
        }
    }

    private func embeddedTask(id: UUID) -> AppTask? {
        relatedTasks.first(where: { $0.id == id }) ?? recentEmbeddedTasks[id]
    }

    private func jumpToOutline(_ item: MarkdownOutlineItem) {
        guard let editorTextView else { return }
        let safeLocation = min(max(item.location, 0), (editorTextView.string as NSString).length)
        editorTextView.window?.makeFirstResponder(editorTextView)
        editorTextView.setSelectedRange(NSRange(location: safeLocation, length: 0))
        editorTextView.scrollRangeToVisible(NSRange(location: safeLocation, length: 0))
    }

    private func insertFrontmatter() {
        let metadata = MarkdownMetadataParser.metadata(in: note.content)
        guard metadata.frontmatter.range == nil else { return }
        note.content = MarkdownMetadataParser.frontmatterInsertion(title: note.displayTitle) + note.content
        note.updatedAt = Date()
    }

    private func applyTemplate(_ template: NoteTemplate) {
        let trimmed = note.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "# \(note.displayTitle)" {
            note.content = template.body
        } else {
            note.content = note.content.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + template.body
        }
        note.updatedAt = Date()
        syncTitleFromH1IfNeeded()
    }

    private func linkMention(_ mentionedNote: Note) {
        let markdown = NoteReferenceParser.noteReferenceMarkdown(for: mentionedNote)
        let title = mentionedNote.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = firstLoosePhraseRange(title, in: note.content) {
            let nsContent = note.content as NSString
            note.content = nsContent.replacingCharacters(in: range, with: markdown)
        } else {
            let separator = note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
            note.content += "\(separator)\(markdown)"
        }
        note.updatedAt = Date()
    }

    private func firstLoosePhraseRange(_ phrase: String, in content: String) -> NSRange? {
        guard !phrase.isEmpty else { return nil }
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        let pattern = #"(?i)(?<![\p{L}\p{N}_])"# + escaped + #"(?![\p{L}\p{N}_])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        return regex.firstMatch(in: content, range: NSRange(location: 0, length: (content as NSString).length))?.range
    }
}

private struct NoteMarkdownSidePanel: View {
    let content: String
    let noteTitle: String
    let noteKind: NoteKind
    let unlinkedMentions: [Note]
    let onJumpToOutline: (MarkdownOutlineItem) -> Void
    let onInsertFrontmatter: () -> Void
    let onApplyTemplate: (NoteTemplate) -> Void
    let onLinkMention: (Note) -> Void

    private var outline: [MarkdownOutlineItem] {
        MarkdownOutlineParser.items(in: content)
    }

    private var metadata: MarkdownNoteMetadata {
        MarkdownMetadataParser.metadata(in: content)
    }

    private var templates: [NoteTemplate] {
        NoteTemplateLibrary.templates(for: noteKind)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sidebarSection("Outline") {
                    if outline.isEmpty {
                        sidebarEmpty("No headings")
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(outline) { item in
                                Button {
                                    onJumpToOutline(item)
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(String(repeating: "  ", count: max(0, item.level - 1)) + item.title)
                                            .font(.system(size: 11, weight: item.level <= 2 ? .semibold : .regular))
                                            .foregroundStyle(item.level <= 2 ? Theme.muted : Theme.dim)
                                            .lineLimit(1)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.vertical, 3)
                                }
                                .buttonStyle(.cadencePlain)
                            }
                        }
                    }
                }

                sidebarSection("Properties") {
                    if metadata.frontmatter.properties.isEmpty && metadata.tags.isEmpty {
                        Button {
                            onInsertFrontmatter()
                        } label: {
                            Label("Add frontmatter", systemImage: "tag")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.blue)
                        }
                        .buttonStyle(.cadencePlain)
                    } else {
                        if !metadata.frontmatter.properties.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(metadata.frontmatter.properties.keys.sorted(), id: \.self) { key in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(key)
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(Theme.dim)
                                            .frame(width: 58, alignment: .leading)
                                        Text(metadata.frontmatter.properties[key] ?? "")
                                            .font(.system(size: 11))
                                            .foregroundStyle(Theme.muted)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        if !metadata.tags.isEmpty {
                            FlowTags(tags: metadata.tags)
                        }
                    }
                }

                sidebarSection("Templates") {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(templates) { template in
                            Button {
                                onApplyTemplate(template)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.title)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Theme.muted)
                                    Text(template.subtitle)
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.dim)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.cadencePlain)
                        }
                    }
                }

                sidebarSection("Unlinked") {
                    if unlinkedMentions.isEmpty {
                        sidebarEmpty("No mentions")
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(unlinkedMentions, id: \.id) { note in
                                HStack(spacing: 6) {
                                    Text(note.displayTitle)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Theme.muted)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    Button {
                                        onLinkMention(note)
                                    } label: {
                                        Image(systemName: "link")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(Theme.blue)
                                    }
                                    .buttonStyle(.cadencePlain)
                                }
                            }
                        }
                    }
                }
            }
            .padding(14)
        }
        .background(Theme.bg.opacity(0.34))
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.borderSubtle).frame(width: 1)
        }
    }

    private func sidebarSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .kerning(0.8)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sidebarEmpty(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.dim)
    }
}

private struct FlowTags: View {
    let tags: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text("#\(tag)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.blue.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }
}
#endif
