#if os(iOS)
import SwiftData
import SwiftUI

/// The inspector's identity block: completion control + title + priority on one row.
///
/// **The control on the left settles the task**, and it is the only thing in the sheet that
/// writes `.done`. T-344 decided what it means on a *cancelled* task: it is a settled/open toggle,
/// so it restores that task to todo rather than completing it — see
/// `CadenceTaskMutationSupport.toggleCompletion` for why that way round. macOS makes its *leading*
/// tile the priority control and puts completion in the foot buttons; iOS goes the other way on
/// purpose. Completing is the dominant touch action, and every task row on this platform already
/// teaches "tinted circle, tap to complete" — the sheet having a *different* meaning for the same
/// glyph would be the surprise. Priority is what the circle is tinted by, exactly as in
/// `iOSTaskRow`, and since T-1278 it is edited from the trailing end of this same row: the two
/// platforms now put the same mark control on the title line, just at opposite ends of it, each
/// beside the control that platform's users reach for first.
///
/// The five-chip strip that used to sit under the title is gone. Not one of those chips was a
/// button — they were painted to look exactly like the tappable chips elsewhere in the app, sat
/// directly above the editable rows that own the same five fields, and swallowed every tap aimed
/// at them.
struct iOSTaskEditorTitleCard: View {
    @Bindable var task: AppTask
    let onToggleCompletion: () -> Void

    @State private var showPriorityPicker = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling

    /// Every figure in this row comes from `iOSTaskInspectorMetrics` and none of them from
    /// `horizontalSizeClass`. The row used to size its circle, its title and the gap above the
    /// circle by the width of the screen *behind* the sheet — three numbers for one control, none
    /// of which the sheet's own 640pt column varies by.
    ///
    /// Since T-1364 the width it does answer to is the reader's text size, and the circle answers
    /// through the same metrics type rather than beside it.
    private var glyphSize: CGFloat {
        iOSTaskInspectorMetrics.completionGlyphSize(at: dynamicTypeSize, scaling: scaling)
    }

    /// Done and cancelled are both "settled": the title reads as struck through and stops being
    /// the loudest text in the sheet.
    ///
    /// Read from `CadenceTaskCompletionState`, the same decision the circle to its left resolves,
    /// rather than restated as `isDone || isCancelled` — this sheet and `iOSTaskRow` had two
    /// spellings of it and only one of them included cancelled.
    private var isSettled: Bool {
        CadenceTaskCompletionState.resolve(task: task).isSettled
    }

    var body: some View {
        HStack(alignment: .top, spacing: iOSTaskInspectorMetrics.titleRowSpacing) {
            Button(action: onToggleCompletion) {
                iOSTaskCompletionCircle(
                    glyph: .resolve(task: task),
                    diameter: glyphSize
                )
                .frame(width: glyphSize, height: glyphSize)
                .iOSExpandedHitArea((44 - glyphSize) / 2)
            }
            .buttonStyle(.iosPressable)
            .accessibilityLabel(CadenceTaskQuerySupport.isFinishedTask(task) ? "Mark task todo" : "Complete task")
            // Aligns the circle with the first line of a title that may wrap to three — derived
            // from the circle and the title it sits beside, so it cannot fall out of step with
            // either.
            .padding(.top, iOSTaskInspectorMetrics.completionTopPadding(at: dynamicTypeSize, scaling: scaling))

            VStack(alignment: .leading, spacing: 3) {
                // Only the two statuses a checkbox cannot express say anything here. "Todo" over
                // every unfinished task is a label that fires on the common case, and the tick
                // already says "done".
                if task.status == .inProgress || task.isCancelled {
                    SectionEyebrowLabel(
                        text: task.status.label,
                        tint: CadenceTaskPresentationSupport.statusColor(task.status)
                    )
                }

                TextField("Task title", text: $task.title, axis: .vertical)
                    .cadenceFont(.editorTitle, base: iOSTaskInspectorMetrics.titleSize)
                    .foregroundStyle(isSettled ? Theme.dim : Theme.text)
                    .strikethrough(isSettled, color: Theme.dim)
                    .textFieldStyle(.plain)
                    .lineLimit(1...iOSTaskInspectorMetrics.titleLineLimit)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            priorityControl
        }
    }

    /// **The trailing slot on the title row, and since T-1278 it is the priority.** It held the
    /// estimate chip; the estimate is a row in the field list now. Fixed-size either way, so a long
    /// title wraps rather than squeezing what sits beside it — the arrangement
    /// `TaskDetailHeaderSection` settled on, which is also where the priority sits on macOS.
    ///
    /// **Marks, not a flag.** The owner asked for a flag "like macOS", and on macOS `flag.fill` is
    /// the **due date** — it is the glyph one row below this in the field list, and it goes red when
    /// the deadline passes. Priority has been the `!` / `!!` / `!!!` convention app-wide for as long
    /// as `TaskPriorityMarkControl` has carried the comment saying so. Shown both, the owner chose
    /// one style across devices, so this draws the shared control itself rather than a copy of its
    /// shape: `Theme.priorityColor` at 10% fill and 30% border, `radiusControlCompact`, and the
    /// glyph from `TaskTitleSupport.priorityMark(for:)`. macOS is unchanged by that choice.
    ///
    /// The tile is 28pt on both platforms because it is one view; the 44pt touch target is added
    /// here, where the platform difference actually is.
    private var priorityControl: some View {
        Button {
            showPriorityPicker = true
        } label: {
            TaskPriorityMarkControl(priority: task.priority)
                .iOSExpandedHitArea(8)
        }
        .buttonStyle(.iosPressable)
        .fixedSize()
        .accessibilityLabel("Priority")
        .accessibilityValue(task.priority.label)
        .popover(isPresented: $showPriorityPicker) {
            iOSChoicePopoverList(
                rows: TaskPriority.allCases.map { priority in
                    iOSChoiceRow(
                        value: priority,
                        // Words, and no glyph. The control that opened this popover draws the
                        // mark; a picker *names* the levels — the same call
                        // `CadenceTaskComposerSupport.priorityValueLabel` makes for the create
                        // sheet's tile, where "the `!!` mark named the field rather than the
                        // value". A `flag.fill` here would be the collision with the Due row that
                        // T-1278 chose marks to avoid, and `iOSChoiceRow`'s leading slot takes an
                        // SF Symbol, not a run of exclamation marks. The tint carries the level.
                        title: priority.label,
                        systemImage: nil,
                        color: Theme.priorityColor(priority)
                    )
                },
                selection: $task.priority,
                isPresented: $showPriorityPicker
            )
        }
    }
}

/// `List › Section`, each segment opening its own picker.
///
/// This replaces a "List" row and a "Section" row — two labelled rows to say one thing. The section
/// segment disappears when the container has nothing to choose between (`CadenceTaskInspectorSupport`
/// decides, so macOS's breadcrumb hides it on exactly the same tasks), which is why an Inbox task
/// reads simply `Inbox` rather than `Inbox › Default`.
struct iOSTaskPlacementBreadcrumb: View {
    @Bindable var task: AppTask
    let containerSelection: Binding<String>
    /// **Every** list, not the active ones (T-514). The sheet's `loadContainerSelection()` seeds
    /// this breadcrumb's token from `task.area` / `task.project` — the unfiltered relationship —
    /// and `iOSTaskDetailSheet.selectedArea` resolves it against the unfiltered `@Query`, so a task
    /// in an area that had since been archived saved and sectioned correctly while the segment
    /// resolved the same id against `activeAreas`, missed, and said **"Inbox"**. Third instance of
    /// the display/save split: T-446 fixed it for Context, T-488 for Area.
    ///
    /// The two halves are now one array and one resolver. The title reads
    /// `CadenceTaskComposerSupport.containerName(for:areas:projects:)`, whose rule is *existence,
    /// not activity* — the same rule the save uses — and the picker narrows for itself.
    let areas: [Area]
    let projects: [Project]
    let availableSectionNames: [String]

    @State private var showContainerPicker = false
    @State private var showSectionPicker = false

    private var container: TaskContainerSelection {
        CadenceTaskComposerSupport.selection(fromToken: containerSelection.wrappedValue)
    }

    /// The list the token names, resolved **once** and read by the segment's name, glyph and
    /// unset-ness alike — the shape `iOSTaskComposerValueTiles` already settled on for T-318.
    private var resolvedContainer: GoalLinkTarget? {
        CadenceTaskComposerSupport.resolvedContainer(for: container, areas: areas, projects: projects)
    }

    private var containerTitle: String {
        CadenceTaskComposerSupport.containerName(for: container, areas: areas, projects: projects)
    }

    private var containerIcon: String {
        switch resolvedContainer {
        case .project: return "checklist"
        case .area, .none: return "tray.full.fill"
        }
    }

    /// A token naming a list that has been *deleted* reads as unset here for the same reason it
    /// reads "Inbox" above: that is where the task is. An archived list is not deleted, so it
    /// resolves and the segment stays set.
    private var isInbox: Bool {
        resolvedContainer == nil
    }

    private var showsSectionSegment: Bool {
        !isInbox && CadenceTaskInspectorSupport.showsSectionSegment(availableSections: availableSectionNames)
    }

    var body: some View {
        CadenceWrappingHStack(spacing: 4, lineSpacing: 4) {
            iOSTaskAttributeChip(
                title: containerTitle,
                field: CadenceTaskControlAccessibility.list,
                systemImage: containerIcon,
                isSet: !isInbox
            ) {
                showContainerPicker = true
            }
            .popover(isPresented: $showContainerPicker) {
                iOSContainerChoicePopover(
                    areas: areas,
                    projects: projects,
                    selection: containerSelection,
                    isPresented: $showContainerPicker
                )
            }

            if showsSectionSegment {
                Text("\u{203A}")
                    .cadenceFont(.controlLabel)
                    .foregroundStyle(Theme.dim)
                    .accessibilityHidden(true)

                iOSTaskAttributeChip(
                    // The real name of where the task is, never "None": dimmer styling is what
                    // conveys "unset", so the segment and its picker cannot disagree.
                    title: CadenceTaskInspectorSupport.sectionSegmentTitle(task.sectionName),
                    field: CadenceTaskControlAccessibility.section,
                    systemImage: nil,
                    isSet: !task.sectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    showSectionPicker = true
                }
                .popover(isPresented: $showSectionPicker) {
                    iOSChoicePopoverList(
                        rows: availableSectionNames.map { name in
                            iOSChoiceRow(value: name, title: name, color: Theme.dim)
                        },
                        selection: $task.sectionName,
                        isPresented: $showSectionPicker
                    )
                }
            }
        }
    }
}

/// The one tappable pill that stands for a single task attribute: a segment of the inspector's
/// placement breadcrumb, and a chip in the create sheet's strip above the keyboard.
///
/// Neutral by default, because which list a task is in is ordinary information and colour in these
/// surfaces is spent only on what is exceptional. `tint` is the opt-out, for the two attributes
/// whose *value* is a colour the user already reads as one — a list's own `colorHex`, and a
/// priority.
struct iOSTaskAttributeChip: View {
    let title: String
    /// **The field this chip names, and it has no default on purpose (T-611).**
    ///
    /// A chip draws its *value* — "Tomorrow", "Weekly", "30m", "Website" — and nothing that says
    /// which field the value belongs to. Sighted users get that from where the chip sits in the
    /// strip; VoiceOver got "Tomorrow, Opens a picker" and had to guess whether it was the do date
    /// or the due date, which is the same defect T-594 fixed on the macOS row.
    ///
    /// The fix is `.accessibilityLabel` + `.accessibilityValue` — SwiftUI's pair for exactly this,
    /// so the name stays put while the reading changes — and it lives **here** rather than at the
    /// seven call sites. That is what stops the eighth: a chip added without naming its field does
    /// not fail a scan, it fails to compile. Take the word from
    /// `CadenceTaskControlAccessibility`; the row and the inspector must not spell one field two
    /// ways.
    let field: String
    var systemImage: String? = nil
    var isSet: Bool = false
    /// Glyph colour once the field is set. `nil` keeps the neutral treatment.
    var tint: Color? = nil
    /// Type ramp and plate height. `.row` exists because a task row's chips sit under a 13pt title
    /// and there may be five of them, so the sheet's 13pt-semibold plate would compete with the
    /// title for the row's loudest text. Only the ramp changes — every size keeps the same 44pt
    /// touch target, because a finger is the same size on both surfaces.
    var size: iOSTaskAttributeChipSize = .standard
    /// Foreground for a *set* chip's text. Defaults to `Theme.text`; the task row passes `Theme.dim`
    /// because there a chip is metadata that happens to be tappable rather than a field being
    /// filled in, and its text at full contrast read louder than the title above it.
    var textColor: Color? = nil
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling

    private var glyphColor: Color {
        guard isSet, let tint else { return Theme.dim }
        return tint
    }

    private var titleColor: Color {
        guard isSet else { return Theme.dim }
        return textColor ?? Theme.text
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: size.iconSpacing) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .cadenceFont(.controlLabel, base: size.iconSize)
                        .foregroundStyle(glyphColor)
                }
                Text(title)
                    .cadenceFont(.controlLabel, base: size.fontSize)
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, size.horizontalPadding)
            // `minHeight`, not `height` (T-1364). The plate was pinned at 30pt around a 13pt label;
            // at an accessibility size that label is 38pt and a fixed 30pt frame does not clip it,
            // it centres it and lets it draw over the chips on the lines above and below. The
            // floor still grows by what the label gained, so a 44pt touch target is unchanged at
            // the sizes it was measured at.
            .frame(minHeight: size.height(at: dynamicTypeSize, scaling: scaling))
            .background(Theme.surfaceElevated.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            .contentShape(Rectangle())
            // Same 44pt target at every size — see `iOSTaskAttributeChipSize.hitInset`. Callers
            // that stack these in a wrapping strip must keep the strip's `lineSpacing` at or above
            // twice this inset, or the expanded regions of two lines overlap and the lower chip,
            // being drawn last, silently answers taps meant for the upper one.
            .iOSExpandedHitArea(size.hitInset)
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel(field)
        .accessibilityValue(title)
        .accessibilityHint("Opens a picker")
    }
}

/// The two scales `iOSTaskAttributeChip` is drawn at, and the geometry each implies.
///
/// `hitInset` is derived rather than chosen: it is whatever brings the plate up to the 44pt touch
/// minimum, so a smaller plate expands further and the target never shrinks with the type.
enum iOSTaskAttributeChipSize {
    /// The create sheet's strip and the inspector's placement breadcrumb.
    case standard
    /// A task row's metadata strip, under a 13pt title.
    case row

    /// Both plates are 30pt, so the two sizes differ **only** in type ramp.
    ///
    /// `.row` was 26pt first, which cost more height than it saved: the strip's line gap has to be
    /// twice the hit inset (see `hitInset`), so a shorter plate bought 4pt of plate and spent 4pt of
    /// gap — and a 26pt pill with an 18pt gap under it read as two disconnected strips rather than
    /// one wrapped one.
    var height: CGFloat { 30 }

    /// The plate, holding its own label at the reader's text size. Additive, like every other
    /// container in `CadenceTypeScale`: the 17pt of padding inside a 30pt plate around a 13pt label
    /// is padding, and padding does not triple.
    func height(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CGFloat {
        CadenceTypeScale.height(self.height, holding: .controlLabel, textBase: fontSize, at: dynamicTypeSize, scaling: scaling)
    }

    var fontSize: CGFloat {
        switch self {
        case .standard: return 13
        case .row: return 11
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .standard: return 10
        case .row: return 9.5
        }
    }

    var iconSpacing: CGFloat {
        switch self {
        case .standard: return 5
        case .row: return 4
        }
    }

    /// Stated in `CadenceTaskChipPadding`, beside macOS's, so the two chips' plates sit in one
    /// place rather than in two (T-617). Still two different numbers: naming them together was not
    /// a decision to converge them.
    var horizontalPadding: CGFloat {
        switch self {
        case .standard: return CadenceTaskChipPadding.iOSStandardHorizontal
        case .row: return CadenceTaskChipPadding.iOSRowHorizontal
        }
    }

    /// Whatever it takes to reach 44pt.
    var hitInset: CGFloat {
        max(0, (44 - height) / 2)
    }
}

/// The task's tags: the chips themselves plus one `+` that opens the picker.
///
/// This replaces a section that listed **every** tag in the app as a row in the middle of the
/// sheet, with a horizontal `ScrollView` of the selected ones above it — a scroller nested in the
/// sheet's own scroll view, which is the defect that made the task row's metadata unreachable. The
/// chips wrap now, and the catalogue lives in the popover where a catalogue belongs.
struct iOSTaskTagStrip: View {
    @Bindable var task: AppTask
    let allTags: [Tag]
    @Binding var newTagName: String
    @Environment(\.modelContext) private var modelContext
    /// The strip is inside `iOSTaskDetailSheet`, which is a declared scaled root, so both halves
    /// of the pair are read here and handed to the two spacings that are derived from the chip's
    /// remove-control overhang (T-1412).
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var typographyScaling

    @State private var showPicker = false
    /// **T-1070.** Set when the store refused a chip's `x`. The popover has its own copy for the
    /// refusals *it* can cause, because it is a separate surface and is still open when one
    /// happens; this one is for the strip, which is what the user is looking at when they remove a
    /// chip from the task.
    @State private var tagFailureNotice: String?

    private var selectedTags: [Tag] {
        TagSupport.sorted(task.tags ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            chips

            if let tagFailureNotice {
                CadenceInlineFailureNotice(text: tagFailureNotice)
            }
        }
    }

    private var chips: some View {
        CadenceWrappingHStack(
            spacing: CadenceTagChipStyle.editableStripSpacing(
                for: .regular, at: dynamicTypeSize, scaling: typographyScaling
            ),
            // Wider than it looks like it needs to be. The chip's remove control carries a 44pt
            // touch target grown past what is drawn, so these two numbers are the clearance that
            // keeps one chip's expanded hit area off the chip beside and below it — see
            // `CadenceTagChipStyle.editableStripSpacing`. They *shrink* as the reader's text size
            // grows, because past a point the drawn `x` is bigger than 44 and nothing spills.
            lineSpacing: CadenceTagChipStyle.editableStripLineSpacing(
                for: .regular, at: dynamicTypeSize, scaling: typographyScaling
            )
        ) {
            // The `+` leads rather than trails. Trailing it — which is where macOS puts its
            // equivalent — meant the button moved every time a tag was added or removed, and a
            // popover anchored to a control that has just relocated gets repositioned by UIKit,
            // twice landing half off the left edge of the screen. Leading, its frame never moves.
            Button {
                showPicker = true
            } label: {
                Image(systemName: "plus")
                    .cadenceFont(.controlLabel, base: CadenceTagPickerMetrics.addButtonGlyphSize, weight: .bold)
                    .foregroundStyle(Theme.dim)
                    // T-1364 converted the glyph and left the box around it a literal `30 × 26`,
                    // which is the residual T-1412 closes: the box grows by what the glyph gained.
                    .frame(
                        width: CadenceTagPickerMetrics.addButtonWidth(
                            at: dynamicTypeSize, scaling: typographyScaling
                        ),
                        height: CadenceTagPickerMetrics.addButtonHeight(
                            at: dynamicTypeSize, scaling: typographyScaling
                        )
                    )
                    .background(Theme.surfaceElevated.opacity(0.62))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                    .contentShape(Rectangle())
                    .iOSExpandedHitArea(9)
            }
            .buttonStyle(.iosPressable)
            .accessibilityLabel("Edit tags")
            .popover(isPresented: $showPicker) {
                iOSTaskTagPickerPopover(
                    selectedTags: Binding(
                        get: { TagSupport.sorted(task.tags ?? []) },
                        set: { task.tags = TagSupport.sorted($0) }
                    ),
                    allTags: allTags,
                    newTagName: $newTagName,
                    onCommit: { previous in commitTags(restoring: previous) }
                )
            }

            ForEach(selectedTags) { tag in
                // The whole chip used to be the remove button — a destructive action on a target
                // that reads as a label. The `x` is the control now, and it is the *only* control,
                // so the chip's fill has nothing to swallow.
                CadenceTagChip(tag: tag) {
                    remove(tag)
                }
            }
        }
    }

    /// **T-1070, the report half of the `try? save()` rule in its plain spelling.** This wrote
    /// `task.tags` and swallowed the commit, and the chip was already gone from the strip by the
    /// time the store refused it — a rearrangement the user can see, over a save nobody checked.
    private func remove(_ tag: Tag) {
        let previous = task.tags ?? []
        task.tags = previous.filter { $0.id != tag.id }
        guard commitTags(restoring: previous) else {
            tagFailureNotice = CadencePendingChangePersistence.editFailureNotice
            return
        }
        tagFailureNotice = nil
    }

    /// Commits a change to `task.tags`, putting `previous` back when the store refuses it.
    ///
    /// **T-1070.** This is the whole of what the popover's `onCommit` used to be, spelled
    /// `{ try? modelContext.save() }` — a refusal that came back indistinguishable from a success,
    /// with the tick already drawn beside the row and the chip already on the task.
    /// `commitEdit(in:undo:)` restores the previous array before the `false` is returned, which is
    /// what makes `editFailureNotice`'s "Nothing was changed" true rather than merely soothing.
    private func commitTags(restoring previous: [Tag]) -> Bool {
        do {
            try CadencePendingChangePersistence.commitEdit(in: modelContext) {
                task.tags = TagSupport.sorted(previous)
            }
            return true
        } catch {
            return false
        }
    }
}

/// Tag catalogue + inline creation, in the popover the `+` opens. Same checkmarked-list language as
/// `iOSChoicePopoverList`, which is single-select and so could not be reused directly.
///
/// It edits a **`[Tag]` binding** rather than an `AppTask` so the create sheet — where the task does
/// not exist yet, and must not until Add is tapped — can present the identical catalogue. The
/// inspector passes a binding through to `task.tags` and commits in `onCommit` — which answers
/// whether the store took it, so the tick can be taken back (T-1070); the create sheet holds the
/// array in `@State`, commits nothing until creation, and accepts every change.
struct iOSTaskTagPickerPopover: View {
    @Binding var selectedTags: [Tag]
    let allTags: [Tag]
    @Binding var newTagName: String
    /// Commits a change to the selection and answers whether the store took it, for callers whose
    /// binding writes straight into SwiftData.
    ///
    /// **T-1070.** It was `() -> Void`, and the inspector supplied `{ try? modelContext.save() }` —
    /// so a refused write reached this popover as a tick beside the row and a chip on the task.
    /// The refusal is *returned* now, and the popover says so: it is still open, which is exactly
    /// the [[T-664]] shape the rule names — the surface stays up and fills itself in.
    ///
    /// It is handed the selection **as it was before the write**, because the binding has already
    /// been written by the time this runs and only the caller knows where its binding points, so
    /// the undo has to be the caller's. Defaults to accepting, which is what a not-yet-created task
    /// wants: the create sheet holds its array in `@State` and commits nothing until Add is tapped.
    var onCommit: ([Tag]) -> Bool = { _ in true }
    @Environment(\.modelContext) private var modelContext
    /// **Only the size, not the flag** (T-1412). This panel *installs* `.enabled` below itself, so
    /// every figure it draws names `.enabled` literally; reading the flag back out of an
    /// environment it is itself setting would be inheriting the answer one level down, which is
    /// the thing T-1398's rule exists to stop.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Set when the store refused the tag the field just tried to create. See `addTag()`.
    @State private var tagFailureNotice: String?

    private var availableTags: [Tag] {
        TagSupport.uniqueBySlug(allTags.filter { !$0.isArchived })
    }

    private var trimmedNewTagName: String {
        TagSupport.displayName(for: newTagName)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if availableTags.isEmpty {
                        Button {
                            addDefaultTags()
                        } label: {
                            Text("Add Default Tags")
                                .cadenceFont(.rowTitle)
                                .foregroundStyle(Theme.blue)
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: CadenceTagPickerMetrics.rowMinHeight(
                                        at: dynamicTypeSize, scaling: .enabled
                                    ),
                                    alignment: .leading
                                )
                                .padding(.horizontal, 12)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.iosPressable)
                    } else {
                        ForEach(availableTags) { tag in
                            tagRow(tag)
                        }
                    }
                }
                .padding(CadenceTagPickerMetrics.listPadding)
            }

            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(height: 1)

            if let tagFailureNotice {
                CadenceInlineFailureNotice(text: tagFailureNotice)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
            }

            HStack(spacing: CadenceTagPickerMetrics.rowContentSpacing) {
                TextField("New tag", text: $newTagName)
                    .textFieldStyle(.plain)
                    .cadenceFont(.fieldLabel)
                    .foregroundStyle(Theme.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 10)
                    .frame(minHeight: CadenceTagPickerMetrics.footerControlSide(
                        at: dynamicTypeSize, scaling: .enabled
                    ))
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                    .onSubmit(addTag)

                Button(action: addTag) {
                    Image(systemName: "plus")
                        .cadenceFont(.fieldLabel, weight: .bold)
                        .foregroundStyle(Theme.onColor(for: Theme.blue))
                        .frame(
                            width: CadenceTagPickerMetrics.footerControlSide(
                                at: dynamicTypeSize, scaling: .enabled
                            ),
                            height: CadenceTagPickerMetrics.footerControlSide(
                                at: dynamicTypeSize, scaling: .enabled
                            )
                        )
                        .background(trimmedNewTagName.isEmpty ? Theme.surface : Theme.blue)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                        .contentShape(Rectangle())
                        .iOSExpandedHitArea(2)
                }
                .buttonStyle(.iosPressable)
                .disabled(trimmedNewTagName.isEmpty)
                .accessibilityLabel("Create tag")
            }
            .padding(CadenceTagPickerMetrics.footerPadding)
        }
        .frame(
            width: CadenceTagPickerMetrics.width(at: dynamicTypeSize, scaling: .enabled),
            height: CadenceTagPickerMetrics.panelHeight(at: dynamicTypeSize, scaling: .enabled)
        )
        .background(Theme.surfaceElevated)
        // **T-1398 pinned this panel because it was clipping, T-1410 left the pin in place because
        // its rows are an unconverted component, and T-1412 converted that component — so this is
        // the conversion the two of them were waiting for.**
        //
        // The pin was never about this file. Every row here *is* a `CadenceTagChip`, whose size
        // lives in `CadenceTagChipStyle` and which twelve surfaces across both platforms draw;
        // converting the panel alone would have produced the other half of the defect T-1364
        // names — a row grown to hold text that had not moved. The chip takes the reader's text
        // size now, and it is safe for the eleven surfaces that have not been converted because a
        // role under `.fixed` resolves to exactly the literal it replaced at every one of the
        // twelve sizes.
        //
        // **The geometry above says `.enabled` literally, and that is the rule rather than a
        // shortcut.** This panel installs the scope, so consulting `\.cadenceTypographyScaling`
        // for its own frame would be reading back a value it is itself setting — inheriting the
        // answer one level down, which is what T-1398 measured to be unsafe across a presentation.
        // The fonts inside read the scope, the frame states it, and the two cannot disagree
        // because both come from `CadenceTagPickerMetrics`.
        .cadenceScaledTypography()
        .presentationCompactAdaptation(.popover)
    }

    private func tagRow(_ tag: Tag) -> some View {
        let isSelected = isSelected(tag)

        return Button {
            toggle(tag)
        } label: {
            HStack(spacing: CadenceTagPickerMetrics.rowContentSpacing) {
                CadenceTagChip(tag: tag)
                Spacer(minLength: CadenceTagPickerMetrics.rowContentSpacing)
                if isSelected {
                    Image(systemName: "checkmark")
                        .cadenceFont(CadenceTagChipStyle.labelRole, weight: .semibold)
                        .foregroundStyle(Theme.blue)
                }
            }
            .padding(.horizontal, CadenceTagPickerMetrics.rowHorizontalPadding)
            .frame(
                maxWidth: .infinity,
                minHeight: CadenceTagPickerMetrics.rowMinHeight(at: dynamicTypeSize, scaling: .enabled),
                alignment: .leading
            )
            .background(isSelected ? Theme.blue.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.iosPressable)
    }

    private func isSelected(_ tag: Tag) -> Bool {
        selectedTags.contains { $0.id == tag.id }
    }

    /// **T-1070.** The checkmark this draws is the report, so it may not outrun the commit: the
    /// caller undoes the write before answering `false`, and the sentence below the list is the
    /// only thing left saying anything happened.
    private func toggle(_ tag: Tag) {
        let previous = selectedTags
        if isSelected(tag) {
            selectedTags = selectedTags.filter { $0.id != tag.id }
        } else {
            selectedTags = TagSupport.sorted(selectedTags + [tag])
        }
        guard onCommit(previous) else {
            tagFailureNotice = CadencePendingChangePersistence.editFailureNotice
            return
        }
        tagFailureNotice = nil
    }

    /// **T-631.** This inserted a `Tag` one frame down in `TagSupport.resolveTags`, into the
    /// popover's ambient `ModelContext`, and committed nothing — while clearing the field and
    /// running `onCommit()`, which is the whole report that the tag was made. So a refused store
    /// left the name gone from the field and the row pending for another screen's save.
    ///
    /// Clearing the field now happens on the committed path alone, the way
    /// `iOSSettingsTagsSection.createTag` — the same act, one screen over — already did.
    ///
    /// **T-1070 closed the other half.** T-631 stopped this minting a tag over a swallowed save,
    /// and left it *selecting* the tag over one: `onCommit()` returned nothing, so the field
    /// cleared and the chip appeared whether or not the store took the attachment. Both the mint
    /// and the selection are guarded now, in that order, and either refusal leaves the typed name
    /// in the field.
    private func addTag() {
        let name = trimmedNewTagName
        guard !name.isEmpty else { return }
        guard let tag = TagSupport.committedTag(named: name, in: modelContext) else {
            tagFailureNotice = CadencePendingChangePersistence.editFailureNotice
            return
        }
        let previous = selectedTags
        if !isSelected(tag) {
            selectedTags = TagSupport.sorted(selectedTags + [tag])
        }
        // **T-1110.** Not `editFailureNotice`. The mint above already committed, so "Nothing was
        // changed" is false here by two lines — and the tag it denies is drawn in the list right
        // above this sentence. Only the attachment failed, and only that is claimed.
        guard onCommit(previous) else {
            tagFailureNotice = TagSupport.attachmentFailureNotice
            return
        }
        tagFailureNotice = nil
        newTagName = ""
    }

    /// T-653, the existence half of the `try? save()` rule. The macOS twin is
    /// `SettingsTagsSection.restoreDefaults`: `seedDefaultTagsCommitting` rolls the whole seed back
    /// on a refusal rather than leaving a half-merged, half-seeded table.
    private func addDefaultTags() {
        do {
            try TagSupport.seedDefaultTagsCommitting(in: modelContext)
            tagFailureNotice = nil
        } catch {
            tagFailureNotice = CadencePendingChangePersistence.editFailureNotice
        }
    }
}

struct iOSSubtaskRow: View {
    @Bindable var subtask: Subtask
    let delete: () -> Void
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(spacing: 9) {
            Button {
                subtask.isDone.toggle()
                save()
            } label: {
                iOSTaskCompletionCircle(isDone: subtask.isDone, tint: Theme.dim, diameter: 16)
                    .frame(width: 20, height: 20)
                    .iOSExpandedHitArea(12)
            }
            .buttonStyle(.iosPressable)
            .accessibilityLabel(subtask.isDone ? "Mark subtask todo" : "Complete subtask")

            TextField("Subtask", text: $subtask.title, axis: .vertical)
                .textFieldStyle(.plain)
                .cadenceFont(.rowTitle)
                .foregroundStyle(subtask.isDone ? Theme.dim : Theme.text)
                .strikethrough(subtask.isDone, color: Theme.dim)
                .lineLimit(2)
                .submitLabel(.done)
                .onSubmit(save)
                .onChange(of: subtask.title) { _, _ in
                    save()
                }

            Spacer(minLength: 8)

            Button(action: delete) {
                Image(systemName: "trash")
                    .cadenceFont(.metadata, weight: .semibold)
                    .foregroundStyle(Theme.dim)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .iOSExpandedHitArea(8)
            }
            .buttonStyle(.iosPressable)
            .accessibilityLabel("Delete subtask")
        }
        .padding(.horizontal, 2)
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.rowSeparator)
                .frame(height: 1)
        }
    }

    private func save() {
        try? modelContext.save()
    }
}

#endif
