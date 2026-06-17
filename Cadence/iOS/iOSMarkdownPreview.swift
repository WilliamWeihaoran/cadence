#if os(iOS)
import SwiftUI

struct iOSMarkdownPreview: View {
    let markdown: String
    var imageAssets: [MarkdownImageAsset] = []
    var taskEmbeds: [UUID: MarkdownTaskEmbedRenderInfo] = [:]
    var onToggleChecklist: ((Int) -> Void)?
    var onToggleEmbeddedTask: ((UUID) -> Void)?
    var onToggleEmbeddedSubtask: ((UUID, UUID) -> Void)?
    var onOpenEmbeddedTask: ((UUID) -> Void)?
    var onOpenReference: ((MarkdownReferenceDisplayTarget) -> Void)?

    private var blocks: [MarkdownPreviewBlock] {
        MarkdownPreviewParser.blocks(in: markdown)
    }

    var body: some View {
        ScrollView {
            if blocks.isEmpty {
                iOSMarkdownPreviewEmptyState()
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        iOSMarkdownPreviewBlockView(
                            block: block,
                            imageAssets: imageAssets,
                            taskEmbeds: taskEmbeds,
                            onToggleChecklist: onToggleChecklist,
                            onToggleEmbeddedTask: onToggleEmbeddedTask,
                            onToggleEmbeddedSubtask: onToggleEmbeddedSubtask,
                            onOpenEmbeddedTask: onOpenEmbeddedTask,
                            onOpenReference: onOpenReference
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            }
        }
        .scrollIndicators(.hidden)
        .background(Theme.surface)
    }
}

private struct iOSMarkdownPreviewBlockView: View {
    let block: MarkdownPreviewBlock
    let imageAssets: [MarkdownImageAsset]
    let taskEmbeds: [UUID: MarkdownTaskEmbedRenderInfo]
    let onToggleChecklist: ((Int) -> Void)?
    let onToggleEmbeddedTask: ((UUID) -> Void)?
    let onToggleEmbeddedSubtask: ((UUID, UUID) -> Void)?
    let onOpenEmbeddedTask: ((UUID) -> Void)?
    let onOpenReference: ((MarkdownReferenceDisplayTarget) -> Void)?

    var body: some View {
        switch block {
        case .heading(let level, let text):
            iOSMarkdownPreviewInlineText(text: text, onOpenReference: onOpenReference)
                .font(.system(size: headingSize(level), weight: .bold))
                .foregroundStyle(Theme.text)
                .padding(.top, level <= 2 ? 4 : 1)

        case .paragraph(let text):
            iOSMarkdownPreviewInlineText(text: text, onOpenReference: onOpenReference)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Theme.text)
                .lineSpacing(5)

        case .bullet(let depth, let text):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle()
                    .fill(Theme.blue.opacity(0.85))
                    .frame(width: 5, height: 5)
                    .alignmentGuide(.firstTextBaseline) { context in context[VerticalAlignment.center] }
                iOSMarkdownPreviewInlineText(text: text, onOpenReference: onOpenReference)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Theme.text)
            }
            .padding(.leading, listIndent(for: depth))

        case .ordered(let depth, let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(number)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.blue)
                    .frame(width: 28, alignment: .trailing)
                iOSMarkdownPreviewInlineText(text: text, onOpenReference: onOpenReference)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Theme.text)
            }
            .padding(.leading, listIndent(for: depth))

        case .checklist(let depth, let isDone, let text, let lineIndex):
            iOSMarkdownPreviewChecklistRow(
                depth: depth,
                isDone: isDone,
                text: text,
                lineIndex: lineIndex,
                onToggleChecklist: onToggleChecklist,
                onOpenReference: onOpenReference
            )

        case .quote(let depth, let text):
            iOSMarkdownPreviewQuoteBlock(
                depth: depth,
                text: text,
                onOpenReference: onOpenReference
            )

        case .code(let language, let text):
            VStack(alignment: .leading, spacing: 8) {
                if let language {
                    Text(language)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.amber)
                        .textCase(.uppercase)
                }

                Text(text.isEmpty ? " " : text)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(Theme.surfaceElevated.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Theme.borderSubtle.opacity(0.48), lineWidth: 1)
            }

        case .image(let reference):
            iOSMarkdownPreviewImageBlock(
                reference: reference,
                asset: MarkdownImageAssetService.renderAsset(for: reference.id, in: imageAssets)
            )

        case .taskEmbed(let reference):
            iOSMarkdownPreviewTaskEmbedBlock(
                task: taskEmbeds[reference.id] ?? .missing(reference: reference),
                onToggleTask: onToggleEmbeddedTask,
                onToggleSubtask: onToggleEmbeddedSubtask,
                onOpenTask: onOpenEmbeddedTask,
                onOpenReference: onOpenReference
            )

        case .table(let table):
            iOSMarkdownPreviewTableBlock(table: table, onOpenReference: onOpenReference)

        case .divider:
            Rectangle()
                .fill(Theme.borderSubtle.opacity(0.72))
                .frame(height: 1)
                .padding(.vertical, 6)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 25
        case 2: return 21
        case 3: return 18
        case 4: return 16
        default: return 15
        }
    }

    private func listIndent(for depth: Int) -> CGFloat {
        CGFloat(min(max(depth, 0), 6)) * 18
    }
}

private struct iOSMarkdownPreviewTableBlock: View {
    let table: MarkdownPreviewTable
    let onOpenReference: ((MarkdownReferenceDisplayTarget) -> Void)?

    private var columnCount: Int {
        max(table.headers.count, table.rows.map(\.count).max() ?? 0)
    }

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(0..<columnCount, id: \.self) { column in
                        cell(text: value(in: table.headers, at: column), isHeader: true)
                    }
                }

                ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(0..<columnCount, id: \.self) { column in
                            cell(text: value(in: row, at: column), isHeader: false)
                                .background(rowIndex.isMultiple(of: 2) ? Theme.surface.opacity(0.18) : Color.clear)
                        }
                    }
                }
            }
            .background(Theme.surfaceElevated.opacity(0.38))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Theme.borderSubtle.opacity(0.54), lineWidth: 1)
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func value(in row: [String], at index: Int) -> String {
        row.indices.contains(index) ? row[index] : ""
    }

    private func cell(text: String, isHeader: Bool) -> some View {
        iOSMarkdownPreviewInlineText(
            text: text.isEmpty ? " " : text,
            fillsWidth: false,
            onOpenReference: onOpenReference
        )
            .font(.system(size: 12, weight: isHeader ? .bold : .medium))
            .foregroundStyle(isHeader ? Theme.text : Theme.muted)
            .lineLimit(3)
            .frame(minWidth: 112, maxWidth: 220, alignment: .topLeading)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(isHeader ? Theme.blue.opacity(0.10) : Color.clear)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Theme.borderSubtle.opacity(0.38))
                    .frame(width: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.borderSubtle.opacity(isHeader ? 0.58 : 0.28))
                    .frame(height: 1)
            }
    }
}

private struct iOSMarkdownPreviewQuoteBlock: View {
    let depth: Int
    let text: String
    let onOpenReference: ((MarkdownReferenceDisplayTarget) -> Void)?

    private var normalizedDepth: Int {
        min(max(depth, 1), 6)
    }

    private var tint: Color {
        normalizedDepth.isMultiple(of: 2) ? Theme.purple : Theme.blue
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(0..<normalizedDepth, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(tint.opacity(level == normalizedDepth - 1 ? 0.72 : 0.32))
                    .frame(width: 3)
            }

            iOSMarkdownPreviewInlineText(text: text, onOpenReference: onOpenReference)
                .font(.system(size: CGFloat(max(13, 15 - normalizedDepth)), weight: .medium))
                .foregroundStyle(Theme.muted)
                .lineSpacing(4)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .padding(.leading, CGFloat(normalizedDepth - 1) * 12)
        .background(tint.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tint.opacity(0.13), lineWidth: 1)
        }
    }
}

private struct iOSMarkdownPreviewImageBlock: View {
    let reference: MarkdownImageReference
    let asset: MarkdownImageRenderAsset?

    var body: some View {
        if let asset {
            VStack(alignment: .leading, spacing: 7) {
                Image(uiImage: asset.image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: min(asset.displayWidth, 620), alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.borderSubtle.opacity(0.48), lineWidth: 1)
                    }

                if !reference.altText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(reference.altText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 10) {
                Image(systemName: "photo")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.dim)

                VStack(alignment: .leading, spacing: 2) {
                    Text(reference.altText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Missing image" : reference.altText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                    Text(reference.id.uuidString)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.dim.opacity(0.75))
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceElevated.opacity(0.38))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Theme.borderSubtle.opacity(0.48), lineWidth: 1)
            }
        }
    }
}

private struct iOSMarkdownPreviewTaskEmbedBlock: View {
    let task: MarkdownTaskEmbedRenderInfo
    let onToggleTask: ((UUID) -> Void)?
    let onToggleSubtask: ((UUID, UUID) -> Void)?
    let onOpenTask: ((UUID) -> Void)?
    let onOpenReference: ((MarkdownReferenceDisplayTarget) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    guard !task.isMissing else { return }
                    onToggleTask?(task.id)
                } label: {
                    Image(systemName: statusImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(statusTint)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(onToggleTask == nil || task.isMissing)

                VStack(alignment: .leading, spacing: 7) {
                    Text(task.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(task.isDone ? Theme.dim : Theme.text)
                        .strikethrough(task.isDone, color: Theme.dim)
                        .lineLimit(2)

                    if !chips.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 6) {
                                ForEach(chips, id: \.title) { chip in
                                    iOSMarkdownPreviewTaskChip(chip: chip)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                }

                Spacer(minLength: 0)
            }

            if task.hasSubtasks {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(task.completedSubtaskCount)/\(task.subtaskTotalCount) subtasks")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.dim)

                    ForEach(task.visibleSubtasks, id: \.id) { subtask in
                        HStack(spacing: 7) {
                            Button {
                                guard !task.isMissing else { return }
                                onToggleSubtask?(task.id, subtask.id)
                            } label: {
                                Image(systemName: subtask.isDone ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(subtask.isDone ? Theme.green : Theme.dim)
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.plain)
                            .disabled(onToggleSubtask == nil || task.isMissing)

                            Text(subtask.title.isEmpty ? "Untitled" : subtask.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(subtask.isDone ? Theme.dim : Theme.muted)
                                .strikethrough(subtask.isDone, color: Theme.dim)
                                .lineLimit(1)
                        }
                    }

                    if task.hiddenSubtaskCount > 0 {
                        Text("+\(task.hiddenSubtaskCount) more")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.dim)
                    }
                }
                .padding(.leading, 32)
            }
        }
        .padding(13)
        .frame(maxWidth: min(MarkdownTaskEmbedRenderInfo.maxCardWidth, 640), alignment: .leading)
        .background(Theme.surfaceElevated.opacity(task.isMissing ? 0.34 : 0.54))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(borderTint, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .onTapGesture {
            guard !task.isMissing else { return }
            openTask()
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: task.isDone ? "Mark Incomplete" : "Complete") {
            guard !task.isMissing else { return }
            onToggleTask?(task.id)
        }
        .accessibilityAction(named: "Open Task") {
            guard !task.isMissing else { return }
            openTask()
        }
        .accessibilityLabel(task.isMissing ? "Missing task reference" : "Open task \(task.title)")
    }

    private func openTask() {
        if let onOpenTask {
            onOpenTask(task.id)
        } else {
            onOpenReference?(
                MarkdownReferenceDisplayTarget(kind: .task, referenceID: task.id, title: task.title)
            )
        }
    }

    private var statusImage: String {
        if task.isMissing { return "exclamationmark.triangle.fill" }
        if task.isDone { return "checkmark.circle.fill" }
        return "circle"
    }

    private var statusTint: Color {
        if task.isMissing { return Theme.red }
        if task.isDone { return Theme.green }
        return Theme.blue
    }

    private var borderTint: Color {
        if task.isMissing { return Theme.red.opacity(0.42) }
        if task.isDone { return Theme.green.opacity(0.26) }
        return Theme.borderSubtle.opacity(0.52)
    }

    private var chips: [iOSMarkdownPreviewTaskChipModel] {
        var output: [iOSMarkdownPreviewTaskChipModel] = []
        let status = TaskStatus(rawValue: task.statusRaw) ?? (task.isDone ? .done : .todo)
        output.append(
            iOSMarkdownPreviewTaskChipModel(
                title: task.isMissing ? "Missing" : status.label,
                tint: task.isDone ? Theme.green : Theme.blue
            )
        )

        if let priority = TaskPriority(rawValue: task.priorityRaw), priority != .none {
            output.append(.init(title: priority.label, tint: priorityTint(priority)))
        }
        if task.estimatedMinutes > 0 {
            output.append(
                .init(
                    title: TimeFormatters.durationLabel(actual: task.actualMinutes, estimated: task.estimatedMinutes),
                    tint: Theme.amber
                )
            )
        }
        if !task.scheduledDate.isEmpty {
            let time = task.scheduledStartMin >= 0 ? " \(TimeFormatters.timeString(from: task.scheduledStartMin))" : ""
            output.append(.init(title: "Do \(DateFormatters.relativeDate(from: task.scheduledDate))\(time)", tint: Theme.blue))
        }
        if !task.dueDate.isEmpty {
            output.append(.init(title: "Due \(DateFormatters.relativeDate(from: task.dueDate))", tint: Theme.red))
        }
        if !task.containerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            output.append(.init(title: task.containerName, tint: Theme.muted))
        }
        return output
    }

    private func priorityTint(_ priority: TaskPriority) -> Color {
        switch priority {
        case .high: return Theme.red
        case .medium: return Theme.amber
        case .low: return Theme.green
        case .none: return Theme.dim
        }
    }
}

private struct iOSMarkdownPreviewTaskChipModel {
    let title: String
    let tint: Color
}

private struct iOSMarkdownPreviewTaskChip: View {
    let chip: iOSMarkdownPreviewTaskChipModel

    var body: some View {
        Text(chip.title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(chip.tint)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(chip.tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(chip.tint.opacity(0.22), lineWidth: 1)
            }
    }
}

private struct iOSMarkdownPreviewChecklistRow: View {
    let depth: Int
    let isDone: Bool
    let text: String
    let lineIndex: Int
    let onToggleChecklist: ((Int) -> Void)?
    let onOpenReference: ((MarkdownReferenceDisplayTarget) -> Void)?

    var body: some View {
        Button {
            onToggleChecklist?(lineIndex)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isDone ? Theme.green : Theme.dim)
                    .alignmentGuide(.firstTextBaseline) { context in context[VerticalAlignment.center] }

                iOSMarkdownPreviewInlineText(text: text, onOpenReference: onOpenReference)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(isDone ? Theme.dim : Theme.text)
                    .strikethrough(isDone, color: Theme.dim)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onToggleChecklist == nil)
        .padding(.leading, CGFloat(min(max(depth, 0), 6)) * 18)
        .accessibilityLabel(isDone ? "Mark checklist item incomplete" : "Complete checklist item")
    }
}

private struct iOSMarkdownPreviewInlineText: View {
    let text: String
    var fillsWidth = true
    let onOpenReference: ((MarkdownReferenceDisplayTarget) -> Void)?

    private var rendered: AttributedString {
        var output = AttributedString()
        for run in MarkdownInlinePreviewSupport.runs(in: text) {
            var renderedSegment = AttributedString(run.text)

            if run.traits.contains(.bold), run.traits.contains(.italic) {
                renderedSegment.inlinePresentationIntent = [.stronglyEmphasized, .emphasized]
            } else if run.traits.contains(.bold) {
                renderedSegment.inlinePresentationIntent = .stronglyEmphasized
            } else if run.traits.contains(.italic) {
                renderedSegment.inlinePresentationIntent = .emphasized
            }

            if run.traits.contains(.inlineCode) {
                renderedSegment.font = .system(size: 14, weight: .medium, design: .monospaced)
                renderedSegment.foregroundColor = Theme.amberLight
                renderedSegment.backgroundColor = Theme.surfaceElevated.opacity(0.72)
            }

            if run.traits.contains(.strikethrough) {
                renderedSegment.strikethroughStyle = .single
                renderedSegment.foregroundColor = Theme.dim
            }

            if run.traits.contains(.highlight) {
                renderedSegment.foregroundColor = Theme.amberLight
                renderedSegment.backgroundColor = Theme.amber.opacity(0.18)
            }

            if run.traits.contains(.tag) {
                renderedSegment.foregroundColor = Theme.greenLight
                renderedSegment.backgroundColor = Theme.green.opacity(0.10)
            }

            if run.traits.contains(.image) {
                renderedSegment.font = .system(size: 14, weight: .semibold)
                renderedSegment.foregroundColor = Theme.blueLight
                renderedSegment.backgroundColor = Theme.blue.opacity(0.12)
            }

            if let linkURL = run.linkURL, let url = URL(string: linkURL) {
                renderedSegment.link = url
                renderedSegment.foregroundColor = Theme.blueLight
                renderedSegment.underlineStyle = .single
            }

            if let target = run.target {
                renderedSegment.link = MarkdownReferenceDisplaySupport.url(for: target)
                renderedSegment.foregroundColor = target.kind == .task ? Theme.greenLight : Theme.blueLight
                renderedSegment.underlineStyle = .single
            }

            output += renderedSegment
        }
        return output
    }

    var body: some View {
        Text(rendered)
            .textSelection(.enabled)
            .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
            .environment(\.openURL, OpenURLAction { url in
                guard let target = MarkdownReferenceDisplaySupport.target(from: url) else {
                    return .systemAction
                }
                onOpenReference?(target)
                return .handled
            })
    }
}

private struct iOSMarkdownPreviewEmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Theme.blue)
                .frame(width: 38, height: 38)
                .background(Theme.blue.opacity(0.11))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Nothing rendered yet")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Write markdown and the rendered note will appear here.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
    }
}

#endif
