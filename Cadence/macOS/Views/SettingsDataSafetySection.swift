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

    /// The `Cadence Store Backups` folders beside store directories Cadence no longer uses
    /// ([[T-1532]]). Shown, never touched — see `UnmanagedBackupDirectory`.
    @State private var unmanagedBackupDirectories: [UnmanagedBackupDirectory] = []

    /// The folders holding Cadence **store** files this launch is not opening ([[T-1680]]): the
    /// `Recovery/` store a failed launch wrote, and the locations earlier versions kept the store
    /// in. Shown, never touched — see `UnmanagedStoreDirectory`.
    @State private var unmanagedStoreDirectories: [UnmanagedStoreDirectory] = []

    /// The `Cadence Unrestored Store Files …` folders a restore retained beside the live store
    /// ([[T-3045]] (2)). Shown, never touched — see `RetainedUnrestoredOriginalsRow`.
    @State private var retainedUnrestoredDirectories: [URL] = []

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
    /// Kept across the save panel so the success sentence cannot quietly drop the one thing a
    /// recovery launch has to know: which store these bytes came from ([[T-3102]]).
    @State private var exportProvenanceNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsPrivacyStatementSection()
            // Keeping a copy comes before destroying one, on the screen as well as in the reading
            // order: this card is the only route to data that outlives the app.
            SettingsDataExportCard(onExport: prepareArchiveExport)
            // …and reading one back comes directly after keeping it, because the two are halves of
            // the same promise and a user who has just been told to keep a file elsewhere should
            // see, in the same breath, what Cadence can do with it. Above the Backups card
            // deliberately: those copies live inside the container and die with the app, so the
            // archive is the route that answers "I lost the device", and it reads first.
            SettingsArchiveImportCard()
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
                            Text(CadenceStoreBackupPresentation.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.text)
                            // What this said before: "Cadence backs up the local store, CloudKit
                            // assets, and external files before migration work." Two things wrong
                            // with it, both the kind T-19 exists to catch — backups are taken at
                            // every launch, not only around a migration, and it never said the
                            // copies sit inside the app, which is the fact that decides whether a
                            // user needs an archive as well.
                            Text(CadenceStoreBackupPresentation.description)
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
                                Label(CadenceStoreBackupPresentation.createButtonTitle, systemImage: "plus.circle.fill")
                            }
                            SettingsActionButton(tone: .tinted(Theme.amber), action: cleanUpAutomaticBackups) {
                                Label(CadenceStoreBackupPresentation.cleanUpButtonTitle, systemImage: "wand.and.sparkles")
                            }
                            SettingsActionButton(tone: .tinted(Theme.blue), action: revealBackupFolder) {
                                Label("Show Folder", systemImage: "folder.fill")
                            }
                        }
                    }
                }
            }

            // **T-1126.** Grouped with the card it names: it used to sit 16pt below the Backups
            // card above it and 16pt above the list it labels, which is to say attached to
            // neither.
            VStack(alignment: .leading, spacing: CadenceSectionLabelMetrics.labelToNamedBlock) {
                SettingsSectionLabel(text: CadenceStoreBackupPresentation.availableBackupsLabel)
                SettingsCard {
                    VStack(spacing: 0) {
                        if backups.isEmpty {
                            HStack(spacing: 12) {
                                Image(systemName: "externaldrive")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.dim)
                                Text(CadenceStoreBackupPresentation.noBackupsText)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.dim)
                                Spacer()
                            }
                        } else {
                            ForEach(Array(backups.prefix(CadenceStoreBackupPresentation.listedBackupLimit).enumerated()), id: \.element.id) { index, backup in
                                StoreBackupRow(
                                    backup: backup,
                                    onReveal: { NSWorkspace.shared.activateFileViewerSelecting([backup.url]) },
                                    onRestore: { pendingRestore = backup }
                                )
                                if index < min(backups.count, CadenceStoreBackupPresentation.listedBackupLimit) - 1 {
                                    CadenceRowDivider(leadingInset: 42)
                                }
                            }
                        }
                    }
                }
            }

            // **T-1532 — the 86 MB this screen used to answer for and could not see.** The list
            // above is `listBackups()`, which resolves the live store directory, and it was the
            // screen's whole answer to "what copies does Cadence keep". On the owner's Mac on
            // 2026-09-29 that was 10 folders / 145 MB out of four directories holding 231 MB: the
            // rest sat beside store locations the app had moved on from, reachable by nothing,
            // newest entry four months old.
            //
            // It is a list and not a control on purpose. These are under paths the app no longer
            // owns, and one of them holds the only copies of pre-app-group state on the machine —
            // a "Clean" or "Clear" button that reached them would make this screen delete data on
            // the strength of a path it inferred, which is a worse failure than the silence it
            // replaces. Reveal only; the rest is Finder's and the user's.
            if !unmanagedBackupDirectories.isEmpty {
                VStack(alignment: .leading, spacing: CadenceSectionLabelMetrics.labelToNamedBlock) {
                    SettingsSectionLabel(text: "Other Backup Folders")
                    SettingsCard {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Earlier versions of Cadence kept the store somewhere else and left these copies behind. Cadence does not add to them, thin them, or delete them — not even when you delete all Cadence data. Remove them in Finder if you want the space back.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.bottom, 12)

                            ForEach(Array(unmanagedBackupDirectories.enumerated()), id: \.element.id) { index, directory in
                                UnmanagedBackupDirectoryRow(
                                    directory: directory,
                                    onReveal: { NSWorkspace.shared.activateFileViewerSelecting([directory.url]) }
                                )
                                if index < unmanagedBackupDirectories.count - 1 {
                                    CadenceRowDivider(leadingInset: 42)
                                }
                            }
                        }
                    }
                }
            }

            // **T-3045 (2) — the last copy of store files a restore moved aside.** A swap
            // interrupted mid-move leaves its originals in `.cadence-restore-previous.tmp`; the
            // next attempt retains that folder as `Cadence Unrestored Store Files <timestamp>`
            // rather than deleting it, and if that attempt then succeeds no failed-restore banner
            // is ever written. Until this section nothing on screen named the folder at all.
            //
            // Reveal only, for the reason the two lists below are: it may be the only copy of
            // those files, and the one thing allowed to remove it is Delete Account & Data,
            // which says so. iOS has no section because iOS has no way to schedule a restore yet
            // (T-1477 is PARTIAL: the phone's section is parked, and lists these when it lands).
            if !retainedUnrestoredDirectories.isEmpty {
                VStack(alignment: .leading, spacing: CadenceSectionLabelMetrics.labelToNamedBlock) {
                    SettingsSectionLabel(text: CadenceStoreBackupPresentation.unrestoredSectionTitle)
                    SettingsCard {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(CadenceStoreBackupPresentation.unrestoredExplanation)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.bottom, 12)

                            ForEach(Array(retainedUnrestoredDirectories.enumerated()), id: \.element) { index, directoryURL in
                                RetainedUnrestoredOriginalsRow(
                                    directoryURL: directoryURL,
                                    onReveal: { NSWorkspace.shared.activateFileViewerSelecting([directoryURL]) }
                                )
                                if index < retainedUnrestoredDirectories.count - 1 {
                                    CadenceRowDivider(leadingInset: 42)
                                }
                            }
                        }
                    }
                }
            }

            // **T-1680 — the copies this screen answered for and could not see, one directory
            // further in.** T-1532 made the stray *backups* visible. The stray *stores* stayed
            // invisible, and they are the worse half: `Recovery/` is a child of the live store
            // directory, so it is inside the container "Delete Account & Data" has just emptied,
            // and neither `listBackups()` nor `unmanagedBackupDirectories()` can see it because it
            // is not a backups folder. On the owner's Mac on 2026-09-30 that was 512 KB written by
            // a failed launch on 2026-08-19 and never read since, plus two earlier store locations
            // holding a further ~2.4 MB.
            //
            // Reveal only, for T-1532's reason and one more: a recovery store is opened with
            // CloudKit off, so anything typed during that degraded session synced nowhere and this
            // folder is its only copy. Whether the reset should take it is T-1840, and it is the
            // owner's call, not a button this row can grow.
            if !unmanagedStoreDirectories.isEmpty {
                VStack(alignment: .leading, spacing: CadenceSectionLabelMetrics.labelToNamedBlock) {
                    SettingsSectionLabel(text: CadenceUnmanagedStoreCopy.sectionTitle)
                    SettingsCard {
                        VStack(alignment: .leading, spacing: 0) {
                            // The two shared claims, then the one sentence that is this
                            // platform's own: a Mac has Finder and a phone has no route into the
                            // container at all, so that half cannot be shared (T-1841).
                            Text("\(CadenceUnmanagedStoreCopy.whatTheyAre) \(CadenceUnmanagedStoreCopy.whatCadenceDoesNotDo) Remove them in Finder if you want the space back.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.bottom, 12)

                            ForEach(Array(unmanagedStoreDirectories.enumerated()), id: \.element.id) { index, directory in
                                UnmanagedStoreDirectoryRow(
                                    directory: directory,
                                    onReveal: { NSWorkspace.shared.activateFileViewerSelecting([directory.url]) }
                                )
                                if index < unmanagedStoreDirectories.count - 1 {
                                    CadenceRowDivider(leadingInset: 42)
                                }
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
                let saved = CadenceDataExportPresentation.successMessage(
                    recordCount: exportedRecordCount,
                    filename: url.lastPathComponent
                )
                statusMessage = [saved, exportProvenanceNote].compactMap { $0 }.joined(separator: " ")
            case .failure(let error):
                statusMessage = CadenceDataExportPresentation.failureMessage(error.localizedDescription)
            }
            exportDocument = nil
        }
        .confirmationDialog(
            CadenceStoreBackupPresentation.confirmationTitle,
            isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingRestore
        ) { backup in
            Button(CadenceStoreBackupPresentation.confirmButtonTitle, role: .destructive) {
                stageRestore(backup)
                pendingRestore = nil
            }
            Button(CadenceStoreBackupPresentation.cancelButtonTitle, role: .cancel) {
                pendingRestore = nil
            }
        } message: { backup in
            // T-1477: the shared sentence, which now also says the replaced store is kept and what
            // iCloud sync can do afterwards — the words the phone's dialog is built on as well.
            Text(CadenceStoreBackupPresentation.confirmationMessage(for: backup, on: .mac))
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
        backups = backupControls?.backups() ?? []
        // Read-only, and the only call on this screen that reaches a path outside the live store
        // directory. `unmanagedBackupDirectories` lists and sizes; nothing here can write.
        unmanagedBackupDirectories = StoreBackupManager.unmanagedBackupDirectories()
        unmanagedStoreDirectories = StoreBackupManager.unmanagedStoreDirectories()
        retainedUnrestoredDirectories = backupControls?.retainedUnrestoredOriginals() ?? []
    }

    /// Builds the archive, then hands it to the system save panel. Encoding happens *before* the
    /// panel opens so a failure is reported in this pane rather than as an empty file the user has
    /// already chosen a home for.
    ///
    /// **Not `CadenceDataExportService.exportArchive(in: modelContext)` any more ([[T-3102]]).**
    /// That reads the container this launch *opened*, which is the person's store on every launch
    /// but one: after a fallback to `makeRecoveryContainer` it is the empty recovery store, and
    /// the archive came out holding nothing. The Mac has a restore control a few rows below this
    /// one, so it was never stranded the way the phone was — but the archive is the only copy that
    /// outlives the app, and both screens take the same call deliberately, so that "export my
    /// data" cannot come to mean two different things on two platforms.
    private func prepareArchiveExport() {
        do {
            let export = try PersistenceController.exportArchiveForDataSafety(
                openedStoreContext: modelContext
            )
            exportedRecordCount = export.outcome.recordCount
            exportDocument = CadenceArchiveDocument(data: export.outcome.data)
            // Written before the panel opens, not after: on a recovery launch the pane behind this
            // button is showing an empty store, so the provenance has to be readable at the moment
            // the user decides whether the file is worth keeping.
            exportProvenanceNote = export.provenanceNote
            statusMessage = export.provenanceNote
            isExportingArchive = true
        } catch {
            exportProvenanceNote = nil
            statusMessage = CadenceDataExportPresentation.failureMessage(error.localizedDescription)
        }
    }

    /// The calls this card makes — the same ones the phone's section will make (T-1477).
    private var backupControls: CadenceStoreBackupControls? { CadenceStoreBackupControls.forThisLaunch() }

    private func createBackup() {
        guard let backupControls else { return }
        backupStatusMessage = backupControls.createBackup()
        refreshBackups()
    }

    private func cleanUpAutomaticBackups() {
        guard let backupControls else { return }
        backupStatusMessage = backupControls.cleanUpAutomaticBackups()
        refreshBackups()
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
        guard let backupControls else { return }
        backupStatusMessage = backupControls.stageRestore(backup, on: .mac)
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
                    // [[T-7208]]: it said "selected note content", the clause [[T-1322]] took out
                    // of the AI pane's disclosure as the one a reader could not check. An AI
                    // action sends the note's title, whole text and list name, which is what the
                    // AI pane (`CadenceAISettingsCopy.keyPrivacyDisclosure`) and privacy.html say.
                    Text("Cadence stores planning data locally and in your private iCloud database when sync is available. Calendar access is used for calendar features, and AI actions send a note's title, full text, and list name to OpenAI only when you run one.")
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
                    // **T-1680 — the second clause is the one that was missing.** The sentence
                    // named five things and stopped, and a reader takes a list that specific as
                    // exhaustive. It is not: the reset reaches the live store directory only, so a
                    // `Recovery/` store inside that very directory, and every earlier store
                    // location, survive it. Naming the exception here rather than only in the
                    // modal means the screen is honest before anyone presses anything.
                    Text("Delete the local Cadence account profile, Cadence data from this store, local Cadence backups, pending restores, and the saved OpenAI key. \(CadenceUnmanagedStoreCopy.resetLeavesThem)")
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
                                // The trailing claim is `CadenceUnmanagedStoreCopy`'s, read by
                                // iOS's gate as well (T-1841). It used to be welded onto the
                                // Calendar clause with "and neither are"; split into its own
                                // sentence so one string can serve both platforms without either
                                // depending on what precedes it. [[T-7207]]: the sync sentence
                                // is the phone gate's, so both say the deletions leave this Mac.
                                Text("This permanently deletes the local Cadence account profile, Cadence tasks, lists, notes, documents, tags, saved links, retained legacy records, local Cadence backups, pending restores, and the saved OpenAI key. \(CadenceDataResetCopy.deletionsReachOtherDevices) Apple Calendar events that already exist in Calendar are not deleted. \(CadenceUnmanagedStoreCopy.resetGateLeavesThem)")
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

/// One folder of backups Cadence left behind, with the path that makes it findable.
///
/// **The row has one button and it opens Finder ([[T-1532]]).** No reveal-and-delete pair, no
/// destructive tone: `UnmanagedBackupDirectory` says why, and the shape of this view is where that
/// rule is actually enforced — a row that cannot be handed a delete action cannot grow one by
/// accident.
private struct UnmanagedBackupDirectoryRow: View {
    let directory: UnmanagedBackupDirectory
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: Theme.radiusControl)
                .fill(Theme.dim.opacity(0.14))
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                }

            VStack(alignment: .leading, spacing: 3) {
                // The path in full, because it is the only thing that makes the folder findable
                // and the whole complaint T-1532 records is that the screen never said where.
                Text(directory.url.path)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(directory.displayCount) • \(directory.displaySize) • not managed by Cadence")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }

            Spacer(minLength: 8)

            SettingsActionButton(tone: .tinted(Theme.blue), action: onReveal) {
                Text("Reveal")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 2)
    }
}

/// One folder of Cadence store files the app is not using, with the path that makes it findable.
///
/// **The row has one button and it opens Finder ([[T-1680]], following [[T-1532]]).** Same two
/// members as `UnmanagedBackupDirectoryRow` — `directory` and `onReveal` — so a delete cannot be
/// handed to it, which is the rule enforced by the shape of the view rather than by a convention.
/// A recovery store never synced and is the only copy of what a degraded session recorded; a
/// "Clear" button here would be this screen destroying that on the strength of a path it inferred.
private struct UnmanagedStoreDirectoryRow: View {
    let directory: UnmanagedStoreDirectory
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: Theme.radiusControl)
                .fill(Theme.dim.opacity(0.14))
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                }

            VStack(alignment: .leading, spacing: 3) {
                // The path in full, for the reason `UnmanagedBackupDirectoryRow` shows one: it is
                // the only thing that makes the folder findable, and none of these are guessable.
                Text(directory.url.path)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text(directory.displayDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }

            Spacer(minLength: 8)

            SettingsActionButton(tone: .tinted(Theme.blue), action: onReveal) {
                Text("Reveal")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 2)
    }
}

/// One folder of store files a restore moved aside and Cadence retained ([[T-3045]] (2)).
///
/// **One button, and it opens Finder** — the same two members as `UnmanagedStoreDirectoryRow`, so
/// a delete cannot be handed to it. The only thing in the app that removes this folder is the
/// data reset, and a second, quieter way to destroy what may be the last copy of a store is
/// exactly what that rule keeps off this screen.
private struct RetainedUnrestoredOriginalsRow: View {
    let directoryURL: URL
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: Theme.radiusControl)
                .fill(Theme.amber.opacity(0.14))
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.amber)
                }

            VStack(alignment: .leading, spacing: 3) {
                // The path in full: the folder is visible in Finder on purpose, and the path is
                // what makes it findable.
                Text(directoryURL.path)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Kept by an unfinished restore • not read by Cadence")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }

            Spacer(minLength: 8)

            SettingsActionButton(tone: .tinted(Theme.blue), action: onReveal) {
                Text("Reveal")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 2)
    }
}

private struct StoreBackupRow: View {
    let backup: StoreBackupSnapshot
    let onReveal: () -> Void
    let onRestore: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: Theme.radiusControl)
                .fill(Theme.amber.opacity(0.14))
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "externaldrive.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.amber)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(CadenceStoreBackupPresentation.rowTitle(backup))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(CadenceStoreBackupPresentation.rowDetail(backup))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }

            Spacer()

            SettingsActionButton(tone: .tinted(Theme.blue), action: onReveal) {
                Text("Reveal")
            }
            SettingsActionButton(tone: .tinted(Theme.amber), action: onRestore) {
                Text(CadenceStoreBackupPresentation.restoreButtonTitle)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 2)
    }
}
#endif
