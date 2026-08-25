#if os(macOS)
import AppKit
import SwiftUI

/// Settings → About: which build of Cadence this is, and the two public pages about it.
///
/// The desktop had nowhere to read a version number at all — the figures were computed on
/// `iOSSettingsView` and rendered by `iOSAboutSettingsSection`, and `SettingsCategory` had no
/// `.about` case to hang a macOS screen on. Both the strings and the row come from `Shared`
/// (`CadenceAppBuildIdentity`, `CadenceSettingsInfoRow`), so this is the same About screen and
/// not a second opinion about it.
///
/// **The Privacy Policy and Support links live here, and this file used to argue the opposite.**
/// It said they belonged under Data Safety "beside the privacy paragraph and the delete control
/// they belong with", and explained iOS filing them under About with "because iOS's Data Safety
/// screen does not carry them" — which describes the accident rather than justifying it. iOS's
/// Data Safety screen did not carry them because at the time it drew read-only count tiles and had
/// no delete route at all. Neither link is a data-safety control: `Support` is a help page with no
/// relationship to deletion whatsoever, and the pair only ever sat on that screen because the
/// privacy *paragraph* landed there and the buttons were bolted onto the same card. Filing them a
/// tab-stop from a button that irreversibly erases everything makes a harmless link read as one
/// more thing that might delete something — the same argument that keeps `.about` out of the
/// Account & Safety rail group. The paragraph stays on Data Safety, because what happens to your
/// data *is* that screen's subject.
struct SettingsAboutSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSectionLabel(text: "Build")
            SettingsCard {
                VStack(spacing: 0) {
                    CadenceSettingsInfoRow(title: "Version", value: CadenceAppBuildIdentity.version)
                    CadenceRowDivider()
                    CadenceSettingsInfoRow(title: "Build", value: CadenceAppBuildIdentity.build)
                    CadenceRowDivider()
                    CadenceSettingsInfoRow(title: "Bundle ID", value: CadenceAppBuildIdentity.bundleID)
                }
            }

            SettingsSectionLabel(text: CadenceAppReferenceLink.sectionTitle)
            SettingsCard {
                HStack(spacing: 10) {
                    ForEach(CadenceAppReferenceLink.all) { link in
                        SettingsAboutLinkButton(link: link)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

/// One link button, in the tone every other action button on a macOS settings card uses.
///
/// The chrome is the one thing here that is deliberately per-platform: `SettingsActionButton` is
/// what the dozen other buttons across these panes look like, and iOS's needs a 44pt tap target.
/// What is shared is the part that could drift — the link itself, from
/// `CadenceAppReferenceLink.all`.
private struct SettingsAboutLinkButton: View {
    let link: CadenceAppReferenceLink

    var body: some View {
        if let url = link.url {
            SettingsActionButton(tone: .tinted(Theme.blue), action: { NSWorkspace.shared.open(url) }) {
                Label(link.title, systemImage: link.systemImage)
            }
        } else {
            #if DEBUG
            VStack(alignment: .leading, spacing: 4) {
                Label(link.title, systemImage: link.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                Text(link.missingMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.dim.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            #endif
        }
    }
}
#endif
