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

    var body: some View {
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
        .background(Theme.surface.opacity(0.66))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct KanbanCompletionButton: View {
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(color)
        }
        .buttonStyle(.cadencePlain)
    }
}

struct KanbanCardHeader: View {
    let title: String
    let titleColor: Color
    let isStruckThrough: Bool
    let durationBadge: String?
    let completionButtonIcon: String
    let completionButtonColor: Color
    let onCompletionTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            KanbanCompletionButton(
                icon: completionButtonIcon,
                color: completionButtonColor,
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
                KanbanDurationBadge(duration: durationBadge)
                    .padding(.top, -1)
            }
        }
    }
}

struct KanbanCardScheduleTopRow: View {
    let startTime: String?
    let duration: String?

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
                KanbanDurationBadge(duration: duration)
            }
        }
        .frame(height: 14)
    }
}

struct KanbanDurationBadge: View {
    let duration: String

    var body: some View {
        Text(duration)
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(Theme.dim)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Theme.surface.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
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
        RoundedRectangle(cornerRadius: 8)
            .fill(isHovered ? Theme.surfaceElevated.opacity(1.0) : Theme.surfaceElevated)
            .overlay {
                if urgencyBackgroundTint != .clear {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(urgencyBackgroundTint)
                }
            }
            .overlay {
                if isPendingCompletion {
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Theme.green.opacity(0.24))
                            .frame(width: proxy.size.width * completionProgress, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if isPendingCancel {
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Theme.dim.opacity(0.18))
                            .frame(width: proxy.size.width * cancelProgress, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .overlay {
                if isDone {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.surface.opacity(0.18))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.white.opacity(0.04))
            }
    }
}
#endif
