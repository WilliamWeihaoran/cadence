import SwiftUI
import SwiftData
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
///   `PersistenceController.attemptReadOnlyStoreForRecoveryExport()` is what gets it into an
///   export instead of behind a crash.
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
                exportOutcome = .failed(error.localizedDescription)
            }
            exportDocument = nil
        }
    }

    private var explanation: String {
        """
        Cadence tried three different ways to open your data when it started — through iCloud, from a backup location on this device, and as a temporary store — and none of them worked. This usually means the device was very low on memory or storage at the moment it launched.

        Quit Cadence and reopen it. If this keeps happening, try the recovery below before you give up on this launch.
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
                .foregroundStyle(Theme.onColor)
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
            case .failed(let reason):
                CadenceInlineFailureNotice(text: "Found a store, but exporting failed: \(reason)")
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

    /// Not a retry of the boot sequence — see the type's doc comment. Every step is optional or
    /// `try?`, so a second, third or hundredth failure here only ever updates `exportOutcome`.
    private func attemptExport() {
        guard !isAttemptingExport else { return }
        isAttemptingExport = true
        exportOutcome = .idle

        guard let container = PersistenceController.attemptReadOnlyStoreForRecoveryExport() else {
            exportOutcome = .notFound
            isAttemptingExport = false
            return
        }

        let context = ModelContext(container)
        do {
            let outcome = try CadenceDataExportService.exportArchive(in: context)
            exportDocument = CadenceArchiveDocument(data: outcome.data)
            isPresentingExporter = true
        } catch {
            exportOutcome = .failed(error.localizedDescription)
        }
        isAttemptingExport = false
    }
}
