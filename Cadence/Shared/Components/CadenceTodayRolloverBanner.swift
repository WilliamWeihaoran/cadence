import SwiftUI

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

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .frame(width: 22, height: 22)
                .background(Theme.amber.opacity(0.16))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(CadenceTodayRolloverSupport.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(CadenceTodayRolloverSupport.message)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            // The pill's padding and fill live *inside* the button label. They used to be applied
            // to the `Button` itself, which leaves the button's hit region at the bare text — the
            // blue ring around "Roll Over" looked pressable and was inert.
            Button(action: onRollOver) {
                Text(CadenceTodayRolloverSupport.confirmActionTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.onColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .contentShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .fixedSize()
        }
    }

    /// The refusal, under the rows it failed to move. Nothing at all when the last roll landed —
    /// `@ViewBuilder` rather than an `if` around the whole `VStack`, so the banner's spacing is
    /// unchanged in the ordinary case.
    @ViewBuilder
    private var failureRow: some View {
        if let failureNotice {
            Text(failureNotice)
                .font(.system(size: 11))
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
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(hex: task.containerColor))
                        .frame(width: 6, height: 6)
                    Text(task.title.isEmpty ? "Untitled" : task.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Spacer()
                    if !task.containerName.isEmpty {
                        Text(task.containerName)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.dim)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
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
