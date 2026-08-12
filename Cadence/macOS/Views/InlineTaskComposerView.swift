#if os(macOS)
import SwiftUI
import SwiftData

/// The in-place task composer that a board column's ghost row opens.
///
/// **One** view for every such column — the kanban section columns, the All Tasks board's list
/// columns, and the Calendar Board's day columns. What differs between them is data, not code:
/// `InlineTaskComposerSurface` says what the column contributes, `InlineTaskComposerSupport` turns
/// that into seeded fields and a chip set, and everything below just renders it.
///
/// It exists because those columns already answer "where does this go", so the full create sheet
/// asks a question the surface has answered. The chips keep the answer editable without leaving the
/// column, and every picker here is the one the sheet uses — `TaskTitleEntryField` (so `~`, `#` and
/// `!`/`!!`/`!!!` behave identically), `ContainerPickerBadge`, `TaskSectionPickerBadge`,
/// `TaskDateChip`, `TagPickerControl`.
///
/// Creation goes through `TaskCreationService`, the same service the sheet uses. Nothing here
/// builds an `AppTask` by hand — doing that is what let the Calendar Board's old "+" drop an
/// untitled "New Task" card into a column with no way to have meant anything by it.
struct InlineTaskComposer: View {
    let surface: InlineTaskComposerSurface
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query(sort: \Area.order)    private var areas:    [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query(sort: \Tag.order)     private var tags:     [Tag]

    @State private var title = ""
    @State private var fields: InlineTaskComposerFields
    @State private var selectedTags: [Tag] = []
    @State private var showDayPicker = false
    /// Bumped after each create so the title field is rebuilt and re-autofocuses, leaving the
    /// composer ready for the next card instead of stranding the caret.
    @State private var entryGeneration = 0

    init(surface: InlineTaskComposerSurface, onDismiss: @escaping () -> Void) {
        self.surface = surface
        self.onDismiss = onDismiss
        _fields = State(initialValue: InlineTaskComposerSupport.initialFields(for: surface))
    }

    private var chips: InlineTaskComposerChips {
        InlineTaskComposerSupport.chips(for: surface, fields: fields)
    }

    private var availableSections: [String] {
        TaskContainerResolver(areas: areas, projects: projects)
            .availableSections(for: fields.container)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            titleField
            chipRow
            hint
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: kanbanCardCornerRadius, style: .continuous)
                .fill(Theme.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: kanbanCardCornerRadius, style: .continuous)
                .strokeBorder(Theme.blue.opacity(0.45), lineWidth: 1)
        }
        // Focus-scoped rather than a `.cancelAction` button: two columns can hold open composers at
        // once, and a cancel-action shortcut would not know which of them Escape meant.
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .onChange(of: fields.container) { _, container in
            fields.sectionName = InlineTaskComposerSupport.normalizedSectionName(
                fields.sectionName,
                for: container,
                areas: areas,
                projects: projects
            )
        }
    }

    private var titleField: some View {
        TaskTitleEntryField(
            title: $title,
            placeholder: "Task name",
            font: .system(size: 12),
            lineLimit: 1...3,
            autofocus: true,
            contexts: contexts,
            areas: areas,
            projects: projects,
            allTags: tags,
            containerSelection: $fields.container,
            sectionName: $fields.sectionName,
            selectedTags: $selectedTags,
            onCreateTag: createTag,
            onSubmit: create
        )
        .id(entryGeneration)
    }

    @ViewBuilder
    private var chipRow: some View {
        let chips = chips
        HStack(spacing: 6) {
            if chips.showsList {
                ContainerPickerBadge(
                    selection: $fields.container,
                    contexts: contexts,
                    areas: areas,
                    projects: projects,
                    compact: true
                )
            }

            if chips.showsSection {
                TaskSectionPickerBadge(
                    selection: $fields.sectionName,
                    sections: availableSections,
                    compact: true
                )
            }

            if chips.showsDay {
                TaskDateChip(
                    label: "Do Date",
                    icon: "calendar",
                    activeColor: Theme.blue,
                    isOn: dayIsOn,
                    date: dayDate,
                    showPicker: $showDayPicker
                )
            }

            if chips.showsTimeRange, let label = InlineTaskComposerSupport.timeRangeLabel(for: fields) {
                timeRangeChip(label)
            }

            // Only once `#` has actually put a tag on the draft: the surface does not imply tags, so
            // a permanent trigger would be an affordance the column never asked for — but a tag the
            // title field added must stay visible and removable.
            if !selectedTags.isEmpty {
                TagPickerControl(
                    selectedTags: $selectedTags,
                    allTags: tags,
                    onCreateTag: createTag
                )
            }

            Spacer(minLength: 0)
        }
    }

    private func timeRangeChip(_ label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.system(size: 9))
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(Theme.dim)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Theme.borderSubtle, lineWidth: 1)
        }
        .accessibilityLabel("Scheduled \(label)")
    }

    private var hint: some View {
        Text("Return to add · Esc to close")
            .font(.system(size: 9))
            .foregroundStyle(Theme.dim)
    }

    // MARK: - Date chip bindings

    /// Turning the chip *on* must not overwrite a date the chip's own picker just wrote:
    /// `TaskDateChip` sets the date first and flips `isOn` after, so "on" only supplies a default
    /// when there is genuinely no date yet.
    private var dayIsOn: Binding<Bool> {
        Binding(
            get: { !fields.doDateKey.isEmpty },
            set: { isOn in
                if isOn {
                    if fields.doDateKey.isEmpty {
                        fields.doDateKey = DateFormatters.todayKey()
                    }
                } else {
                    fields.doDateKey = ""
                    fields.startMin = -1
                }
            }
        )
    }

    private var dayDate: Binding<Date> {
        Binding(
            get: { DateFormatters.date(from: fields.doDateKey) ?? Date() },
            set: { fields.doDateKey = DateFormatters.dateKey(from: $0) }
        )
    }

    // MARK: - Actions

    private func create() {
        guard InlineTaskComposerSupport.canCreate(title: title) else { return }
        let draft = InlineTaskComposerSupport.draft(title: title, fields: fields, tags: selectedTags)
        guard TaskCreationService(areas: areas, projects: projects)
            .insertTask(from: draft, into: modelContext) != nil else { return }
        try? modelContext.save()
        // Same fast-path reconcile the create sheet runs, so a card created with a do date does not
        // wait for the next scenePhase checkpoint to get its reminder.
        HabitNotificationReconcileSupport.scheduleReconcile(in: modelContext)

        title = ""
        selectedTags = []
        entryGeneration += 1
    }

    private func createTag(_ name: String) -> Tag {
        TagSupport.resolveTags(named: [name], in: modelContext)?.first ?? Tag(name: name)
    }
}
#endif
