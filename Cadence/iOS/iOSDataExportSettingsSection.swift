#if os(iOS)
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Settings > Data Safety on iPhone and iPad: the route to a copy of the data that survives the
/// app.
///
/// **Why this exists.** `StoreBackupManager` already snapshots the store at every launch on this
/// platform too — but until T-1477 iOS had no control over any of it: no create, no list, no
/// restore, and no way to get a copy off the device; the one data-safety action the phone had was
/// the irreversible one. This card is still the only way off the device: every backup either
/// platform takes lives inside the app's own container, so the automatic copies do not answer
/// "what if I lose the phone" on either one.
///
/// The archive it writes is `CadenceDataExportService`'s, the same bytes macOS writes, and every
/// word on this card is `CadenceDataExportPresentation`'s — including the last sentence, which is
/// the part a user has to know before treating this as a safety net. Until T-1082 that sentence
/// said Cadence could not read an archive back in at all; `iOSArchiveImportSettingsSection` sits
/// directly below this card now, and what the sentence says instead is that an import adds and
/// never deletes, so the file is still not a rewind by itself.
///
/// One view for both size classes: iPhone and iPad differ in the width this is handed, not in how
/// a card or a button inside it looks.
struct iOSDataExportSettingsSection: View {
    @Environment(\.modelContext) private var modelContext
    @State private var exportDocument: CadenceArchiveDocument?
    @State private var isExporting = false
    @State private var exportedRecordCount = 0
    @State private var statusMessage: String?
    /// Kept across the save panel so the success sentence cannot quietly drop the one thing a
    /// recovery launch has to know: which store these bytes came from ([[T-3102]]).
    @State private var provenanceNote: String?

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
                let saved = CadenceDataExportPresentation.successMessage(
                    recordCount: exportedRecordCount,
                    filename: url.lastPathComponent
                )
                statusMessage = [saved, provenanceNote].compactMap { $0 }.joined(separator: " ")
            case .failure(let error):
                statusMessage = CadenceDataExportPresentation.failureMessage(error.localizedDescription)
            }
            exportDocument = nil
        }
    }

    /// Encode first, present second. A failure then lands on this card rather than producing an
    /// empty file at a destination the user has already chosen.
    ///
    /// **Not `CadenceDataExportService.exportArchive(in: modelContext)` any more ([[T-3102]]).**
    /// That reads the container the app *opened*, which is the user's store on every launch except
    /// the one where this card matters most: a launch that fell back to a recovery store exported
    /// an archive of nothing, and on this platform that was the whole escape route — iOS then
    /// scheduled no restore and listed no backup (T-1477 added both), and it still has no Files
    /// route into the container, while Delete Cadence Data on the screen below reaches
    /// `deleteAllBackups()`. The decision about which store to read lives in
    /// `PersistenceController`, with the search it reuses, so it can
    /// be driven against real isolated stores by a macOS test target that never compiles this file.
    private func prepareArchiveExport() {
        do {
            let export = try PersistenceController.exportArchiveForDataSafety(
                openedStoreContext: modelContext
            )
            exportedRecordCount = export.outcome.recordCount
            exportDocument = CadenceArchiveDocument(data: export.outcome.data)
            // Written before the save panel opens, not after: on a recovery launch the card behind
            // this button is showing an empty store, so the provenance has to be readable at the
            // moment the user decides whether the file is worth keeping.
            provenanceNote = export.provenanceNote
            statusMessage = export.provenanceNote
            isExporting = true
        } catch {
            provenanceNote = nil
            statusMessage = CadenceDataExportPresentation.failureMessage(error.localizedDescription)
        }
    }
}
#endif
