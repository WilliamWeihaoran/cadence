#if os(macOS)
import SwiftUI
import AppKit
import SwiftData

struct SettingsDataSafetySection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AISettingsManager.self) private var aiSettingsManager
    @Environment(AppleAccountManager.self) private var appleAccountManager
    @State private var backups: [StoreBackupSnapshot] = []
    @State private var statusMessage: String?
    @State private var pendingRestore: StoreBackupSnapshot?
    @State private var isConfirmingDataDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsReviewLinksSection()
            SettingsDataResetCard(
                statusMessage: statusMessage,
                onDeleteData: { isConfirmingDataDelete = true }
            )

            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.amber.opacity(0.16))
                            .frame(width: 42, height: 42)
                            .overlay {
                                Image(systemName: "externaldrive.fill.badge.timemachine")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Theme.amber)
                            }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Backups")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.text)
                            Text("Cadence backs up the local store, CloudKit assets, and external files before migration work. Automatic backups are thinned over time.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                            if let statusMessage {
                                Text(statusMessage)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.muted)
                            }
                        }

                        Spacer()

                        HStack(spacing: 10) {
                            SettingsActionButton(tone: .filled(Theme.blue), action: createBackup) {
                                Label("Create Backup", systemImage: "plus.circle.fill")
                            }
                            SettingsActionButton(tone: .tinted(Theme.amber), action: cleanUpAutomaticBackups) {
                                Label("Clean Automatic", systemImage: "wand.and.sparkles")
                            }
                            SettingsActionButton(tone: .tinted(Theme.blue), action: revealBackupFolder) {
                                Label("Show Folder", systemImage: "folder.fill")
                            }
                        }
                    }
                }
            }

            SettingsSectionLabel(text: "Available Backups")
            SettingsCard {
                VStack(spacing: 0) {
                    if backups.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "externaldrive")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.dim)
                            Text("No backups available.")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.dim)
                            Spacer()
                        }
                    } else {
                        ForEach(Array(backups.prefix(16).enumerated()), id: \.element.id) { index, backup in
                            StoreBackupRow(
                                backup: backup,
                                onReveal: { NSWorkspace.shared.activateFileViewerSelecting([backup.url]) },
                                onRestore: { pendingRestore = backup }
                            )
                            if index < min(backups.count, 16) - 1 {
                                Divider().background(Theme.borderSubtle).padding(.leading, 42)
                            }
                        }
                    }
                }
            }
        }
        .onAppear(perform: refreshBackups)
        .confirmationDialog(
            "Restore Backup?",
            isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Stage Restore", role: .destructive) {
                if let pendingRestore {
                    stageRestore(pendingRestore)
                }
                pendingRestore = nil
            }
            Button("Cancel", role: .cancel) {
                pendingRestore = nil
            }
        } message: {
            Text("Cadence will restore this backup before the store opens on the next launch. Quit and reopen Cadence after staging.")
        }
        .confirmationDialog(
            "Delete Cadence Account and Data?",
            isPresented: $isConfirmingDataDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Account & Data", role: .destructive) {
                deleteCadenceData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the local Cadence account profile, Cadence tasks, lists, notes, documents, goals, habits, tags, saved links, local Cadence backups, pending restores, and the saved OpenAI key. Apple Calendar events that already exist in Calendar are not deleted.")
        }
    }

    private func refreshBackups() {
        backups = StoreBackupManager.listBackups()
    }

    private func createBackup() {
        do {
            if let url = try StoreBackupManager.createBackupIfStoreExists(reason: .manual) {
                statusMessage = "Created \(url.lastPathComponent)."
            } else {
                statusMessage = "No active store exists yet."
            }
            refreshBackups()
        } catch {
            statusMessage = "Backup failed: \(error.localizedDescription)"
        }
    }

    private func cleanUpAutomaticBackups() {
        do {
            let removedCount = try StoreBackupManager.cleanUpAutomaticBackups()
            statusMessage = removedCount == 0
                ? "Automatic backups are already thinned."
                : "Removed \(removedCount) older automatic backup\(removedCount == 1 ? "" : "s")."
            refreshBackups()
        } catch {
            statusMessage = "Cleanup failed: \(error.localizedDescription)"
        }
    }

    private func revealBackupFolder() {
        do {
            try FileManager.default.createDirectory(at: StoreBackupManager.backupRootURL, withIntermediateDirectories: true)
            NSWorkspace.shared.activateFileViewerSelecting([StoreBackupManager.backupRootURL])
        } catch {
            statusMessage = "Could not open backup folder: \(error.localizedDescription)"
        }
    }

    private func stageRestore(_ backup: StoreBackupSnapshot) {
        do {
            try StoreBackupManager.scheduleRestore(from: backup.url)
            statusMessage = "Restore staged. Quit and reopen Cadence to apply it."
        } catch {
            statusMessage = "Could not stage restore: \(error.localizedDescription)"
        }
    }

    private func deleteCadenceData() {
        do {
            // The sequence itself is in `PrivacyDataResetService` rather than here, so iOS's
            // Data Safety screen runs the same reset instead of a second hand-written copy of it.
            let outcome = try PrivacyDataResetService.deleteCadenceDataAndLocalArtifacts(
                in: modelContext,
                aiSettingsManager: aiSettingsManager
            )
            // Sign in with Apple is entitlement-gated and macOS-only (`AppleAccountManager` is
            // inside `#if os(macOS)`), so this is the one step the shared sweep cannot take.
            appleAccountManager.signOut()
            statusMessage = outcome.statusMessage
            refreshBackups()
        } catch {
            statusMessage = "Could not delete Cadence account and data: \(error.localizedDescription)"
        }
    }
}

private struct SettingsReviewLinksSection: View {
    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Theme.blue.opacity(0.16))
                        .frame(width: 42, height: 42)
                        .overlay {
                            Image(systemName: "hand.raised.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Theme.blue)
                        }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Privacy")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text("Cadence stores planning data locally and in your private iCloud database when sync is available. Calendar access is used for calendar features, and AI actions send selected note content only when you run them.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    HStack(spacing: 10) {
                        reviewLinkButton(
                            title: "Privacy Policy",
                            icon: "lock.shield.fill",
                            url: AppStoreReviewReadiness.privacyPolicyURL,
                            missingMessage: AppStoreReviewReadiness.privacyPolicyMissingMessage
                        )
                        reviewLinkButton(
                            title: "Support",
                            icon: "questionmark.circle.fill",
                            url: AppStoreReviewReadiness.supportURL,
                            missingMessage: AppStoreReviewReadiness.supportURLMissingMessage
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func reviewLinkButton(title: String, icon: String, url: URL?, missingMessage: String) -> some View {
        if let url {
            SettingsActionButton(tone: .tinted(Theme.blue), action: { NSWorkspace.shared.open(url) }) {
                Label(title, systemImage: icon)
            }
        } else {
            #if DEBUG
            VStack(alignment: .trailing, spacing: 4) {
                Label(title, systemImage: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.dim.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(missingMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.amber)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 190, alignment: .trailing)
            }
            #endif
        }
    }
}

private struct SettingsDataResetCard: View {
    let statusMessage: String?
    let onDeleteData: () -> Void

    var body: some View {
        SettingsCard {
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.red.opacity(0.14))
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: "person.crop.circle.badge.xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.red)
                    }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Account & Data Controls")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Delete the local Cadence account profile, Cadence data from this store, local Cadence backups, pending restores, and the saved OpenAI key.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                    if let statusMessage {
                        Text(statusMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                    }
                }

                Spacer()

                SettingsActionButton(tone: .tinted(Theme.red), action: onDeleteData) {
                    Label("Delete Account & Data", systemImage: "trash.fill")
                }
            }
        }
    }
}

private struct StoreBackupRow: View {
    let backup: StoreBackupSnapshot
    let onReveal: () -> Void
    let onRestore: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.amber.opacity(0.14))
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "externaldrive.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.amber)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(backup.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("\(backup.reason) • \(backup.displaySize)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }

            Spacer()

            SettingsActionButton(tone: .tinted(Theme.blue), action: onReveal) {
                Text("Reveal")
            }
            SettingsActionButton(tone: .tinted(Theme.amber), action: onRestore) {
                Text("Restore")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 2)
    }
}
#endif
