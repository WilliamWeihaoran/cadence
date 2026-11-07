import SwiftUI

/// The grey "Canceled" capsule a cancelled task's row draws — one view, both rows ([[T-12640]]).
///
/// `MacTaskRow` drew it beside the title since `a3ddd763`; `iOSTaskRow` never had one, so on
/// iPhone and iPad a cancelled task in a Completed section (the completed queries admit cancelled
/// tasks) read as a finished one with a different glyph — struck and dimmed exactly like done work,
/// with only the grey `xmark.circle.fill` to tell them apart. No input constraint separates the two
/// rows ([[T-8201]]), so the word is drawn by this one view, and only its metrics are per-row: the
/// Mac row's chip ramp, or the touch row's.
///
/// The word is `TaskStatus.cancelled.label`, the status vocabulary the inspector, search and the
/// list editor already read, rather than a third literal.
struct CadenceTaskCancelledChip: View {
    /// Type size and plate geometry — the only things the two rows differ in. `nonisolated`, as
    /// `CadenceTaskRowMetrics` is, so the macOS-built test target can compare it.
    nonisolated struct Metrics: Equatable, Sendable {
        let fontSize: CGFloat
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        /// A plate floor, for a strip whose neighbours are fixed-height plates (the touch row's
        /// 30pt chips), so the line reads level. `nil` lets the padding decide, as the Mac row's
        /// single fixed-height `HStack` wants.
        var minHeight: CGFloat? = nil

        /// `MacTaskRow`: the row's secondary type size at `CadenceTaskChipPadding.desktop*`, the
        /// figures its do-date and due-date pills read (T-597, T-617).
        static let desktop = Metrics(
            fontSize: CadenceTaskRowMetrics.desktop.secondaryFontSize,
            horizontalPadding: CadenceTaskChipPadding.desktopHorizontal,
            verticalPadding: CadenceTaskChipPadding.desktopVertical
        )
    }

    static var label: String { TaskStatus.cancelled.label }

    let metrics: Metrics

    var body: some View {
        Text(Self.label)
            .cadenceFont(.controlLabel, base: metrics.fontSize, weight: .semibold)
            .foregroundStyle(Theme.dim)
            .lineLimit(1)
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, metrics.verticalPadding)
            .frame(minHeight: metrics.minHeight)
            .background(Theme.dim.opacity(0.14))
            .clipShape(Capsule())
            .fixedSize()
    }
}
