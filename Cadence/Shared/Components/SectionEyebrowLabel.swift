import SwiftUI

/// Small-caps "eyebrow" section label (e.g. STATUS, COLOR, UNASSIGNED) used above
/// filter groups, form fields, and card headers. Consolidates several near-identical
/// one-off label styles into a single consistent size/weight/kerning.
///
/// **It comes in two sizes, and that is a tier rather than drift.** A popover group heading or an
/// inspector well label is legitimately smaller than a page's eyebrow, and T-284 kept that
/// distinction rather than flattening it — flattening would have been a size decision dressed as a
/// refactor. What T-284 removed is the *four kernings* the smaller tier had accumulated across six
/// hand-rolled spellings (0.45, 0.54, 0.6, 0.7 and, twice, none at all). Letterspacing is now
/// derived from the size by one ratio, so the two tiers are one decision and a third size could
/// only ever be added on purpose.
struct SectionEyebrowLabel: View {

    /// Which of the two eyebrow tiers a label belongs to.
    ///
    /// `nonisolated` members throughout for the same reason `fontSize` is: `CadenceEyebrowMetrics`'
    /// readers include nonisolated value types, and a nonisolated static cannot initialise from a
    /// main-actor-isolated one.
    enum Size {
        /// Page and section eyebrows — the default, and what 19 macOS files already draw.
        case standard
        /// Popover group headings and inspector well labels, deliberately one point smaller.
        case compact

        nonisolated var fontSize: CGFloat {
            switch self {
            case .standard: SectionEyebrowLabel.fontSize
            case .compact: SectionEyebrowLabel.compactFontSize
            }
        }

        nonisolated var kerning: CGFloat { fontSize * SectionEyebrowLabel.kerningRatio }

        nonisolated var font: Font { .system(size: fontSize, weight: .semibold) }
    }

    /// The app's one eyebrow size. Exposed because things drawn *beside* an eyebrow have to agree
    /// with it — `CadenceBoardColumnHeaderMetrics.labelSize` and
    /// `CadenceTaskGroupHeadingMetrics.countSize` are both this number, and both were a
    /// hand-typed 10 or 11 before somebody noticed which one they were meant to match.
    /// `nonisolated` because `CadenceTaskGroupHeadingMetrics` is, and a nonisolated value type
    /// cannot read a main-actor-isolated static. A literal, so there is nothing to initialise from.
    nonisolated static let fontSize: CGFloat = 10

    /// The sub-label tier. One point smaller, and only that — every other property of an eyebrow is
    /// shared.
    nonisolated static let compactFontSize: CGFloat = 9

    /// Letterspacing as a fraction of the font size, so the two tiers cannot drift apart.
    ///
    /// `0.08` reproduces the standard tier's long-standing `0.8` at 10pt exactly, and gives the
    /// compact tier `0.72` — which is what the six hand-rolled 9pt labels were each guessing at,
    /// one of them with a comment computing "~0.05em at 9pt" and another "~0.06em at 9pt". A ratio
    /// is the reason there is nothing left to guess.
    nonisolated static let kerningRatio: CGFloat = 0.08

    let text: String
    var size: Size = .standard
    var tint: Color = Theme.dim

    var body: some View {
        Text(text.uppercased())
            .font(size.font)
            .foregroundStyle(tint)
            .kerning(size.kerning)
    }
}
