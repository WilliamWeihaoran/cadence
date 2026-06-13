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
                    .foregroundStyle(statusColor)
                    .frame(width: isRegularWidth ? 38 : 34, height: isRegularWidth ? 38 : 34)
                    .background(statusColor.opacity(0.13))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.status.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(statusColor)
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
                            title: "Due \(DateFormatters.relativeDate(from: task.dueDate))",
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
        .padding(isRegularWidth ? 18 : 16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.55), lineWidth: 1)
        }
    }

    private var statusColor: Color {
        switch task.status {
        case .todo: return Theme.blue
        case .inProgress: return Theme.amber
        case .done: return Theme.green
        case .cancelled: return Theme.red
        }
    }

    private var estimateLabel: String {
        if task.estimatedMinutes < 60 { return "\(task.estimatedMinutes)m" }
        if task.estimatedMinutes % 60 == 0 { return "\(task.estimatedMinutes / 60)h" }
        return String(format: "%.1fh", Double(task.estimatedMinutes) / 60.0)
    }
}

struct iOSTaskEditorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isRegularWidth ? 11 : 10) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .textCase(.uppercase)
                .kerning(0.8)

            VStack(alignment: .leading, spacing: isRegularWidth ? 12 : 10) {
                content()
            }
            .padding(isRegularWidth ? 14 : 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.borderSubtle.opacity(0.5), lineWidth: 1)
            }
        }
    }
}

struct iOSTaskEditorRow<Content: View>: View {
    let label: String
    let systemImage: String
    let color: Color
    @ViewBuilder let content: () -> Content
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        HStack(spacing: isRegularWidth ? 12 : 10) {
            Image(systemName: systemImage)
                .font(.system(size: isRegularWidth ? 13 : 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: isRegularWidth ? 30 : 26, height: isRegularWidth ? 30 : 26)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: isRegularWidth ? 8 : 7, style: .continuous))

            Text(label)
                .font(.system(size: isRegularWidth ? 14 : 13, weight: .semibold))
                .foregroundStyle(Theme.text)

            Spacer(minLength: 12)

            content()
        }
        .frame(minHeight: isRegularWidth ? 44 : 38)
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
            .overlay {
                Capsule()
                    .strokeBorder(color.opacity(0.18), lineWidth: 1)
            }
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

    var body: some View {
        HStack(spacing: 9) {
            Button {
                subtask.isDone.toggle()
            } label: {
                Image(systemName: subtask.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(subtask.isDone ? Theme.green : Theme.dim)
            }
            .buttonStyle(.plain)

            Text(subtask.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(subtask.isDone ? Theme.dim : Theme.text)
                .strikethrough(subtask.isDone, color: Theme.dim)
                .lineLimit(2)

            Spacer(minLength: 8)

            Button(action: delete) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 28, height: 28)
                    .background(Theme.surfaceElevated.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.surfaceElevated.opacity(0.34))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.4), lineWidth: 1)
        }
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
                    .background(Theme.surfaceElevated.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Theme.borderSubtle.opacity(0.45), lineWidth: 1)
                    }
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
