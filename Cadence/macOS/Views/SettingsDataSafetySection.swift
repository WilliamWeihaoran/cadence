#if os(macOS)
import SwiftUI
import AppKit

struct SettingsDataSafetySection: View {
    @State private var backups: [StoreBackupSnapshot] = []
    @State private var statusMessage: String?
    @State private var pendingRestore: StoreBackupSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
