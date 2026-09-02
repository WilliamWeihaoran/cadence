import CoreGraphics
import Foundation
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import Cadence

/// **T-194.** macOS has exported a note as markdown or as a rendered PDF for as long as the note
/// action picker has existed. iOS had neither, and `ShareLink` appeared nowhere under
/// `Cadence/iOS/` at all.
///
/// Unlike the seven capabilities lifted out of `#if os(macOS)` before it, `NoteExportService` is
/// genuinely AppKit-bound — it renders PDF by running `MarkdownStylist.apply` over an offscreen
/// `NSTextView` and asking for `dataWithPDF`. So iOS gets a **second renderer**, and the whole risk
/// of this ticket is that two renderers drift into two documents. The defence is that every
/// decision either one makes about the page, the filename or the text is in `Services/`, where this
/// macOS-built target can assert it at the value level, and neither renderer may restate one.
///
/// Two kinds of test here, and the second kind is the point: the values, and then a scan proving
/// the two renderers actually read them. A shared decision with one reader is not a convergence —
/// the same lesson `MarkdownHeadingRampTests` records.
struct NoteExportSurfaceTests {

    // MARK: - The shared decisions, as values

    /// Both formats, on both platforms. A format the Mac offers and the phone does not is the whole
    /// class of bug this ticket is in.
    @Test func bothFormatsAreOffered() {
        #expect(NoteExportFormat.allCases == [.markdown, .pdf])
        #expect(NoteExportFormat.markdown.pathExtension == "md")
        #expect(NoteExportFormat.pdf.pathExtension == "pdf")
        #expect(NoteExportFormat.markdown.contentType == .plainText)
        #expect(NoteExportFormat.pdf.contentType == .pdf)
    }

    /// The row title and glyph belong to the format, so the two platforms' menus cannot come to
    /// call the same file two things.
    @Test func aFormatCarriesItsOwnMenuRow() {
        #expect(NoteExportFormat.markdown.actionTitle == "Export Markdown")
        #expect(NoteExportFormat.pdf.actionTitle == "Export PDF")
        #expect(Set(NoteExportFormat.allCases.map(\.systemImage)).count == NoteExportFormat.allCases.count)
        #expect(NoteExportFormat.allCases.allSatisfy { !$0.actionTitle.isEmpty })
    }

    /// An untitled note gets a name rather than a bare `.md`. On iOS the destination is a Files
    /// picker where the suggested name is the only thing separating one export from the next.
    @Test func anUntitledNoteStillGetsAFilename() {
        #expect(NoteExportSupport.suggestedFilename(title: "", format: .markdown) == "Untitled Note.md")
        #expect(NoteExportSupport.suggestedFilename(title: "   \n ", format: .pdf) == "Untitled Note.pdf")
    }

    @Test func aFilenameIsTheTitleTrimmedPlusTheFormatsExtension() {
        #expect(NoteExportSupport.suggestedFilename(title: "  Weekly Review  ", format: .markdown) == "Weekly Review.md")
        #expect(NoteExportSupport.suggestedFilename(title: "Weekly Review", format: .pdf) == "Weekly Review.pdf")
    }

    /// The page box, and the two derived figures both renderers lay out against. `contentWidth` is
    /// also what a rendered block — an image, a table, a task-embed card — is measured against, so a
    /// renderer that computed its own would produce cards of a different width.
    ///
    /// **The content-width line is bound to a `let`, and it has to be.** It was written
    /// `#expect(options.contentWidth == 612 - 84)`, which **fails on the correct value**: `#expect`
    /// captures each operand of a binary expression separately, and an unannotated arithmetic
    /// expression beside a `CGFloat` gets inferred as `Double` in that capture, so the macro
    /// compares a `CGFloat` box against a `Double` box and reports
    /// `(options.contentWidth → 528.0) == (612 - 84 → 528)`. Plain Swift evaluates the same
    /// expression to `true`. Reproduced against the toolchain in isolation: `== 528`, `== someCGFloat`
    /// and `== CGFloat(612 - 84)` all pass, `== 612 - 84` and `== 612.0 - 84.0` both fail, and the
    /// same arithmetic against a `Double` passes — so it is `CGFloat` beside an arithmetic operand,
    /// not this page box. Written as spelled, the line had **no** discriminating power: it was red
    /// whatever `contentWidth` returned. The `let` keeps the derivation visible and restores it.
    @Test func thePageBoxIsOneSetOfNumbers() {
        let options = NotePDFRenderOptions()
        let expectedContentWidth: CGFloat = 612 - 84

        #expect(options.pageWidth == 612)
        #expect(options.horizontalInset == 42)
        #expect(options.verticalInset == 42)
        #expect(options.minimumHeight == 240)
        #expect(options.contentWidth == expectedContentWidth)
    }

    /// The floor is what stops a one-line note exporting as a 612x20 sliver that opens looking
    /// broken. Above the floor the height is the text plus both insets.
    @Test func theDocumentHeightIsTheTextPlusInsetsAboveAFloor() {
        let options = NotePDFRenderOptions()

        #expect(options.documentHeight(forContentHeight: 0) == 240)
        #expect(options.documentHeight(forContentHeight: 100) == 240)
        #expect(options.documentHeight(forContentHeight: 400) == 484)
        #expect(options.documentHeight(forContentHeight: 400.2) == 485)
    }

    @Test func thePageBoxIsConfigurable() {
        let narrow = NotePDFRenderOptions(pageWidth: 400, horizontalInset: 20, verticalInset: 10, minimumHeight: 50)

        #expect(narrow.contentWidth == 360)
        #expect(narrow.documentHeight(forContentHeight: 100) == 120)
        #expect(narrow.documentHeight(forContentHeight: 5) == 50)
    }

    // MARK: - The text that is exported

    /// An export names every `[[task:UUID|Title]]` embed by its **live** task, so it never carries a
    /// title the task was renamed out of months ago. Both formats go through this, on both
    /// platforms.
    @Test func anExportCarriesTheLiveTaskTitleNotTheCachedOne() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Ship the release")
        context.insert(task)

        let content = "Before\n\n[[task:\(task.id.uuidString)|Ship the beta]]\n\nAfter"
        let resolved = NoteExportSupport.resolvedContent(content, embeddedTasks: [task])

        #expect(resolved.contains("Ship the release"))
        #expect(!resolved.contains("Ship the beta"))
    }

    /// A note that embeds nothing comes out byte-identical, which is what makes markdown export
    /// lossless for the overwhelming majority of notes.
    @Test func aNoteWithNoEmbedsIsExportedUnchanged() {
        let content = "# Heading\n\nA paragraph with `code` and a [link](https://example.com).\n"

        #expect(NoteExportSupport.resolvedContent(content, embeddedTasks: []) == content)
    }

    /// The embed map a PDF renderer needs. Handed an empty one, a renderer draws every task embed
    /// as a "missing task" card carrying the stale cached title — which is what macOS's export used
    /// to do, and exactly the trap a second renderer falls into on its own.
    @Test func theEmbedMapIsKeyedByTaskIDAndCarriesTheLiveTask() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let first = AppTask(title: "First")
        let second = AppTask(title: "Second")
        context.insert(first)
        context.insert(second)

        let infos = NoteExportSupport.taskEmbedRenderInfos(for: [first, second])

        #expect(infos.count == 2)
        #expect(infos[first.id]?.title == "First")
        #expect(infos[second.id]?.title == "Second")
        #expect(infos[first.id]?.isMissing == false)
    }

    /// The fetch that keeps a note header cheap. `MarkdownImageAsset.data` is externally stored and
    /// runs to megabytes, so a note referencing no image must not touch the store at all — and a
    /// note referencing one must not drag in every other note's images.
    @Test func onlyTheImagesANoteActuallyReferencesAreFetched() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let referenced = imageAsset(0x1)
        let unreferenced = imageAsset(0x2)
        context.insert(referenced)
        context.insert(unreferenced)

        let empty = Note(kind: .permanent, title: "No images", content: "Just words")
        let withImage = Note(
            kind: .permanent,
            title: "One image",
            content: "![](cadence-image://\(referenced.id.uuidString))"
        )
        context.insert(empty)
        context.insert(withImage)

        #expect(NoteExportSupport.referencedImageAssets(in: empty, modelContext: context).isEmpty)
        #expect(NoteExportSupport.referencedImageAssets(in: withImage, modelContext: context).map(\.id) == [referenced.id])
    }

    // MARK: - The two renderers, which are the actual risk

    private static let renderers = [
        "Cadence/macOS/Services/NoteExportService.swift",
        "Cadence/iOS/iOSNoteExportService.swift",
    ]

    /// **The regression this file exists to catch.** Either renderer re-spelling the page geometry
    /// is the drift the ticket predicted. Neither may contain the numbers; both must take
    /// `NotePDFRenderOptions` and ask it.
    @Test func neitherRendererSpellsThePageGeometryItself() throws {
        for path in Self.renderers {
            let code = strippingNoteExportComments(try noteExportSource(path))

            #expect(code.contains("NotePDFRenderOptions"), "\(path) does not take the shared page box")
            #expect(code.contains("options.contentWidth"), "\(path) computes its own content width")
            #expect(code.contains("options.documentHeight("), "\(path) computes its own page height")
            #expect(!code.contains("612"), "\(path) re-spells the page width")
            #expect(!code.contains("minimumHeight)"), "\(path) applies the height floor itself")
        }
    }

    /// The filename and the live-title resolution are shared too, and for the same reason: two
    /// exporters that each trim their own title are two answers to "what is this file called".
    @Test func neitherExporterSpellsTheFilenameOrTheTitleResolutionItself() throws {
        for path in Self.renderers {
            let code = strippingNoteExportComments(try noteExportSource(path))
            guard code.contains("suggestedFilename") || code.contains("resolvedContent") else { continue }

            #expect(!code.contains("Untitled Note"), "\(path) re-spells the untitled fallback")
            #expect(!code.contains("MarkdownTaskEmbedTitleCache.resolving"), "\(path) re-spells the title resolution")
        }
    }

    /// `NoteExportFormat` and `NotePDFRenderOptions` are declared **once**, in `Services/`, where
    /// this target can reach them. They were inside `NoteExportService`'s `#if os(macOS)`, which is
    /// why iOS could not have named a format even if it had a renderer.
    @Test func theExportVocabularyIsDeclaredOnceAndOutsideThePlatformGuard() throws {
        var declarations: [String] = []

        for path in try noteExportSwiftFiles() {
            let code = strippingNoteExportComments(try noteExportSource(path))
            if code.contains("enum NoteExportFormat") || code.contains("struct NotePDFRenderOptions") {
                declarations.append(path)
            }
        }

        #expect(declarations == ["Cadence/Services/CadenceNoteExportSupport.swift"], "\(declarations)")
    }

    /// The iOS renderer must lay out through `iOSMarkdownBlockCanvasLayoutManager`, not a plain
    /// `NSLayoutManager`. Tables, fenced code, dividers, images and task-embed cards are not glyphs
    /// on iOS — they are images hung on `cadenceMarkdownBlockCanvas` over a hidden run and painted
    /// by that subclass's `drawGlyphs`. A plain layout manager exports a PDF with a tall empty gap
    /// where each of them should be, which is precisely the bug that attribute exists to fix and is
    /// invisible in any test that only checks the bytes are a PDF.
    @Test func theIOSRendererDrawsThroughTheBlockCanvasLayoutManager() throws {
        let code = strippingNoteExportComments(try noteExportSource("Cadence/iOS/iOSNoteExportService.swift"))

        #expect(code.contains("iOSMarkdownBlockCanvasLayoutManager()"))
        #expect(code.contains("iOSMarkdownStyler.attributedString"), "the export styles a note differently from the editor")
        #expect(code.contains("contentWidth: contentWidth"), "the styler is not measured at the page's content width")
    }

    /// The iOS export control is **one** view rendered by three headers, not three menus. The same
    /// rule `iOSNoteAIActionsMenu` follows, and the reason `CompactTagStrip` had to be
    /// de-duplicated three times.
    @Test func theIOSExportControlIsOneViewWithThreeCallSites() throws {
        var declarations: [String] = []
        var callSites: [String] = []

        for path in try noteExportSwiftFiles() {
            let code = strippingNoteExportComments(try noteExportSource(path))
            if code.contains("struct iOSNoteExportMenu") { declarations.append(path) }
            if code.contains("iOSNoteExportMenu(note:") { callSites.append(path) }
        }

        #expect(declarations == ["Cadence/iOS/iOSNoteExportMenu.swift"])
        #expect(callSites.sorted() == [
            "Cadence/iOS/iOSListNotesView.swift",
            "Cadence/iOS/iOSNotesView.swift",
        ], "\(callSites.sorted())")
    }

    /// Non-vacuity. Every assertion above is a count or an absence over files read off disk; if the
    /// read silently returned nothing they would all pass.
    @Test func theScannerIsReadingRealSourceInNoteExportSurface() throws {
        let shared = try noteExportSource("Cadence/Services/CadenceNoteExportSupport.swift")

        #expect(shared.contains("enum NoteExportFormat"))
        #expect(shared.contains("struct NotePDFRenderOptions"))
        #expect(try noteExportSwiftFiles().count > 300)
        #expect(strippingNoteExportComments("let x = 1 // struct NotePDFRenderOptions").contains("NotePDFRenderOptions") == false)
    }

    // MARK: - An export that produces no file (T-506)

    /// `try?` over the write that produces the file, anywhere under `Cadence/`.
    ///
    /// **Why this is a sweep and not a line in the `try? save()` rule.** T-508 measured that rule's
    /// needle against `write(to:)` and deliberately left it out: a swallowed file write has no
    /// pending change to be left in, and nothing after it reports success in source, because the
    /// report *is* the absence of an error sheet. So the shape is real and that rule cannot see it.
    /// This is the guard that can.
    private static let swallowedWrite = "try\\?[^\\n]*\\.write\\(to:"

    private static func swallowedWriteInstrument() throws -> CadenceScanInstrument {
        try CadenceScanInstrument(
            "swallowedFileWrite",
            fires: "try? content.write(to: url, atomically: true, encoding: .utf8)",
            andNotOn: "try content.write(to: url, atomically: true, encoding: .utf8)",
            by: { source in
                CadenceSourceScan.matchCount(Self.swallowedWrite, in: CadenceSourceScan.codeOnly(source)) > 0
            }
        )
    }

    /// **The T-506 regression.** macOS wrote both formats with `try?` inside the save panel's
    /// completion, so a refused write — a read-only folder, a full disk, a revoked sandbox extent —
    /// left the user having chosen a destination and receiving neither a file nor a word about it.
    ///
    /// Swept over the whole app rather than pinned to the one file: the two sites were the only
    /// swallowed writes in `Cadence/` when this was written, and a sweep is what keeps the third
    /// one from being added quietly.
    @Test func noExportSwallowsTheWriteThatProducesTheFile() throws {
        let instrument = try Self.swallowedWriteInstrument()

        let offenders = try instrument.sweep(
            try CadenceSourceScan.swiftFiles(under: "Cadence"),
            atLeast: 300,
            including: "Cadence/macOS/Services/NoteExportService.swift",
            read: { try CadenceSourceScan.sourceFile($0) }
        )

        #expect(offenders.isEmpty, "\(offenders)")
    }

    /// The detector reads **code**, and here that is load-bearing rather than hygienic: the fix's
    /// own doc comment quotes the line it removed, and `CadenceSaveCommitDisciplineTests` carries
    /// the same text as a fixture. A sweep that counted prose would accuse the files explaining the
    /// rule.
    @Test func theSwallowedWriteDetectorReadsCodeAndNotTheCommentDescribingIt() throws {
        let instrument = try Self.swallowedWriteInstrument()

        #expect(instrument.fires(on: "try? pdfData.write(to: url)"))
        #expect(!instrument.fires(on: "// was try? pdfData.write(to: url)"))
        #expect(!instrument.fires(on: "let sample = \"try? pdfData.write(to: url)\""))
    }

    /// An export can produce no file two ways, and macOS said nothing for **both**: the write was
    /// swallowed, and a PDF that failed to render left through a bare `guard … else { return }`.
    /// iOS reported both from the start, which is what made the asymmetry a defect rather than a
    /// missing feature.
    ///
    /// **Scoped to `export`'s own body, and that is the whole care in this test.** The file holds a
    /// second, entirely correct `else { return }` — the save panel's cancel guard, where a user who
    /// pressed Cancel must be told nothing at all. A file-wide assertion could not tell the two
    /// apart, so it would either pass on the defect or fail on the fix.
    @Test func theMacExporterReportsBothWaysAnExportCanProduceNoFile() throws {
        let code = strippingNoteExportComments(
            try noteExportSource("Cadence/macOS/Services/NoteExportService.swift")
        )
        let body = try #require(
            CadenceSourceScan.functionBody(named: "export", in: code),
            "export() is not where this scan thinks it is"
        )

        #expect(body.contains("catch"), "the export has no failure branch at all")
        #expect(body.contains("NoteExportSupport.writeFailureMessage("), "a refused write is not reported")
        #expect(body.contains("NoteExportSupport.renderFailureMessage("), "a PDF that did not render is not reported")
        #expect(!body.contains("else { return }"), "a failure still leaves through a bare guard")
    }

    /// The other half of the pair above: **cancelling** stays silent. An alert saying the export
    /// failed because the user pressed Cancel would be a worse bug than the one T-506 fixed, and it
    /// is the obvious way to overshoot the fix.
    @Test func cancellingTheSavePanelReportsNothing() throws {
        let code = strippingNoteExportComments(
            try noteExportSource("Cadence/macOS/Services/NoteExportService.swift")
        )
        let body = try #require(CadenceSourceScan.functionBody(named: "presentSavePanel", in: code))

        #expect(body.contains("guard response == .OK"), "the cancel guard is not where this scan thinks it is")
        #expect(!body.contains("presentFailure("), "cancelling raises an export-failed alert")
    }

    /// The failure copy is shared, so the two platforms cannot come to describe the same failure two
    /// ways — the same rule the page box, the filename and the title resolution already follow, and
    /// the rule whose absence *was* the defect: macOS had no words for either failure.
    @Test func neitherExporterSpellsTheFailureCopyItself() throws {
        #expect(NoteExportSupport.failureAlertTitle == "Export Failed")
        #expect(NoteExportSupport.renderFailureMessage(for: .pdf) == "Cadence could not render this note as a PDF.")
        #expect(NoteExportSupport.renderFailureMessage(for: .markdown) == "Cadence could not render this note as a MD.")
        #expect(NoteExportSupport.writeFailureMessage("Permission denied") == "Cadence could not write the file: Permission denied")

        for path in ["Cadence/macOS/Services/NoteExportService.swift", "Cadence/iOS/iOSNoteExportMenu.swift"] {
            let code = strippingNoteExportComments(try noteExportSource(path))

            #expect(!code.contains("could not render this note"), "\(path) re-spells the render failure")
            #expect(!code.contains("Export Failed"), "\(path) re-spells the alert title")
            #expect(
                code.contains("NoteExportSupport.writeFailureMessage("),
                "\(path) does not report a refused write through the shared copy"
            )
        }
    }

    private func imageAsset(_ byte: UInt8) -> MarkdownImageAsset {
        MarkdownImageAsset(
            data: Data([byte]),
            mimeType: "image/png",
            pixelWidth: 20,
            pixelHeight: 20,
            displayWidth: 20
        )
    }

    private func makeContainer() throws -> ModelContainer {
        try CadenceTestStore.container()
    }
}

private func noteExportRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func noteExportSwiftFiles() throws -> [String] {
    let directory = noteExportRepositoryRoot().appendingPathComponent("Cadence")
    guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else { return [] }
    return enumerator.compactMap { element in
        guard let relativePath = element as? String, relativePath.hasSuffix(".swift") else { return nil }
        return "Cadence/\(relativePath)"
    }
}

private func noteExportSource(_ relativePath: String) throws -> String {
    try String(contentsOf: noteExportRepositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

private func strippingNoteExportComments(_ source: String) -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound)))
        }
    }
    return result
}
