import CoreGraphics
import Foundation
import SwiftData
import UniformTypeIdentifiers

/// What a note can be exported as, and everything about that choice that is not a renderer.
///
/// This lived inside `macOS/Services/NoteExportService.swift`, inside its `#if os(macOS)`, along
/// with the page geometry below and the two lines that decide what a file is called and what text
/// goes in it. Unlike the seven services lifted out of that guard before it, `NoteExportService`
/// **is** genuinely AppKit-bound — it renders PDF by running the live editor styling over an
/// offscreen `NSTextView` and asking it for `dataWithPDF` — so it stays where it is. What comes out
/// here is the half that was never AppKit: the format list, the page box, the filename, and the
/// resolution of a note's live task titles.
///
/// **The point is drift, not tidiness.** iOS necessarily gets a *second* PDF renderer (T-194), and
/// two renderers that each decide their own page width, their own margins and their own filename
/// are two documents. They share these decisions, so the only thing either one owns is how it puts
/// glyphs on a page.
nonisolated enum NoteExportFormat: String, CaseIterable, Identifiable, Sendable {
    case markdown
    case pdf

    nonisolated var id: String { rawValue }

    nonisolated var pathExtension: String {
        switch self {
        case .markdown: return "md"
        case .pdf: return "pdf"
        }
    }

    nonisolated var contentType: UTType {
        switch self {
        case .markdown: return .plainText
        case .pdf: return .pdf
        }
    }

    /// The menu row, on both platforms. macOS's note action picker and the iOS export menu read
    /// these rather than spelling "Export PDF" twice — the same reason
    /// `CadenceDataExportPresentation` owns the archive card's every word.
    nonisolated var actionTitle: String {
        switch self {
        case .markdown: return "Export Markdown"
        case .pdf: return "Export PDF"
        }
    }

    nonisolated var systemImage: String {
        switch self {
        case .markdown: return "doc.text"
        case .pdf: return "doc.richtext"
        }
    }
}

/// The page a note is rendered onto, on either platform.
///
/// **One tall page, not paginated, and that is a decision.** A US Letter width with the note's full
/// height means a heading, a table or a task-embed card is never sliced across a page break, and it
/// is what the macOS exporter has always produced. Two renderers agreeing to paginate identically
/// would be a much harder promise to keep than two renderers agreeing not to.
nonisolated struct NotePDFRenderOptions: Equatable, Sendable {
    var pageWidth: CGFloat
    var horizontalInset: CGFloat
    var verticalInset: CGFloat
    var minimumHeight: CGFloat

    nonisolated init(
        pageWidth: CGFloat = 612,
        horizontalInset: CGFloat = 42,
        verticalInset: CGFloat = 42,
        minimumHeight: CGFloat = 240
    ) {
        self.pageWidth = pageWidth
        self.horizontalInset = horizontalInset
        self.verticalInset = verticalInset
        self.minimumHeight = minimumHeight
    }

    /// The width the text is laid out in, which is also the width a rendered block — an image, a
    /// table, a task-embed card — is measured against. Both renderers hand this to their styler, so
    /// a card is the same width in both documents.
    nonisolated var contentWidth: CGFloat {
        max(1, pageWidth - (horizontalInset * 2))
    }

    /// The page height for laid-out text of `contentHeight`, insets included.
    ///
    /// The floor is what stops an empty or one-line note exporting as a sliver: a PDF that is 612
    /// wide and 20 tall opens looking broken rather than short.
    nonisolated func documentHeight(forContentHeight contentHeight: CGFloat) -> CGFloat {
        max(ceil(contentHeight + (verticalInset * 2)), minimumHeight)
    }
}

/// The decisions both note exporters make before either one draws anything.
nonisolated enum NoteExportSupport {
    /// The suggested file name, extension included.
    ///
    /// An untitled note gets a name rather than a bare `.md`, because the destination on iOS is a
    /// share sheet or a Files picker where the name is the only thing distinguishing one export
    /// from the next.
    nonisolated static func suggestedFilename(title: String, format: NoteExportFormat) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.isEmpty ? CadenceTitleNormalization.defaultNoteTitle : trimmed) + ".\(format.pathExtension)"
    }

    /// The text that is exported, with every `[[task:UUID|Title]]` embed named by its **live** task.
    ///
    /// Both the markdown file and the PDF go through this, so an export never carries a title the
    /// task was renamed out of months ago.
    nonisolated static func resolvedContent(_ content: String, embeddedTasks: [AppTask]) -> String {
        MarkdownTaskEmbedTitleCache.resolving(content, tasks: embeddedTasks)
    }

    /// The embed map a PDF renderer needs.
    ///
    /// A renderer handed an empty map draws every task embed through
    /// `MarkdownTaskEmbedRenderInfo.missing(reference:)` — a "missing task" card carrying the stale
    /// cached title. That is what exporting a note used to do on macOS, and it is exactly the trap
    /// a second renderer would fall into independently.
    nonisolated static func taskEmbedRenderInfos(for tasks: [AppTask]) -> [UUID: MarkdownTaskEmbedRenderInfo] {
        Dictionary(
            tasks.map { ($0.id, MarkdownTaskEmbedRenderInfo.task($0)) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// The tasks a note embeds, fetched on demand.
    ///
    /// Fetched at export time rather than held in a `@Query`: the control that offers an export
    /// renders in every note header, and a live query of every task in the store behind a menu
    /// nobody has opened yet is a cost paid on every keystroke.
    static func embeddedTasks(in note: Note, modelContext: ModelContext) -> [AppTask] {
        MarkdownTaskEmbedTitleCache.embeddedTasks(in: note.content, modelContext: modelContext)
    }

    // MARK: - What the user is told when no file appears (T-506)

    /// An export can produce no file two ways, and both platforms say so in these words.
    ///
    /// **Shared for the reason the page box is shared, and the same failure proves it.** macOS
    /// wrote both formats with `try?` inside the save panel's completion and let a PDF that would
    /// not render leave through a bare `guard … else { return }` — so a user who had already chosen
    /// a destination got no file and no message, on the one path a TestFlight tester walks first.
    /// iOS reported both from the beginning, in words it had spelled itself. Copy that exists on
    /// one platform only is how the other platform comes to say nothing at all, so it lives here
    /// where a test can read it and neither exporter may restate it.
    ///
    /// This is deliberately *not* `CadenceDataExportPresentation`: that type owns the archive
    /// card's every word, including a description a view may not drop, and a note is not an
    /// archive. Two vocabularies, each spelled once.
    nonisolated static let failureAlertTitle = "Export Failed"

    /// The renderer produced no bytes. Named by format, because "could not render this note" is
    /// true of a PDF and never of markdown — encoding a Swift string as UTF-8 is total.
    nonisolated static func renderFailureMessage(for format: NoteExportFormat) -> String {
        "Cadence could not render this note as a \(format.pathExtension.uppercased())."
    }

    /// The bytes existed and did not reach the destination the user picked: a read-only folder, a
    /// full disk, a sandbox extent that has gone away. `reason` is the underlying
    /// `localizedDescription`, which is the only part that says *which*.
    nonisolated static func writeFailureMessage(_ reason: String) -> String {
        "Cadence could not write the file: \(reason)"
    }

    /// The image assets a note references, and only those.
    ///
    /// `MarkdownImageAsset.data` is externally stored and can run to megabytes, so the fetch is
    /// gated on the note referencing anything at all before it touches the store.
    static func referencedImageAssets(in note: Note, modelContext: ModelContext) -> [MarkdownImageAsset] {
        let referencedIDs = MarkdownImageAssetService.referencedIDs(in: note.content)
        guard !referencedIDs.isEmpty else { return [] }
        let descriptor = FetchDescriptor<MarkdownImageAsset>()
        return ((try? modelContext.fetch(descriptor)) ?? []).filter { referencedIDs.contains($0.id) }
    }
}
