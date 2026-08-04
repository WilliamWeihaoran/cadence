#if os(iOS)
import SwiftUI

enum iOSMarkdownReferencePickerKind: String, Identifiable {
    case note
    case task

    var id: String { rawValue }

    var title: String {
        switch self {
        case .note: return "Insert Note Link"
        case .task: return "Insert Task Reference"
        }
    }

    var emptyTitle: String {
        switch self {
        case .note: return "No notes yet"
        case .task: return "No tasks yet"
        }
    }

    var emptySubtitle: String {
        switch self {
        case .note: return "Create or open a note first, then link it here."
        case .task: return "Create a task first, then reference it here."
        }
    }
}

struct iOSMarkdownReferencePickerSheet: View {
    let kind: iOSMarkdownReferencePickerKind
    let notes: [Note]
    let tasks: [AppTask]
    let insert: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filteredNotes: [Note] {
        notes
            .filter { matches($0.displayTitle) || matches($0.content) }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
            }
    }

    private var filteredTasks: [AppTask] {
        tasks
            .filter { !$0.isCancelled }
            .filter { matches($0.title) || matches($0.notes) || matches($0.containerName) }
            .sorted { lhs, rhs in
                if lhs.isDone != rhs.isDone { return !lhs.isDone && rhs.isDone }
                if priorityRank(lhs.priority) != priorityRank(rhs.priority) {
                    return priorityRank(lhs.priority) > priorityRank(rhs.priority)
                }
                if lhs.order != rhs.order { return lhs.order < rhs.order }
                return lhs.createdAt > rhs.createdAt
            }
    }

    private var isEmpty: Bool {
        switch kind {
        case .note: return filteredNotes.isEmpty
        case .task: return filteredTasks.isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isEmpty {
                    emptyState
                } else {
                    List {
                        switch kind {
                        case .note:
                            ForEach(filteredNotes) { note in
                                Button {
                                    insert(NoteReferenceParser.noteReferenceMarkdown(for: note))
                                    dismiss()
                                } label: {
                                    iOSMarkdownNoteReferenceRow(note: note)
                                }
                                .buttonStyle(.plain)
                            }
                        case .task:
                            ForEach(filteredTasks) { task in
                                Button {
                                    insert(NoteReferenceParser.taskReferenceMarkdown(for: task))
                                    dismiss()
                                } label: {
                                    iOSMarkdownTaskReferenceRow(task: task)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Theme.surface)
                }
            }
            .background(Theme.surface.ignoresSafeArea())
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: kind == .note ? "doc.text.magnifyingglass" : "checklist")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.dim)
            Text(kind.emptyTitle)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(kind.emptySubtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func matches(_ value: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return value.localizedCaseInsensitiveContains(trimmed)
    }

    private func priorityRank(_ priority: TaskPriority) -> Int {
        switch priority {
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        case .none: return 0
        }
    }
}

private struct iOSMarkdownNoteReferenceRow: View {
    let note: Note

    private var subtitle: String {
        switch note.kind {
        case .daily:
            return note.dateKey.isEmpty ? "Daily note" : note.dateKey
        case .weekly:
            return note.weekKey.isEmpty ? "Weekly note" : note.weekKey
        case .permanent:
            return "Notepad"
        case .list:
            return "Linked note"
        case .meeting:
            return note.eventDateKey.isEmpty ? "Meeting note" : "Meeting · \(note.eventDateKey)"
        }
    }

    private var preview: String {
        let preview = CadenceMarkdownPresentationSupport.plainPreviewText(from: note.content, limit: 120)
        return preview.isEmpty ? "Empty note" : preview
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.blue)
                .frame(width: 34, height: 34)
                .background(Theme.blue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(note.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                Text(preview)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

private struct iOSMarkdownTaskReferenceRow: View {
    let task: AppTask

    private var title: String {
        let trimmed = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Task" : trimmed
    }

    private var subtitle: String {
        var parts: [String] = []
        if !task.containerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(task.containerName)
        }
        if !task.scheduledDate.isEmpty {
            parts.append("Do \(CadenceTaskPresentationSupport.scheduledDateLabel(for: task))")
        } else if !task.dueDate.isEmpty {
            parts.append("Due \(CadenceTaskPresentationSupport.dueDateLabel(for: task))")
        }
        if task.isDone {
            parts.append("Completed")
        }
        return parts.isEmpty ? "Inbox" : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(task.isDone ? Theme.green : Theme.blue)
                .frame(width: 34, height: 34)
                .background((task.isDone ? Theme.green : Theme.blue).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(task.isDone ? Theme.muted : Theme.text)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

struct iOSMarkdownReferenceCompletionChoice: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let markdown: String
}

struct iOSMarkdownReferenceCompletionStrip: View {
    let context: MarkdownReferenceCompletionContext
    let choices: [iOSMarkdownReferenceCompletionChoice]
    let insert: (String) -> Void

    private var title: String {
        switch context.kind {
        case .note: return "Notes"
        case .task: return "Tasks"
        }
    }

    private var emptyText: String {
        switch context.kind {
        case .note: return "No matching notes"
        case .task: return "No matching tasks"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: context.kind == .task ? "checkmark.circle" : "doc.text")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(context.kind == .task ? Theme.green : Theme.blue)

                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .textCase(.uppercase)

                if !context.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(context.query)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            if choices.isEmpty {
                Text(emptyText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surfaceElevated.opacity(0.38))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(choices) { choice in
                            Button {
                                insert(choice.markdown)
                            } label: {
                                iOSMarkdownReferenceCompletionPill(choice: choice)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.trailing, 10)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.bg.opacity(0.28))
    }
}

private struct iOSMarkdownReferenceCompletionPill: View {
    let choice: iOSMarkdownReferenceCompletionChoice

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: choice.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(choice.tint)
                .frame(width: 24, height: 24)
                .background(choice.tint.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(choice.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                Text(choice.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: 220, alignment: .leading)
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(Theme.surfaceElevated.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.54), lineWidth: 1)
        }
    }
}

struct iOSMarkdownSlashCommandStrip: View {
    let context: MarkdownSlashCommandContext
    let commands: [MarkdownSlashCommand]
    let apply: (MarkdownSlashCommand) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "slash.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.purple)

                Text("Commands")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .textCase(.uppercase)

                if !context.query.isEmpty {
                    Text("/\(context.query)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            if commands.isEmpty {
                Text("No matching commands")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surfaceElevated.opacity(0.38))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(commands) { command in
                            Button {
                                apply(command)
                            } label: {
                                iOSMarkdownSlashCommandPill(command: command)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.trailing, 10)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.bg.opacity(0.28))
    }
}

private struct iOSMarkdownSlashCommandPill: View {
    let command: MarkdownSlashCommand

    var body: some View {
        HStack(spacing: 9) {
            Text("/\(command.id)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.blue)
                .frame(minWidth: 38, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(command.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                Text(command.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: 230, alignment: .leading)
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(Theme.surfaceElevated.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.54), lineWidth: 1)
        }
    }
}

struct iOSMarkdownFormatToolbar: View {
    let apply: (MarkdownFormatCommand) -> Void
    let chooseImages: () -> Void

    private let primaryItems: [iOSMarkdownFormatToolbarItem] = [
        .text("P", "Paragraph", .paragraph),
        .text("H1", "Heading 1", .heading(1)),
        .text("H2", "Heading 2", .heading(2)),
        .icon("bold", "Bold", .bold),
        .icon("italic", "Italic", .italic),
        .icon("strikethrough", "Strikethrough", .strikethrough),
        .icon("chevron.left.forwardslash.chevron.right", "Inline Code", .inlineCode),
        .icon("link", "Link", .link),
        .icon("list.bullet", "Bulleted List", .unorderedList),
        .icon("list.number", "Numbered List", .orderedList),
        .icon("checklist", "Checklist", .todoList),
        .icon("text.quote", "Quote", .quote),
        .icon("curlybraces.square", "Code Block", .codeBlock),
        .icon("minus", "Divider", .divider),
        .icon("text.badge.plus", "Note Link", .noteLink),
        .icon("checkmark.circle", "Task Reference", .taskReference)
    ]

    private var compactItems: [iOSMarkdownFormatToolbarItem] {
        [
            .icon("bold", "Bold", .bold),
            .icon("italic", "Italic", .italic),
            .icon("link", "Link", .link),
            .icon("list.bullet", "Bulleted List", .unorderedList),
            .icon("checklist", "Checklist", .todoList),
            .icon("text.badge.plus", "Note Link", .noteLink)
        ]
    }

    private var compactMoreItems: [iOSMarkdownFormatToolbarItem] {
        primaryItems.filter { item in
            !compactItems.contains(where: { $0.id == item.id })
        }
    }

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width < 620 {
                compactToolbar
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            } else {
                fullToolbar
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            }
        }
        .frame(height: 48)
        .background(Theme.bg.opacity(0.2))
    }

    private var fullToolbar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(Array(primaryItems.enumerated()), id: \.element.id) { index, item in
                    if [3, 8, 11, 14].contains(index) {
                        Capsule()
                            .fill(Theme.borderSubtle.opacity(0.62))
                            .frame(width: 1, height: 18)
                            .padding(.horizontal, 2)
                    }

                    iOSMarkdownFormatButton(item: item) {
                        apply(item.command)
                    }
                }

                Capsule()
                    .fill(Theme.borderSubtle.opacity(0.62))
                    .frame(width: 1, height: 18)
                    .padding(.horizontal, 2)

                Button(action: chooseImages) {
                    Image(systemName: "photo")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 38, height: 36)
                        .background(Theme.surface.opacity(0.78))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                                .strokeBorder(Theme.borderSubtle.opacity(0.44), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Image")
            }
            .padding(6)
            .cadenceCard(background: Theme.surfaceElevated.opacity(0.46), cornerRadius: Theme.radiusCard, shadowRadius: 8, shadowY: 3)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
    }

    private var compactToolbar: some View {
        // Wrapped in a horizontal ScrollView (matching fullToolbar) so the
        // row can never clip on smaller phones or larger Dynamic Type sizes
        // instead of silently hiding trailing buttons.
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(compactItems) { item in
                    iOSMarkdownFormatButton(item: item) {
                        apply(item.command)
                    }
                }

                Button(action: chooseImages) {
                    Image(systemName: "photo")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 38, height: 36)
                        .background(Theme.surface.opacity(0.78))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                                .strokeBorder(Theme.borderSubtle.opacity(0.44), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Image")

                Menu {
                    ForEach(compactMoreItems) { item in
                        Button {
                            apply(item.command)
                        } label: {
                            if let systemImage = item.systemImage {
                                Label(item.title, systemImage: systemImage)
                            } else {
                                Label(item.id, systemImage: item.menuSystemImage)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 38, height: 36)
                        .background(Theme.surface.opacity(0.78))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                                .strokeBorder(Theme.borderSubtle.opacity(0.44), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More formatting")
            }
            .padding(6)
            .cadenceCard(background: Theme.surfaceElevated.opacity(0.46), cornerRadius: Theme.radiusCard, shadowRadius: 8, shadowY: 3)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
    }
}

private struct iOSMarkdownFormatToolbarItem: Identifiable {
    let id: String
    let title: String
    let systemImage: String?
    let command: MarkdownFormatCommand

    static func icon(_ systemImage: String, _ title: String, _ command: MarkdownFormatCommand) -> iOSMarkdownFormatToolbarItem {
        iOSMarkdownFormatToolbarItem(id: title, title: title, systemImage: systemImage, command: command)
    }

    static func text(_ title: String, _ accessibilityTitle: String, _ command: MarkdownFormatCommand) -> iOSMarkdownFormatToolbarItem {
        iOSMarkdownFormatToolbarItem(id: accessibilityTitle, title: title, systemImage: nil, command: command)
    }

    var menuSystemImage: String {
        switch command {
        case .paragraph:
            return "paragraphsign"
        case .heading:
            return "textformat.size"
        default:
            return systemImage ?? "textformat"
        }
    }
}

private struct iOSMarkdownFormatButton: View {
    let item: iOSMarkdownFormatToolbarItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage = item.systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                } else {
                    Text(item.title)
                        .font(.system(size: 11, weight: .bold))
                }
            }
            .foregroundStyle(Theme.text)
            .frame(width: 38, height: 36)
            .background(Theme.surface.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                    .strokeBorder(Theme.borderSubtle.opacity(0.44), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.id)
    }
}

struct iOSMarkdownEmptyPrompt: View {
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(placeholder)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text.opacity(0.74))

            VStack(alignment: .leading, spacing: 5) {
                iOSMarkdownHintRow(text: "# Heading")
                iOSMarkdownHintRow(text: "- [ ] Task")
                iOSMarkdownHintRow(text: "**Bold** · [[Link]] · #tag")
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
    }
}

private struct iOSMarkdownHintRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(Theme.dim.opacity(0.76))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Theme.surfaceElevated.opacity(0.38))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct iOSMarkdownStatusBar: View {
    let wordCount: Int
    let lineCount: Int
    let mode: iOSMarkdownEditorMode
    let isRegularWidth: Bool

    var body: some View {
        HStack(spacing: 8) {
            Label(statusTitle, systemImage: mode.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(statusTint)

            Spacer(minLength: 8)

            if isRegularWidth {
                Text("\(lineCount) \(lineCount == 1 ? "line" : "lines")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
            }

            Text("\(wordCount) \(wordCount == 1 ? "word" : "words")")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.dim)
        }
        .padding(.horizontal, isRegularWidth ? 14 : 12)
        .frame(height: isRegularWidth ? 34 : 32)
        .background(Theme.bg.opacity(0.34))
    }

    private var statusTitle: String {
        switch mode {
        case .live: return "Live Markdown"
        case .edit: return "Markdown"
        case .preview: return "Rendered"
        }
    }

    private var statusTint: Color {
        switch mode {
        case .live: return Theme.purple
        case .edit: return Theme.blue
        case .preview: return Theme.green
        }
    }
}
#endif
