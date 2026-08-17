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
    var minHeight: CGFloat = CadenceValueTileMetrics.minHeight

    var body: some View {
        VStack(alignment: .leading, spacing: CadenceValueTileMetrics.captionValueSpacing) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(glyphColor)
                }

                SectionEyebrowLabel(text: caption)

                Spacer(minLength: 4)

                if showsDisclosure {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                }
            }

            Text(value)
                .font(.system(size: CadenceValueTileMetrics.valueFontSize, weight: .semibold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, CadenceValueTileMetrics.horizontalPadding)
        .padding(.vertical, CadenceValueTileMetrics.verticalPadding)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
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

    /// 56pt: 10 + a 12pt eyebrow line + 3 + an 18pt value line + 10, rounded up to leave the value
    /// room to grow one point under a larger dynamic type setting before the tile has to.
    static let minHeight: CGFloat = 56
}
