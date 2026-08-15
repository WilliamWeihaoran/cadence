#if os(iOS)
import SwiftData
import SwiftUI

/// iOS's full task-creation sheet — the counterpart of macOS's `CreateTaskSheet`.
///
/// Every iOS entry point used to be a one-line "Add a task…" capture bar, so a task acquired a list,
/// a date or a priority only by being created first and then opened again in the inspector. This is
/// the screen that lets it be said once.
///
/// **Keyboard-first.** The title field takes focus on open and the keyboard comes straight up:
/// capture is the app's highest-frequency action and now sits on the tab bar of every screen, so
/// speed is the point. The attribute chips ride *above* the keyboard rather than living in the
/// scroll view, because reaching them must not mean dismissing it.
///
/// The `~` list, `#` tag and `!`/`!!`/`!!!` priority title markers work here exactly as they do in
/// macOS's `TaskTitleEntryField` — same parser (`TaskTitleSupport`), no second implementation. They
/// pay off more here than anywhere: hands are already on the keyboard.
///
/// Creation goes through `TaskCreationService`, like every other path in the app. On success the
/// sheet closes immediately and says nothing — matching macOS, where the feedback is the global
/// toast rather than a confirmation inside the sheet. (iOS has no such toast yet; what it must not
/// do is invent a private one.)
struct iOSCreateTaskSheet: View {
    let seed: CadenceTaskComposerSeed
    /// Handed the created task, for a caller that wants to select or scroll to it. The sheet
    /// dismisses itself either way.
    let onCreated: ((AppTask) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query(sort: \Tag.order) private var tags: [Tag]

    @State private var title: String
    @State private var notes: String
    @State private var fields: CadenceTaskComposerFields
    @State private var selectedTags: [Tag] = []
    @State private var newTagName = ""

    /// A **real** `@FocusState`, attached to the title field with `.focused(_:equals:)`.
    ///
    /// `ToolbarItemGroup(placement: .keyboard)` is driven off SwiftUI's own focus system: seven of
    /// those groups were declared across the iOS markdown surfaces against `@FocusState` properties
    /// that were never attached to anything, and not one of them ever appeared. An unattached
    /// `@FocusState` does not even hold a value.
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case title
        case notes
    }

    init(
        seed: CadenceTaskComposerSeed = CadenceTaskComposerSeed(),
        onCreated: ((AppTask) -> Void)? = nil
    ) {
        self.seed = seed
        self.onCreated = onCreated
        _title = State(initialValue: seed.title)
        _notes = State(initialValue: seed.notes)
        _fields = State(initialValue: CadenceTaskComposerSupport.initialFields(for: seed))
    }

    var body: some View {
        NavigationStack {
            content
                .background(Theme.bg)
                .navigationTitle("New task")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add", action: create)
                            .fontWeight(.semibold)
                            .disabled(!canCreate)
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        chipStrip
                    }
                }
        }
        .tint(Theme.blue)
        .preferredColorScheme(.dark)
        .presentationBackground(Theme.bg)
        // Focus has to be set after the sheet's first layout, or UIKit hands it straight back and
        // the keyboard never comes up — the whole point of this screen.
        .onAppear {
            DispatchQueue.main.async { focusedField = .title }
        }
        .onChange(of: fields.container) { _, _ in normalizeSection() }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                titleField
                markerSuggestions
                notesField
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.never)
        .scrollIndicators(.hidden)
    }

    /// A single-line field on purpose: on a vertical-axis `TextField` the Return key inserts a
    /// newline and `onSubmit` never fires, and Return creating the task is the fastest path off
    /// this screen.
    private var titleField: some View {
        TextField("What needs doing?", text: $title)
            .textFieldStyle(.plain)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Theme.text)
            .tint(Theme.blue)
            .focused($focusedField, equals: .title)
            .submitLabel(.done)
            .onSubmit(create)
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
    }

    private var notesField: some View {
        TextField("Notes", text: $notes, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .foregroundStyle(Theme.text)
            .tint(Theme.blue)
            .focused($focusedField, equals: .notes)
            .lineLimit(2...6)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
    }

    @ViewBuilder
    private var markerSuggestions: some View {
        if let shortcut = TaskTitleSupport.containerShortcut(in: title) {
            iOSTaskComposerMarkerSuggestions(
                kind: .list,
                shortcut: shortcut,
                activeAreas: activeAreas,
                activeProjects: activeProjects,
                allTags: tags,
                onPickContainer: { selection in
                    title = CadenceTaskComposerSupport.title(removingShortcut: shortcut)
                    fields.container = selection
                    normalizeSection()
                },
                onPickTag: { _ in },
                onCreateTag: { _ in }
            )
        } else if let shortcut = TaskTitleSupport.tagShortcut(in: title) {
            iOSTaskComposerMarkerSuggestions(
                kind: .tag,
                shortcut: shortcut,
                activeAreas: activeAreas,
                activeProjects: activeProjects,
                allTags: tags,
                onPickContainer: { _ in },
                onPickTag: { tag in
                    title = CadenceTaskComposerSupport.title(removingShortcut: shortcut)
                    select(tag)
                },
                onCreateTag: { name in
                    title = CadenceTaskComposerSupport.title(removingShortcut: shortcut)
                    if let tag = TagSupport.resolveTags(named: [name], in: modelContext)?.first {
                        select(tag)
                    }
                }
            )
        }
    }

    private var chipStrip: some View {
        iOSTaskComposerChipStrip(
            fields: $fields,
            selectedTags: $selectedTags,
            newTagName: $newTagName,
            titleText: title,
            activeAreas: activeAreas,
            activeProjects: activeProjects,
            availableSections: availableSections,
            allTags: tags,
            onPickPriority: { priority in
                // Strip any `!` marker first: it wins at creation, so leaving it in place would
                // silently overrule the choice just made here.
                title = CadenceTaskComposerSupport.titleClearingPriorityMarker(title)
                fields.priority = priority
            }
        )
    }

    // MARK: - Derived state

    private var activeAreas: [Area] {
        areas.filter(\.isActive)
    }

    private var activeProjects: [Project] {
        projects.filter(\.isActive)
    }

    private var containerResolver: TaskContainerResolver {
        TaskContainerResolver(areas: areas, projects: projects)
    }

    private var availableSections: [String] {
        containerResolver.availableSections(for: fields.container)
    }

    private var canCreate: Bool {
        CadenceTaskComposerSupport.canCreate(title: title)
    }

    // MARK: - Actions

    private func select(_ tag: Tag) {
        guard !selectedTags.contains(where: { $0.id == tag.id }) else { return }
        selectedTags = TagSupport.sorted(selectedTags + [tag])
    }

    private func normalizeSection() {
        fields.sectionName = containerResolver.normalizedSectionName(fields.sectionName, for: fields.container)
    }

    private func create() {
        guard canCreate else { return }

        let draft = CadenceTaskComposerSupport.draft(
            title: title,
            notes: notes,
            fields: fields,
            tags: selectedTags,
            scheduledStartMin: seed.scheduledStartMin,
            estimatedMinutes: seed.estimatedMinutes
        )

        guard let task = TaskCreationService(areas: areas, projects: projects)
            .insertTask(from: draft, into: modelContext)
        else { return }

        try? modelContext.save()
        // Fast-path reconcile so a newly-created scheduled/due task's notification is picked up
        // immediately rather than waiting for the next scenePhase checkpoint — the same call
        // `CreateTaskSheet` makes on macOS.
        HabitNotificationReconcileSupport.scheduleReconcile(in: modelContext)

        onCreated?(task)
        dismiss()
    }
}
#endif
