import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// The archive as a document the system save panel / share sheet can write.
///
/// A `FileDocument` rather than an `NSSavePanel` on macOS and a `UIActivityViewController` on iOS:
/// `.fileExporter` is the one SwiftUI spelling that works on both, and this repo already avoids
/// blocking `NSSavePanel.runModal()` in the note export flow for the same reason.
///
/// `init(configuration:)` **decodes** rather than throwing, which is what made the round trip
/// assertable at the value level before there was an importer to assert it against. There is one
/// now (T-274/T-1082) and it does *not* come through here: `CadenceArchiveImportFlow` reads the
/// picked URL itself, because a `FileDocument` hands a view bytes and the import needs a plan
/// first. This type is still the export's writer and still the shortest proof that what Cadence
/// writes is what `CadenceDataExportService.decode` reads.
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
/// The reset already works this way (`PrivacyDataResetOutcome.accountAndDataStatusMessage`) and for the reason
/// T-19 names: a data-safety control has to say plainly what it does, and copy written twice is
/// copy that comes to say two things. In particular the last sentence of `description` is not a
/// caveat a view may drop — though **what it has to say changed in T-1082**, when the import
/// shipped. It used to read "Cadence cannot read an archive back in yet", and that stopped being
/// true; `CadenceRetiredCopyTests` now refuses the old sentence anywhere in the app. What replaced
/// it is the fact that outlived it: `CadenceArchiveImportService` adds and never deletes, so the
/// file is still not a rewind on its own. `CadenceArchiveImportPresentation.neverDeletesNote`
/// carries the same fact in full, beside the button that acts on it; this is the one-clause
/// version, read at the moment a user decides whether the file is a safety net.
nonisolated enum CadenceDataExportPresentation {
    static let title = "Export an Archive"

    static let description = """
        One JSON file holding every task, list, note, goal, habit, tag, saved link and image \
        Cadence stores, readable in any text editor. Keep it somewhere outside Cadence: automatic \
        backups live inside the app and are deleted when Cadence's data is. Import an Archive reads \
        one back in — but an import adds and never deletes, so this file is a copy to keep rather \
        than, on its own, a rewind to the day you exported it.
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
