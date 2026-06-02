#if os(macOS)
import SwiftUI

struct QuickCreateTaskPanelHandoffView: View {
    let dateKey: String
    let startMin: Int
    let endMin: Int
    let containerName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                    .frame(width: 34, height: 34)
                    .background(Theme.blue.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Use the task panel")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Continue to the shared task creator with this slot prefilled.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                handoffDetail(icon: "calendar", text: DateFormatters.relativeDate(from: dateKey))
                handoffDetail(icon: "clock", text: TimeFormatters.timeRange(startMin: startMin, endMin: endMin))
                handoffDetail(icon: "tray", text: containerName)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceElevated.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 9))

            Text("Tip: type `~` in the title to route the task to a list before opening the panel.")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.dim.opacity(0.82))
        }
    }

    private func handoffDetail(icon: String, text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .frame(width: 13)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
    }
}

struct QuickCreateTaskDetailsView: View {
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
            HStack(alignment: .center, spacing: 8) {
                ContainerPickerBadge(
                    selection: $selectedContainer,
                    contexts: contexts,
                    areas: areas,
                    projects: projects
                )
                .onChange(of: selectedContainer) { onContainerChanged() }

                sectionPicker
            }

            notesEditor
            subtasksEditor
        }
    }

    private var notesEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dim)

            TextEditor(text: $notes)
                .scrollContentBackground(.hidden)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
                .frame(minHeight: 72)
                .padding(8)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var subtasksEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Subtasks")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dim)

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

    private var sectionPicker: some View {
        Menu {
            ForEach(availableSections, id: \.self) { section in
                Button(section) {
                    selectedSectionName = section
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                Text(selectedSectionName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .frame(maxWidth: 92, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(minHeight: 28)
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.cadencePlain)
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
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Theme.surfaceElevated.opacity(0.52))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func commitSubtaskDraft() {
        let trimmed = subtaskDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        subtaskTitles.append(trimmed)
        subtaskDraft = ""
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
                maxHeight: 188,
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
            Text(task.title.isEmpty ? "Untitled" : task.title)
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
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Theme.surfaceElevated.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func addSelectedTask(_ task: AppTask) {
        guard !selectedTaskIDs.contains(task.id) else { return }
        selectedTaskIDs.append(task.id)
        searchText = ""
    }
}
#endif
