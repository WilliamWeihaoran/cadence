#if os(macOS)
import SwiftUI

/// Settings → Account & Sync: whether this Mac's data is actually reaching the user's other
/// devices, and why not when it is not.
///
/// **What was missing here, and what was not.** Both root views already show
/// `cadenceStartupIssueBanner`, so the *store* half — a recovery store, an in-memory store, a
/// failed maintenance save — has been surfaced on macOS all along. What had no macOS surface at
/// all was the *account* half: signed out of iCloud, or restricted by policy. `CKAccountStatus`
/// was read nowhere in the macOS app, and `SettingsCategory` had no `.sync` case to hang it on,
/// while `CadenceSettingsCategoryKind.sync` — the shared case iOS files under "System" — already
/// existed. So this is macOS offering a category that was already defined rather than a new one.
///
/// The verdict is **not** computed here. `CadenceSyncHealth.resolve` folds the two halves together
/// and lets the store win, because an available account is necessary for sync and not sufficient:
/// a store opened with `cloudKitDatabase: .none` syncs nothing however healthy the account is.
/// Reading `CKAccountStatus` on its own is exactly the bug iOS Settings shipped — a green
/// `checkmark.icloud` over a store that could not sync — so this file must keep going through
/// `resolve` rather than switching on the account itself.
struct SettingsSyncSection: View {
    let probe: CadenceCloudAccountProbe

    /// The page's **one** call to `resolve`, static so the settings rail's status badge can read
    /// the same verdict this card draws without a second one. Two `resolve` calls on one screen
    /// would be two chances for the badge and the card to disagree about whether sync works, which
    /// is the disagreement this whole type exists to have ended.
    static func health(for account: CadenceCloudAccountState) -> CadenceSyncHealth {
        CadenceSyncHealth.resolve(
            startupIssue: PersistenceController.startupIssue,
            account: account
        )
    }

    private var health: CadenceSyncHealth {
        Self.health(for: probe.state)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            statusCard
        }
    }

    private var statusCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: health.iconName)
                        .foregroundStyle(health.tone.tint)
                        .font(.system(size: 14))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(health.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text(health.detail)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    if probe.isChecking {
                        ProgressView()
                            .controlSize(.small)
                    }

                    SettingsActionButton(tone: .tinted(Theme.blue), action: probe.refresh) {
                        Text("Check iCloud Status")
                    }
                    .disabled(probe.isChecking)
                }

                if let lastChecked = probe.lastChecked {
                    Text("Last checked \(lastChecked.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                }
            }
        }
    }
}
#endif
