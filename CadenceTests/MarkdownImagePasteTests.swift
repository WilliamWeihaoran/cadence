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
            try CadenceTestStore.container()
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

    // MARK: - T-280: the iOS half of the same fix, taken as far off-device as it goes

    private func strippedSource(_ path: String) throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }

    /// `count` distinct assets, minted the way a paste mints them.
    private func pastedAssets(_ count: Int, in context: ModelContext) -> [MarkdownImageAsset] {
        let assets = (0..<count).compactMap { _ in
            MarkdownImageAssetService.createAsset(from: makeImage(), in: context)
        }
        #expect(Set(assets.map(\.id)).count == count, "minted \(assets.count) distinct assets, wanted \(count)")
        return assets
    }

    /// The text `iOSMarkdownEditor.Coordinator.insertPastedImages` leaves behind, evaluated here.
    ///
    /// Every call it makes is shared code this target compiles: the markdown for each asset joined
    /// by a blank line, `MarkdownInsertionSupport.paddedBlockInsertion`, and
    /// `MarkdownFormatCommandSupport.apply(.insertMarkdown(_:))` — whose `insertSnippet` is a plain
    /// replacement of the selection that adds no padding of its own, which is why two different
    /// text systems can land on one string.
    private func mobilePasteResult(_ assets: [MarkdownImageAsset], into text: String) -> String {
        let selection = NSRange(location: (text as NSString).length, length: 0)
        let markdown = assets
            .map { MarkdownImageAssetService.markdown(for: $0) }
            .joined(separator: "\n\n")
        let insertion = MarkdownInsertionSupport.paddedBlockInsertion(markdown, in: text, selection: selection)
        return MarkdownFormatCommandSupport.apply(.insertMarkdown(insertion), text: text, selection: selection).text
    }

    /// **The iOS paste writes the same text the measured macOS paste writes.**
    ///
    /// `Cadence/iOS/` is inside `#if os(iOS)` and invisible to this macOS-built target, so the iOS
    /// path cannot be *run* here — but it is not a second implementation either. It composes the
    /// same shared calls `CadenceTextView.insertMarkdownImages(_:)` does, so its outcome is
    /// arithmetic over code this target compiles, and this pins it against the one platform that
    /// was measured against a real clipboard.
    ///
    /// `theMobilePasteChainIsWiredEndToEnd` below is what holds the iOS source to that composition.
    /// Without it, this compares macOS to a formula nobody is keeping true.
    @Test func theMobilePasteWritesTheSameTextTheMeasuredMacOSPasteDoes() throws {
        let context = try makeContext()
        for count in [1, 2, 3] {
            let assets = pastedAssets(count, in: context)
            let desktop = makeTextView("Hello")
            desktop.insertMarkdownImages(assets)

            #expect(mobilePasteResult(assets, into: "Hello") == desktop.string)
        }
    }

    /// The multi-image paste, which is iOS's case rather than a shared one: `UIPasteboard.images`
    /// is plural where `NSPasteboard` hands over a single bitmap, so on the phone a two-image
    /// clipboard arrives as one call.
    ///
    /// Both references have to survive the join as *standalone* lines. A separator that merged them
    /// into one paragraph would render as a line of literal markdown, which from the outside looks
    /// exactly like the paste having done nothing.
    @Test func aTwoImageMobilePasteInsertsTwoStandaloneReferencesTheRendererResolves() throws {
        let context = try makeContext()
        let assets = pastedAssets(2, in: context)

        let text = mobilePasteResult(assets, into: "Hello")

        #expect(text.hasPrefix("Hello"), "the paste replaced the note instead of inserting into it")
        #expect(MarkdownImageAssetService.referencedIDs(in: text) == Set(assets.map(\.id)))

        let lines = text.components(separatedBy: "\n").filter { $0.contains("cadence-image://") }
        #expect(lines.count == 2)
        for (line, asset) in zip(lines, assets) {
            #expect(
                MarkdownBlockSupport.standaloneImageReference(in: line)?.id == asset.id,
                "\(line) is not a standalone image reference; it renders as literal markdown"
            )
            #expect(
                MarkdownImageAssetService.renderAsset(for: asset.id, in: assets)?.pixelSize
                    == CGSize(width: 40, height: 20)
            )
        }
    }

    /// **The four links between the edit menu and the composition above.**
    ///
    /// T-280's risk was never the composition — it is that the command never arrives. That is
    /// precisely how the macOS half of this bug survived: a correct `paste(_:)` AppKit refused to
    /// dispatch. So the chain is read link by link: the gate offers Paste for an image-only
    /// pasteboard, the override dispatches to a handler, `makeUIView` assigns that handler
    /// unconditionally, and the coordinator it lands in composes what the tests above evaluated.
    ///
    /// The one link this cannot read — whether UIKit consults the override when it builds the menu —
    /// was **settled on a simulator on 2026-09-02** ([T-280]) and is no longer on
    /// `docs/device-checks.md`. With a real PNG on the pasteboard (`simctl addmedia`, then Photos →
    /// Copy; `simctl pbcopy` lands a PNG as *text* and proves nothing), Paste appeared in a note's
    /// edit menu and inserted the picture — while in the same session, same clipboard, the refusing
    /// event-mode composer offered no Paste at all. Nothing but `allowsMarkdownImageInsertion`
    /// separates those two text views, so the menu is reading this override.
    @Test func theMobilePasteChainIsWiredEndToEnd() throws {
        let view = try strippedSource("Cadence/iOS/iOSMarkdownTextView.swift")
        let editor = try strippedSource("Cadence/iOS/iOSMarkdownEditor.swift")
        let desktop = try strippedSource("Cadence/macOS/Editor/MarkdownEditorInteractionSupport.swift")

        // Link 1 — the gate. `hasImages` and not `.images`: reading the pasteboard's contents to
        // answer a menu-enablement question raises the system's "pasted from" banner.
        let gate = try #require(
            CadenceSourceScan.functionBody(named: "canPerformAction", in: view),
            "canPerformAction() could not be read; the assertions below would measure nothing"
        )
        #expect(gate.contains("#selector(UIResponderStandardEditActions.paste(_:))"))
        #expect(gate.contains("isEditable"), "a read-only note offers Paste")
        #expect(gate.contains("UIPasteboard.general.hasImages"))
        #expect(
            CadenceSourceScan.matchCount("UIPasteboard\\.general\\.images", in: gate) == 0,
            "the enablement check reads the pasteboard's contents and raises the paste banner"
        )
        #expect(
            gate.contains("return super.canPerformAction(action, withSender: sender)"),
            "the override answers for every action rather than deferring the ones it does not widen"
        )

        // Link 2 — the dispatch, and its fall-through. A refused image paste stays an ordinary text
        // paste rather than becoming a swallowed one, exactly as macOS's does.
        let paste = try #require(
            CadenceSourceScan.functionBody(named: "paste", in: view),
            "paste(_:) could not be read; the assertions below would measure nothing"
        )
        #expect(paste.contains("imagePasteHandler?(images) == true"))
        #expect(paste.contains("super.paste(sender)"), "a host that mints no asset swallows the paste")

        // Link 3 — the handler. Written in exactly one place, and that place is `makeUIView`, so it
        // cannot become conditional on a host: a `nil` there would leave the widened gate offering
        // an enabled Paste that does nothing, which is worse than the bug it fixes.
        let made = try #require(
            CadenceSourceScan.functionBody(named: "makeUIView", in: editor),
            "makeUIView() could not be read; the assertions below would measure nothing"
        )
        #expect(made.contains("textView.imagePasteHandler = "))
        #expect(made.contains("coordinator?.insertPastedImages(images, in: textView)"))
        #expect(
            CadenceSourceScan.matchCount("imagePasteHandler", in: editor) == 1,
            "the handler is written somewhere other than makeUIView; check that path assigns it too"
        )

        // Link 4 — the composition both platforms' paste reaches. Two needles rather than one line
        // because macOS writes it on one line and iOS across three.
        let mobileInsert = try #require(
            CadenceSourceScan.functionBody(named: "insertPastedImages", in: editor),
            "insertPastedImages() could not be read; the assertions below would measure nothing"
        )
        let desktopInsert = try #require(
            CadenceSourceScan.functionBody(named: "insertMarkdownImages", in: desktop),
            "insertMarkdownImages() could not be read; the assertions below would measure nothing"
        )
        for body in [mobileInsert, desktopInsert] {
            #expect(body.contains("MarkdownImageAssetService.markdown(for: $0)"))
            #expect(body.contains(".joined(separator: \"\\n\\n\")"))
            #expect(body.contains("MarkdownInsertionSupport.paddedBlockInsertion("))
        }
        #expect(
            mobileInsert.contains("apply(.insertMarkdown(insertion), to: textView)"),
            "the mobile insertion no longer goes through MarkdownFormatCommandSupport"
        )
    }

    /// Two of the three files above are never compiled by this target, and all three are read as
    /// text. A reader that returned an empty string would satisfy every `matchCount(…) == 0` here,
    /// so the reads are pinned rather than assumed.
    @Test func theMobilePasteScanReachesTheFilesItClaimsTo() throws {
        for path in [
            "Cadence/iOS/iOSMarkdownTextView.swift",
            "Cadence/iOS/iOSMarkdownEditor.swift",
            "Cadence/macOS/Editor/MarkdownEditorInteractionSupport.swift"
        ] {
            let raw = try CadenceSourceScan.sourceFile(path)
            #expect(raw.count > 1_000, "\(path) read as \(raw.count) characters; that is not the file")

            let stripped = CadenceSourceScan.strippingComments(raw)
            #expect(stripped != raw, "\(path) lost no comment text; the stripper did not run")
            #expect(stripped.count == raw.count)
        }

        // `strippingComments` and not `codeOnly`, pinned because the choice is load-bearing: link 4
        // above asserts on a *string literal* in the source, and `codeOnly` blanks literals along
        // with comments, so that assertion would be permanently and silently green there.
        let literal = "let separator = \"\\n\\n\""
        #expect(CadenceSourceScan.strippingComments(literal).contains("\"\\n\\n\""))
        #expect(
            CadenceSourceScan.codeOnly(literal).contains("\"\\n\\n\"") == false,
            "codeOnly no longer blanks string literals; the two readers have collapsed into one"
        )
    }
}
#endif
