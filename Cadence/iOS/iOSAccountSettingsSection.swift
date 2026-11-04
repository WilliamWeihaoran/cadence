#if os(iOS)
import SwiftUI

/// Settings → Account on iPhone and iPad: Sign in with Apple, Sign Out and Delete Account
/// ([[T-8736]], owner decision 2026-10-31, option (a)).
///
/// The Mac's `SettingsAccountSection` was the only account surface, behind a `desktopOnly` entry
/// whose "entitlement-gated, macOS-only today" reason was stale: `Cadence-iOS.entitlements`
/// already declared `com.apple.developer.applesignin`, and the gap was `AppleAccountManager` being
/// `#if os(macOS)`. App Store rule 5.1.1(v) asks for in-app deletion wherever an account can be
/// created, so the delete route arrives with the sign-in rather than after it.
///
/// Every word is `CadenceAccountSettingsCopy`'s, read by the Mac card too. Two things differ, each
/// for a stated reason: the actions stack under the copy, the mobile settings idiom for a
/// finger-sized button on a narrow row (`iOSRemindersSettingsSection` records the same choice),
/// and there is no entitlement row, because the iOS SDK has no `SecTask` to read one with
/// (`AppleSignInEntitlementStatus.current()`).
///
/// **Delete Account… deletes nothing here.** It opens Data Safety, where
/// `iOSDataResetSettingsSection` runs the one shared reset behind its typed-phrase gate — and that
/// reset clears this profile (`PrivacyDataResetService.clearAppleAccountProfile`). The Mac's button
/// routes to its Data Safety pane the same way.
///
/// One view for both size classes: iPhone and iPad differ in the width this is handed.
struct iOSAccountSettingsSection: View {
    let appleAccountManager: AppleAccountManager
    let onDeleteAccount: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CadenceSettingsSectionLabel(text: CadenceAccountSettingsCopy.accountTitle)

            iOSSettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: iOSSettingsMetrics.glyphLabelSpacing) {
                        iOSIconTile(
                            systemImage: "person.crop.circle.fill",
                            color: appleAccountManager.isSignedIn ? Theme.green : Theme.dim,
                            size: 34,
                            iconSize: 16
                        )

                        identity

                        Spacer(minLength: 0)
                    }

                    actions

                    iOSRowDivider()

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(CadenceAccountSettingsCopy.credentialStatusTitle)
                            .cadenceFont(.metadata, base: 11, weight: .semibold)
                            .foregroundStyle(Theme.muted)
                        Spacer(minLength: 0)
                        Text(appleAccountManager.credentialStatus.title)
                            .cadenceFont(.metadata, base: 11, weight: .semibold)
                            .foregroundStyle(appleAccountManager.credentialStatus == .authorized ? Theme.green : Theme.dim)
                    }
                }
            }
        }
        .onAppear {
            appleAccountManager.refreshCredentialState()
        }
    }

    @ViewBuilder
    private var identity: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let profile = appleAccountManager.profile {
                Text(profile.displayName)
                    .cadenceFont(.rowTitle, base: 15, weight: .semibold)
                    .foregroundStyle(Theme.text)
                if !profile.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(profile.email)
                        .cadenceFont(.metadata, base: 12, weight: .regular)
                        .foregroundStyle(Theme.subdued)
                }
                Text(CadenceAccountSettingsCopy.signedInLabel(profile.signedInAt))
                    .cadenceFont(.metadata, base: 11, weight: .regular)
                    .foregroundStyle(Theme.muted)
            } else {
                Text(CadenceAccountSettingsCopy.accountTitle)
                    .cadenceFont(.rowTitle, base: 15, weight: .semibold)
                    .foregroundStyle(Theme.text)
                Text(CadenceAccountSettingsCopy.signedOutDetail)
                    .cadenceFont(.metadata, base: 12, weight: .regular)
                    .foregroundStyle(Theme.subdued)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let statusMessage = appleAccountManager.statusMessage {
                Text(statusMessage)
                    .cadenceFont(.metadata, base: 11, weight: .regular)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if appleAccountManager.isSignedIn {
            HStack(spacing: 10) {
                iOSActionButton(
                    title: CadenceAccountSettingsCopy.signOutTitle,
                    role: .destructive,
                    size: .compact,
                    action: { appleAccountManager.signOut() }
                )
                iOSActionButton(
                    title: CadenceAccountSettingsCopy.deleteAccountTitle,
                    role: .primary,
                    size: .compact,
                    tint: Theme.red,
                    action: onDeleteAccount
                )
            }
        } else {
            Button {
                appleAccountManager.signIn()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "apple.logo")
                        .cadenceFont(.metadata, base: 13, weight: .semibold)
                    Text(CadenceAccountSettingsCopy.signInTitle(isAuthorizing: appleAccountManager.isAuthorizing))
                        .cadenceFont(.metadata, base: 13, weight: .semibold)
                }
                // The Mac card's reason, unchanged: Sign in with Apple is a brand-locked
                // black-fill/white-label pair, so the ink is not the app's to solve.
                .foregroundStyle(Theme.onColor)
                .padding(.horizontal, 14)
                .frame(minHeight: iOSSettingsMetrics.minimumTapTarget)
                .background(appleAccountManager.isAuthorizing ? Theme.dim : Theme.appleSignInFill)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.iosPressable)
            .disabled(appleAccountManager.isAuthorizing)
        }
    }
}
#endif
