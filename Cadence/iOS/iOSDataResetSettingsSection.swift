#if os(iOS)
import SwiftData
import SwiftUI

/// Settings > Data Safety on iPhone and iPad: the in-app "delete my Cadence data" route.
///
/// **Why this exists.** `docs/privacy.html` and `docs/app-review-notes.md` both promised the user
/// could delete their Cadence account and data from Settings > Account or Settings > Data Safety.
/// On iOS neither route existed: `.account` is `CadenceMobileSettingsLayout.desktopOnly`, and
/// `.dataSafety` drew read-only count tiles. The reset itself was written, tested and sitting
/// behind an `#if os(macOS)` that nothing in it needed — the `RemindersManager` shape exactly.
///
/// The sequence it runs is `PrivacyDataResetService.deleteCadenceDataAndLocalArtifacts`, the same
/// function macOS's pane calls, so "delete my data" cannot come to mean two different things on
/// two platforms. Sign in with Apple is macOS-only, so there is no account profile to clear here
/// and this screen does not claim one.
///
/// One view for both size classes: iPhone and iPad differ in the width this is handed, not in how
/// a card, a sheet or a button inside it looks.
struct iOSDataResetSettingsSection: View {
    /// [[T-5807]]: told once the reset has finished, so `iOSSettingsView` can tell the backup
    /// section on the same page to re-read what the reset deleted — the Mac pane's
    /// `refreshBackups()` after the same call.
    let onDidReset: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(AISettingsManager.self) private var aiSettingsManager
    @State private var isConfirming = false
    @State private var statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // "Delete Account & Data" on macOS, where an account profile exists to delete.
            // Not here.
            CadenceSettingsSectionLabel(text: "Delete Cadence Data")

            iOSSettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: iOSSettingsMetrics.glyphLabelSpacing) {
                        iOSIconTile(
                            systemImage: "person.crop.circle.badge.xmark",
                            color: Theme.red,
                            size: 34,
                            iconSize: 16
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Delete Cadence Data")
                                .cadenceFont(.rowTitle, base: 15, weight: .semibold)
                                .foregroundStyle(Theme.text)

                            // The enumeration used to end here, at five things, which a reader
                            // takes as exhaustive (T-1680 on the Mac, T-1841 here). Since T-1840
                            // the reset also takes the store folders Cadence is not using, and the
                            // clause is `CadenceUnmanagedStoreCopy`'s rather than a second copy of
                            // macOS's, so the two cannot drift into promising different things
                            // about the same reset.
                            Text("Removes every task, list, note, tag, saved link, and retained legacy record Cadence holds in this store, along with local Cadence backups, pending restores, and the saved OpenAI key. \(CadenceUnmanagedStoreCopy.resetDeletesThem)")
                                .cadenceFont(.metadata, base: 12, weight: .regular)
                                .foregroundStyle(Theme.subdued)
                                .fixedSize(horizontal: false, vertical: true)

                            if let statusMessage {
                                Text(statusMessage)
                                    .cadenceFont(.metadata, base: 11, weight: .regular)
                                    .foregroundStyle(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Spacer(minLength: 0)
                    }

                    // This button does not delete anything. It opens the confirmation sheet, and
                    // the destructive control lives only there — the same shape macOS's pane has
                    // since T-575. See `PrivacyDataResetConfirmation`.
                    iOSActionButton(
                        title: "Delete Cadence Data",
                        systemImage: "trash.fill",
                        role: .destructive,
                        size: .compact,
                        action: { isConfirming = true }
                    )
                }
            }
        }
        .sheet(isPresented: $isConfirming) {
            iOSDataResetConfirmationSheet(onConfirm: deleteCadenceData)
        }
    }

    private func deleteCadenceData() {
        // `await`, and therefore a `Task`: the reset does not return until the pending OS
        // notifications for the deleted data are actually cancelled (T-297), so the status
        // message below is written when the sweep is finished rather than when it was started.
        Task {
            do {
                let outcome = try await PrivacyDataResetService.deleteCadenceDataAndLocalArtifacts(
                    in: modelContext,
                    aiSettingsManager: aiSettingsManager
                )
                // `dataOnlyStatusMessage`, not the account one: this screen has already told
                // the reader that Sign in with Apple is macOS-only, and the shared sentence used
                // to contradict that on the way out (T-474).
                statusMessage = outcome.dataOnlyStatusMessage
                onDidReset()
            } catch {
                statusMessage = "Could not delete Cadence data: \(error.localizedDescription)"
            }
        }
    }
}

/// The second and third gates: a modal that enumerates what is about to be lost, and a phrase
/// that has to be typed before the destructive button is live at all.
private struct iOSDataResetConfirmationSheet: View {
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var typedPhrase = ""
    @FocusState private var isPhraseFocused: Bool

    private var isArmed: Bool {
        PrivacyDataResetConfirmation.authorizes(typedPhrase)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    iOSSettingsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: iOSSettingsMetrics.glyphLabelSpacing) {
                                iOSIconTile(
                                    systemImage: "exclamationmark.triangle.fill",
                                    color: Theme.red,
                                    size: 34,
                                    iconSize: 16
                                )

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("This cannot be undone")
                                        .cadenceFont(.rowTitle, base: 15, weight: .semibold)
                                        .foregroundStyle(Theme.text)

                                    // Same correction as the card above, in the stronger place:
                                    // this is the last thing read before an irreversible button,
                                    // so it names the two kinds outright and then names the
                                    // section that gives their full paths (T-1841). T-1840: it
                                    // names the recovery store before the button is live, and
                                    // keeps quiet about deleting the one this launch runs on.
                                    Text("Cadence permanently deletes your tasks, lists, notes, tags, saved links, focus history, and retained legacy records from this store, plus local Cadence backups, any pending restore, and the saved OpenAI key. \(CadenceUnmanagedStoreCopy.resetGateDeletesThem(runningOnRecoveryStore: PersistenceController.startupIssue?.kind == .recoveryStore))")
                                        .cadenceFont(.metadata, base: 12, weight: .regular)
                                        .foregroundStyle(Theme.subdued)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer(minLength: 0)
                            }

                            iOSRowDivider()

                            Text("\(CadenceDataResetCopy.deletionsReachOtherDevices) Apple Calendar events that already exist in Calendar are managed by Calendar and are not deleted.")
                                .cadenceFont(.metadata, base: 12, weight: .regular)
                                .foregroundStyle(Theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    iOSSettingsCard {
                        iOSSettingsField(title: "Type \(PrivacyDataResetConfirmation.requiredPhrase) to confirm") {
                            TextField(PrivacyDataResetConfirmation.requiredPhrase, text: $typedPhrase)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .focused($isPhraseFocused)
                        }
                    }

                    iOSActionButton(
                        title: "Delete Everything",
                        systemImage: "trash.fill",
                        role: .destructive,
                        size: .regular,
                        fullWidth: true,
                        isDisabled: !isArmed,
                        action: {
                            dismiss()
                            onConfirm()
                        }
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .cadenceScaledTypography()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Delete Cadence Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .tint(Theme.blue)
                }
            }
            .onAppear { isPhraseFocused = true }
        }
        .preferredColorScheme(.dark)
    }
}
#endif
