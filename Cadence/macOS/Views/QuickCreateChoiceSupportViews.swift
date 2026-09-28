#if os(macOS)
import SwiftUI
import EventKit

/// The Task tab's inspector when the popover hands the draft on to the task panel.
///
/// **T-1433, owner-reported.** This was `QuickCreateTaskPanelHandoffView`: a blue
/// `rectangle.on.rectangle.angled` tile headed *"Use the task panel"*, a recessed card of three
/// read-only `Text` rows — the date, the time range and the list name — and a tip explaining that
/// typing `~` in the title was how you routed the task to a list *before opening the panel*.
///
/// The three rows described state the reader could not act on, and the blurb and the tip existed
/// to say where to go and act on it. So the fields are editable here now, and the blurb and the
/// tip are not deleted for tidiness: making the list editable and adding priority is what stops
/// them being **true**. `~` routing itself is untouched — `TildeContainerPicker` still runs in the
/// title field above; an editable List row is simply the discoverable form of the same thing.
///
/// Date and time lead, per the owner. Both are the app's existing controls rather than new ones:
/// `CadenceDatePicker` and `CadenceStartTimeFieldRow`, which is also why the row idiom here is the
/// shared `CadenceFieldRow` rather than this file's `QuickCreateDetailRow` — the start-time row
/// brings its own label, and a card with two row shapes in it is the drift, not the fix.
struct QuickCreateTaskSlotInspectorView: View {
    @Binding var dateKey: String
    @Binding var startMin: Int
    @Binding var selectedContainer: TaskContainerSelection
    @Binding var selectedSectionName: String
    @Binding var priority: TaskPriority

    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    let availableSections: [String]
    let onContainerChanged: () -> Void

    var body: some View {
        QuickCreateCompactSection {
            CadenceFieldRow(label: "Date", systemImage: "calendar", color: Theme.blue) {
                CadenceDatePicker(selection: dateSelection)
            }

            CadenceStartTimeFieldRow(minutes: $startMin)

            CadenceFieldRow(label: "List", systemImage: "tray") {
                QuickCreateContainerFieldControls(
                    selection: $selectedContainer,
                    sectionName: $selectedSectionName,
                    contexts: contexts,
                    areas: areas,
                    projects: projects,
                    availableSections: availableSections,
                    onContainerChanged: onContainerChanged
                )
            }

            // `exclamationmark.circle.fill`, not a flag: the iOS composer's priority tile already
            // reads that glyph, and T-1278 recorded the owner choosing the mark language over a
            // flag for priority across both platforms.
            CadenceFieldRow(label: "Priority", systemImage: "exclamationmark.circle.fill") {
                TaskPriorityPicker(selection: $priority, trigger: .value)
            }
        }
    }

    /// The stored form is the repo's `yyyy-MM-dd` key; the picker speaks `Date`. Round-tripping
    /// through `DateFormatters` in the binding is what keeps the key canonical no matter which
    /// day the calendar popover lands on.
    private var dateSelection: Binding<Date> {
        Binding(
            get: { DateFormatters.date(from: dateKey) ?? Date() },
            set: { dateKey = DateFormatters.dateKey(from: $0) }
        )
    }
}

/// The List field's controls — the container chip, plus the section chip when the chosen list has
/// sections. Shared by the two Task composers in this file so the pair cannot drift apart the way
/// the handoff card's read-only `tray` row drifted from the editable one beside it.
struct QuickCreateContainerFieldControls: View {
    @Binding var selection: TaskContainerSelection
    @Binding var sectionName: String

    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    let availableSections: [String]
    let onContainerChanged: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            ContainerPickerBadge(
                selection: $selection,
                contexts: contexts,
                areas: areas,
                projects: projects
            )
            .onChange(of: selection) { onContainerChanged() }

            if showsSectionPicker {
                TaskSectionPickerBadge(
                    selection: $sectionName,
                    sections: availableSections
                )
            }
        }
    }

    private var showsSectionPicker: Bool {
        switch selection {
        case .inbox: return false
        case .area, .project: return true
        }
    }
}

struct QuickCreateTaskDetailsView: View {
    let dateKey: String
    let startMin: Int
    let endMin: Int
    @Binding var selectedContainer: TaskContainerSelection
    @Binding var selectedSectionName: String
    @Binding var notes: String
    @Binding var subtaskDraft: String
    @Binding var subtaskTitles: [String]

    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    let availableSections: [String]
    let onContainerChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            QuickCreateSlotSummary(dateKey: dateKey, startMin: startMin, endMin: endMin)

            QuickCreateCompactSection {
                QuickCreateDetailRow(title: "List", icon: "tray") {
                    QuickCreateContainerFieldControls(
                        selection: $selectedContainer,
                        sectionName: $selectedSectionName,
                        contexts: contexts,
                        areas: areas,
                        projects: projects,
                        availableSections: availableSections,
                        onContainerChanged: onContainerChanged
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            QuickCreateCompactSection {
                QuickCreateDetailRow(title: "Notes", icon: "note.text") {
                    QuickCreateNotesEditor(text: $notes, minHeight: 64)
                }
            }

            subtasksEditor
        }
    }

    private var subtasksEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !subtaskTitles.isEmpty {
                VStack(spacing: 5) {
                    ForEach(Array(subtaskTitles.enumerated()), id: \.offset) { index, title in
                        subtaskRow(title: title, index: index)
                    }
                }
            }

            HStack(spacing: 7) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                TextField("Add subtask...", text: $subtaskDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text)
                    .onSubmit { commitSubtaskDraft() }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(Theme.surfaceElevated.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func subtaskRow(title: String, index: Int) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dim)
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button {
                subtaskTitles.remove(at: index)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.cadencePlain)
            // T-673: this row already has the draft's own text as `title`; hand it down rather
            // than leaving VoiceOver with eight identical "Remove" announcements.
            .accessibilityLabel("Remove")
            .accessibilityValue(TaskTitleSupport.displayTitle(title, fallback: TaskTitleSupport.defaultCompactDisplayTitle))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Theme.surfaceElevated.opacity(0.52))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact))
    }

    private func commitSubtaskDraft() {
        let trimmed = subtaskDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        subtaskTitles.append(trimmed)
        subtaskDraft = ""
    }
}

struct QuickCreateEventDetailsView: View {
    let dateKey: String
    let startMin: Int
    let endMin: Int
    let calendars: [EKCalendar]
    @Binding var selectedCalendarID: String
    @Binding var notes: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            QuickCreateSlotSummary(dateKey: dateKey, startMin: startMin, endMin: endMin)

            QuickCreateCompactSection {
                QuickCreateDetailRow(title: "Calendar", icon: "calendar") {
                    if calendars.isEmpty {
                        Text("No writable calendars")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.dim)
                            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                    } else {
                        CadenceCalendarPickerButton(
                            calendars: calendars,
                            selectedID: $selectedCalendarID,
                            allowNone: false,
                            style: .compact
                        )
                    }
                }
            }

            QuickCreateCompactSection {
                QuickCreateDetailRow(title: "Notes", icon: "note.text") {
                    QuickCreateNotesEditor(text: $notes, minHeight: 84)
                }
            }
        }
    }
}

struct QuickCreateBundleDetailsView: View {
    let dateKey: String
    let startMin: Int
    let endMin: Int
    let bundleDateKey: String
    let allTasks: [AppTask]
    let areas: [Area]
    let projects: [Project]
    @Binding var searchText: String
    @Binding var selectedTaskIDs: [UUID]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            QuickCreateSlotSummary(dateKey: dateKey, startMin: startMin, endMin: endMin)

            QuickCreateCompactSection {
                QuickCreateDetailRow(title: "Tasks", icon: "checklist") {
                    QuickCreateBundleTaskSelectionView(
                        bundleDateKey: bundleDateKey,
                        allTasks: allTasks,
                        areas: areas,
                        projects: projects,
                        searchText: $searchText,
                        selectedTaskIDs: $selectedTaskIDs
                    )
                }
            }
        }
    }
}

/// Label-left / content-right metadata row used by the quick-create sheets.
struct QuickCreateDetailRow<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 11)
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
            .frame(width: 76, alignment: .leading)
            .padding(.top, 7)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 28, alignment: .top)
    }
}

struct QuickCreateCompactSection<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            content()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Theme.surface.opacity(0.76))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.72), lineWidth: 1)
        )
    }
}

struct QuickCreateSlotSummary: View {
    let dateKey: String
    let startMin: Int
    let endMin: Int

    var body: some View {
        HStack(spacing: 8) {
            QuickCreateInspectorValue(text: DateFormatters.relativeDate(from: dateKey), icon: "calendar")
            QuickCreateInspectorValue(text: TimeFormatters.timeRange(startMin: startMin, endMin: endMin), icon: "clock")
            Spacer(minLength: 0)
        }
    }
}

struct QuickCreateInspectorValue: View {
    let text: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.surfaceElevated.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact))
    }
}

struct QuickCreateNotesEditor: View {
    @Binding var text: String
    var minHeight: CGFloat = 78

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("Notes")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim.opacity(0.45))
                    .padding(.top, 8)
                    .padding(.leading, 10)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
                .frame(minHeight: minHeight)
                .padding(7)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct QuickCreateBundleTaskSelectionView: View {
    let bundleDateKey: String
    let allTasks: [AppTask]
    let areas: [Area]
    let projects: [Project]

    @Binding var searchText: String
    @Binding var selectedTaskIDs: [UUID]

    private var selectedTaskSet: Set<UUID> {
        Set(selectedTaskIDs)
    }

    private var selectedTasks: [AppTask] {
        selectedTaskIDs.compactMap { id in
            allTasks.first { $0.id == id }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            selectedTasksList

            TaskBundleTaskPickerPanel(
                bundleDateKey: bundleDateKey,
                allTasks: allTasks,
                areas: areas,
                projects: projects,
                excludedTaskIDs: selectedTaskSet,
                searchText: $searchText,
                maxHeight: 170,
                onAdd: addSelectedTask
            )
        }
    }

    private var header: some View {
        HStack {
            Text(selectedTaskIDs.isEmpty ? "Add tasks now" : "\(selectedTaskIDs.count) selected")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dim)
            Spacer()
            if !selectedTaskIDs.isEmpty {
                Button("Clear") {
                    selectedTaskIDs.removeAll()
                }
                .buttonStyle(.cadencePlain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dim)
            }
        }
    }

    @ViewBuilder
    private var selectedTasksList: some View {
        if !selectedTasks.isEmpty {
            VStack(spacing: 5) {
                ForEach(selectedTasks) { task in
                    selectedTaskRow(task)
                }
            }
        }
    }

    private func selectedTaskRow(_ task: AppTask) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.amber)
            Text(TaskTitleSupport.displayTitle(task.title, fallback: TaskTitleSupport.defaultCompactDisplayTitle))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(max(task.estimatedMinutes, 5))m")
                .font(.system(size: 10))
                .foregroundStyle(Theme.dim)
            Button {
                selectedTaskIDs.removeAll { $0 == task.id }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.cadencePlain)
            // T-673: same normalisation the row's own title text already reads, so an untitled
            // task removed from the block announces the same placeholder it displays.
            .accessibilityLabel("Remove")
            .accessibilityValue(TaskTitleSupport.displayTitle(task.title, fallback: TaskTitleSupport.defaultCompactDisplayTitle))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Theme.surfaceElevated.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact))
    }

    private func addSelectedTask(_ task: AppTask) {
        guard !selectedTaskIDs.contains(task.id) else { return }
        selectedTaskIDs.append(task.id)
        searchText = ""
    }
}
#endif
