import SwiftUI

/// The copy both Appearance screens read, so the two cannot say different things about one setting.
///
/// The heading is `Accents` and not `Theme`: what is selectable is six hues, and a screen that
/// says "Theme" promises the near-black chrome moves too. The note under the rows says what does
/// *not* change, because that is the question a user asks before touching a colour setting.
enum CadenceAccentPalettePresentation {
    static let sectionTitle = "Accents"
    static let note = """
        Backgrounds, surfaces, borders and text do not change — Cadence stays dark. \
        Colours you have already chosen for a list, tag, habit or section keep the exact \
        colour you gave them.
        """

    /// Reads out what a row's swatches show, for VoiceOver. The six are the *jobs*, in the order
    /// the strip draws them, rather than six colour names a screen reader cannot verify.
    static func accessibilityLabel(for palette: CadenceAccentPalette) -> String {
        "\(palette.name). \(palette.detail)"
    }
}

/// The accent picker, whole — every palette as a row, with the active one marked.
///
/// **One view, both platforms.** macOS and iOS wrap it in their own settings card and nothing
/// else; the rows, the swatches, the selected state and the copy are shared, because two
/// hand-written pickers over one list is the near-copy this repo keeps having to delete. The only
/// per-platform value is the row's minimum height — iOS needs a 44pt tap target and the Mac does
/// not — and it is a parameter rather than a fork.
struct CadenceAccentPalettePicker: View {
    var minimumRowHeight: CGFloat = 0

    /// Read through the shared selection rather than a `@Binding` from the settings screen: the
    /// selection is process-wide state that `Theme` also reads, so a second copy held in a view
    /// would be a second answer to "which palette is active".
    @State private var selection = CadenceAccentPaletteSelection.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(CadenceAccentPalette.all) { palette in
                CadenceAccentPaletteRow(
                    palette: palette,
                    isSelected: palette == selection.palette,
                    minimumHeight: minimumRowHeight,
                    action: { selection.select(palette) }
                )
            }

            Text(CadenceAccentPalettePresentation.note)
                .font(.system(size: 11))
                .foregroundStyle(Theme.subdued)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }
}

/// One palette: its name, what it is, its six hues, and whether it is the active one.
struct CadenceAccentPaletteRow: View {
    let palette: CadenceAccentPalette
    let isSelected: Bool
    var minimumHeight: CGFloat = 0
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(palette.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(isSelected ? Theme.blue : Theme.dim)
                }

                Text(palette.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                CadenceAccentSwatchStrip(hexes: palette.swatchHexes)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: minimumHeight)
            // One layer at one radius: selection and hover share this background rather than
            // stacking a selected fill under a hover fill at two different corner radii.
            .background(rowBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(CadenceAccentPalettePresentation.accessibilityLabel(for: palette))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var rowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
        if isSelected {
            shape
                .fill(Theme.surfaceHighlight)
                .overlay(shape.strokeBorder(Theme.blue.opacity(0.35)))
        } else if isHovered {
            shape.fill(Theme.surfaceHover)
        } else {
            shape.fill(Color.clear)
        }
    }
}

/// The six hues of one palette, warm through cool.
///
/// Drawn from the palette's *hex strings* rather than from `Theme.blue` and friends, because a row
/// has to show the set it offers and not the set currently in force — reading `Theme` here would
/// draw three identical rows.
struct CadenceAccentSwatchStrip: View {
    let hexes: [String]
    var diameter: CGFloat = 16

    var body: some View {
        HStack(spacing: 6) {
            ForEach(hexes, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: diameter, height: diameter)
                    .overlay(Circle().strokeBorder(Theme.onColorBorder))
            }
        }
        .accessibilityHidden(true)
    }
}
