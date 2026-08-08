#if os(macOS)
import SwiftUI

enum KanbanMetaAction: Hashable {
    case none
    case priority
    case doDate
    case dueDate
}

struct KanbanMetaItem: Identifiable {
    let id: String
    let icon: String
    let text: String
    let tint: Color
    let textColor: Color
    let action: KanbanMetaAction
}

enum KanbanCardPresentation {
    case listBoard
    case calendarBoard(dateKey: String)
}

struct KanbanMetaChip: View {
    let item: KanbanMetaItem
    var isFocused: Bool = false
    var onHoverChanged: (Bool) -> Void = { _ in }
    @State private var isHovered = false

    var body: some View {
        let focused = isFocused || isHovered
        HStack(spacing: 5) {
            Image(systemName: item.icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(item.tint)
                .frame(width: 10)
            Text(item.text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(item.textColor)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.surfaceElevated.opacity(focused ? 1 : 0.75))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(item.tint.opacity(focused ? 0.10 : 0))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(item.tint.opacity(focused ? 0.28 : 0), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover { hovering in
            isHovered = hovering
            onHoverChanged(hovering)
        }
    }
}

struct KanbanCompletionButton: View {
    let icon: String
    let color: Color
    var progress: Double?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TaskCompletionProgressGlyph(
                icon: icon,
                color: color,
                progress: progress,
                size: 15,
                lineWidth: 1.8
            )
        }
        .buttonStyle(.cadencePlain)
    }
}

struct KanbanCardHeader: View {
    let title: String
    let titleColor: Color
    let isStruckThrough: Bool
    let durationBadge: String?
    let onDurationTap: (() -> Void)?
    var isDurationFocused = false
    var onDurationHoverChanged: (Bool) -> Void = { _ in }
    let completionButtonIcon: String
    let completionButtonColor: Color
    var completionProgress: Double?
    let onCompletionTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            KanbanCompletionButton(
                icon: completionButtonIcon,
                color: completionButtonColor,
                progress: completionProgress,
                action: onCompletionTap
            )

            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(titleColor)
                .strikethrough(isStruckThrough, color: Theme.dim)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())

            if let durationBadge {
                KanbanDurationBadge(
                    duration: durationBadge,
                    onTap: onDurationTap,
                    isFocused: isDurationFocused,
                    onHoverChanged: onDurationHoverChanged
                )
                    .padding(.top, -1)
            }
        }
    }
}

struct KanbanCardScheduleTopRow: View {
    let startTime: String?
    let duration: String?
    let onDurationTap: (() -> Void)?
    var isDurationFocused = false
    var onDurationHoverChanged: (Bool) -> Void = { _ in }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            if let startTime {
                Text(startTime)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let duration {
                KanbanDurationBadge(
                    duration: duration,
                    onTap: onDurationTap,
                    isFocused: isDurationFocused,
                    onHoverChanged: onDurationHoverChanged
                )
            }
        }
        .frame(height: 14)
    }
}

struct KanbanDurationBadge: View {
    let duration: String
    var onTap: (() -> Void)?
    var isFocused = false
    var onHoverChanged: (Bool) -> Void = { _ in }
    @State private var isHovered = false

    var body: some View {
        Group {
            if let onTap {
                Button(action: onTap) {
                    label
                }
                .buttonStyle(.cadencePlain)
                .help("Set duration")
            } else {
                label
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .onHover { hovering in
            isHovered = hovering
            onHoverChanged(hovering)
        }
    }

    private var label: some View {
        Text(duration)
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(focused ? Theme.text : Theme.dim)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Theme.surfaceElevated.opacity(focused ? 1 : 0.75))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Theme.blue.opacity(focused ? 0.12 : 0))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Theme.blue.opacity(focused ? 0.30 : 0), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var focused: Bool {
        isFocused || isHovered
    }
}

struct KanbanMetadataRows: View {
    let rows: [[KanbanMetaItem]]
    let chipContent: (KanbanMetaItem) -> AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 6) {
                    ForEach(rows[rowIndex]) { item in
                        chipContent(item)
                    }
                }
            }
        }
    }
}

struct KanbanPriorityPickerPopover: View {
    @Binding var priority: TaskPriority
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(TaskPriority.allCases, id: \.self) { value in
                Button {
                    priority = value
                    isPresented = false
                    } label: {
                        HStack(spacing: 8) {
                        Text(TaskTitleSupport.priorityMark(for: value))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(value == .none ? Theme.dim : Theme.priorityColor(value))
                            .frame(width: 24, alignment: .leading)
                        Text(value.label)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.text)
                        Spacer()
                        if priority == value {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.blue)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.cadencePlain)
            }
        }
        .padding(.vertical, 6)
        .frame(minWidth: 150)
        .background(Theme.surfaceElevated)
    }
}

struct KanbanCardBackground: View {
    let isHovered: Bool
    let isDone: Bool
    let isPendingCompletion: Bool
    let isPendingCancel: Bool
    let urgencyBackgroundTint: Color
    let completionProgress: CGFloat
    let cancelProgress: CGFloat

    var body: some View {
        // Columns are containerless now, so the card's own container is what makes it read
        // as an object sitting on the canvas: flat Theme.surface, hairline border (applied
        // by the caller), tight radius, no elevation shadow.
        RoundedRectangle(cornerRadius: kanbanCardCornerRadius, style: .continuous)
            .fill(isHovered ? Theme.surfaceElevated : Theme.surface)
            .overlay {
                if urgencyBackgroundTint != .clear {
                    RoundedRectangle(cornerRadius: kanbanCardCornerRadius, style: .continuous)
                        .fill(urgencyBackgroundTint)
                }
            }
            .overlay {
                if isPendingCompletion {
                    TaskCompletionPendingOverlay(
                        progress: Double(completionProgress),
                        tint: Theme.green,
                        cornerRadius: kanbanCardCornerRadius
                    )
                } else if isPendingCancel {
                    TaskCompletionPendingOverlay(
                        progress: Double(cancelProgress),
                        tint: Theme.dim,
                        cornerRadius: kanbanCardCornerRadius
                    )
                }
            }
            .overlay {
                if isDone {
                    RoundedRectangle(cornerRadius: kanbanCardCornerRadius, style: .continuous)
                        .fill(Theme.bg.opacity(0.28))
                }
            }
    }
}
#endif
