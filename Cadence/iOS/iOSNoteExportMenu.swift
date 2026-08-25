#if os(iOS)
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// A note as a document the system exporter can write.
///
/// One document for both formats, with the type chosen at the `.fileExporter` call rather than by
/// having two near-identical `FileDocument`s — the bytes are already made by the time this exists,
/// so there is nothing format-shaped left for the type to decide.
///
/// `init(configuration:)` reads rather than throwing, for the same reason `CadenceArchiveDocument`
/// does: a document that can read what it writes is what makes a round trip assertable. Nothing
/// imports a note today.
nonisolated struct NoteExportDocument: FileDocument {
    nonisolated static var readableContentTypes: [UTType] { [.plainText, .pdf] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// **T-194.** Export a note as markdown or as a rendered PDF, from iOS.
///
/// macOS has had both since the note action picker existed; iOS had neither, and `ShareLink`
/// appeared nowhere under `Cadence/iOS` at all. Three things about this control are decisions
/// rather than accidents:
///
/// - **One menu, three headers.** The Notes tab's regular-width header, `iOSListNotesView`'s
///   header, and the compact editor cover's navigation bar all render *this* view rather than each
///   building a menu. A note therefore offers the same two formats wherever you reached it from —
///   the same rule `iOSNoteAIActionsMenu` follows for the same reason, and the reason
///   `CompactTagStrip` had to be de-duplicated three times.
/// - **`.fileExporter`, not `ShareLink`.** The ticket suggested a `ShareLink` over the export
///   string and it would work for markdown, but this repo already made this choice once:
///   `CadenceDataExportPresentation` records that `.fileExporter` is the one SwiftUI spelling that
///   works on both platforms. A share sheet for the markdown and a file picker for the PDF would be
///   two answers to "where does this go" inside one menu.
/// - **Render first, present second.** The bytes are made before the exporter opens, so a PDF that
///   could not be rendered surfaces as an alert instead of writing an empty file to a destination
///   the user has already chosen. Same order as the archive export.
struct iOSNoteExportMenu: View {
    let note: Note

    @Environment(\.modelContext) private var modelContext
    @State private var exportDocument: NoteExportDocument?
    @State private var exportFormat: NoteExportFormat?
    @State private var exportFilename = ""
    @State private var isExporting = false
    @State private var errorMessage: String?

    var body: some View {
        Menu {
            ForEach(NoteExportFormat.allCases) { format in
                Button {
                    prepareExport(as: format)
                } label: {
                    Label(format.actionTitle, systemImage: format.systemImage)
                }
            }
        } label: {
            label
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: exportFormat?.contentType ?? .plainText,
            defaultFilename: exportFilename
        ) { result in
            if case .failure(let error) = result {
                errorMessage = error.localizedDescription
            }
            exportDocument = nil
            exportFormat = nil
        }
        .alert("Export Failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// The same quiet 34pt tile `iOSNotesHeaderIconButton`, `iOSNoteTemplateMenu` and
    /// `iOSNoteAIActionsMenu` draw, at the same 44pt hit area — these controls sit in one row and
    /// are one kind of control. Blue stays reserved for the thing you came to the note to do.
    private var label: some View {
        iOSIconTile(systemImage: "square.and.arrow.up", color: Theme.muted, size: 34, iconSize: 13)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("Export note")
    }

    private func prepareExport(as format: NoteExportFormat) {
        let embeddedTasks = NoteExportSupport.embeddedTasks(in: note, modelContext: modelContext)
        let imageAssets = format == .pdf
            ? NoteExportSupport.referencedImageAssets(in: note, modelContext: modelContext)
            : []

        guard let data = iOSNoteExportService.exportData(
            for: note,
            as: format,
            imageAssets: imageAssets,
            embeddedTasks: embeddedTasks
        ) else {
            errorMessage = "Cadence could not render this note as a \(format.pathExtension.uppercased())."
            return
        }

        exportFormat = format
        exportFilename = NoteExportSupport.suggestedFilename(title: note.displayTitle, format: format)
        exportDocument = NoteExportDocument(data: data)
        isExporting = true
    }
}
#endif
