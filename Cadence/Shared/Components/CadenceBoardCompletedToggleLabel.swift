import SwiftUI

/// The "Completed N" row that closes a board column's card stack, drawn once for every board on
/// both platforms: the Mac's section board and Calendar Board (through `KanbanCompletedTasksToggle`)
/// and the iOS Calendar Board's day column.
///
/// [[T-9835]]: iOS used to draw its own -- the count pushed to the trailing edge in a neutral
/// capsule on a strokeless plate at `Theme.radiusControl` -- beside the Mac's green count right
/// after the word on a hairlined surface plate. The Mac's was already the deliberate shared look,
/// so it is the one kept. The only platform input is `minimumHeight`: iOS passes its 44pt touch
/// row, which nothing on a pointer asks for.
///
/// This is the label only. Each platform wraps it in its own button style and states
/// Expanded/Collapsed itself, because the press feedback is the part that really differs.
struct CadenceBoardCompletedToggleLabel: View {
    /// The plate's radius. A `.cadencePlain` wrapper passes this so its hover wash meets the
    /// plate's corners ([[T-9535]]).
    static let cornerRadius: CGFloat = Theme.radiusControlCompact

    let count: Int
    let isExpanded: Bool
    /// A floor for the row, in points at the default text size, grown as iOS's touch rows grow
    /// (`.rowTitle`, as this row's own 44pt floor always was). `nil` lets the padding decide, as the Mac does.
    var minimumHeight: CGFloat? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
    }

    private var resolvedMinimumHeight: CGFloat? {
        minimumHeight.map { CadenceTypeScale.height($0, holding: .rowTitle, at: dynamicTypeSize, scaling: scaling) }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .cadenceFont(.metadata, base: 10, weight: .semibold)
                .accessibilityHidden(true)
            Text("Completed")
                .cadenceFont(.metadata, base: 11, weight: .semibold)
            Text("\(count)")
                .cadenceFont(.metadata, base: 10, weight: .medium)
                .monospacedDigit()
                .foregroundStyle(Theme.green)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.green.opacity(0.12))
                .clipShape(Capsule())
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.dim)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: resolvedMinimumHeight, alignment: .leading)
        .background {
            shape.fill(Theme.surface)
        }
        .overlay {
            shape.strokeBorder(Theme.borderSubtle, lineWidth: 1)
        }
        .contentShape(shape)
    }
}
