import SwiftUI

nonisolated enum CadenceTodayRolloverMetrics {
    static func iconSide(at size: DynamicTypeSize, scaling: CadenceTypographyScaling) -> CGFloat {
        max(
            CadenceTypeScale.height(22, holding: .controlLabel, textBase: 14, at: size, scaling: scaling),
            CadenceTypeScale.lineHeight(.controlLabel, base: 14, at: size, scaling: scaling) + 4
        )
    }

    static func dotSide(at size: DynamicTypeSize, scaling: CadenceTypographyScaling) -> CGFloat {
        6 * CadenceTypeScale.multiplier(.metadata, at: size, scaling: scaling)
    }
}

/// How the rollover banner meets the surface under it. The *content* — icon, copy, button, rows —
/// is the same on both platforms and is not parameterised; only the container is.
enum CadenceTodayRolloverBannerStyle {
    /// macOS's Today task column: a full-bleed band with a hairline under it, flush with the
    /// section headings above and below.
    case panelBand
    /// iOS's Today: a card, at the shared card radius, on the page's own background.
    case card
}

/// Today's "leftover tasks are rolling over" notice — one view, both platforms.
///
/// It was `TasksPanelRolloverNoticeSectionView` under `macOS/Views/` (T-195). Nothing in it was
/// AppKit-shaped: it is a header row, a button, and a list of dot-title-list rows. Bringing it here
/// rather than hand-writing an iOS twin is the same call `CompactTagStrip` records the cost of not
/// making — that one was written out by hand three times before it was shared.
///
/// The copy is `CadenceTodayRolloverSupport`'s, so the two platforms cannot describe the same
/// offer differently.
struct CadenceTodayRolloverBanner: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling
    let tasks: [AppTask]
    var style: CadenceTodayRolloverBannerStyle = .card
    /// `CadenceTodayRolloverSupport.rollFailureNotice` when the last roll was refused, `nil`
    /// otherwise (T-635).
    ///
    /// It belongs here rather than on either host for the reason the offer itself does: a refused
    /// roll leaves the banner **on screen** — the dismissal is written only on the success path
    /// now — so the sentence goes under the copy that made the offer, in the one place both
    /// platforms already share. A notice owned by one host would be missing from the other, which
    /// is precisely the macOS-only shape T-195 spent a ticket undoing.
    let failureNotice: String?
    let onRollOver: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            taskRows
            failureRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.surface)
        .modifier(CadenceTodayRolloverBannerContainer(style: style))
    }

    private var wraps: Bool {
        scaling == .enabled && CadenceTypeScale.isAccessibilitySize(dynamicTypeSize)
    }

    @ViewBuilder
    private var headerRow: some View {
        if wraps {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    headerIcon
                    headerCopy
                }
                rollOverButton
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                headerIcon
                headerCopy
                Spacer(minLength: 8)
                rollOverButton
            }
        }
    }

    private var headerIcon: some View {
        let side = CadenceTodayRolloverMetrics.iconSide(at: dynamicTypeSize, scaling: scaling)
        return Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
            .cadenceFont(.controlLabel, base: 14, weight: .semibold)
            .foregroundStyle(Theme.amber)
            .frame(width: side, height: side)
            .background(Theme.amber.opacity(0.16))
            .clipShape(Circle())
    }

    private var headerCopy: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(CadenceTodayRolloverSupport.title)
                .cadenceFont(.controlLabel)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(CadenceTodayRolloverSupport.message)
                .cadenceFont(.metadata, base: 11, weight: .regular)
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var rollOverButton: some View {
        // Keep padding inside the label so the whole visible button remains tappable.
        Button(action: onRollOver) {
            Text(CadenceTodayRolloverSupport.confirmActionTitle)
                .cadenceFont(.metadata, base: 11, weight: .semibold)
                .foregroundStyle(Theme.onColor(for: Theme.blue))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(minHeight: wraps ? 44 : nil)
                .background(Theme.blue)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact))
                .contentShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact))
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: !wraps, vertical: true)
    }

    /// The refusal, under the rows it failed to move. Nothing at all when the last roll landed —
    /// `@ViewBuilder` rather than an `if` around the whole `VStack`, so the banner's spacing is
    /// unchanged in the ordinary case.
    @ViewBuilder
    private var failureRow: some View {
        if let failureNotice {
            Text(failureNotice)
                .cadenceFont(.metadata, base: 11, weight: .regular)
                .foregroundStyle(Theme.red)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
        }
    }

    /// Plain rows, like every other task row in the panel. Each of these used to sit on a
    /// `Theme.amber.opacity(0.12)` wash, so a banner that already says "rolling over to today" said
    /// it again once per task. The dot keeps the list's own `colorHex`.
    private var taskRows: some View {
        VStack(spacing: 4) {
            ForEach(tasks) { task in
                taskRow(task)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder
    private func taskRow(_ task: AppTask) -> some View {
        if wraps {
            VStack(alignment: .leading, spacing: 4) {
                taskTitle(task)
                HStack(spacing: 8) {
                    taskDot(task)
                    containerName(task)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 8) {
                taskDot(task)
                taskTitle(task)
                Spacer()
                containerName(task)
            }
        }
    }

    private func taskDot(_ task: AppTask) -> some View {
        let side = CadenceTodayRolloverMetrics.dotSide(at: dynamicTypeSize, scaling: scaling)
        return Circle().fill(Color(hex: task.containerColor)).frame(width: side, height: side)
    }

    private func taskTitle(_ task: AppTask) -> some View {
        Text(TaskTitleSupport.displayTitle(task.title, fallback: TaskTitleSupport.defaultCompactDisplayTitle))
            .cadenceFont(.metadata)
            .foregroundStyle(Theme.text)
            .lineLimit(wraps ? nil : 1)
            .fixedSize(horizontal: false, vertical: wraps)
    }

    @ViewBuilder
    private func containerName(_ task: AppTask) -> some View {
        if !task.containerName.isEmpty {
            Text(task.containerName)
                .cadenceFont(.metadata, base: 10, weight: .regular)
                .foregroundStyle(Theme.dim)
                .lineLimit(wraps ? nil : 1)
                .fixedSize(horizontal: false, vertical: wraps)
        }
    }
}

/// The one thing that differs between the platforms, isolated so the rest cannot follow it.
private struct CadenceTodayRolloverBannerContainer: ViewModifier {
    let style: CadenceTodayRolloverBannerStyle

    func body(content: Content) -> some View {
        switch style {
        case .panelBand:
            content
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.borderSubtle.opacity(0.6)).frame(height: 0.5)
                }
        case .card:
            content
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                        .strokeBorder(Theme.borderSubtle, lineWidth: 1)
                }
        }
    }
}
