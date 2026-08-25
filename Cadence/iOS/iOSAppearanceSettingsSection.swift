#if os(iOS)
import SwiftUI

/// Settings → Appearance on iPhone and iPad: which of the six accents the app draws with.
///
/// The same `CadenceAccentPalettePicker` macOS renders, inside iOS's settings card and at iOS's
/// 44pt minimum tap target. iPhone and iPad are one style and differ only in layout, so there is
/// no size-class branch here at all — the card is the same either side.
struct iOSAppearanceSettingsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CadenceSettingsSectionLabel(text: CadenceAccentPalettePresentation.sectionTitle)
            iOSSettingsCard {
                CadenceAccentPalettePicker(
                    minimumRowHeight: iOSSettingsMetrics.minimumTapTarget
                )
            }
        }
    }
}
#endif
