#if os(iOS)
import SwiftData
import SwiftUI

/// Shared 13pt outline completion circle used by task rows across iOS: transparent center
/// with a 1.6pt border in the row's tint color while pending, solid green fill + white
/// checkmark when done (priority/tint color drops once a task is complete).
struct iOSTaskCompletionCircle: View {
    let isDone: Bool
    let tint: Color
    var diameter: CGFloat = 13

    var body: some View {
        ZStack {
            Circle()
                .fill(isDone ? Theme.doneFill : Color.clear)
            if !isDone {
                Circle()
                    .stroke(tint, lineWidth: 1.6)
            }
            if isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: diameter * 0.6, weight: .bold))
                    .foregroundStyle(Theme.onColor)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

struct iOSFeatureListPane<Content: View>: View {
    let eyebrow: String
    let title: String
    let count: Int
    let emptyTitle: String
    let emptySubtitle: String
    let emptyIcon: String
    var actionTitle: String? = nil
    var actionSystemImage = "plus"
    var action: (() -> Void)? = nil
    /// Set on iPhone, where this pane is a pushed screen with its navigation bar hidden. See
    /// `iOSHidesCompactNavigationBar()`.
    var onBack: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSPanelHeader(eyebrow: eyebrow, title: title, count: count, onBack: onBack)
            Divider().background(Theme.borderSubtle)

            if let actionTitle, let action {
                // `.borderedProminent` renders the OS's own capsule at the OS's own height; this is
                // the same primary treatment every other Cadence button uses, at 48pt.
                iOSActionButton(
                    title: actionTitle,
                    systemImage: actionSystemImage,
                    role: .primary,
                    fullWidth: true,
                    action: action
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Divider().background(Theme.borderSubtle)
            }

            if count == 0 {
                iOSEmptyPanel(systemImage: emptyIcon, title: emptyTitle, subtitle: emptySubtitle)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        content()
                    }
                    .padding(14)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(minWidth: 300, idealWidth: 360)
        .background(Theme.surface)
    }
}

struct iOSCompactPageHeader: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let eyebrow: String
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var color: Color = Theme.blue
    /// Trailing count badge, same shape and job as `iOSPanelHeader`'s.
    var count: Int? = nil
    /// Set on a pushed compact screen whose navigation bar is hidden, so the back control sits on
    /// this row instead of on one of its own above it. See `iOSHidesCompactNavigationBar()`.
    var onBack: (() -> Void)? = nil

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    var body: some View {
        HStack(alignment: .center, spacing: isCompact ? 10 : 12) {
            if let onBack {
                iOSHeaderBackButton(action: onBack)
                    .padding(.leading, -8)
            }

            if let systemImage {
                iOSIconTile(
                    systemImage: systemImage,
                    color: color,
                    size: isCompact ? 32 : 36,
                    iconSize: isCompact ? 15 : 16,
                    fillOpacity: 0.13
                )
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .textCase(.uppercase)
                    .kerning(0.8)
                Text(title)
                    .font(.system(size: isCompact ? 26 : 30, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: isCompact ? 12 : 13, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            if let count {
                Text("\(count)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.blue)
                    .monospacedDigit()
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Theme.blue.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct iOSCompactPanelCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
            .shadow(color: Theme.cardElevationShadow, radius: 16, x: 0, y: 8)
    }
}

extension View {
    func iOSCompactPanelCard() -> some View {
        modifier(iOSCompactPanelCardModifier())
    }
}

struct iOSFeatureSummaryRow: View {
    let title: String
    let subtitle: String
    var detail: String? = nil
    let icon: String
    let color: Color
    /// Overrides the trailing value's colour. It follows `color` by default, which is right where
    /// `color` is a calendar's or a list's own `colorHex`. The More tab passes `Theme.dim` for
    /// `color` — its glyphs are navigation chrome — and a value rendered in `dim` would be the
    /// quietest thing in a row whose whole point is the number.
    var detailTint: Color? = nil
    var isSelected = false

    var body: some View {
        HStack(spacing: 10) {
            iOSIconTile(systemImage: icon, color: color, size: 30, iconSize: 14, fillOpacity: 0.11, bordered: false)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(subtitle.isEmpty ? "No context" : subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.subdued)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(detailTint ?? color)
                    .lineLimit(1)
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isSelected ? color.opacity(0.14) : Theme.surfaceElevated.opacity(0.36))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .shadow(color: Theme.cardElevationShadow, radius: 6, x: 0, y: 2)
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: 3)
                    .padding(.vertical, 8)
            }
        }
    }
}


struct iOSMetricTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.subdued)
                .textCase(.uppercase)
                .kerning(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cadenceCard(background: Theme.surfaceElevated.opacity(0.55), cornerRadius: Theme.radiusCard, shadowRadius: 8, shadowY: 3)
    }
}

struct iOSFeatureEmptyDetail: View {
    let systemImage: String
    let title: String

    var body: some View {
        iOSEmptyPanel(
            systemImage: systemImage,
            title: title,
            subtitle: "Select an item from the list."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }
}

struct iOSInlineErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .padding(.top, 1)

            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 24, height: 24)
                    .iOSExpandedHitArea(10)
            }
            .buttonStyle(.iosPressable)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.amber.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                .strokeBorder(Theme.amber.opacity(0.24), lineWidth: 1)
        }
    }
}

#endif
