#if os(iOS)
import SwiftData
import SwiftUI

/// The list-detail **Notes** tab: an area's or project's notes, grouped into the folders they were
/// filed in, beside (or over) the editor.
///
/// **This replaces `iOSListNotesPanel`, which showed exactly one note.** It called
/// `CadenceListNoteSupport.firstOrCreateNote`, so a list holding eight notes in three folders
/// rendered whichever one the store handed back first and offered no way to reach the other seven —
/// which is why "folders are invisible on iOS" understated the problem. The folders were invisible
/// because the *notes* were. `Note.folderPath` was read in three macOS files and nowhere else, so a
/// note created here also always landed at the root of a filing system this platform could not
/// draw. Both halves are here now: the groups come from `CadenceNoteFolderGrouping`, the same
/// function macOS's column is built from, and the `+` menu and the row's "Move to Folder" write
/// through `CadenceListNoteFiling` — the one owner of normalization-on-write.
///
/// **Layout only, per size class.** iPad puts the column beside the editor and iPhone makes the
/// column the screen and presents the editor over it — the identical rule the four-tab Notes
/// surface follows, read from the identical function
/// (`CadenceNotesListMetrics.layout(isRegularWidth:hostWidth:)`), so this host cannot acquire a
/// second floor. **The floor is not changed and no third pane is added**: a folder is a heading
/// inside the existing column, exactly as on macOS, not a column of its own.
struct iOSListNotesView: View {
    let area: Area?
    let project: Project?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Note.order) private var allNotes: [Note]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]

    /// Which row is lit, and — in the two-column form — which note the pane beside it holds.
    @State private var selectedNoteID: UUID?
    /// One-column only. The column is the screen there, so the editor is presented over it.
    @State private var presentedNote: Note?
    @State private var folderRequest: iOSNoteFolderRequest?
    /// Set by a row's menu; the `iOSNoteDeletion` modifier owns the confirmation and the delete.
    @State private var noteToDelete: Note?
    /// The width this view was handed, which is not what the size class says about it. Zero until
    /// the first measurement lands — see `CadenceNotesListMetrics.layout`.
    @State private var hostWidth: CGFloat = 0
    // Deliberately `@State` rather than `@FocusState`: the editor's first responder is a
    // `UITextView` inside a `UIViewRepresentable` and nothing here is attached with `.focused(...)`.
    // Same reasoning as `iOSNotesView`.
    @State private var isEditorFocused = false
    @State private var selectedReferenceNote: Note?
    @State private var selectedReferenceTask: AppTask?

    /// The size class only. Every *layout* question goes through `layout`.
    private var isCompactWidth: Bool {
        horizontalSizeClass == .compact
    }

    private var layout: CadenceNotesLayout {
        CadenceNotesListMetrics.layout(isRegularWidth: !isCompactWidth, hostWidth: hostWidth)
    }

    private var metrics: CadenceNotesListMetrics {
        CadenceNotesListMetrics.metrics(isRegularWidth: !isCompactWidth)
    }

    private var listNotes: [Note] {
        CadenceListNoteSupport.notes(for: area, project: project, in: allNotes)
    }

    private var groups: [CadenceNoteFolderGroup] {
        CadenceNoteFolderGrouping.groups(for: listNotes)
    }

    private var folderNames: [String] {
        CadenceNoteFolderGrouping.folderNames(in: listNotes)
    }

    private var selectedNote: Note? {
        guard let selectedNoteID else { return nil }
        return listNotes.first { $0.id == selectedNoteID }
    }

    var body: some View {
        VStack(spacing: 0) {
            controlRow

            iOSListHairline()

            content
        }
        // Measured rather than wrapped, the same call `iOSNotesView` makes: a `GeometryReader`
        // around this stack reads the same width but also becomes the layout container, and this
        // stack holds an editor and a scrolling column that size themselves from what is left.
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            hostWidth = newWidth
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
        .onAppear(perform: normalizeSelection)
        .onChange(of: listNotes.map(\.id)) { _, _ in
            normalizeSelection()
        }
        .fullScreenCover(item: $presentedNote) { note in
            iOSNoteEditorCover(
                note: note,
                templateKind: .list,
                title: note.displayTitle,
                embeddedTaskArea: area,
                embeddedTaskProject: project
            )
        }
        .sheet(item: $folderRequest) { request in
            iOSNoteFolderSheet(request: request, existingFolders: folderNames) { folderPath in
                apply(request, folderPath: folderPath)
            }
        }
        .iOSMarkdownReferenceSheets(
            selectedNote: $selectedReferenceNote,
            selectedTask: $selectedReferenceTask,
            referenceNotes: allNotes,
            referenceTasks: allTasks
        )
        .iOSNoteDeletion(note: $noteToDelete)
    }

    /// No panel header — the tab strip above already says "Notes", and this row carries only
    /// controls. Same rule the other list-detail tabs follow.
    private var controlRow: some View {
        HStack(spacing: 8) {
            Spacer()

            // Regular width only, for the same reason `iOSNotesView.showsHeaderTemplateMenu`
            // gives: in the one-column form the editor is a cover whose own format row already
            // carries the template control, so this row dropping it moves the control rather than
            // removing it.
            if layout == .twoColumn, let note = selectedNote {
                iOSNoteTemplateMenu(kind: .list, compact: true) { template in
                    apply(template, to: note)
                }
                iOSNoteAIActionsMenu(note: note, area: note.area, project: note.project)
            }

            newNoteMenu
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// macOS's `ListNotesHeaderView` menu, item for item: a note at the root, or a note in a
    /// folder named in the sheet.
    private var newNoteMenu: some View {
        Menu {
            Button("New Note") {
                addNote()
            }
            Button("New Note in Folder...") {
                folderRequest = iOSNoteFolderRequest(mode: .newNote)
            }
        } label: {
            iOSIconTile(systemImage: "plus", color: Theme.blue, size: 34, iconSize: 13)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("New note")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .oneColumn:
            notesColumn
        case .twoColumn:
            HStack(spacing: 0) {
                notesColumn
                    .frame(width: CadenceNotesListMetrics.regularColumnWidth)

                Divider().background(Theme.borderSubtle)

                editorPane
            }
        }
    }

    @ViewBuilder
    private var notesColumn: some View {
        Group {
            if groups.isEmpty {
                iOSEmptyPanel(
                    systemImage: "doc.text",
                    title: "No notes",
                    subtitle: "Tap + to create one."
                )
            } else {
                ScrollView {
                    NoteFolderGroupList(groups: groups, metrics: metrics) { note in
                        noteRow(note)
                    }
                    .padding(.horizontal, metrics.columnHorizontalPadding)
                    .padding(.vertical, metrics.columnVerticalPadding)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
    }

    private func noteRow(_ note: Note) -> some View {
        Button {
            open(note)
        } label: {
            NoteFolderListRow(
                title: note.displayTitle,
                detail: NoteRowText.previewBelowTitleHeading(note),
                tags: note.sortedTags,
                isSelected: selectedNoteID == note.id,
                metrics: metrics
            )
        }
        .buttonStyle(.iosPressable)
        // macOS's `ListNoteFolderRow` menu, item for item and in its order: copy, move, delete.
        .contextMenu {
            iOSNoteCopyLinkButton(note: note)
            NoteFolderMoveMenu(
                folderNames: folderNames,
                move: { CadenceListNoteFiling.move(note, toFolder: $0) },
                newFolder: { folderRequest = iOSNoteFolderRequest(mode: .moveNote(note.id)) }
            )
            iOSNoteDeleteMenuButton(note: note) { noteToDelete = $0 }
        }
    }

    /// Regular width only; at compact width the editor is presented over the column instead.
    @ViewBuilder
    private var editorPane: some View {
        if let note = selectedNote {
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
                embeddedTaskArea: area,
                embeddedTaskProject: project
            )
            .id(note.id)
        } else {
            // Title only, macOS's exact wording — a "nothing selected" state, not an empty list.
            iOSEmptyPanel(systemImage: "doc.text", title: "Select a note", subtitle: "")
        }
    }

    // MARK: - Selection

    /// Selecting a row *is* opening it in the two-column form; in the one-column form there is no
    /// pane, so the editor is presented over the column.
    private func open(_ note: Note) {
        selectedNoteID = note.id
        guard layout == .oneColumn else { return }
        presentedNote = note
    }

    private func normalizeSelection() {
        guard selectedNoteID == nil || !listNotes.contains(where: { $0.id == selectedNoteID }) else { return }
        selectedNoteID = groups.first?.notes.first?.id
    }

    // MARK: - Creating and filing

    private func addNote(folderPath: String = CadenceNoteFolderPath.root) {
        let note = CadenceListNoteFiling.createNote(
            in: modelContext,
            area: area,
            project: project,
            folderPath: folderPath,
            order: listNotes.count
        )
        selectedNoteID = note.id
        guard layout == .oneColumn else { return }
        presentedNote = note
    }

    private func apply(_ request: iOSNoteFolderRequest, folderPath: String) {
        switch request.mode {
        case .newNote:
            addNote(folderPath: folderPath)
        case .moveNote(let noteID):
            guard let note = listNotes.first(where: { $0.id == noteID }) else { return }
            CadenceListNoteFiling.move(note, toFolder: folderPath)
        }
    }

    /// Same focus-drop rule as `iOSNotesView.apply(_:to:)`: the editing surface ignores external
    /// writes to its text binding while focused, and a `Menu` does not resign the text view's first
    /// responder — so a template picked with the caret in the editor would be written into a
    /// binding nobody was reading and then overwritten by the stale draft.
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

// MARK: - Folder sheet

/// What the folder sheet was opened to do. macOS's `NoteFolderSheetRequest`, in the iOS spelling —
/// the type itself is inside `#if os(macOS)`, and its `.moveNote` payload is a note id rather than
/// a `Note` for the reason that matters on both platforms: the sheet outlives the row that opened
/// it, so it must re-resolve the note when it is answered.
struct iOSNoteFolderRequest: Identifiable {
    enum Mode {
        case newNote
        case moveNote(UUID)
    }

    let id = UUID()
    let mode: Mode

    var title: String {
        switch mode {
        case .newNote: return "New Folder Note"
        case .moveNote: return "Move to Folder"
        }
    }

    var actionTitle: String {
        switch mode {
        case .newNote: return "Create Note"
        case .moveNote: return "Move"
        }
    }
}

/// Naming a folder. A text field, because a folder **is** a string — there is no folder record to
/// pick from a list, and `CadenceNoteFolderPath` is what turns what is typed into a path.
///
/// Existing folders are offered as rows above the field rather than only in the row's context menu,
/// so filing a note into a folder that already exists never needs it spelled correctly twice.
struct iOSNoteFolderSheet: View {
    let request: iOSNoteFolderRequest
    var existingFolders: [String] = []
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var folderPath = ""
    @FocusState private var isFieldFocused: Bool

    private var normalized: String {
        CadenceNoteFolderPath.normalized(folderPath)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionEyebrowLabel(text: "Folder")
                        TextField("Planning/Research", text: $folderPath)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.text)
                            .focused($isFieldFocused)
                            .submitLabel(.done)
                            .onSubmit(save)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                                    .fill(Theme.surfaceElevated)
                            )
                        Text("Use / to nest, like Planning/Research.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                    }

                    if !existingFolders.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionEyebrowLabel(text: "Existing")
                            ForEach(existingFolders, id: \.self) { folder in
                                Button {
                                    folderPath = folder
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "folder")
                                            .font(.system(size: 13))
                                            .foregroundStyle(Theme.dim)
                                        Text(folder)
                                            .font(.system(size: 15))
                                            .foregroundStyle(normalized == folder ? Theme.text : Theme.muted)
                                            .lineLimit(1)
                                        Spacer(minLength: 0)
                                        if normalized == folder {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(Theme.blue)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 44)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                                            .fill(normalized == folder ? Theme.blue.opacity(0.16) : .clear)
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.iosPressable)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(request.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(request.actionTitle, action: save)
                        .disabled(normalized.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Same deferred focus the macOS pickers use, and for the same reason: setting the
            // `@FocusState` synchronously in `onAppear` lands before the sheet is on screen.
            DispatchQueue.main.async { isFieldFocused = true }
        }
    }

    private func save() {
        guard !normalized.isEmpty else { return }
        onSave(normalized)
        dismiss()
    }
}
#endif
