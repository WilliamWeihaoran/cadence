#if os(iOS)
import SwiftData
import SwiftUI

struct iOSTaskEditorTitleCard: View {
    @Bindable var task: AppTask
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isRegularWidth ? 14 : 12) {
            HStack(alignment: .center, spacing: 11) {
                Image(systemName: task.status.systemImage)
                    .font(.system(size: isRegularWidth ? 17 : 15, weight: .semibold))
                    .foregroundStyle(CadenceTaskPresentationSupport.statusColor(task.status))
                    .frame(width: isRegularWidth ? 38 : 34, height: isRegularWidth ? 38 : 34)
                    .background(CadenceTaskPresentationSupport.statusColor(task.status).opacity(0.13))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.status.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CadenceTaskPresentationSupport.statusColor(task.status))
                        .textCase(.uppercase)
                        .kerning(0.8)

                    TextField("Untitled task", text: $task.title, axis: .vertical)
                        .font(.system(size: isRegularWidth ? 26 : 22, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .textFieldStyle(.plain)
                        .lineLimit(1...3)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    iOSTaskEditorContextChip(
                        title: task.priority.label,
                        systemImage: "flag.fill",
                        color: Theme.priorityColor(task.priority)
                    )

                    if !task.scheduledDate.isEmpty {
                        iOSTaskEditorContextChip(
                            title: "Do \(DateFormatters.relativeDate(from: task.scheduledDate))",
                            systemImage: "sun.max.fill",
                            color: Theme.amber
                        )
                    }

                    if !task.dueDate.isEmpty {
                        iOSTaskEditorContextChip(
                            title: "Due \(CadenceTaskPresentationSupport.dueDateLabel(for: task))",
                            systemImage: "flag.fill",
                            color: task.dueDate < DateFormatters.todayKey() ? Theme.red : Theme.blue
                        )
                    }

                    iOSTaskEditorContextChip(
                        title: estimateLabel,
                        systemImage: "clock.fill",
                        color: Theme.blue
                    )

                    if task.recurrenceRule != .none {
                        iOSTaskEditorContextChip(
                            title: task.recurrenceRule.label,
                            systemImage: task.recurrenceRule.systemImage,
                            color: Theme.purple
                        )
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private var estimateLabel: String {
        CadenceTaskPresentationSupport.estimateLabel(for: task)
    }
}

struct iOSTaskEditorOverviewCard: View {
    @Bindable var task: AppTask
    let containerTitle: String
    let goalTitle: String?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var completedSubtasks: Int {
        CadenceTaskPresentationSupport.subtaskProgress(for: task)?.completed ?? 0
    }

    private var totalSubtasks: Int {
        CadenceTaskPresentationSupport.subtaskProgress(for: task)?.total ?? 0
    }

    private var hasNotes: Bool {
        CadenceTaskPresentationSupport.hasNotes(task)
    }

    private var tagCount: Int {
        (task.tags ?? []).filter { !$0.isArchived }.count
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            iOSTaskOverviewMetric(
                title: "List",
                value: containerTitle,
                systemImage: "tray.full.fill",
                color: Theme.blue
            )
            iOSTaskOverviewMetric(
                title: "Subtasks",
                value: totalSubtasks == 0 ? "None" : "\(completedSubtasks)/\(totalSubtasks)",
                systemImage: "checklist",
                color: totalSubtasks == 0 ? Theme.dim : Theme.green
            )
            iOSTaskOverviewMetric(
                title: "Logged",
                value: loggedLabel,
                systemImage: "timer",
                color: task.actualMinutes == 0 ? Theme.dim : Theme.green
            )
            iOSTaskOverviewMetric(
                title: "Milestone",
                value: goalTitle ?? "None",
                systemImage: goalTitle == nil ? "circle.dashed" : "flag.fill",
                color: goalTitle == nil ? Theme.dim : Theme.amber
            )
            iOSTaskOverviewMetric(
                title: "Notes",
                value: hasNotes ? "Ready" : "Empty",
                systemImage: hasNotes ? "doc.text.fill" : "doc.text",
                color: hasNotes ? Theme.purple : Theme.dim
            )
            iOSTaskOverviewMetric(
                title: "Tags",
                value: tagCount == 0 ? "None" : "\(tagCount)",
                systemImage: "tag.fill",
                color: tagCount == 0 ? Theme.dim : Theme.amber
            )
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: isRegularWidth ? 122 : 108), spacing: 8)]
    }

    private var loggedLabel: String {
        if task.actualMinutes == 0 { return "None" }
        return CadenceTaskPresentationSupport.estimateLabel(minutes: task.actualMinutes)
    }
}

private struct iOSTaskOverviewMetric: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.11))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .textCase(.uppercase)
                    .kerning(0.5)
                    .lineLimit(1)

                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(Theme.surface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Theme.borderSubtle.opacity(0.5), lineWidth: 1)
        }
    }
}

struct iOSTaskEditorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .textCase(.uppercase)
                .kerning(0.8)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 12)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.borderSubtle.opacity(0.35))
                .frame(height: 1)
        }
    }
}

struct iOSTaskEditorRow<Content: View>: View {
    let label: String
    let systemImage: String
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 14, alignment: .center)

            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .textCase(.uppercase)
                .kerning(0.4)

            Spacer(minLength: 12)

            content()
        }
        .frame(minHeight: 34)
    }
}

private struct iOSTaskEditorContextChip: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

struct iOSTaskEditorToggleRow: View {
    let label: String
    let systemImage: String
    let color: Color
    @Binding var isOn: Bool

    var body: some View {
        iOSTaskEditorRow(label: label, systemImage: systemImage, color: color) {
            Toggle(label, isOn: $isOn)
                .labelsHidden()
                .tint(color)
        }
    }
}

struct iOSTaskEditorDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.borderSubtle.opacity(0.55))
            .frame(height: 1)
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
                iOSTaskCompletionCircle(isDone: subtask.isDone, tint: Theme.dim)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(subtask.isDone ? "Mark subtask todo" : "Complete subtask")

            TextField("Subtask", text: $subtask.title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
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
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete subtask")
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 6)
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

struct iOSTaskTagEditorSection: View {
    @Bindable var task: AppTask
    let allTags: [Tag]
    @Binding var newTagName: String
    @Environment(\.modelContext) private var modelContext

    private var selectedTags: [Tag] {
        TagSupport.sorted(task.tags ?? [])
    }

    private var availableTags: [Tag] {
        TagSupport.uniqueBySlug(allTags.filter { !$0.isArchived })
    }

    private var trimmedNewTagName: String {
        TagSupport.displayName(for: newTagName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if selectedTags.isEmpty {
                Text("No tags")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.dim)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(selectedTags) { tag in
                            Button {
                                remove(tag)
                            } label: {
                                HStack(spacing: 5) {
                                    iOSTagChip(tag: tag)
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.dim)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if availableTags.isEmpty {
                Button {
                    TagSupport.seedDefaultTags(in: modelContext)
                } label: {
                    Label("Add Default Tags", systemImage: "tag")
                }
            } else {
                ForEach(availableTags) { tag in
                    Button {
                        toggle(tag)
                    } label: {
                        HStack {
                            iOSTagChip(tag: tag)
                            Spacer()
                            if isSelected(tag) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Theme.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                TextField("New tag", text: $newTagName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .cadenceCard(background: Theme.surfaceElevated.opacity(0.55), cornerRadius: Theme.radiusControl, shadowRadius: 8, shadowY: 3)
                    .onSubmit(addTag)

                Button(action: addTag) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(trimmedNewTagName.isEmpty ? Theme.surfaceElevated : Theme.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(trimmedNewTagName.isEmpty)
            }
        }
    }

    private func isSelected(_ tag: Tag) -> Bool {
        (task.tags ?? []).contains { $0.id == tag.id }
    }

    private func toggle(_ tag: Tag) {
        if isSelected(tag) {
            remove(tag)
        } else {
            task.tags = TagSupport.sorted((task.tags ?? []) + [tag])
            try? modelContext.save()
        }
    }

    private func remove(_ tag: Tag) {
        task.tags = (task.tags ?? []).filter { $0.id != tag.id }
        try? modelContext.save()
    }

    private func addTag() {
        let name = trimmedNewTagName
        guard !name.isEmpty else { return }

        let resolved = TagSupport.resolveTags(named: [name], in: modelContext)
        guard let tag = resolved.first else { return }
        if !isSelected(tag) {
            task.tags = TagSupport.sorted((task.tags ?? []) + [tag])
        }
        newTagName = ""
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
