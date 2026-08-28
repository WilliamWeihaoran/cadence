#if os(macOS)
import AppKit
import SwiftData
import Testing
@testable import Cadence

@MainActor
@Suite(.serialized)
struct MarkdownImageAssetServiceTests {
    @Test func extractsStandaloneCadenceImageReferences() {
        let firstID = UUID()
        let secondID = UUID()
        let markdown = """
        Intro

        ![Diagram](cadence-image://\(firstID.uuidString))
        Inline ![ignored](cadence-image://\(UUID().uuidString)) text
        ![](cadence-image://\(secondID.uuidString))
        """

        let references = MarkdownImageAssetService.standaloneReferences(in: markdown)

        #expect(references.map(\.id) == [firstID, secondID])
        #expect(references.map(\.altText) == ["Diagram", ""])
    }

    /// Alt text written before escaping existed can end in a lone backslash. The widened
    /// pattern's `\\.` branch swallows the closing `]` unless the trailing `\\?` lets the
    /// backslash stand alone — and an unmatched reference is what gets the image collected.
    @Test func legacyAltTextEndingInABackslashStillResolvesItsAsset() {
        let id = UUID()
        for label in [#"photo\"#, #"C:\path\"#, #"a\"#, #"\"#] {
            let text = "![\(label)](cadence-image://\(id.uuidString))"
            let references = MarkdownImageAssetService.standaloneReferences(in: text)
            #expect(references.count == 1, "alt text \(label) must still resolve its asset")
            #expect(references.first?.id == id)
        }
    }

    @Test func altTextContainingABracketStillResolvesItsAsset() {
        // A file called "chart [v2].png" seeds that alt text. If the emitted reference stops
        // matching, the note renders raw markdown *and* the asset reads as unreferenced — which
        // is what deletes the image data out from under a live reference.
        let asset = MarkdownImageAsset(
            data: Data([1]),
            mimeType: "image/png",
            originalFilename: "chart [v2].png",
            altText: "chart [v2]",
            pixelWidth: 100,
            pixelHeight: 80,
            displayWidth: 100
        )
        let markdown = MarkdownImageAssetService.markdown(for: asset)

        let references = MarkdownImageAssetService.standaloneReferences(in: markdown)

        #expect(references.map(\.id) == [asset.id])
        #expect(references.first?.altText == "chart [v2]")
        #expect(MarkdownImageAssetService.unreferencedAssets(allAssets: [asset], markdownTexts: [markdown]).isEmpty)
    }

    @Test func referencesAlreadyWrittenWithAnEscapedBracketStillResolve() {
        let id = UUID()
        let markdown = "![chart [v2\\]](cadence-image://\(id.uuidString))"

        #expect(MarkdownImageAssetService.standaloneReferences(in: markdown).map(\.id) == [id])
        #expect(MarkdownImageAssetService.standaloneReferences(in: markdown).first?.altText == "chart [v2]")
    }

    @Test func findsUnreferencedAssetsAcrossMarkdownFields() {
        let referencedID = UUID()
        let orphanID = UUID()
        let referenced = MarkdownImageAsset(
            data: Data([1]),
            mimeType: "image/png",
            pixelWidth: 100,
            pixelHeight: 80,
            displayWidth: 100
        )
        referenced.id = referencedID
        let orphan = MarkdownImageAsset(
            data: Data([2]),
            mimeType: "image/png",
            pixelWidth: 100,
            pixelHeight: 80,
            displayWidth: 100
        )
        orphan.id = orphanID

        let unused = MarkdownImageAssetService.unreferencedAssets(
            allAssets: [referenced, orphan],
            markdownTexts: ["![used](cadence-image://\(referencedID.uuidString))"]
        )

        #expect(unused.map(\.id) == [orphanID])
    }

    /// **T-350, at the predicate.** `unreferencedAssets` is the lifecycle question, and an image
    /// written inside a sentence is a reference to it. It used to reuse the rendering predicate —
    /// standalone lines only — so this asset read as garbage while a note was still showing it.
    @Test func inlineImageReferenceKeepsItsAssetOutOfTheUnreferencedSweep() {
        let inlineID = UUID()
        let orphanID = UUID()
        let inlineAsset = MarkdownImageAsset(
            data: Data([1]),
            mimeType: "image/png",
            pixelWidth: 100,
            pixelHeight: 80,
            displayWidth: 100
        )
        inlineAsset.id = inlineID
        let orphanAsset = MarkdownImageAsset(
            data: Data([2]),
            mimeType: "image/png",
            pixelWidth: 100,
            pixelHeight: 80,
            displayWidth: 100
        )
        orphanAsset.id = orphanID
        let survivingNote = "See ![the chart](cadence-image://\(inlineID.uuidString)) before Friday."

        let collected = MarkdownImageAssetService.unreferencedAssets(
            allAssets: [inlineAsset, orphanAsset],
            markdownTexts: [survivingNote]
        )

        #expect(!collected.contains { $0.id == inlineID })
        #expect(collected.map(\.id) == [orphanID])
        #expect(MarkdownImageAssetService.referencedIDs(in: survivingNote).contains(inlineID))
    }

    /// The other half of the split, and the reason the shared predicate was **not** widened: an
    /// inline reference is paragraph text. It must not become an image block, must not be a
    /// deletable rendered block, and must not reach the renderer's asset table. This passes before
    /// the T-350 fix as well as after — it is what keeps the fix from being made by widening.
    @Test func inlineImageReferenceStillDoesNotRenderAsABlock() {
        let id = UUID()
        let line = "See ![the chart](cadence-image://\(id.uuidString)) before Friday."

        #expect(MarkdownBlockSupport.standaloneImageReference(in: line) == nil)
        #expect(MarkdownRenderedBlockDeletionSupport.renderedBlockRanges(in: line).isEmpty)
        #expect(!MarkdownImageAssetService.standaloneReferencedIDs(in: line).contains(id))

        // ... while the block form still is one, on both counts.
        let block = "![the chart](cadence-image://\(id.uuidString))"
        #expect(MarkdownBlockSupport.standaloneImageReference(in: block)?.id == id)
        #expect(MarkdownImageAssetService.standaloneReferencedIDs(in: block) == [id])
        #expect(MarkdownImageAssetService.referencedIDs(in: block) == [id])
    }

    @Test func createsImageAssetWithMetadataAndDisplayWidth() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let image = testImage(size: CGSize(width: 800, height: 400))

        let asset = try #require(MarkdownImageAssetService.createAsset(
            from: image,
            originalFilename: "diagram.png",
            altText: "Diagram",
            in: context
        ))

        #expect(asset.originalFilename == "diagram.png")
        #expect(asset.altText == "Diagram")
        #expect(asset.data.isEmpty == false)
        #expect(asset.pixelWidth == 800)
        #expect(asset.pixelHeight == 400)
        // The literal, not the production constant read back: `== defaultDisplayWidth` is true of
        // an implementation that ignores the image's own width entirely.
        #expect(asset.displayWidth == 520)
        #expect(["image/png", "image/jpeg"].contains(asset.mimeType))
    }

    /// The two clamps around the initial display width, each exercised from the side its input
    /// actually lands on. Every existing test used an 800px image, which sits past both of them —
    /// so `min(defaultDisplayWidth, pixelWidth)` could be replaced by `defaultDisplayWidth` and
    /// `max(minDisplayWidth,)` deleted outright with the suite still green, while every narrow
    /// image in the editor — a 200px icon, a screenshot crop — silently upscaled to 520pt.
    @Test func narrowImagesKeepTheirOwnWidthAndTinyOnesFloorAtTheMinimum() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        // Between the floor (120) and the default (520): its own width, untouched.
        let narrow = try #require(MarkdownImageAssetService.createAsset(
            from: testImage(size: CGSize(width: 200, height: 100)),
            in: context
        ))
        #expect(narrow.pixelWidth == 200)
        #expect(narrow.displayWidth == 200)

        // Below the floor: raised to it, not left at 40.
        let tiny = try #require(MarkdownImageAssetService.createAsset(
            from: testImage(size: CGSize(width: 40, height: 40)),
            in: context
        ))
        #expect(tiny.pixelWidth == 40)
        #expect(tiny.displayWidth == 120)

        // Exactly on the default is still the default, from the other side of the `min`.
        let exact = try #require(MarkdownImageAssetService.createAsset(
            from: testImage(size: CGSize(width: 520, height: 260)),
            in: context
        ))
        #expect(exact.displayWidth == 520)
    }

    /// `setDisplayWidth` is the drag-to-resize handler in the markdown editor, and its clamp had
    /// no test at all — a drag past either end could write a width the editor then draws with.
    @Test func setDisplayWidthClampsToBothEndsAndIgnoresUnknownAssets() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let asset = try #require(MarkdownImageAssetService.createAsset(
            from: testImage(size: CGSize(width: 800, height: 400)),
            in: context
        ))

        MarkdownImageAssetService.setDisplayWidth(5_000, for: asset.id, in: [asset])
        #expect(asset.displayWidth == 1_200)

        MarkdownImageAssetService.setDisplayWidth(5, for: asset.id, in: [asset])
        #expect(asset.displayWidth == 120)

        // In range: written through unchanged, so the clamp is not a constant.
        MarkdownImageAssetService.setDisplayWidth(300, for: asset.id, in: [asset])
        #expect(asset.displayWidth == 300)

        // An id that is not in the array must leave every asset alone.
        MarkdownImageAssetService.setDisplayWidth(900, for: UUID(), in: [asset])
        #expect(asset.displayWidth == 300)
    }

    /// Public, called straight from `MarkdownInlinePreviewSupport`, and previously covered only
    /// indirectly through `references(in:)`.
    @Test func unescapedAltTextUndoesTheEscapesTheWriterAdds() {
        #expect(MarkdownImageAssetService.unescapedAltText("Plain caption") == "Plain caption")
        // The two escapes the writer emits, undone.
        #expect(MarkdownImageAssetService.unescapedAltText(#"closing \] bracket"#) == "closing ] bracket")
        #expect(MarkdownImageAssetService.unescapedAltText(#"back\\slash"#) == #"back\slash"#)
        // An escaped backslash immediately before a real `]` must not eat the bracket.
        #expect(MarkdownImageAssetService.unescapedAltText(#"trailing\\"#) == #"trailing\"#)
        // A backslash before anything else predates the escaping and is left alone.
        #expect(MarkdownImageAssetService.unescapedAltText(#"C:\path"#) == #"C:\path"#)
    }

    @Test func downscalesOversizedImagesToLongEdgeLimit() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let image = testImage(size: CGSize(width: 3_000, height: 1_200))

        let asset = try #require(MarkdownImageAssetService.createAsset(from: image, in: context))

        #expect(max(asset.pixelWidth, asset.pixelHeight) <= Int(MarkdownImageAssetService.maxLongEdge))
        #expect(asset.pixelWidth == 2_400)
        #expect(asset.pixelHeight == 960)
    }

    @Test func notePDFExportRendersMarkdownImages() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let image = testImage(size: CGSize(width: 320, height: 180))
        let asset = try #require(MarkdownImageAssetService.createAsset(from: image, in: context))
        let content = """
        # Export

        ![Preview](cadence-image://\(asset.id.uuidString))

        After image.
        """

        let data = try #require(NoteExportService.renderedPDFData(content: content, imageAssets: [asset]))
        // The same note rendered without the asset registered: the reference line stays as raw
        // text and no bitmap is embedded. Anything that distinguishes the two has to compare
        // against *this*, not against a size floor — a text-only page clears 1 KB comfortably, so
        // `count > 1_000` was satisfied by a PDF containing no image at all.
        let withoutImage = try #require(NoteExportService.renderedPDFData(content: content, imageAssets: []))

        #expect(data.starts(with: Data("%PDF".utf8)))
        #expect(withoutImage.starts(with: Data("%PDF".utf8)))

        // A PDF that draws a bitmap carries an image XObject; a text-only page does not. This is
        // the only assertion here that is *about the image* — `count > 1_000` was true of a
        // text-only render, and the un-rendered variant is in fact the longer document, because
        // the raw `![Preview](cadence-image://…)` line stays visible in it.
        #expect(contains(data, "/Subtype/Image") || contains(data, "/Subtype /Image"))
        #expect(!contains(withoutImage, "/Subtype/Image") && !contains(withoutImage, "/Subtype /Image"))
    }

    private func contains(_ data: Data, _ marker: String) -> Bool {
        data.range(of: Data(marker.utf8)) != nil
    }

    private func testImage(size: CGSize) -> NSImage {
        let width = Int(size.width)
        let height = Int(size.height)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        if let bitmapData = rep.bitmapData {
            for y in 0..<height {
                for x in 0..<width {
                    let offset = y * rep.bytesPerRow + x * 4
                    bitmapData[offset] = UInt8((x + y) % 255)
                    bitmapData[offset + 1] = UInt8((x * 2) % 255)
                    bitmapData[offset + 2] = UInt8((y * 2) % 255)
                    bitmapData[offset + 3] = 255
                }
            }
        }
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }
}
#endif
