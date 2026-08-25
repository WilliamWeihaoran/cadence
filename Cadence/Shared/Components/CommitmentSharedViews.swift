#if os(macOS)
import SwiftUI

/// A `.page`-role `DesktopPageHeader` with a controls row under it. Goals and Habits are the two
/// callers; the search field and status filter below the title are what earns the second row.
///
/// It used to spell its own title, its own gutter and its own header padding, plus a `titleSize`
/// parameter no caller had ever passed. The padding lives on this stack rather than on the header
/// because the two rows are one band — hence `padded: false, background: nil` on the header.
struct CommitmentPageHeader<Accessory: View, Controls: View>: View {
    let title: String
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let controls: Controls

    private var metrics: CadencePageHeaderMetrics {
        CadencePageHeaderMetrics.metrics(role: .page, surface: .desktop)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DesktopPageHeader(
                role: .page,
                title: title,
                padded: false,
                background: nil
            ) {
                accessory
            }

            controls
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.top, metrics.topPadding)
        .padding(.bottom, metrics.bottomPadding)
        .background(Theme.surface)
    }
}

struct CommitmentIconTile: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 32
    /// Defaulted from the one glyph-to-tile ratio rather than restated, so a caller that resizes
    /// the tile and forgets the glyph gets a proportional tile instead of a third ratio. See
    /// `CadencePageHeaderMetrics.iconSize`.
    var iconSize: CGFloat? = nil
    /// Defaults to the shared tile radius rather than `min(12, size * 0.28)` — see
    /// `CadencePageHeaderMetrics.tileCornerRadius` for the renders that settled it.
    var cornerRadius: CGFloat = CadencePageHeaderMetrics.tileCornerRadius
    var fillOpacity: Double = CadencePageHeaderMetrics.tileFillOpacity
    /// Matches `iOSIconTile`. This tile used to draw no border at all, which made the *same* habit
    /// tile — `HabitIconTile` picks between the two platform tiles and nothing else — a plate on an
    /// iPad and a soft wash on a Mac at within 4pt of the same size. See
    /// `CadencePageHeaderMetrics.tileBorderOpacity`.
    var bordered = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: CadencePageHeaderMetrics.tileCornerStyle)

        return Image(systemName: systemImage)
            .font(.system(size: iconSize ?? size * CadencePageHeaderMetrics.tileGlyphRatio, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(shape.fill(color.opacity(fillOpacity)))
            .overlay {
                if bordered {
                    shape.strokeBorder(color.opacity(CadencePageHeaderMetrics.tileBorderOpacity), lineWidth: 1)
                }
            }
    }
}

struct CommitmentSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.dim)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 11)
        .frame(minHeight: CadenceDesktopMetrics.regularControlHeight)
        .background(Theme.surfaceElevated.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: CadenceDesktopMetrics.controlCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CadenceDesktopMetrics.controlCornerRadius, style: .continuous)
                .stroke(Theme.borderSubtle.opacity(0.9), lineWidth: 1)
        }
        .frame(maxWidth: .infinity)
    }
}

struct CommitmentFilterBar<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    var minWidth: CGFloat = 52
    var spacing: CGFloat = 6
    var tint: Color = Theme.blue
    let label: (Item) -> String

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(items, id: \.self) { item in
                CadencePillButton(
                    title: label(item),
                    isSelected: selection == item,
                    minWidth: minWidth,
                    tint: tint
                ) {
                    selection = item
                }
            }
        }
        .padding(3)
        .background(Theme.surfaceElevated.opacity(0.46))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.borderSubtle.opacity(0.72), lineWidth: 1)
        }
    }
}

struct CommitmentGroupHeader: View {
    let title: String
    let icon: String
    let color: Color
    let trailingText: String
    var trailingTint: Color? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)

            // Semibold, from the shared eyebrow — this was the app's only `.bold` at the eyebrow
            // size and tint, and nothing chose it. The count beside it keeps `.bold`, which is the
            // same split `CadenceTaskGroupHeading` draws: weight is what demotes the number from
            // the label, so the label may not borrow it.
            SectionEyebrowLabel(text: title)
                .lineLimit(1)

            Spacer()

            Text(trailingText)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(trailingTint ?? Theme.text.opacity(0.75))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.surfaceElevated)
                .clipShape(Capsule())
        }
    }
}

/// Shared small metadata chip used across kanban cards, goal/habit detail rows,
/// planning cards, and timeline bundle inspectors. Prefer this over a local
/// one-off chip struct so tint/padding/shape stay consistent app-wide.
struct CommitmentMetaChip: View {
    let label: String
    let color: Color
    var systemImage: String? = nil
    /// Filled/high-contrast treatment for a chip that should read as the primary metric (e.g. a time range).
    var prominent: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(prominent ? Theme.bg : color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(prominent ? color : color.opacity(0.12))
        .clipShape(Capsule())
    }
}

// The one-line "nothing here" inside a section is `CadenceInlineEmpty` in
// `Shared/Components/CadenceInlineEmpty.swift`, and unlike this file it is not walled behind
// `#if os(macOS)`. `CommitmentInlineEmpty` was declared here — inside `Shared/`, and therefore
// invisible to iOS, which wrote `iOSInlineEmpty` instead.

struct CommitmentEmptyDetail: View {
    let icon: String
    let title: String
    let subtitle: String
    var background: Color = Theme.surface

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(Theme.dim)

            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)

            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
    }
}
#endif
