#if os(iOS)
import SwiftUI

/// Settings → Data Safety on iPhone and iPad: local store backups — create, thin, and stage a
/// restore ([[T-1477]]).
///
/// The Mac has had these three controls since before the archive existed; the phone had none,
/// while `StoreBackupManager` was snapshotting its store at every launch all along. Nothing about
/// the engine is new here. Every call is `CadenceStoreBackupControls`'s — the same calls the Mac's
/// `SettingsDataSafetySection` makes — and every sentence is `CadenceStoreBackupPresentation`'s,
/// where the two decisions the ticket demanded before any UI (what the confirmation says, and what
/// CloudKit does around a restore) are argued.
///
/// **What differs from the Mac, and why.**
/// - No **Show Folder** and no per-row **Reveal**: iOS has no Files route into Cadence's container
///   (see `iOSUnmanagedStoreSettingsSection`), so there is nowhere for either to go.
/// - A **Staged Restore** row with **Cancel Staged Restore** while one is pending. A Mac user
///   applies a restore by quitting; a phone user cannot be sure when the next launch is, because
///   iOS can relaunch the app in the background. An instruction whose moment the user does not
///   control has to be visible and withdrawable for as long as it waits.
/// - The confirmation's second sentence is the phone's: close from the app switcher.
///
/// **Unrestored Store Files** is listed here as well, read-only. The Mac's comment on that list
/// said iOS had none "because iOS has no way to schedule a restore"; it has one now, so it can
/// also be left with the folder an interrupted swap retains, and that folder may be the only copy.
///
/// One view for both size classes: iPhone and iPad differ in the width this is handed.
struct iOSStoreBackupSettingsSection: View {
    @State private var backups: [StoreBackupSnapshot] = []
    @State private var pendingRestore: (url: URL, snapshot: StoreBackupSnapshot?)?
    @State private var retainedUnrestoredDirectories: [URL] = []
    @State private var statusMessage: String?
    @State private var confirmingRestore: StoreBackupSnapshot?

    private let controls = CadenceStoreBackupControls.forThisLaunch()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            backupsCard

            if let pendingRestore {
                pendingRestoreCard(pendingRestore)
            }

            VStack(alignment: .leading, spacing: 10) {
                CadenceSettingsSectionLabel(text: CadenceStoreBackupPresentation.availableBackupsLabel)
                iOSSettingsCard {
                    VStack(alignment: .leading, spacing: 0) {
                        if backups.isEmpty {
                            Text(CadenceStoreBackupPresentation.noBackupsText)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.dim)
                        } else {
                            let listed = Array(backups.prefix(CadenceStoreBackupPresentation.listedBackupLimit))
                            ForEach(Array(listed.enumerated()), id: \.element.id) { index, backup in
                                iOSStoreBackupRow(backup: backup, onRestore: { confirmingRestore = backup })
                                if index < listed.count - 1 {
                                    iOSRowDivider(leadingInset: iOSSettingsMetrics.rowTextInset)
                                }
                            }
                        }
                    }
                }
            }

            if !retainedUnrestoredDirectories.isEmpty {
                unrestoredCard
            }
        }
        .onAppear(perform: refresh)
        .confirmationDialog(
            CadenceStoreBackupPresentation.confirmationTitle,
            isPresented: Binding(
                get: { confirmingRestore != nil },
                set: { if !$0 { confirmingRestore = nil } }
            ),
            titleVisibility: .visible,
            presenting: confirmingRestore
        ) { backup in
            Button(CadenceStoreBackupPresentation.confirmButtonTitle, role: .destructive) {
                stageRestore(backup)
            }
            Button(CadenceStoreBackupPresentation.cancelButtonTitle, role: .cancel) {
                confirmingRestore = nil
            }
        } message: { backup in
            Text(CadenceStoreBackupPresentation.confirmationMessage(for: backup, on: .phone))
        }
    }

    private var backupsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CadenceSettingsSectionLabel(text: CadenceStoreBackupPresentation.title)

            iOSSettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: iOSSettingsMetrics.glyphLabelSpacing) {
                        iOSIconTile(
                            systemImage: "externaldrive.fill.badge.timemachine",
                            color: Theme.amber,
                            size: 34,
                            iconSize: 16
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(CadenceStoreBackupPresentation.description)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.subdued)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(CadenceDataExportPresentation.localBackupLocationNote)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.subdued)
                                .fixedSize(horizontal: false, vertical: true)

                            if let statusMessage {
                                Text(statusMessage)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 10) {
                        iOSActionButton(
                            title: CadenceStoreBackupPresentation.createButtonTitle,
                            systemImage: "plus.circle.fill",
                            size: .compact,
                            tint: Theme.blue,
                            isDisabled: controls == nil,
                            action: createBackup
                        )
                        iOSActionButton(
                            title: CadenceStoreBackupPresentation.cleanUpButtonTitle,
                            systemImage: "wand.and.sparkles",
                            size: .compact,
                            tint: Theme.amber,
                            isDisabled: controls == nil,
                            action: cleanUpAutomaticBackups
                        )
                    }
                }
            }
        }
    }

    private func pendingRestoreCard(_ pending: (url: URL, snapshot: StoreBackupSnapshot?)) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CadenceSettingsSectionLabel(text: CadenceStoreBackupPresentation.pendingRestoreLabel)
            iOSSettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(CadenceStoreBackupPresentation.pendingRestoreDescription(backup: pending.snapshot, on: .phone))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.subdued)
                        .fixedSize(horizontal: false, vertical: true)

                    iOSActionButton(
                        title: CadenceStoreBackupPresentation.cancelStagedRestoreButtonTitle,
                        systemImage: "xmark.circle",
                        size: .compact,
                        tint: Theme.blue,
                        action: cancelStagedRestore
                    )
                }
            }
        }
    }

    private var unrestoredCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CadenceSettingsSectionLabel(text: CadenceStoreBackupPresentation.unrestoredSectionTitle)
            iOSSettingsCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(CadenceStoreBackupPresentation.unrestoredExplanation)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)

                    // Read-only, as on the Mac: it may be the only copy of those files.
                    ForEach(retainedUnrestoredDirectories, id: \.self) { directoryURL in
                        Text(directoryURL.path)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.text)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func refresh() {
        backups = controls?.backups() ?? []
        pendingRestore = controls?.pendingRestore()
        retainedUnrestoredDirectories = controls?.retainedUnrestoredOriginals() ?? []
    }

    private func createBackup() {
        guard let controls else { return }
        statusMessage = controls.createBackup()
        refresh()
    }

    private func cleanUpAutomaticBackups() {
        guard let controls else { return }
        statusMessage = controls.cleanUpAutomaticBackups()
        refresh()
    }

    private func stageRestore(_ backup: StoreBackupSnapshot) {
        confirmingRestore = nil
        guard let controls else { return }
        statusMessage = controls.stageRestore(backup, on: .phone)
        refresh()
    }

    private func cancelStagedRestore() {
        guard let controls else { return }
        statusMessage = controls.cancelStagedRestore()
        refresh()
    }
}

/// One backup: when, what kind, how big, and the one action a phone can take on it.
private struct iOSStoreBackupRow: View {
    let backup: StoreBackupSnapshot
    let onRestore: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: iOSSettingsMetrics.glyphLabelSpacing) {
            iOSIconTile(
                systemImage: "externaldrive.fill",
                color: Theme.amber,
                size: iOSSettingsMetrics.glyphSlot,
                iconSize: 13
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(CadenceStoreBackupPresentation.rowTitle(backup))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(CadenceStoreBackupPresentation.rowDetail(backup))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }

            Spacer(minLength: 0)

            iOSActionButton(
                title: CadenceStoreBackupPresentation.restoreButtonTitle,
                size: .compact,
                tint: Theme.amber,
                action: onRestore
            )
        }
        .padding(.vertical, iOSSettingsMetrics.rowVerticalPadding)
    }
}
#endif
