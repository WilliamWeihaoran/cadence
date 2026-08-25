import Foundation
import Testing
import SwiftData
#if os(macOS)
import AppKit
#endif
@testable import Cadence

#if os(macOS)
/// **Pasting an image into a note.** The bug these pin was not in the paste handler — that code was
/// correct and is untouched — but one step above it, in whether AppKit dispatched the command at
/// all. `NSTextView` validates `paste:` by intersecting the pasteboard's types with its own
/// `readablePasteboardTypes`, and the stock list carries no image type: a screenshot is an
/// image-only pasteboard, the intersection was empty, the menu item was disabled, and
/// `CadenceTextView.paste(_:)` was never called. Measured against a real clipboard holding a real
/// PNG, `validateUserInterfaceItem` for `paste:` answered **false**.
///
/// Every pasteboard here is a **private** one this test owns. A test that wrote
/// `NSPasteboard.general` would destroy whatever the person running it had copied, and would also
/// be reading a value it did not write.
@MainActor
struct MarkdownImagePasteTests {
    // MARK: - Fixtures

    private func makeImage(width: Int = 40, height: Int = 20) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        return image
    }

    private func pngData(width: Int = 40, height: Int = 20) -> Data {
        let rep = NSBitmapImageRep(data: makeImage(width: width, height: height).tiffRepresentation!)!
        return rep.representation(using: .png, properties: [:])!
    }

    /// A private pasteboard, named per test so two running in parallel cannot share one.
    private func pasteboard(_ name: String) -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name("com.haoranwei.Cadence.tests.paste.\(name)"))
        board.clearContents()
        return board
    }

    /// A screenshot: `Cmd-Ctrl-Shift-4` puts TIFF on the pasteboard and nothing else.
    private func screenshotPasteboard(_ name: String) -> NSPasteboard {
        let board = pasteboard(name)
        board.setData(makeImage().tiffRepresentation!, forType: .tiff)
        return board
    }

    /// An image copied out of a browser: PNG (which carries a TIFF rendition with it).
    private func browserImagePasteboard(_ name: String) -> NSPasteboard {
        let board = pasteboard(name)
        board.setData(pngData(), forType: .png)
        return board
    }

    /// A file copied in Finder: a file URL, no bitmap.
    private func finderFilePasteboard(_ name: String, filename: String) throws -> (NSPasteboard, URL) {
        let board = pasteboard(name)
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
        try pngData().write(to: url)
        _ = board.writeObjects([url as NSURL])
        return (board, url)
    }

    private func makeTextView(_ text: String = "Hello") -> CadenceTextView {
        let storage = NSTextStorage()
        let layoutManager = CadenceLayoutManager()
        let container = NSTextContainer(
            containerSize: NSSize(width: 520, height: CGFloat.greatestFiniteMagnitude)
        )
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        let textView = CadenceTextView(
            frame: NSRect(x: 0, y: 0, width: 560, height: 900),
            textContainer: container
        )
        textView.isEditable = true
        textView.isRichText = true
        textView.allowsUndo = true
        textView.font = MarkdownStylist.baseFont
        textView.typingAttributes = MarkdownStylist.baseAttributes
        textView.string = text
        MarkdownStylist.apply(to: textView)
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        return textView
    }

    private func makeContext() throws -> ModelContext {
        ModelContext(
            try ModelContainer(
                for: CadenceSchema.schema,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        )
    }

    /// Wires the text view to a real store the way `MarkdownEditor.createAssets` does.
    private func attachAssetCreation(to textView: CadenceTextView, context: ModelContext) {
        textView.onCreateMarkdownImages = { (images: [NSImage], urls: [URL]) -> [MarkdownImageAsset] in
            var assets = MarkdownImageAssetService.createAssets(fromFileURLs: urls, in: context)
            for image in images {
                if let asset = MarkdownImageAssetService.createAsset(from: image, in: context) {
                    assets.append(asset)
                }
            }
            try? context.save()
            return assets
        }
    }

    // MARK: - The gate AppKit applies before `paste(_:)` runs

    /// The regression itself: with the stock list, all three of these are `nil`.
    @Test func theEditorOffersPasteForAScreenshot() {
        let textView = makeTextView()
        #expect(screenshotPasteboard("screenshot").availableType(from: textView.readablePasteboardTypes) != nil)
    }

    @Test func theEditorOffersPasteForABrowserImage() {
        let textView = makeTextView()
        #expect(browserImagePasteboard("browser").availableType(from: textView.readablePasteboardTypes) != nil)
    }

    @Test func theEditorOffersPasteForAFileCopiedInFinder() throws {
        let textView = makeTextView()
        let (board, url) = try finderFilePasteboard("finder", filename: "probe-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(board.availableType(from: textView.readablePasteboardTypes) != nil)
    }

    /// The anchor under the three above: a stock `NSTextView` configured identically answers `nil`
    /// for a bitmap, which is what the editor's override exists to change. Without this, deleting
    /// the override could leave the three passing on some future AppKit default and the regression
    /// would go unnoticed.
    @Test func aStockTextViewDoesNotOfferPasteForABitmap() {
        let stock = NSTextView(frame: NSRect(x: 0, y: 0, width: 560, height: 900))
        stock.isEditable = true
        stock.isRichText = true
        #expect(screenshotPasteboard("stock.tiff").availableType(from: stock.readablePasteboardTypes) == nil)
        #expect(browserImagePasteboard("stock.png").availableType(from: stock.readablePasteboardTypes) == nil)
    }

    /// The widening is additive and appended, so a paste that carries text *and* an image still
    /// resolves to the text — `readSelection(from:)` takes the first listed type present.
    @Test func aPasteboardCarryingTextAndAnImageStillResolvesToTheText() {
        let textView = makeTextView()
        let board = pasteboard("mixed")
        board.setString("plain words", forType: .string)
        board.setData(pngData(), forType: .png)
        let resolved = board.availableType(from: textView.readablePasteboardTypes)
        #expect(resolved != nil)
        #expect(MarkdownImageAssetService.readableImagePasteboardTypes.contains(resolved!) == false)
    }

    // MARK: - The path the dispatched command then runs

    @Test func pastingAScreenshotWritesAnAssetAndItsMarkdown() throws {
        let context = try makeContext()
        let textView = makeTextView()
        attachAssetCreation(to: textView, context: context)

        #expect(textView.insertMarkdownImages(from: screenshotPasteboard("insert.screenshot")))

        let assets = try context.fetch(FetchDescriptor<MarkdownImageAsset>())
        #expect(assets.count == 1)
        let asset = try #require(assets.first)
        #expect(asset.pixelWidth == 40)
        #expect(asset.pixelHeight == 20)
        #expect(asset.data.isEmpty == false)
        #expect(textView.string == "Hello\n\n\(MarkdownImageAssetService.markdown(for: asset))\n")
    }

    @Test func pastingABrowserImageWritesAnAssetAndItsMarkdown() throws {
        let context = try makeContext()
        let textView = makeTextView()
        attachAssetCreation(to: textView, context: context)

        #expect(textView.insertMarkdownImages(from: browserImagePasteboard("insert.browser")))

        let asset = try #require(try context.fetch(FetchDescriptor<MarkdownImageAsset>()).first)
        #expect(asset.pixelWidth == 40)
        #expect(textView.string == "Hello\n\n\(MarkdownImageAssetService.markdown(for: asset))\n")
    }

    @Test func pastingAFinderFileWritesAnAssetCaptionedFromItsFilename() throws {
        let context = try makeContext()
        let textView = makeTextView()
        attachAssetCreation(to: textView, context: context)
        let (board, url) = try finderFilePasteboard("insert.finder", filename: "holiday-photo.png")
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(textView.insertMarkdownImages(from: board))

        let asset = try #require(try context.fetch(FetchDescriptor<MarkdownImageAsset>()).first)
        #expect(asset.originalFilename == "holiday-photo.png")
        #expect(asset.altText == "holiday photo")
        #expect(textView.string == "Hello\n\n\(MarkdownImageAssetService.markdown(for: asset))\n")
    }

    /// The inserted line is a *standalone* image reference, which is the only shape the renderer
    /// draws a picture for. An insert that produced markdown the styler did not recognise would
    /// look, to the user, exactly like the paste not working.
    @Test func theInsertedMarkdownIsAStandaloneImageTheRendererResolves() throws {
        let context = try makeContext()
        let textView = makeTextView()
        attachAssetCreation(to: textView, context: context)
        #expect(textView.insertMarkdownImages(from: screenshotPasteboard("insert.render")))

        let asset = try #require(try context.fetch(FetchDescriptor<MarkdownImageAsset>()).first)
        let line = try #require(textView.string.components(separatedBy: "\n").first { $0.contains("cadence-image://") })
        let reference = try #require(MarkdownBlockSupport.standaloneImageReference(in: line))
        #expect(reference.id == asset.id)
        #expect(MarkdownImageAssetService.referencedIDs(in: textView.string) == [asset.id])
        #expect(MarkdownImageAssetService.renderAsset(for: asset.id, in: [asset])?.pixelSize == CGSize(width: 40, height: 20))
    }

    /// A pasteboard with no image at all is declined, so `super.paste(_:)` still handles text.
    @Test func aTextOnlyPasteboardIsLeftToAppKit() throws {
        let context = try makeContext()
        let textView = makeTextView()
        attachAssetCreation(to: textView, context: context)
        let board = pasteboard("textonly")
        board.setString("just words", forType: .string)

        #expect(textView.insertMarkdownImages(from: board) == false)
        #expect(textView.string == "Hello")
        #expect(try context.fetch(FetchDescriptor<MarkdownImageAsset>()).isEmpty)
    }

    /// A host that creates no asset must not swallow the command either.
    @Test func aHostThatCreatesNoAssetDeclinesRatherThanSwallowingThePaste() {
        let textView = makeTextView()
        textView.onCreateMarkdownImages = { _, _ in [] }
        #expect(textView.insertMarkdownImages(from: screenshotPasteboard("noassets")) == false)
        #expect(textView.string == "Hello")
    }
}
#endif
