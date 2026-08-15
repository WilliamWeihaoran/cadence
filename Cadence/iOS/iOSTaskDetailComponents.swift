#if os(iOS)
import SwiftData
import SwiftUI

/// The inspector's identity block: completion control + title + estimate on one row.
///
/// **The control on the left completes the task**, and it is the only thing in the sheet that
/// writes `.done`. macOS makes the equivalent tile its priority control and puts completion in the
/// foot buttons; iOS goes the other way on purpose. Completing is the dominant touch action, and
/// every task row on this platform already teaches "tinted circle, tap to complete" — the sheet
/// having a *different* meaning for the same glyph would be the surprise. Priority is what the
/// circle is tinted by, exactly as in `iOSTaskRow`, and is edited in the one place it is editable:
/// the Priority row below.
///
/// The five-chip strip that used to sit under the title is gone. Not one of those chips was a
/// button — they were painted to look exactly like the tappable chips elsewhere in the app, sat
/// directly above the editable rows that own the same five fields, and swallowed every tap aimed
/// at them.
struct iOSTaskEditorTitleCard: View {
    @Bindable var task: AppTask
    let onToggleCompletion: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var glyphSize: CGFloat {
        isRegularWidth ? 26 : 24
    }

    /// Done and cancelled are both "settled": the title reads as struck through and stops being
    /// the loudest text in the sheet.
    private var isSettled: Bool {
        task.isDone || task.isCancelled
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggleCompletion) {
                iOSTaskCompletionCircle(
                    isDone: task.isDone,
                    tint: Theme.priorityColor(task.priority),
                    diameter: glyphSize
                )
                .frame(width: glyphSize, height: glyphSize)
                .iOSExpandedHitArea((44 - glyphSize) / 2)
            }
            .buttonStyle(.iosPressable)
            .accessibilityLabel(task.isDone ? "Mark task todo" : "Complete task")
            // Aligns the circle with the first line of a title that may wrap to three.
            .padding(.top, isRegularWidth ? 5 : 3)

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

                TextField("Untitled task", text: $task.title, axis: .vertical)
                    .font(.system(size: isRegularWidth ? 24 : 21, weight: .bold))
                    .foregroundStyle(isSettled ? Theme.dim : Theme.text)
                    .strikethrough(isSettled, color: Theme.dim)
                    .textFieldStyle(.plain)
                    .lineLimit(1...3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Fixed-size, so a long title wraps rather than squeezing the estimate — the same
            // arrangement `TaskDetailHeaderSection` settled on. An estimate is a property of the
            // task like its priority, not a date, so it does not belong in the schedule well.
            EstimatePickerControl(value: $task.estimatedMinutes)
                .fixedSize()
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
    let activeAreas: [Area]
    let activeProjects: [Project]
    let availableSectionNames: [String]

    @State private var showContainerPicker = false
    @State private var showSectionPicker = false

    private var containerTitle: String {
        if containerSelection.wrappedValue.hasPrefix("area:"),
           let id = UUID(uuidString: String(containerSelection.wrappedValue.dropFirst(5))),
           let area = activeAreas.first(where: { $0.id == id }) {
            return area.name.isEmpty ? "Untitled Area" : area.name
        }
        if containerSelection.wrappedValue.hasPrefix("project:"),
           let id = UUID(uuidString: String(containerSelection.wrappedValue.dropFirst(8))),
           let project = activeProjects.first(where: { $0.id == id }) {
            return project.name.isEmpty ? "Untitled Project" : project.name
        }
        return CadenceTaskInspectorSupport.inboxSegmentTitle
    }

    private var containerIcon: String {
        if containerSelection.wrappedValue.hasPrefix("project:") { return "checklist" }
        return "tray.full.fill"
    }

    private var isInbox: Bool {
        containerSelection.wrappedValue == "inbox"
    }

    private var showsSectionSegment: Bool {
        !isInbox && CadenceTaskInspectorSupport.showsSectionSegment(availableSections: availableSectionNames)
    }

    var body: some View {
        CadenceWrappingHStack(spacing: 4, lineSpacing: 4) {
            iOSTaskBreadcrumbSegment(
                title: containerTitle,
                systemImage: containerIcon,
                isSet: !isInbox
            ) {
                showContainerPicker = true
            }
            .popover(isPresented: $showContainerPicker) {
                iOSContainerChoicePopover(
                    activeAreas: activeAreas,
                    activeProjects: activeProjects,
                    selection: containerSelection,
                    isPresented: $showContainerPicker
                )
            }

            if showsSectionSegment {
                Text("\u{203A}")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .accessibilityHidden(true)

                iOSTaskBreadcrumbSegment(
                    // The real name of where the task is, never "None": dimmer styling is what
                    // conveys "unset", so the segment and its picker cannot disagree.
                    title: CadenceTaskInspectorSupport.sectionSegmentTitle(task.sectionName),
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

/// One tappable segment of the placement breadcrumb. Neutral throughout: which list a task is in is
/// ordinary information, and colour in this sheet is spent only on what is exceptional.
struct iOSTaskBreadcrumbSegment: View {
    let title: String
    let systemImage: String?
    let isSet: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSet ? Theme.text : Theme.dim)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(Theme.surfaceElevated.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            .contentShape(Rectangle())
            .iOSExpandedHitArea(7)
        }
        .buttonStyle(.iosPressable)
        .accessibilityHint("Opens a picker")
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

    @State private var showPicker = false

    private var selectedTags: [Tag] {
        TagSupport.sorted(task.tags ?? [])
    }

    var body: some View {
        CadenceWrappingHStack(spacing: 6, lineSpacing: 6) {
            // The `+` leads rather than trails. Trailing it — which is where macOS puts its
            // equivalent — meant the button moved every time a tag was added or removed, and a
            // popover anchored to a control that has just relocated gets repositioned by UIKit,
            // twice landing half off the left edge of the screen. Leading, its frame never moves.
            Button {
                showPicker = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 30, height: 26)
                    .background(Theme.surfaceElevated.opacity(0.62))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                    .contentShape(Rectangle())
                    .iOSExpandedHitArea(9)
            }
            .buttonStyle(.iosPressable)
            .accessibilityLabel("Edit tags")
            .popover(isPresented: $showPicker) {
                iOSTaskTagPickerPopover(
                    task: task,
                    allTags: allTags,
                    newTagName: $newTagName
                )
            }

            ForEach(selectedTags) { tag in
                Button {
                    remove(tag)
                } label: {
                    HStack(spacing: 4) {
                        iOSTagChip(tag: tag)
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.dim)
                    }
                    .contentShape(Rectangle())
                    .iOSExpandedHitArea(8)
                }
                .buttonStyle(.iosPressable)
                .accessibilityLabel("Remove tag \(tag.name.isEmpty ? tag.slug : tag.name)")
            }
        }
    }

    private func remove(_ tag: Tag) {
        task.tags = (task.tags ?? []).filter { $0.id != tag.id }
        try? modelContext.save()
    }
}

/// Tag catalogue + inline creation, in the popover the `+` opens. Same checkmarked-list language as
/// `iOSChoicePopoverList`, which is single-select and so could not be reused directly.
struct iOSTaskTagPickerPopover: View {
    @Bindable var task: AppTask
    let allTags: [Tag]
    @Binding var newTagName: String
    @Environment(\.modelContext) private var modelContext

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
                            TagSupport.seedDefaultTags(in: modelContext)
                        } label: {
                            Text("Add Default Tags")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.blue)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
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
                .padding(6)
            }

            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(height: 1)

            HStack(spacing: 8) {
                TextField("New tag", text: $newTagName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 10)
                    .frame(minHeight: 40)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                    .onSubmit(addTag)

                Button(action: addTag) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.onColor)
                        .frame(width: 40, height: 40)
                        .background(trimmedNewTagName.isEmpty ? Theme.surface : Theme.blue)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                        .contentShape(Rectangle())
                        .iOSExpandedHitArea(2)
                }
                .buttonStyle(.iosPressable)
                .disabled(trimmedNewTagName.isEmpty)
                .accessibilityLabel("Create tag")
            }
            .padding(10)
        }
        .frame(width: 260, height: 340)
        .background(Theme.surfaceElevated)
        .presentationCompactAdaptation(.popover)
    }

    private func tagRow(_ tag: Tag) -> some View {
        let isSelected = isSelected(tag)

        return Button {
            toggle(tag)
        } label: {
            HStack(spacing: 8) {
                iOSTagChip(tag: tag)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.blue)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(isSelected ? Theme.blue.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.iosPressable)
    }

    private func isSelected(_ tag: Tag) -> Bool {
        (task.tags ?? []).contains { $0.id == tag.id }
    }

    private func toggle(_ tag: Tag) {
        if isSelected(tag) {
            task.tags = (task.tags ?? []).filter { $0.id != tag.id }
        } else {
            task.tags = TagSupport.sorted((task.tags ?? []) + [tag])
        }
        try? modelContext.save()
    }

    private func addTag() {
        let name = trimmedNewTagName
        guard !name.isEmpty else { return }
        guard let tag = TagSupport.resolveTags(named: [name], in: modelContext)?.first else { return }
        if !isSelected(tag) {
            task.tags = TagSupport.sorted((task.tags ?? []) + [tag])
        }
        newTagName = ""
        try? modelContext.save()
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
                .font(.system(size: 14, weight: .medium))
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
                    .font(.system(size: 12, weight: .semibold))
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
                .fill(Theme.borderSubtle.opacity(0.35))
                .frame(height: 1)
        }
    }

    private func save() {
        try? modelContext.save()
    }
}

struct iOSTagChip: View {
    let tag: Tag

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(hex: tag.colorHex))
                .frame(width: 7, height: 7)
            Text(tag.name.isEmpty ? tag.slug : tag.name)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Color(hex: tag.colorHex))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(hex: tag.colorHex).opacity(0.13))
        .clipShape(Capsule())
    }
}
#endif
