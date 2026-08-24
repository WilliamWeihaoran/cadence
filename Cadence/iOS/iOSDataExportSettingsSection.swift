#if os(iOS)
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Settings > Data Safety on iPhone and iPad: the route to a copy of the data that survives the
/// app.
///
/// **Why this exists.** `StoreBackupManager` already snapshots the store at every launch on this
/// platform too — but iOS has never had a single control over any of it: no create, no list, no
/// restore, and no way to get a copy off the device. The one data-safety action the phone had was
/// the irreversible one. Every backup it takes also lives inside the app's own container, so the
/// automatic copies do not answer "what if I lose the phone" for either platform.
///
/// The archive it writes is `CadenceDataExportService`'s, the same bytes macOS writes, and every
/// word on this card is `CadenceDataExportPresentation`'s — including the sentence saying Cadence
/// cannot read an archive back in yet, which is the part a user has to know before treating this
/// as a safety net.
///
/// One view for both size classes: iPhone and iPad differ in the width this is handed, not in how
/// a card or a button inside it looks.
struct iOSDataExportSettingsSection: View {
    @Environment(\.modelContext) private var modelContext
    @State private var exportDocument: CadenceArchiveDocument?
    @State private var isExporting = false
    @State private var exportedRecordCount = 0
    @State private var statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CadenceSettingsSectionLabel(text: "Export")

            iOSSettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: iOSSettingsMetrics.glyphLabelSpacing) {
                        iOSIconTile(
                            systemImage: "square.and.arrow.up.on.square.fill",
                            color: Theme.green,
                            size: 34,
                            iconSize: 16
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(CadenceDataExportPresentation.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.text)

                            Text(CadenceDataExportPresentation.description)
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

                    iOSActionButton(
                        title: CadenceDataExportPresentation.buttonTitle,
                        systemImage: "square.and.arrow.up",
                        size: .compact,
                        tint: Theme.green,
                        action: prepareArchiveExport
                    )
                }
            }
        }
        .fileExporter(
            isPresented: $isExporting,
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
    }

    /// Encode first, present second. A failure then lands on this card rather than producing an
    /// empty file at a destination the user has already chosen.
    private func prepareArchiveExport() {
        do {
            let outcome = try CadenceDataExportService.exportArchive(in: modelContext)
            exportedRecordCount = outcome.recordCount
            exportDocument = CadenceArchiveDocument(data: outcome.data)
            isExporting = true
        } catch {
            statusMessage = CadenceDataExportPresentation.failureMessage(error.localizedDescription)
        }
    }
}
#endif
