#if os(macOS)
import SwiftUI

/// Settings → About: which build of Cadence this is.
///
/// The desktop had nowhere to read a version number at all — the figures were computed on
/// `iOSSettingsView` and rendered by `iOSAboutSettingsSection`, and `SettingsCategory` had no
/// `.about` case to hang a macOS screen on. Both the strings and the row come from `Shared`
/// (`CadenceAppBuildIdentity`, `CadenceSettingsInfoRow`), so this is the same About screen and
/// not a second opinion about it.
///
/// **No Privacy Policy / Support buttons here on purpose.** macOS already offers both, in
/// Settings → Data Safety, beside the privacy paragraph and the delete control they belong with.
/// A second copy on this screen would be two affordances for one link — iOS files them under
/// About because iOS's Data Safety screen does not carry them.
struct SettingsAboutSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSectionLabel(text: "Build")
            SettingsCard {
                VStack(spacing: 0) {
                    CadenceSettingsInfoRow(title: "Version", value: CadenceAppBuildIdentity.version)
                    Divider().background(Theme.borderSubtle)
                    CadenceSettingsInfoRow(title: "Build", value: CadenceAppBuildIdentity.build)
                    Divider().background(Theme.borderSubtle)
                    CadenceSettingsInfoRow(title: "Bundle ID", value: CadenceAppBuildIdentity.bundleID)
                }
            }
        }
    }
}
#endif
