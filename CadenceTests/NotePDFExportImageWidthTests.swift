import Foundation
import SwiftData
import Testing
#if os(macOS)
import AppKit
#endif
@testable import Cadence

#if os(macOS)
/// A standalone image in an exported PDF must be given a line fragment it fits inside.
///
/// This is [[T-1043]]'s defect in the surface that still ships it. `MarkdownStylist.applyImageBlock`
/// reserves an image line's height from `textView.bounds.width`, and `CadenceTextView`'s draw pass
/// re-derives the drawn size from `bounds.width` when it paints. In the editor those two agree
/// because `MarkdownEditorScrollView.layout()` calls `MarkdownStylist.refreshImageBlockLayout` on
/// every width change. `NoteExportService.renderedPDFData` builds its text view offscreen, in a
/// scroll view it never has, in a window it never enters — nothing lays it out, so nothing calls
/// that reader.
///
/// The order it was written in made that fatal: the view was constructed `frame: .zero`, styled,
/// measured with `usedRect`, and only *then* given `options.pageWidth`. So the image reserved its
/// height against a zero width and was painted against the page width.
///
/// Everything below is measured through the shipped entry point — `renderedPDFData` — and read back
/// off the PDF it returns, rather than off a replica of its construction. `NotePDFRenderOptions`
/// is public and its `minimumHeight` floor is settable, which is what makes the page height a
/// usable proxy for the height the document reserved: with the floor out of the way,
/// `documentHeight(forContentHeight:)` is `ceil(usedRect.height) + 2 × verticalInset`.
@MainActor
struct NotePDFExportImageWidthTests {
    /// 16:9, so a wrong reservation and a right one are hundreds of points apart rather than tens.
    private static let pixelSize = CGSize(width: 640, height: 360)

    /// Shipped defaults: 612pt page, 42pt insets.
    private static let defaults = NotePDFRenderOptions()

    /// The same defaults with the sliver floor removed, so the page height tracks the content
    /// instead of being clamped to 240pt. Without this every measurement here reads the floor.
    private static let unfloored = NotePDFRenderOptions(minimumHeight: 1)

    // MARK: - Fixture

    private func makeAsset() throws -> MarkdownImageAsset {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        return try #require(
            MarkdownImageAssetService.createAsset(from: solidImage(size: Self.pixelSize), in: context)
        )
    }

    private func solidImage(size: CGSize) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let image = NSImage(size: NSSize(width: size.width, height: size.height))
        image.addRepresentation(rep)
        image.lockFocus()
        Theme.nsBlue.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.unlockFocus()
        return image
    }

    private func imageLine(_ asset: MarkdownImageAsset) -> String {
        "![banner](cadence-image://\(asset.id.uuidString))"
    }

    /// The height of the page `renderedPDFData` produced, read from the PDF itself.
    private func pageHeight(
        _ content: String,
        assets: [MarkdownImageAsset],
        options: NotePDFRenderOptions
    ) throws -> CGFloat {
        let data = try #require(
            NoteExportService.renderedPDFData(content: content, imageAssets: assets, options: options)
        )
        return try #require(NSPDFImageRep(data: data)).bounds.height
    }

    /// The height the draw pass paints the picture at, from the width the exported page has.
    ///
    /// Same two helpers `CadenceTextView.drawMarkdownImages` and `MarkdownStylist.applyImageBlock`
    /// use, handed the width the export view ends up with, so this restates none of their literals.
    private func drawnImageHeight(
        for asset: MarkdownImageAsset,
        options: NotePDFRenderOptions
    ) -> CGFloat {
        let contentWidth = MarkdownDecorationGeometry.imageContentWidth(
            viewWidth: options.pageWidth,
            textContainerInsetWidth: options.horizontalInset
        )
        return MarkdownImageAssetService.fittedSize(
            displayWidth: CGFloat(asset.displayWidth),
            pixelSize: Self.pixelSize,
            maxWidth: contentWidth
        ).height
    }

    // MARK: - Tests

    /// The reported defect, in the configuration the app actually exports with.
    ///
    /// Measured before the fix: this note exported **240.0pt** tall — the `minimumHeight` floor,
    /// which is to say the content did not even reach it — for a picture the draw pass paints
    /// **283.5pt** tall and which needs **385.5pt** of page with the insets. The image line had
    /// reserved 18.5625pt, a 1pt-wide picture's worth, and the prose around it was laid out as if
    /// that were all the room the picture needed.
    @Test func theExportedPageIsTallEnoughToHoldThePictureItPaints() throws {
        let asset = try makeAsset()
        let content = """
        Prose above the image.

        \(imageLine(asset))

        Prose below the image.
        """

        let height = try pageHeight(content, assets: [asset], options: Self.defaults)
        let drawn = drawnImageHeight(for: asset, options: Self.defaults)
        let needed = drawn + MarkdownDecorationGeometry.imageLinePadding + (Self.defaults.verticalInset * 2)

        #expect(
            height >= needed,
            "page is \(height)pt for a \(drawn)pt picture that needs \(needed)pt"
        )
    }

    /// The same fact stated as a difference, which is what removes the prose's own metrics from the
    /// answer: adding one image line to a note has to make the exported page grow by at least the
    /// picture that line draws.
    ///
    /// Measured before the fix: the image line added **50.0pt** to the page, for a picture painted
    /// **283.5pt** tall.
    @Test func addingAnImageGrowsTheExportedPageByThePicturesHeight() throws {
        let asset = try makeAsset()
        let prose = """
        Prose above the image.

        Prose below the image.
        """
        let withImage = """
        Prose above the image.

        \(imageLine(asset))

        Prose below the image.
        """

        let bare = try pageHeight(prose, assets: [asset], options: Self.unfloored)
        let full = try pageHeight(withImage, assets: [asset], options: Self.unfloored)
        let drawn = drawnImageHeight(for: asset, options: Self.unfloored)

        #expect(
            full - bare >= drawn,
            "the image line added \(full - bare)pt for a \(drawn)pt picture"
        )
    }

    /// The width that reaches the styler has to be the page's, not some constant.
    ///
    /// A narrower page fits the same asset smaller, so it must reserve less. This is what a fix
    /// that hardcoded 612 — or that reserved a fixed slab — would fail, and it is measured as a
    /// comparison between two exports rather than against a number written down here. Before the
    /// fix both pages came back at exactly **103.0pt**: the width never reached the styler at all.
    @Test func aNarrowerPageReservesLessHeightForTheSamePicture() throws {
        let asset = try makeAsset()
        let content = imageLine(asset)
        let narrow = NotePDFRenderOptions(pageWidth: 320, minimumHeight: 1)

        let wideHeight = try pageHeight(content, assets: [asset], options: Self.unfloored)
        let narrowHeight = try pageHeight(content, assets: [asset], options: narrow)

        #expect(drawnImageHeight(for: asset, options: narrow) < drawnImageHeight(for: asset, options: Self.unfloored))
        #expect(
            narrowHeight < wideHeight,
            "a 320pt page reserved \(narrowHeight)pt where a 612pt page reserved \(wideHeight)pt"
        )
        #expect(
            narrowHeight >= drawnImageHeight(for: asset, options: narrow)
                + MarkdownDecorationGeometry.imageLinePadding + (narrow.verticalInset * 2),
            "the narrow page is \(narrowHeight)pt for a \(drawnImageHeight(for: asset, options: narrow))pt picture"
        )
    }

    /// The height still has to come from `usedRect`, and the export view is measured before it is
    /// given its final frame — so a fix that set the frame early must not have made the measurement
    /// stale in the other direction.
    ///
    /// A note with no image at all is the control: its page height is the text it contains plus the
    /// insets, and it must not have picked up the page-sized slab the image case now reserves.
    @Test func aNoteWithoutAnImageIsStillMeasuredFromItsText() throws {
        let asset = try makeAsset()
        let oneLine = try pageHeight("One line.", assets: [asset], options: Self.unfloored)
        let manyLines = try pageHeight(
            (1...12).map { "Line \($0)." }.joined(separator: "\n"),
            assets: [asset],
            options: Self.unfloored
        )

        #expect(oneLine > Self.unfloored.verticalInset * 2)
        #expect(oneLine < 120, "a one-line note exported \(oneLine)pt tall")
        #expect(
            manyLines > oneLine + 100,
            "12 lines exported \(manyLines)pt where one line exported \(oneLine)pt"
        )
    }
}
#endif
