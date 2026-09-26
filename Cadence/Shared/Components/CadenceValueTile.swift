import SwiftUI

/// A field stated as a **tile**: a small uppercase caption with the field's current value beneath it.
///
/// This is the vertical spelling of the labelled row (`iOSEditorFieldRow` on iOS,
/// `TaskInspectorFieldRow` on macOS) — same job, same vocabulary, different axis. A row puts the
/// label and the value on one line and so costs a full line of height per field; a tile stacks them,
/// which is half as wide and lets two fields share a line. On a sheet whose height is the binding
/// constraint that is the whole trade: four fields in two lines instead of four.
///
/// **Built entirely from existing tokens, deliberately.** `SectionEyebrowLabel` for the caption,
/// `Theme.surface` for the plate and `Theme.radiusCard` for its corner — the same pair the sheet's
/// title and notes fields already sit on, so a tile reads as another field on the same sheet rather
/// than as a new kind of object. The disclosure glyph is the one `iOSChoiceValueButton` uses. There
/// is no tile-specific radius, fill or shadow to keep in sync with anything.
///
/// It draws no button and owns no state: a caller wraps it in whatever `Button` and press style its
/// platform uses and hangs its own picker off that. That is what keeps it usable outside the sheet
/// it was built for — nothing here knows about tasks.
struct CadenceValueTile: View {
    /// The field's name. Uppercased by `SectionEyebrowLabel`; pass it in sentence case.
    let caption: String
    /// The field's current value, always a real answer — `None` for an unset field rather than a
    /// prompt like "Add a tag". Dimmer `valueColor` is what conveys "unset", so the tile and the
    /// picker it opens can never disagree about what the field says.
    let value: String
    var systemImage: String? = nil
    /// Tint for the glyph only. Use it where the *value* is a colour the user already reads as one
    /// — a list's colour, a priority's — and leave it `Theme.dim` everywhere else.
    var glyphColor: Color = Theme.dim
    var valueColor: Color = Theme.text
    /// Draws the same `chevron.up.chevron.down` an `iOSChoiceValueButton` carries. Turn it off for a
    /// read-only tile, which is then honestly not offering to open anything.
    var showsDisclosure: Bool = true
    /// The floor the tile is drawn at. `nil` means "whatever the text inside currently needs",
    /// which is the only answer that survives an accessibility text size — see
    /// `CadenceValueTileMetrics.minHeight(at:scaling:)`. A caller passing a number is pinning the
    /// tile to that number at every text size and had better know why.
    var minHeight: CGFloat? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling

    var body: some View {
        VStack(alignment: .leading, spacing: CadenceValueTileMetrics.captionValueSpacing) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .cadenceFont(.sectionLabel, base: CadenceValueTileMetrics.captionGlyphSize)
                        .foregroundStyle(glyphColor)
                }

                SectionEyebrowLabel(text: caption)

                Spacer(minLength: 4)

                if showsDisclosure {
                    Image(systemName: "chevron.up.chevron.down")
                        .cadenceFont(.sectionLabel, base: CadenceValueTileMetrics.disclosureGlyphSize)
                        .foregroundStyle(Theme.dim)
                }
            }

            Text(value)
                .cadenceFont(.fieldValue, base: CadenceValueTileMetrics.valueFontSize)
                .foregroundStyle(valueColor)
                // **The shrink-to-fit is dropped at accessibility sizes, not kept "as a safety
                // net".** `minimumScaleFactor` answers a too-long value by making the text smaller,
                // which is the exact opposite of what a reader who turned their text size up asked
                // for; the audit calls it out by name. Below the accessibility sizes it stays,
                // because there it is doing what it was added for — keeping "Tomorrow" on one line
                // in a half-width tile — and the tile is tall enough that nothing is lost.
                .lineLimit(CadenceValueTileMetrics.valueLineLimit(at: dynamicTypeSize, scaling: scaling))
                .minimumScaleFactor(CadenceValueTileMetrics.valueMinimumScaleFactor(at: dynamicTypeSize, scaling: scaling))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, CadenceValueTileMetrics.horizontalPadding)
        .padding(.vertical, CadenceValueTileMetrics.verticalPadding)
        .frame(
            maxWidth: .infinity,
            minHeight: minHeight ?? CadenceValueTileMetrics.minHeight(at: dynamicTypeSize, scaling: scaling),
            alignment: .leading
        )
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// The tile's geometry, in one place so a layout that has to *add tiles up* — a sheet checking it
/// clears a keyboard, say — reads the same numbers the tile draws itself with instead of a second
/// copy that can drift.
///
/// `nonisolated` so tests and off-main layout arithmetic can read it, the same reason
/// `TaskOrdering` is.
nonisolated enum CadenceValueTileMetrics {
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 10
    static let captionValueSpacing: CGFloat = 3
    static let valueFontSize: CGFloat = 15

    /// The two glyphs on the caption line, named because they scale with the eyebrow beside them
    /// and a height computed from that eyebrow has to be able to say so.
    static let captionGlyphSize: CGFloat = 9
    static let disclosureGlyphSize: CGFloat = 8

    /// 56pt: 10 + a 12pt eyebrow line + 3 + an 18pt value line + 10, rounded up to leave the value
    /// room to grow one point under a larger dynamic type setting before the tile has to.
    ///
    /// **That last clause was the whole plan, and one point is not a text size (T-1364).** At
    /// `accessibility5` the caption is set at 31pt and the value at 42, over two lines — about
    /// 161pt of content once the padding is counted, against a tile pinned at 56. A tile that short
    /// does not clip; it *overlaps*, because the value is drawn where the caption already is. So 56
    /// is the floor at the default size and `minHeight(at:scaling:)` is what the tile asks for.
    static let minHeight: CGFloat = 56

    /// The gap between what the two lines need and what the tile reserves, at the default size:
    /// 56 less the 53 of padding, eyebrow, spacing and value. Kept as the headroom term so the
    /// tile stays exactly 56pt tall when nothing has been scaled.
    static let headroom: CGFloat = minHeight - intrinsicHeight(
        at: .large,
        scaling: .fixed
    )

    /// Padding, caption line, gap, value line — what the tile's content actually occupies.
    static func intrinsicHeight(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CGFloat {
        let caption = CadenceTypeScale.lineHeight(.sectionLabel, base: SectionEyebrowLabel.fontSize, at: dynamicTypeSize, scaling: scaling)
        let value = CadenceTypeScale.lineHeight(.fieldValue, base: valueFontSize, at: dynamicTypeSize, scaling: scaling)
        let lines = CGFloat(valueLineLimit(at: dynamicTypeSize, scaling: scaling))
        return 2 * verticalPadding + caption + captionValueSpacing + value * lines
    }

    /// What the tile reserves: its content plus the same headroom the 56 was chosen with.
    static func minHeight(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CGFloat {
        intrinsicHeight(at: dynamicTypeSize, scaling: scaling) + Self.headroom
    }

    /// One line normally; two once the text size is an accessibility setting.
    ///
    /// A half-width tile is about 160pt across. "Tomorrow" fits at 15pt and does not at 42, so the
    /// choice at an accessibility size is between a second line and a truncated answer — and a
    /// truncated answer is the failure this tile was built to fix, since the whole point of it is
    /// that a *seeded* field can be read.
    static func valueLineLimit(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> Int {
        guard scaling == .enabled, CadenceTypeScale.isAccessibilitySize(dynamicTypeSize) else { return 1 }
        return 2
    }

    /// `1` — no shrinking — once the reader has asked for larger text.
    static func valueMinimumScaleFactor(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CGFloat {
        guard scaling == .enabled, CadenceTypeScale.isAccessibilitySize(dynamicTypeSize) else { return 0.8 }
        return 1
    }
}
