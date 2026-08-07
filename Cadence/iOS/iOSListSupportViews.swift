#if os(iOS)
import SwiftData
import SwiftUI

/// Page-level header for the Lists page. Mirrors `iOSPanelHeader`'s sizing/spacing
/// (so it fits comfortably in the iPad split pane) while adding the icon-square
/// treatment used by other top-level pages (Today/Inbox/Focus), so the Lists page
/// reads as a first-class page rather than a plain nav-bar title. Used identically
/// by both the compact (iPhone) and regular (iPad) Lists layouts so the two look
/// like the same page rather than a shrunk/expanded variant of each other.
struct iOSListsPageHeader: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let count: Int

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        HStack(alignment: .center, spacing: isRegularWidth ? 12 : 10) {
            Image(systemName: "folder.fill")
                .font(.system(size: isRegularWidth ? 16 : 15, weight: .semibold))
                .foregroundStyle(Theme.blue)
                .frame(width: isRegularWidth ? 36 : 32, height: isRegularWidth ? 36 : 32)
                .background(Theme.blue.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: isRegularWidth ? 10 : 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: isRegularWidth ? 10 : 9, style: .continuous)
                        .strokeBorder(Theme.blue.opacity(0.20), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("Workspace")
                    .font(.system(size: isRegularWidth ? 10 : 9, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .textCase(.uppercase)
                    .kerning(0.8)
                Text("Lists")
                    .font(.system(size: isRegularWidth ? 21 : 17, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if count > 0 {
                Text("\(count)")
                    .font(.system(size: isRegularWidth ? 13 : 12, weight: .bold))
                    .foregroundStyle(Theme.blue)
                    .padding(.horizontal, isRegularWidth ? 10 : 8)
                    .padding(.vertical, isRegularWidth ? 6 : 4)
                    .background(Theme.blue.opacity(0.11))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, isRegularWidth ? 20 : 16)
        .padding(.top, isRegularWidth ? 16 : 13)
        .padding(.bottom, isRegularWidth ? 11 : 7)
    }
}

/// Shared "New Area / New Project" action row for the Lists page. Used by both the
/// compact and regular layouts so list creation doesn't rely on a native nav-bar
/// toolbar menu (which disappears once the plain nav bar is hidden in favor of
/// `iOSListsPageHeader`).
struct iOSListCreateButtonsRow: View {
    @Binding var editorMode: iOSListEditorMode?

    var body: some View {
        HStack(spacing: 8) {
            Button {
                editorMode = .newArea
            } label: {
                Label("Area", systemImage: "folder.badge.plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.blue)

            Button {
                editorMode = .newProject
            } label: {
                Label("Project", systemImage: "checklist")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.green)
        }
    }
}

struct iOSListDetailPagePicker: View {
    @Binding var page: iOSListDetailPage

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(iOSListDetailPage.allCases) { item in
                    Button {
                        page = item
                    } label: {
                        Label(item.rawValue, systemImage: item.systemImage)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .foregroundStyle(page == item ? Theme.text : Theme.dim)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(page == item ? Theme.blue.opacity(0.18) : Theme.surface)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollIndicators(.hidden)
    }
}

struct iOSListPickerRow: View {
    let title: String
    let subtitle: String?
    let icon: String
    let colorHex: String
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: colorHex))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title.isEmpty ? "Untitled" : title)
                    .foregroundStyle(Theme.text)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.dim)
                }
            }

            Spacer()

            Text("\(count)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.dim)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.surfaceElevated)
                .clipShape(Capsule())
        }
    }
}

struct iOSArchivedListRow: View {
    let title: String
    let subtitle: String?
    let icon: String
    let colorHex: String
    let restore: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(hex: colorHex).opacity(0.58))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title.isEmpty ? "Untitled" : title)
                    .foregroundStyle(Theme.muted)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.dim)
                }
            }

            Spacer()

            Button("Restore", action: restore)
                .font(.caption.weight(.semibold))
        }
        .padding(.vertical, 3)
    }
}

struct iOSListNotesPanel: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    let area: Area?
    let project: Project?
    @State private var note: Note?
    @State private var isEditorFocused = false
    @AppStorage(iOSMarkdownEditorPreferences.modeKey) private var editorModeRaw = iOSMarkdownEditorPreferences.defaultMode.rawValue
    @State private var selectedReferenceNote: Note?
    @State private var selectedReferenceTask: AppTask?

    private var editorModeBinding: Binding<iOSMarkdownEditorMode> {
        iOSMarkdownEditorPreferences.binding(for: $editorModeRaw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSPanelHeader(eyebrow: "List Notes", title: "Notes")

            if let note {
                HStack {
                    iOSMarkdownModePicker(mode: editorModeBinding, compact: true)

                    Spacer()

                    iOSNoteTemplateMenu(kind: .list) { template in
                        apply(template, to: note)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            Divider().background(Theme.borderSubtle)

            if let note {
                iOSMarkdownEditingSurface(
                    text: Binding(
                        get: { note.content },
                        set: { update(note, content: $0) }
                    ),
                    isFocused: $isEditorFocused,
                    mode: editorModeBinding,
                    placeholder: "Start writing...",
                    referenceNotes: allNotes,
                    referenceTasks: allTasks,
                    onOpenReference: openMarkdownReference,
                    embeddedTaskArea: area,
                    embeddedTaskProject: project
                )
            } else {
                ProgressView()
                    .tint(Theme.blue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.surface)
        .onAppear(perform: loadOrCreateNote)
        .iOSMarkdownReferenceSheets(
            selectedNote: $selectedReferenceNote,
            selectedTask: $selectedReferenceTask,
            referenceNotes: allNotes,
            referenceTasks: allTasks
        )
    }

    private func loadOrCreateNote() {
        note = CadenceListNoteSupport.firstOrCreateNote(for: area, project: project, in: modelContext)
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

struct iOSListCompletedPanel: View {
    let tasks: [AppTask]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSPanelHeader(eyebrow: "Archive", title: "Completed", count: tasks.count)
            Divider().background(Theme.borderSubtle)

            if tasks.isEmpty {
                iOSEmptyPanel(
                    systemImage: "checkmark.circle",
                    title: "No completed tasks",
                    subtitle: "Completed work from this list will collect here."
                )
            } else {
                List {
                    ForEach(tasks) { task in
                        iOSTaskListRow(task: task, opacity: 0.62)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Theme.surface)
            }
        }
        .background(Theme.surface)
    }
}

struct iOSListPlanningPanel: View {
    let tasks: [AppTask]

    private var todayKey: String { DateFormatters.todayKey() }

    private var planningGroups: [CadenceTaskDisplayGroup] {
        CadenceTaskQuerySupport.planningDisplayGroups(from: tasks, todayKey: todayKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSPanelHeader(eyebrow: "Dates", title: "Planning", count: tasks.count)
            Divider().background(Theme.borderSubtle)

            if tasks.isEmpty {
                iOSEmptyPanel(
                    systemImage: "calendar",
                    title: "No active tasks",
                    subtitle: "Add tasks before planning dates."
                )
            } else {
                List {
                    ForEach(planningGroups) { group in
                        planningSection(group)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Theme.surface)
            }
        }
        .background(Theme.surface)
    }

    @ViewBuilder
    private func planningSection(_ group: CadenceTaskDisplayGroup) -> some View {
        Section {
            ForEach(group.tasks) { task in
                iOSTaskListRow(task: task)
            }
        } header: {
            iOSTaskSectionHeader(title: group.title, color: group.accent)
        }
    }
}

struct iOSListKanbanPanel: View {
    let title: String
    let tasks: [AppTask]
    let sectionNames: [String]
    let accent: Color

    private var columns: [(name: String, tasks: [AppTask])] {
        CadenceTaskQuerySupport.sectionGroups(from: tasks, sectionNames: sectionNames)
            .map { ($0.title, $0.tasks) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSPanelHeader(eyebrow: title, title: "Kanban", count: tasks.count)
            Divider().background(Theme.borderSubtle)

            if columns.isEmpty {
                iOSEmptyPanel(
                    systemImage: "square.grid.3x2",
                    title: "No kanban cards",
                    subtitle: "Tasks grouped by section will appear here."
                )
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(columns, id: \.name) { column in
                            iOSListKanbanColumn(
                                title: column.name,
                                tasks: column.tasks,
                                accent: accent
                            )
                        }
                    }
                    .padding(14)
                }
                .background(Theme.bg)
            }
        }
        .background(Theme.surface)
    }
}

private struct iOSListKanbanColumn: View {
    let title: String
    let tasks: [AppTask]
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(title.uppercased()) · \(tasks.count)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(accent.opacity(0.8))
                .kerning(0.6)
                .lineLimit(1)

            VStack(spacing: 6) {
                ForEach(tasks) { task in
                    iOSListKanbanCard(task: task)
                }
            }
        }
        .padding(8)
        .frame(width: 260, alignment: .topLeading)
        .background(accent.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(accent.opacity(0.18), lineWidth: 1)
        }
    }
}

private struct iOSListKanbanCard: View {
    @Bindable var task: AppTask
    @Environment(\.modelContext) private var modelContext
    @State private var showDetail = false

    private var rowTint: Color {
        switch task.priority {
        case .high: return Theme.red
        case .medium: return Theme.amber
        case .low: return Theme.blue
        case .none: return Theme.dim
        }
    }

    var body: some View {
        Button {
            showDetail = true
        } label: {
            HStack(alignment: .top, spacing: 8) {
                iOSTaskCompletionCircle(isDone: task.isDone, tint: rowTint)
                    .frame(width: 13, height: 13)
                    .padding(.top, 2)
                    .onTapGesture {
                        CadenceTaskMutationSupport.toggleCompletion(task, modelContext: modelContext)
                    }

                Text(task.title.isEmpty ? "Untitled" : task.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(task.isDone ? Theme.dim : Theme.text)
                    .strikethrough(task.isDone, color: Theme.dim)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(9)
            .background(Color(hex: "#151824"))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Theme.borderSubtle, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            iOSTaskDetailSheet(task: task)
        }
    }
}

struct iOSListLinksPanel: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query(sort: \SavedLink.order) private var allLinks: [SavedLink]
    let area: Area?
    let project: Project?
    @State private var isAdding = false
    @State private var newTitle = ""
    @State private var newURL = ""

    private var links: [SavedLink] {
        if let area {
            return allLinks.filter { $0.area?.id == area.id }
        }
        if let project {
            return allLinks.filter { $0.project?.id == project.id }
        }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSPanelHeader(eyebrow: "Reference", title: "Links", count: links.count)

            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isAdding.toggle()
                    }
                } label: {
                    Label(isAdding ? "Cancel" : "Add Link", systemImage: isAdding ? "xmark" : "plus")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(isAdding ? Theme.dim : Theme.blue)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            if isAdding {
                iOSAddLinkForm(
                    title: $newTitle,
                    url: $newURL,
                    save: addLink
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            Divider().background(Theme.borderSubtle)

            if links.isEmpty {
                iOSEmptyPanel(
                    systemImage: "link",
                    title: "No saved links",
                    subtitle: "Save URLs that belong with this list."
                )
            } else {
                List {
                    ForEach(links) { link in
                        Button {
                            open(link)
                        } label: {
                            iOSLinkRow(link: link)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                delete(link)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Theme.surface)
            }
        }
        .background(Theme.surface)
    }

    private func addLink() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        var url = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }

        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            url = "https://\(url)"
        }

        let link = SavedLink(title: title.isEmpty ? url : title, url: url)
        link.area = area
        link.project = project
        link.order = (links.map(\.order).max() ?? -1) + 1
        modelContext.insert(link)
        try? modelContext.save()
        newTitle = ""
        newURL = ""
        isAdding = false
    }

    private func open(_ link: SavedLink) {
        guard let url = URL(string: link.url) else { return }
        openURL(url)
    }

    private func delete(_ link: SavedLink) {
        modelContext.delete(link)
        try? modelContext.save()
    }
}

private struct iOSAddLinkForm: View {
    @Binding var title: String
    @Binding var url: String
    let save: () -> Void

    var body: some View {
        VStack(spacing: 9) {
            TextField("Title (optional)", text: $title)
                .textInputAutocapitalization(.words)
                .textFieldStyle(.roundedBorder)

            TextField("URL", text: $url)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

            Button(action: save) {
                Label("Save Link", systemImage: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.blue)
            .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

private struct iOSLinkRow: View {
    let link: SavedLink

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "link")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.blue)
                .frame(width: 32, height: 32)
                .background(Theme.blue.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(link.title.isEmpty ? link.url : link.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                Text(link.url)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "arrow.up.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.dim.opacity(0.72))
        }
        .padding(.vertical, 5)
    }
}
#endif
