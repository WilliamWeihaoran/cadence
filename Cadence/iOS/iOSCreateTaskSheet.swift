#if os(iOS)
import SwiftData
import SwiftUI

/// iOS's full task-creation sheet — the counterpart of macOS's `CreateTaskSheet`.
///
/// Every iOS entry point used to be a one-line "Add a task…" capture bar, so a task acquired a list,
/// a date or a priority only by being created first and then opened again in the inspector. This is
/// the screen that lets it be said once.
///
/// **Keyboard-first, but nothing is pinned to the floor.** The title field takes focus on open and
/// the keyboard comes straight up: capture is the app's highest-frequency action and sits on the
/// tab bar of every screen, so speed is the point. Everything the task can be given is then stated
/// **in the page** — a Do row of three one-tap buttons, then labelled rows for List, Section, Due,
/// Priority and Tags, each showing its current value.
///
/// It used to be a horizontally-scrolling chip strip above the keyboard with ~700pt of empty sheet
/// over it. The strip scrolled, so the sixth chip was off the right edge of a 390pt phone and
/// unreachable without dragging a control most people never knew moved. The stronger reason for
/// rows is what this sheet is *for*: it is opened from four places — the tab bar `+`, the iPad
/// corner `+`, quick capture, and a `+` dragged onto a row — and three of them **seed** fields. A
/// seeded chip is indistinguishable from an unseeded one until the whole strip has been read; a
/// seeded row says `List   Errands` at a glance, which is the entire argument.
///
/// **No estimate control**, deliberately: how long something takes is a judgement made once the
/// task is real, and macOS's `CreateTaskSheet` has never had one either.
///
/// **Size class changes layout, never content.** iPhone and iPad get the same fields in the same
/// order; only the width the sheet is drawn at differs.
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
            VStack(alignment: .leading, spacing: 14) {
                titleField
                markerSuggestions
                notesField
                iOSTaskComposerDoDateButtons(doDateKey: $fields.doDateKey)
                fieldRows
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 20)
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

    /// One line at rest, growing to six once you are actually writing in it.
    ///
    /// It was `lineLimit(2...6)` — a permanently two-line box on a sheet whose height is the
    /// binding constraint. Measured on a 390pt phone: the rows below reach ~580pt, and with a
    /// software keyboard up (~336pt) only ~508pt of the sheet is visible, so the Tags row sat about
    /// 70pt below the fold — and a seeded value you cannot see is the thing the rows were chosen
    /// over chips to avoid. Collapsing the resting state is the first step of the retreat the task
    /// recorded, before folding Tags into the title field's `#` picker or letting the sheet scroll.
    private var notesField: some View {
        TextField("Notes", text: $notes, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .foregroundStyle(Theme.text)
            .tint(Theme.blue)
            .focused($focusedField, equals: .notes)
            .lineLimit(focusedField == .notes || !notes.isEmpty ? 3...6 : 1...1)
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

    private var fieldRows: some View {
        iOSTaskComposerFieldRows(
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
