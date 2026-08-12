#if os(iOS)
import SwiftData
import SwiftUI

/// A 1pt palette hairline.
///
/// `Divider().background(Theme.borderSubtle)` — which every surface in this file used to draw —
/// does **not** recolour the divider on iOS: it paints the palette colour *behind* a translucent
/// UIKit separator, so what actually shipped was a system grey line with a Theme colour hidden
/// underneath. This is the same `Rectangle().fill(Theme.borderSubtle).frame(height: 1)` macOS's
/// `SidebarSectionDivider` draws.
struct iOSListHairline: View {
    var body: some View {
        Rectangle()
            .fill(Theme.borderSubtle)
            .frame(maxWidth: .infinity)
            .frame(height: 1)
    }
}

/// Section eyebrow for the Lists page's `List`. `Section("Areas")` renders UIKit's own header —
/// system grey small-caps sitting on a system plate — which is a second, non-palette surface on
/// top of the page background. This is the shared `SectionEyebrowLabel` instead.
struct iOSListSectionHeader: View {
    let title: String

    var body: some View {
        SectionEyebrowLabel(text: title)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .textCase(nil)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

extension View {
    /// One row treatment for the Lists page: no plate of its own so the page background shows
    /// through, a palette separator instead of the UIKit one, and insets that line every row's
    /// icon tile up with the page header's.
    func iOSListRowChrome() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparatorTint(Theme.borderSubtle)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }
}

/// Trailing count on a list row, in `SidebarNavCountBadge`'s vocabulary: neutral capsule, neutral
/// digits, fixed size so three digits are never squeezed by a long list name. It is deliberately
/// *not* tinted — the row's identity colour is the icon badge, and a second coloured element per
/// row turns a page of lists into a page of colours.
struct iOSListCountBadge: View {
    let count: Int

    var body: some View {
        Text(count > 999 ? "999+" : "\(count)")
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(Theme.muted)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .frame(minWidth: 24, minHeight: 20)
            .background(Capsule(style: .continuous).fill(Theme.borderSubtle))
            .accessibilityHidden(true)
    }
}

/// The identity tile a list row leads with: the list's own `colorHex` on the glyph over a wash of
/// itself. Delegates to `iOSIconTile` — the shared iOS counterpart of `ListEditorIdentityTile` —
/// rather than re-spelling a rounded square, so a list looks the same wherever it is listed.
struct iOSListIconBadge: View {
    let icon: String
    let colorHex: String
    var size: CGFloat = 34
    var isMuted = false

    var body: some View {
        iOSIconTile(
            systemImage: icon,
            color: Color(hex: colorHex).opacity(isMuted ? 0.55 : 1),
            size: size,
            iconSize: size * 0.44,
            fillOpacity: isMuted ? 0.09 : 0.14
        )
    }
}

/// Page-level header for the Lists page. Used identically by both the compact (iPhone) and
/// regular (iPad) Lists layouts so the two look like the same page rather than a shrunk/expanded
/// variant of each other.
struct iOSListsPageHeader: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let count: Int

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        HStack(alignment: .center, spacing: isRegularWidth ? 12 : 10) {
            iOSListIconBadge(icon: "folder.fill", colorHex: Theme.blueHex, size: isRegularWidth ? 36 : 32)

            VStack(alignment: .leading, spacing: 2) {
                SectionEyebrowLabel(text: "Workspace")
                Text("Lists")
                    .font(.system(size: isRegularWidth ? 21 : 17, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if count > 0 {
                iOSListCountBadge(count: count)
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
///
/// These were two full-width `.borderedProminent` slabs, one blue and one green — the loudest
/// thing on a page whose subject is the user's own list colours. They are the same neutral chip
/// the task view-options bar uses now; the type still carries its colour, on the glyph only.
struct iOSListCreateButtonsRow: View {
    @Binding var editorMode: iOSListEditorMode?

    var body: some View {
        HStack(spacing: 8) {
            iOSActionButton(
                title: "New Area",
                systemImage: "folder.badge.plus",
                role: .secondary,
                size: .compact,
                tint: Theme.blue,
                fullWidth: true
            ) {
                editorMode = .newArea
            }

            iOSActionButton(
                title: "New Project",
                systemImage: "checklist",
                role: .secondary,
                size: .compact,
                tint: Theme.green,
                fullWidth: true
            ) {
                editorMode = .newProject
            }
        }
    }
}

/// The list-detail tab bar, in the vocabulary `CadenceQuietTabButton` established on macOS: text
/// only, exactly one neutral fill layer at one radius, state carried by fill depth and label
/// weight instead of an accent wash. Sized to a 44pt touch target.
///
/// `.plain` rather than `.cadencePlain` on purpose — that style paints its own fill and stroke,
/// which would stack a second selection layer on top of this one.
struct iOSListDetailPagePicker: View {
    @Binding var page: iOSListDetailPage

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                ForEach(iOSListDetailPage.allCases) { item in
                    let isSelected = page == item
                    Button {
                        page = item
                    } label: {
                        Text(item.rawValue)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? Theme.text : Theme.dim)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                                    .fill(isSelected ? Theme.surfaceHighlight : Color.clear)
                            )
                            .contentShape(
                                RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.rawValue)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
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
            iOSListIconBadge(icon: icon, colorHex: colorHex)

            VStack(alignment: .leading, spacing: 3) {
                Text(title.isEmpty ? "Untitled" : title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.subdued)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            iOSListCountBadge(count: count)
        }
        .frame(minHeight: 44)
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
            iOSListIconBadge(icon: icon, colorHex: colorHex, isMuted: true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title.isEmpty ? "Untitled" : title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            iOSActionButton(
                title: "Restore",
                role: .secondary,
                size: .compact,
                action: restore
            )
        }
        .frame(minHeight: 44)
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
            if let note {
                HStack {
                    iOSMarkdownModePicker(mode: editorModeBinding, compact: true)

                    Spacer()

                    iOSNoteTemplateMenu(kind: .list) { template in
                        apply(template, to: note)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                iOSListHairline()
            }

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

/// No panel header on any of the list-detail tabs. The tab bar sits directly above them and
/// already names the tab; a second "COMPLETED / Completed" block 40pt underneath it was the page
/// describing the page you are already on.
struct iOSListCompletedPanel: View {
    let tasks: [AppTask]

    var body: some View {
        Group {
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }
}

struct iOSListPlanningPanel: View {
    let tasks: [AppTask]

    private var todayKey: String { DateFormatters.todayKey() }

    private var planningGroups: [CadenceTaskDisplayGroup] {
        CadenceTaskQuerySupport.planningDisplayGroups(from: tasks, todayKey: todayKey)
    }

    var body: some View {
        Group {
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
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

/// The list's kanban board, in the vocabulary the three macOS boards share
/// (`BoardColumnHeader` / `KanbanColumnScroll` / `KanbanCard`): a containerless column — no fill,
/// no stroke — opened by a section-coloured dot, an uppercase name, a count and a closing
/// hairline, with flat `Theme.surface` cards under it.
///
/// Each column used to be a plate tinted with the **list's** colour, so a six-column board was
/// six identical washes and the per-column colour the list editor stores had nowhere to show. The
/// dot is where that colour lives now, exactly as on macOS.
struct iOSListKanbanPanel: View {
    let tasks: [AppTask]
    let sectionNames: [String]
    /// Colour/completion for the named columns. Names that only exist on a task (a section a list
    /// no longer configures) have no config and fall back to the list's own colour.
    let sectionConfigs: [TaskSectionConfig]
    let accent: Color

    private var columns: [CadenceTaskDisplayGroup] {
        CadenceTaskQuerySupport.sectionGroups(from: tasks, sectionNames: sectionNames)
    }

    var body: some View {
        Group {
            if columns.isEmpty {
                iOSEmptyPanel(
                    systemImage: "square.grid.3x2",
                    title: "No kanban cards",
                    subtitle: "Tasks grouped by section will appear here."
                )
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(columns) { column in
                            iOSListKanbanColumn(
                                title: column.title,
                                dotColor: dotColor(for: column.title),
                                tasks: column.tasks
                            )
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }

    private func dotColor(for name: String) -> Color {
        guard let config = sectionConfigs.first(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) else {
            return accent
        }
        return config.isCompleted ? Theme.green : Color(hex: config.colorHex)
    }
}

private let iOSKanbanColumnWidth: CGFloat = 272

private struct iOSListKanbanColumn: View {
    let title: String
    let dotColor: Color
    let tasks: [AppTask]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSBoardColumnHeader(dotColor: dotColor, title: title, count: tasks.count)

            // The card stack scrolls inside the column, as `KanbanColumnScroll` does on macOS. The
            // board only scrolled horizontally before, so anything past the bottom of a tall column
            // was unreachable.
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(tasks) { task in
                        iOSListKanbanCard(task: task)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .frame(width: iOSKanbanColumnWidth, alignment: .topLeading)
    }
}

private struct iOSListKanbanCard: View {
    @Bindable var task: AppTask
    @Environment(\.modelContext) private var modelContext
    @State private var showDetail = false

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                completionButton

                Text(task.title.isEmpty ? "Untitled" : task.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(task.isDone ? Theme.dim : Theme.text)
                    .strikethrough(task.isDone, color: Theme.dim)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if hasMetadata {
                HStack(spacing: 10) {
                    metadata
                    Spacer(minLength: 0)
                }
                .padding(.leading, 28)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardShape.fill(Theme.surface))
        .overlay { cardShape.strokeBorder(Theme.borderSubtle, lineWidth: 1) }
        .contentShape(cardShape)
        .onTapGesture {
            showDetail = true
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens task details")
        .sheet(isPresented: $showDetail) {
            iOSTaskDetailSheet(task: task)
        }
    }

    /// Same construction `iOSTaskRow` documents: a 44pt touch target inside a glyph-sized layout
    /// frame, so a compliant target does not push the title 20pt into the card.
    private var completionButton: some View {
        Button {
            CadenceTaskMutationSupport.toggleCompletion(task, modelContext: modelContext)
        } label: {
            iOSTaskCompletionCircle(
                isDone: task.isDone,
                tint: Theme.priorityColor(task.priority),
                diameter: 15
            )
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        // `.cadencePlain` is macOS's hover wash: it paints a blue fill and stroke at radius 10
        // around the 44pt label, which then overflows this 20pt layout slot and spills across the
        // card's leading edge and title. `.iosPressable` is the touch equivalent, and is what the
        // rest of the iOS surface uses.
        .buttonStyle(.iosPressable)
        .frame(width: 20, height: 20)
        .padding(.top, 1)
        .accessibilityLabel(task.isDone ? "Mark task todo" : "Complete task")
    }

    private var hasMetadata: Bool {
        !task.scheduledDate.isEmpty || dueUrgency != nil
    }

    /// Tinted icon carries which field this is, neutral text carries its state, and the text only
    /// goes red when the date is genuinely late — `KanbanCard`'s rule, shared with `iOSTaskRow`.
    @ViewBuilder
    private var metadata: some View {
        if !task.scheduledDate.isEmpty {
            iOSTaskMetaLabel(
                systemImage: task.scheduledStartMin >= 0 ? "clock.fill" : "sun.max.fill",
                text: CadenceTaskPresentationSupport.scheduledDateLabel(for: task),
                tint: Theme.amber,
                textColor: isOverdo ? Theme.red : Theme.dim
            )
        }

        if let dueUrgency {
            iOSTaskMetaLabel(
                systemImage: "flag.fill",
                text: CadenceTaskPresentationSupport.dueDateLabel(for: task),
                tint: dueUrgency == .overdue ? Theme.red : Theme.dim,
                textColor: dueUrgency == .overdue ? Theme.red : Theme.dim
            )
        }
    }

    private var dueUrgency: CadenceDueUrgency? {
        CadenceDueUrgency.evaluate(dueDateKey: task.dueDate, isDone: task.isDone)
    }

    private var isOverdo: Bool {
        guard !task.scheduledDate.isEmpty, !task.isDone else { return false }
        return (DateFormatters.dayOffset(from: task.scheduledDate) ?? 0) < 0
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
            HStack {
                iOSActionButton(
                    title: isAdding ? "Cancel" : "Add Link",
                    systemImage: isAdding ? "xmark" : "plus",
                    role: isAdding ? .ghost : .secondary,
                    size: .compact
                ) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isAdding.toggle()
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if isAdding {
                iOSAddLinkForm(
                    title: $newTitle,
                    url: $newURL,
                    save: addLink
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }

            iOSListHairline()

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
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Theme.borderSubtle)
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.bg)
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

/// `.roundedBorder` and `.borderedProminent` are UIKit's own chrome: a grey system field and a
/// filled tint capsule, neither of which reads from the palette. These are the same fields and
/// the same primary action every other iOS surface draws.
private struct iOSAddLinkForm: View {
    @Binding var title: String
    @Binding var url: String
    let save: () -> Void

    private var isSaveDisabled: Bool {
        url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 9) {
            iOSLinkField(placeholder: "Title (optional)", text: $title)
                .textInputAutocapitalization(.words)

            iOSLinkField(placeholder: "URL", text: $url)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(save)

            iOSActionButton(
                title: "Save Link",
                systemImage: "checkmark",
                role: .primary,
                size: .compact,
                fullWidth: true,
                isDisabled: isSaveDisabled,
                action: save
            )
        }
    }
}

private struct iOSLinkField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Theme.surfaceElevated.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
    }
}

private struct iOSLinkRow: View {
    let link: SavedLink

    var body: some View {
        HStack(spacing: 12) {
            iOSListIconBadge(icon: "link", colorHex: Theme.blueHex)

            VStack(alignment: .leading, spacing: 3) {
                Text(link.title.isEmpty ? link.url : link.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                Text(link.url)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.subdued)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "arrow.up.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.dim)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
#endif
