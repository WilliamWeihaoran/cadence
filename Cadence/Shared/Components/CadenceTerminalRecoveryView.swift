import SwiftUI
import UniformTypeIdentifiers

/// What `CadenceApp` shows instead of the normal window group when
/// `PersistenceController.shared.container` is `nil` — the CloudKit store, an on-disk recovery
/// store, and a fully in-memory container all failed to open this launch.
///
/// This used to be a `fatalError` inside `PersistenceController.init`. Reaching it is not
/// something a user action or a synced record can drive — it needs SwiftData to be unable to
/// build even an in-memory container, which touches neither the network nor disk — but "not
/// reachable" is a claim about probability, not a promise, and a bare crash is the worst possible
/// answer if it is ever wrong: no explanation, nothing tried, nothing offered.
///
/// **Every action here has to be honest about what it can and cannot do (T-817).**
/// - It does not offer a "Retry" that repeats the three-tier boot sequence: that already ran and
///   already failed, so a button that reruns it verbatim would be theatre, not a recovery.
/// - It does offer one thing none of those three tried: opening the **primary store's own file**,
///   read-only, with CloudKit switched off. If the boot failure was CloudKit's — unreachable
///   network, a bad container entitlement, a rejected schema push, all common and all outside this
///   app's control — the user's real data is sitting on disk untouched, and
///   `PersistenceController.attemptRecoveryExport()` is what gets it into an export instead of
///   behind a crash. It keeps going past a store that opens and then fails to export (T-1099), and
///   says so when one did.
/// - If that also fails, it says so plainly rather than hiding an empty result behind a spinner
///   that never resolves.
///
/// **It must not itself be able to crash.** It runs precisely when everything else already has,
/// so every step below is a `do`/`catch` or an `if let`/`guard let` — no force unwraps, no `try!`,
/// no `fatalError`.
struct CadenceTerminalRecoveryView: View {
    let failure: CadenceStartupTerminalFailure?

    private enum ExportOutcome: Equatable {
        case idle
        case notFound
        case failed(String)
        /// An archive was built, and something else on this device was not in it (T-1099).
        case exportedWithUnreadableStores(String)
    }

    @State private var exportOutcome: ExportOutcome = .idle
    @State private var isAttemptingExport = false
    @State private var exportDocument: CadenceArchiveDocument?
    @State private var isPresentingExporter = false

    private var detailMessage: String {
        failure?.message ?? "No further detail was recorded for this launch."
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                icon

                VStack(spacing: 10) {
                    Text("Cadence Couldn't Open Your Data")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center)
                    Text(explanation)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 460)

                exportCard
                    .frame(maxWidth: 460)

                technicalDetail
                    .frame(maxWidth: 460)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg)
        .fileExporter(
            isPresented: $isPresentingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: CadenceDataExportService.suggestedFilename()
        ) { result in
            if case .failure(let error) = result {
                // A destination failure, not a source one: the archive was built and this is the
                // save refusing. Named as such rather than left to read as "exporting failed",
                // which would send someone looking for another store when the data is in hand.
                exportOutcome = .failed("The data was read, but saving the file failed: \(error.localizedDescription)")
            }
            exportDocument = nil
        }
    }

    /// **T-1097 — this paragraph used to describe a backup Cadence does not have, and diagnose a
    /// cause nobody measured.** It said startup tried "a backup location on this device", and that
    /// failing "usually means the device was very low on memory or storage".
    ///
    /// Neither is true. `PersistenceController.makeRecoveryContainer` opens a *separate* store at
    /// `recovery.store` and restores nothing into it — a brand-new, empty database, created because
    /// the real one would not open. Calling that a backup tells a user in the worst moment of the
    /// app's life that a safety copy was tried and failed, which invites exactly the wrong
    /// conclusion about what is still on disk. And "usually" is a frequency claim: no
    /// failure-frequency measurement exists anywhere in this repository to support it.
    ///
    /// What replaces them is what the code actually does, plus a pointer at the one thing on this
    /// screen that *is* measured — the recorded error in `technicalDetail`. The export card below
    /// keeps its own promise conditional ("tries to get a backup"), because that one is a copy this
    /// screen is about to attempt, not a copy it is claiming already exists.
    private var explanation: String {
        """
        Cadence tried three ways to open your data when it started — its main database, a separate empty one it creates here when the main one will not open, and a temporary in-memory one — and none of them worked. The second and third are fallbacks rather than backups: nothing was restored from them, and nothing has been deleted.

        The recorded reason is at the bottom of this screen. Quit Cadence and reopen it; if this keeps happening, try the export below before you give up on this launch.
        """
    }

    private var icon: some View {
        ZStack {
            Circle()
                .fill(Theme.red.opacity(0.14))
                .frame(width: 64, height: 64)
            Circle()
                .strokeBorder(Theme.red.opacity(0.28), lineWidth: 1)
                .frame(width: 64, height: 64)
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.red)
        }
        .accessibilityHidden(true)
    }

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recover What You Can")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text("Cadence can try to open your data directly, without iCloud, just long enough to save a copy. This does not fix Cadence — it only tries to get a backup of what is already on this device.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: attemptExport) {
                HStack(spacing: 8) {
                    if isAttemptingExport {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Text(isAttemptingExport ? "Looking For Your Data…" : "Try to Export My Data")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Theme.onColor(for: Theme.green))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.green)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isAttemptingExport)
            .accessibilityLabel(isAttemptingExport ? "Looking for your data" : "Try to export my data")

            switch exportOutcome {
            case .idle:
                EmptyView()
            case .notFound:
                CadenceInlineFailureNotice(text: "Cadence could not open any store on this device. If you use iCloud Backup or Time Machine, a backup made before today may still have your data.")
            // One notice for both, deliberately. `.exportedWithUnreadableStores` follows a press
            // that produced a file, and it is still a failure sentence: part of what is on this
            // device is not in that file, and this screen's whole job is to be exact about how
            // much was recovered. Two arms drawing the same component is a second call site of a
            // notice that means one thing.
            case .failed(let reason), .exportedWithUnreadableStores(let reason):
                CadenceInlineFailureNotice(text: reason)
            }
        }
        .padding(16)
        .background(Theme.surfaceElevated)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .strokeBorder(Theme.borderSubtle, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
    }

    private var technicalDetail: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Details")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dim)
            Text(detailMessage)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Not a retry of the boot sequence — see the type's doc comment. Every branch below is a
    /// `case` of a returned result, so a second, third or hundredth failure here only ever updates
    /// `exportOutcome`.
    ///
    /// The search itself lives in `PersistenceController.attemptRecoveryExport()`, not here: this
    /// used to take a container back and export it, which is what made the *first store that
    /// opened* the last store anyone tried (T-1099). Deciding which candidate to try is one
    /// decision and it belongs in one place, with the candidate list.
    private func attemptExport() {
        guard !isAttemptingExport else { return }
        isAttemptingExport = true
        exportOutcome = .idle

        switch PersistenceController.attemptRecoveryExport() {
        case .noStoreOpened:
            exportOutcome = .notFound
        case .everyOpenedStoreFailed(let failures):
            exportOutcome = .failed(Self.everyStoreFailedSentence(failures))
        case .exported(let export):
            exportDocument = CadenceArchiveDocument(data: export.data)
            isPresentingExporter = true
            if !export.precedingFailures.isEmpty {
                exportOutcome = .exportedWithUnreadableStores(
                    Self.partialRecoverySentence(export)
                )
            }
        }
        isAttemptingExport = false
    }

    /// Every store that opened refused to export. Each one is named with its own reason, because
    /// "exporting failed" without which store or why is the sentence a user can do nothing with.
    static func everyStoreFailedSentence(
        _ failures: [PersistenceController.RecoveryExportFailure]
    ) -> String {
        let reasons = failures
            .map { "\($0.storeURL.path): \($0.reason)" }
            .joined(separator: " ")
        let count = failures.count
        return count == 1
            ? "Found a store, but exporting failed. \(reasons)"
            : "Found \(count) stores on this device and none of them could be exported. \(reasons)"
    }

    /// The export worked, and it is not everything. Says the count that *was* saved first, so the
    /// sentence cannot be read as "nothing was recovered", then names what was left out.
    static func partialRecoverySentence(_ export: PersistenceController.RecoveryExport) -> String {
        let skipped = export.precedingFailures
            .map { "\($0.storeURL.path): \($0.reason)" }
            .joined(separator: " ")
        let count = export.precedingFailures.count
        let records = export.recordCount == 1 ? "1 record" : "\(export.recordCount) records"
        return count == 1
            ? "Saved \(records) from \(export.storeURL.path). One other store on this device could not be exported and is not in this file. \(skipped)"
            : "Saved \(records) from \(export.storeURL.path). \(count) other stores on this device could not be exported and are not in this file. \(skipped)"
    }
}
