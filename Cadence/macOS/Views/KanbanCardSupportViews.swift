#if os(macOS)
import SwiftUI

/// What a meta chip does when clicked. Every case must open something — a board chip is never
/// decorative, so there is deliberately no "inert" case.
enum KanbanMetaAction: Hashable {
    case doDate
    case dueDate
    /// Opens the same searchable list picker `ContainerPickerBadge` presents elsewhere.
    case container
}

/// How a meta chip washes on hover. Deliberately separate from `KanbanMetaItem.tint`: the tint
/// colors the chip's **icon** (identity — which list this is, what kind of date this is), while
/// this decides the hover **state** color. Conflating the two is what made the list chip hover in
/// whatever color its container happened to be.
enum KanbanMetaHoverStyle {
    /// Hover wash in the chip's own semantic color — the do chip is amber, the due chip is red,
    /// because those hues *mean* something about the field.
    case semantic(Color)
    /// Neutral raise only: the base fill goes to full `Theme.surfaceElevated` and picks up a
    /// `Theme.borderSubtle` hairline, matching the neutral hover used everywhere else in the app.
    /// Used by the list chip, whose tint is the container color.
    case neutral
}

struct KanbanMetaItem: Identifiable {
    let id: String
    let icon: String
    let text: String
    /// Icon color. Identity, not hover state — see `KanbanMetaHoverStyle`.
    let tint: Color
    let textColor: Color
    /// Hover fill/border treatment. Defaults to neutral so a new chip cannot accidentally leak a
    /// container color into its hover.
    var hoverStyle: KanbanMetaHoverStyle = .neutral
    let action: KanbanMetaAction
}

struct KanbanMetaChip: View {
    let item: KanbanMetaItem
    var isFocused: Bool = false
    var onHoverChanged: (Bool) -> Void = { _ in }
    @State private var isHovered = false

    /// Hue washed over the resting fill on hover. Neutral chips add nothing here — their raise
    /// comes from the base fill going to full `Theme.surfaceElevated` below.
    private func hoverFill(focused: Bool) -> Color {
        guard focused, case .semantic(let color) = item.hoverStyle else { return .clear }
        return color.opacity(0.10)
    }

    private func hoverBorder(focused: Bool) -> Color {
        guard focused else { return .clear }
        switch item.hoverStyle {
        case .semantic(let color): return color.opacity(0.28)
        case .neutral: return Theme.borderSubtle
        }
    }

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
                        .fill(hoverFill(focused: focused))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(hoverBorder(focused: focused), lineWidth: 1)
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
    let duration: String
    let onDurationTap: (() -> Void)?
    var isDurationFocused = false
    var onDurationHoverChanged: (Bool) -> Void = { _ in }
    /// Passed through to the duration badge, which is the only thing in this row a test clicks.
    /// Defaulted, so the row keeps its existing call signature. See `KanbanDurationBadge`.
    var durationAccessibilityIdentifier: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            if let startTime {
                Text(startTime)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            KanbanDurationBadge(
                duration: duration,
                onTap: onDurationTap,
                isFocused: isDurationFocused,
                onHoverChanged: onDurationHoverChanged,
                accessibilityIdentifier: durationAccessibilityIdentifier
            )
        }
        .frame(height: 14)
    }
}

struct KanbanDurationBadge: View {
    let duration: String
    var onTap: (() -> Void)?
    var isFocused = false
    var onHoverChanged: (Bool) -> Void = { _ in }
    /// **Why not a label query** (T-1740): this badge already has an accessibility label and it is
    /// the field's *name*, but the badge sits on a card that draws a second estimate badge in its
    /// header when there is no scheduled start (`KanbanCard.headerDurationBadge`), so "the button
    /// called Estimate on this card" is not a unique address. An identifier carrying the task's
    /// title is.
    var accessibilityIdentifier: String? = nil
    @State private var isHovered = false

    var body: some View {
        Group {
            if let onTap {
                Button(action: onTap) {
                    label
                }
                .buttonStyle(.cadencePlain)
                .accessibilityLabel(CadenceTaskControlAccessibility.estimate)
                .accessibilityValue(duration)
                .help("Set duration")
            } else {
                label
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        // `accessibilityIdentifier(_:)` takes a non-optional, and an empty string is not the same
        // as no identifier — it would replace whatever the element inherits. So the modifier is
        // applied only when there is one to apply.
        .modifier(CadenceOptionalAccessibilityIdentifier(identifier: accessibilityIdentifier))
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
    let completionProgress: CGFloat
    let cancelProgress: CGFloat

    var body: some View {
        // Columns are containerless now, so the card's own container is what makes it read
        // as an object sitting on the canvas: flat Theme.surface, hairline border (applied
        // by the caller), tight radius, no elevation shadow.
        //
        // Hover is the neutral `Theme.surfaceElevated` raise and nothing else — no list/priority
        // tint, no overdue wash. Urgency stays readable through the persistent red do/due text.
        RoundedRectangle(cornerRadius: kanbanCardCornerRadius, style: .continuous)
            .fill(TaskHoverVisuals.cardFill(isHovered: isHovered))
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

/// Apply an accessibility identifier **only when there is one**.
///
/// `accessibilityIdentifier(_:)` takes a non-optional `String`, and passing `""` is a real
/// assignment rather than a no-op — it clears whatever the element would otherwise publish. A
/// control that takes its identifier from a caller that may not have one therefore needs the
/// modifier to be absent, not empty, and a `ViewModifier` is the only way to say that without
/// erasing the view through `AnyView`.
private struct CadenceOptionalAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}
#endif
