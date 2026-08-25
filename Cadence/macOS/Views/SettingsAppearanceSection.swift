#if os(macOS)
import SwiftUI

/// Settings → Appearance: which of the six accents the app draws with.
///
/// The screen is thin on purpose. Every row, swatch and word inside the card comes from
/// `CadenceAccentPalettePicker` in `Shared/Components/`, which iOS's Appearance screen renders
/// too, so the two platforms cannot end up offering different sets or describing the setting
/// differently. What is left here is the card chrome, which is the one half that is genuinely
/// per-platform.
///
/// Filed under **Interface** beside Navigation and Sidebar rather than in the "App" group of one
/// that holds About: this configures how the app looks, which is what that group is for.
struct SettingsAppearanceSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSectionLabel(text: CadenceAccentPalettePresentation.sectionTitle)
            SettingsCard {
                CadenceAccentPalettePicker()
            }
        }
    }
}
#endif
