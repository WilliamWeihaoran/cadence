import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// The archive as a document the system save panel / share sheet can write.
///
/// A `FileDocument` rather than an `NSSavePanel` on macOS and a `UIActivityViewController` on iOS:
/// `.fileExporter` is the one SwiftUI spelling that works on both, and this repo already avoids
/// blocking `NSSavePanel.runModal()` in the note export flow for the same reason.
///
/// `init(configuration:)` **decodes** rather than throwing. Nothing imports an archive yet, but the
/// type is the only place a reader can be spelled once, and a document that can read what it writes
/// is what makes the round trip assertable at the value level — which is the evidence a future
/// import path has to start from. Reading a file is not restoring it; see
/// `CadenceDataExportService`'s note and `docs/TODO.md` T-274.
nonisolated struct CadenceArchiveDocument: FileDocument {
    nonisolated static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // Decode-and-discard: proves the bytes are an archive this build understands rather than
        // any JSON that happens to be lying around, and keeps the failure at open time.
        _ = try CadenceDataExportService.decode(contents)
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Every user-facing word the export shows, on both platforms, in one place.
///
/// The reset already works this way (`PrivacyDataResetOutcome.statusMessage`) and for the reason
/// T-19 names: a data-safety control has to say plainly what it does, and copy written twice is
/// copy that comes to say two things. In particular the last sentence of `description` — that an
/// archive cannot be read back in yet — is not a caveat a view may drop.
nonisolated enum CadenceDataExportPresentation {
    static let title = "Export an Archive"

    static let description = """
        One JSON file holding every task, list, note, goal, habit, tag, saved link and image \
        Cadence stores, readable in any text editor. Keep it somewhere outside Cadence: automatic \
        backups live inside the app and are deleted when Cadence's data is. Cadence cannot read an \
        archive back in yet, so this is a copy to keep, not a restore point.
        """

    static let buttonTitle = "Export Archive"

    static func successMessage(recordCount: Int, filename: String) -> String {
        "Exported \(recordCount) record\(recordCount == 1 ? "" : "s") to \(filename)."
    }

    static func failureMessage(_ reason: String) -> String {
        "Export failed: \(reason)"
    }

    /// Shown where the *automatic* store backups are listed, because "there are backups" and
    /// "the backups are somewhere safe" are different claims and only the first was ever true.
    static let localBackupLocationNote = """
        These backups are copies of the local store kept inside Cadence's own container, so they \
        survive a bad launch but not a lost device, a deleted app, or Delete Cadence Data. Export \
        an archive for a copy that outlives the app.
        """
}
