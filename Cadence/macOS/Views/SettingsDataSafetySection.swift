#if os(macOS)
import SwiftUI
import AppKit
import SwiftData
import UniformTypeIdentifiers

struct SettingsDataSafetySection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AISettingsManager.self) private var aiSettingsManager
    @Environment(AppleAccountManager.self) private var appleAccountManager
    @State private var backups: [StoreBackupSnapshot] = []

    /// The outcome of the **export** and of the **reset**, shown under the reset card.
    ///
    /// Sharing one line between those two is deliberate — see `SettingsDataExportCard` — because
    /// both answer "what just happened to my data" and the export card has no status line of its
    /// own. Sharing it with the *Backups* card was not: this was one `@State` rendered in two
    /// cards at once, so creating a backup printed "Created backup-….sqlite." underneath the red
    /// **Delete Account & Data** button as well as under the backup buttons (T-582). iOS never
    /// had the bug — `iOSDataExportSettingsSection` and `iOSDataResetSettingsSection` each own
    /// their own line — and this is the same rule: a status line belongs to the card whose button
    /// produced it.
    @State private var statusMessage: String?

    /// Create / clean / reveal / stage-restore, shown under the Backups card and nowhere else.
    @State private var backupStatusMessage: String?
    @State private var pendingRestore: StoreBackupSnapshot?
    @State private var isConfirmingDataDelete = false
    @State private var exportDocument: CadenceArchiveDocument?
    @State private var isExportingArchive = false
    @State private var exportedRecordCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsPrivacyStatementSection()
            // Keeping a copy comes before destroying one, on the screen as well as in the reading
            // order: this card is the only route to data that outlives the app.
            SettingsDataExportCard(onExport: prepareArchiveExport)
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
                            // What this said before: "Cadence backs up the local store, CloudKit
                            // assets, and external files before migration work." Two things wrong
                            // with it, both the kind T-19 exists to catch — backups are taken at
                            // every launch, not only around a migration, and it never said the
                            // copies sit inside the app, which is the fact that decides whether a
                            // user needs an archive as well.
                            Text("Cadence copies the local store — including CloudKit assets and external files — at every launch, before a restore, and whenever you ask. Automatic copies are thinned over time.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(CadenceDataExportPresentation.localBackupLocationNote)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                            if let backupStatusMessage {
                                Text(backupStatusMessage)
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
                                CadenceRowDivider(leadingInset: 42)
                            }
                        }
                    }
                }
            }
        }
        .onAppear(perform: refreshBackups)
        .fileExporter(
            isPresented: $isExportingArchive,
            document: exportDocument,
            contentType: .json,
            defaultFilename: CadenceDataExportService.suggestedFilename()
        ) { result in
            switch result {
            case .success(let url):
                statusMessage = CadenceDataExportPresentation.successMessage(
                    recordCount: exportedRecordCount,
                    filename: url.lastPathComponent
                )
            case .failure(let error):
                statusMessage = CadenceDataExportPresentation.failureMessage(error.localizedDescription)
            }
            exportDocument = nil
        }
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
        // Not a `confirmationDialog` (T-575). This was the one destructive action in the app whose
        // *less*-guarded path deleted the **more**: the Mac's dialog put a live "Delete Account &
        // Data" button one click away, while the phone made you type DELETE for a reset that does
        // not even sign the Apple account out. Same gate on both platforms now —
        // `PrivacyDataResetConfirmation`, which is where the rule lives and the only thing that
        // decides.
        .sheet(isPresented: $isConfirmingDataDelete) {
            SettingsDataResetConfirmationSheet(onConfirm: deleteCadenceData)
        }
    }

    private func refreshBackups() {
        backups = StoreBackupManager.listBackups()
    }

    /// Builds the archive, then hands it to the system save panel. Encoding happens *before* the
    /// panel opens so a failure is reported in this pane rather than as an empty file the user has
    /// already chosen a home for.
    private func prepareArchiveExport() {
        do {
            let outcome = try CadenceDataExportService.exportArchive(in: modelContext)
            exportedRecordCount = outcome.recordCount
            exportDocument = CadenceArchiveDocument(data: outcome.data)
            isExportingArchive = true
        } catch {
            statusMessage = CadenceDataExportPresentation.failureMessage(error.localizedDescription)
        }
    }

    private func createBackup() {
        do {
            if let url = try StoreBackupManager.createBackupIfStoreExists(reason: .manual) {
                backupStatusMessage = "Created \(url.lastPathComponent)."
            } else {
                backupStatusMessage = "No active store exists yet."
            }
            refreshBackups()
        } catch {
            backupStatusMessage = "Backup failed: \(error.localizedDescription)"
        }
    }

    private func cleanUpAutomaticBackups() {
        do {
            let removedCount = try StoreBackupManager.cleanUpAutomaticBackups()
            backupStatusMessage = removedCount == 0
                ? "Automatic backups are already thinned."
                : "Removed \(removedCount) older automatic backup\(removedCount == 1 ? "" : "s")."
            refreshBackups()
        } catch {
            backupStatusMessage = "Cleanup failed: \(error.localizedDescription)"
        }
    }

    private func revealBackupFolder() {
        do {
            try FileManager.default.createDirectory(at: StoreBackupManager.backupRootURL, withIntermediateDirectories: true)
            NSWorkspace.shared.activateFileViewerSelecting([StoreBackupManager.backupRootURL])
        } catch {
            backupStatusMessage = "Could not open backup folder: \(error.localizedDescription)"
        }
    }

    private func stageRestore(_ backup: StoreBackupSnapshot) {
        do {
            try StoreBackupManager.scheduleRestore(from: backup.url)
            backupStatusMessage = "Restore staged. Quit and reopen Cadence to apply it."
        } catch {
            backupStatusMessage = "Could not stage restore: \(error.localizedDescription)"
        }
    }

    private func deleteCadenceData() {
        // `await`, and therefore a `Task`: the reset does not return until the pending OS
        // notifications for the deleted data are actually cancelled (T-297), so the status
        // message below is written when the sweep is finished rather than when it was started.
        Task {
            do {
                // The sequence itself is in `PrivacyDataResetService` rather than here, so iOS's
                // Data Safety screen runs the same reset instead of a second hand-written copy.
                let outcome = try await PrivacyDataResetService.deleteCadenceDataAndLocalArtifacts(
                    in: modelContext,
                    aiSettingsManager: aiSettingsManager
                )
                // Sign in with Apple is entitlement-gated and macOS-only (`AppleAccountManager` is
                // inside `#if os(macOS)`), so this is the one step the shared sweep cannot take.
                appleAccountManager.signOut()
                statusMessage = outcome.accountAndDataStatusMessage
                refreshBackups()
            } catch {
                statusMessage = "Could not delete Cadence account and data: \(error.localizedDescription)"
            }
        }
    }
}

/// What Cadence does with your data, in one paragraph, above the control that erases it.
///
/// This was `SettingsReviewLinksSection`, and it carried the `Privacy Policy` and `Support`
/// buttons in a trailing `HStack`. Those moved to Settings → About (T-220): a support page is not a
/// data-safety control, and the pair only ever sat here because *this* paragraph did. The paragraph
/// stays — how Cadence stores and transmits data is exactly this screen's subject — so the struct
/// is renamed to say what is left rather than keeping a name that promises links it no longer has.
private struct SettingsPrivacyStatementSection: View {
    var body: some View {
        SettingsCard {
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

                Spacer(minLength: 0)
            }
        }
    }
}

/// The route to a copy of the data that Cadence cannot delete.
///
/// Every word it shows is `CadenceDataExportPresentation`'s, so iOS's card cannot come to describe
/// a different file. It has no status line of its own: the outcome sentence goes to `statusMessage`
/// and is drawn by `SettingsDataResetCard` directly below, because both are answers to "what just
/// happened to my data".
///
/// **That pairing is the whole of the sharing now (T-582).** `statusMessage` used to be rendered by
/// the Backups card as well, so "Created backup-….sqlite." also appeared under the red
/// **Delete Account & Data** button. The backup buttons write `backupStatusMessage` instead.
private struct SettingsDataExportCard: View {
    let onExport: () -> Void

    var body: some View {
        SettingsCard {
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.green.opacity(0.14))
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: "square.and.arrow.up.on.square.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.green)
                    }

                VStack(alignment: .leading, spacing: 6) {
                    Text(CadenceDataExportPresentation.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(CadenceDataExportPresentation.description)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                SettingsActionButton(tone: .tinted(Theme.green), action: onExport) {
                    Label(CadenceDataExportPresentation.buttonTitle, systemImage: "square.and.arrow.up")
                }
            }
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

/// The second and third gates on the Mac: a modal that enumerates what is about to be lost, and a
/// phrase that has to be typed before the destructive button is live at all.
///
/// **T-575.** This pane used to gate the reset behind a `confirmationDialog` whose destructive
/// button was live the moment it appeared, while iPhone and iPad required `DELETE` to be typed —
/// and the Mac's reset is the *larger* one, because only here is there a Sign in with Apple
/// profile to clear. The less guarded path deleted more. The gate is
/// `PrivacyDataResetConfirmation`, the same value `iOSDataResetConfirmationSheet` reads, so
/// neither surface re-spells what counts as authorization and neither can be relaxed alone.
private struct SettingsDataResetConfirmationSheet: View {
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var typedPhrase = ""
    @FocusState private var isPhraseFocused: Bool

    private var isArmed: Bool {
        PrivacyDataResetConfirmation.authorizes(typedPhrase)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionEyebrowLabel(text: "Delete Account & Data")
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 14) {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 14) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Theme.red.opacity(0.14))
                                .frame(width: 42, height: 42)
                                .overlay {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(Theme.red)
                                }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("This cannot be undone")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                Text("This permanently deletes the local Cadence account profile, Cadence tasks, lists, notes, documents, goals, habits, tags, saved links, local Cadence backups, pending restores, and the saved OpenAI key. Apple Calendar events that already exist in Calendar are not deleted.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.dim)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)
                        }
                    }
                }

                SettingsCard {
                    CadenceSettingsField(
                        title: "Type \(PrivacyDataResetConfirmation.requiredPhrase) to confirm"
                    ) {
                        TextField(PrivacyDataResetConfirmation.requiredPhrase, text: $typedPhrase)
                            .focused($isPhraseFocused)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)

            // `CadenceRowDivider`, not `Divider().background(…)`: a settings pane that paints its
            // own colour under the system separator is what T-286/T-553 sweep for, and this file
            // is inside that sweep's corpus.
            CadenceRowDivider()

            HStack(spacing: 8) {
                Spacer(minLength: 12)
                CadenceActionButton(title: "Cancel", role: .ghost, size: .compact) {
                    dismiss()
                }
                CadenceActionButton(
                    title: "Delete Everything",
                    systemImage: "trash.fill",
                    role: .destructive,
                    size: .compact,
                    isDisabled: !isArmed
                ) {
                    dismiss()
                    onConfirm()
                }
            }
            .padding(16)
        }
        .frame(width: 460)
        .background(Theme.surface)
        .onAppear { isPhraseFocused = true }
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
