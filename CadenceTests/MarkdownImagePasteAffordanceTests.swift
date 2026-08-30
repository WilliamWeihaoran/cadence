import Foundation
import Testing
#if os(macOS)
import AppKit
#endif
@testable import Cadence

#if os(macOS)
/// **What the edit menu promises over a copied image** (T-504), the paste-side twin of
/// `MarkdownImageDropAffordanceTests`.
///
/// T-478 threaded `allowsImageInsertion` into the *drag* answer so the pointer stopped showing a
/// copy badge over an editor that had already declined images. The paste kept promising. Both
/// platforms had the same shape, and both were **safe but not honest**: the creator returned `[]`,
/// so nothing was minted and the command fell through to `super` — which, on a view whose
/// `allowsEditingTextAttributes`/`importsGraphics` is deliberately off, does nothing at all. So
/// **Paste** was enabled, Cmd-V was dispatched, and the note did not change.
///
/// - macOS: `CadenceTextView.readablePasteboardTypes` widened *unconditionally*, even though the
///   same class already carried `allowsMarkdownImageInsertion` and its two neighbours
///   (`registerMarkdownDraggedTypes`, `markdownImageDropOperation`) both read it.
/// - iOS: `iOSMarkdownTextView.canPerformAction` answered `true` for any image-bearing pasteboard.
///
/// The macOS half is exercised against **private** pasteboards this suite owns, for the reason
/// `MarkdownImagePasteTests` gives: writing `NSPasteboard.general` would destroy whatever the
/// person running the suite had copied. The iOS half is a source scan — `Cadence/iOS/` is inside
/// `#if os(iOS)` and this target does not compile it — with a non-vacuity test at the bottom.
@MainActor
struct MarkdownImagePasteAffordanceTests {

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

    private func pasteboard(_ name: String) -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name("com.haoranwei.Cadence.tests.pasteaffordance.\(name)"))
        board.clearContents()
        return board
    }

    /// A screenshot: `Cmd-Ctrl-Shift-4` puts TIFF on the pasteboard and nothing else.
    private func screenshotPasteboard(_ name: String) -> NSPasteboard {
        let board = pasteboard(name)
        board.setData(makeImage().tiffRepresentation!, forType: .tiff)
        return board
    }

    private func makeTextView(allowsImages: Bool) -> CadenceTextView {
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
        textView.allowsMarkdownImageInsertion = allowsImages
        return textView
    }

    /// The bitmap half of `readableImagePasteboardTypes`. `.fileURL` is deliberately excluded: it is
    /// not image-specific, and whether the stock list already carries it is AppKit's business, not
    /// this rule's — the same reason `registerMarkdownDraggedTypes` keeps `.fileURL` on both paths.
    private var bitmapTypes: Set<NSPasteboard.PasteboardType> {
        Set(NSImage.imageTypes.map { NSPasteboard.PasteboardType($0) })
    }

    // MARK: - The gate AppKit applies before `paste(_:)` runs

    /// The anchor. Every note, document and task-notes editor in the app is this host, and T-280's
    /// fix has to keep working — a refusal that also refused here would be a regression, not a fix.
    @Test func anAcceptingHostOffersPasteForAScreenshot() {
        let textView = makeTextView(allowsImages: true)
        #expect(screenshotPasteboard("accept").availableType(from: textView.readablePasteboardTypes) != nil)
    }

    /// The defect, stated the way the user met it: the template editor's **Paste** was enabled over
    /// a copied screenshot, and using it did nothing at all.
    @Test func aRefusingHostDoesNotOfferPasteForAScreenshot() {
        let textView = makeTextView(allowsImages: false)
        #expect(screenshotPasteboard("refuse").availableType(from: textView.readablePasteboardTypes) == nil)
    }

    /// The refusal is scoped to the widening and nothing else: a refusing host still pastes text,
    /// which is the entire remaining point of the editor. Without this, "offer nothing" would pass
    /// the test above.
    @Test func aRefusingHostStillOffersPasteForText() {
        let textView = makeTextView(allowsImages: false)
        let board = pasteboard("refuse.text")
        board.setString("just words", forType: .string)
        #expect(board.availableType(from: textView.readablePasteboardTypes) != nil)
    }

    /// Stated over the whole list rather than one pasteboard: a refusing host advertises no bitmap
    /// type at all, so no image format — HEIC and WebP included — can enable the command by a route
    /// the two pasteboards above do not happen to cover.
    @Test func aRefusingHostAdvertisesNoBitmapTypeAndAnAcceptingOneAdvertisesThemAll() {
        let accepting = Set(makeTextView(allowsImages: true).readablePasteboardTypes)
        let refusing = Set(makeTextView(allowsImages: false).readablePasteboardTypes)

        // Counted rather than compared as sets: `NSImage.imageTypes` is 65 entries here and a
        // failed set `#expect` prints both sides in full, which buries the verdict in the log.
        #expect(bitmapTypes.count > 10, "NSImage.imageTypes has \(bitmapTypes.count) entries; this measures nothing")
        #expect(bitmapTypes.subtracting(accepting).count == 0, "the accepting host stopped advertising an image format")
        #expect(bitmapTypes.intersection(refusing).count == 0, "the refusing host still advertises image formats")
        // And the refusal removes only those: the text types are untouched, which is the same claim
        // the text pasteboard above makes, made once over the whole list.
        #expect(accepting.subtracting(refusing).subtracting(bitmapTypes).subtracting([.fileURL]).count == 0)
    }

    /// Hosts that never mention the flag are untouched. The default lives on the text view, so a
    /// future representable that forgets to thread it still gets the accepting behaviour rather
    /// than silently losing the paste every note editor depends on.
    @Test func aTextViewOffersTheImagePasteUntilAHostSaysOtherwise() {
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
        #expect(textView.allowsMarkdownImageInsertion)
        #expect(screenshotPasteboard("default").availableType(from: textView.readablePasteboardTypes) != nil)
    }

    // MARK: - The iOS half of the same door

    private func strippedSource(_ path: String) throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }

    /// The gate itself, and that it reads the flag rather than only the pasteboard.
    ///
    /// `hasImages` stays, and stays *after* the flag: reading the pasteboard's contents to answer a
    /// menu-enablement question raises the system's "pasted from" banner, so the cheap local answer
    /// has to come first.
    @Test func theMobilePasteGateConsultsTheHostsImagePolicy() throws {
        let view = try strippedSource("Cadence/iOS/iOSMarkdownTextView.swift")

        #expect(
            view.contains("var allowsMarkdownImageInsertion = true"),
            "the iOS text view does not carry the flag, or spells it differently from CadenceTextView"
        )
        let gate = try #require(
            CadenceSourceScan.functionBody(named: "canPerformAction", in: view),
            "canPerformAction() could not be read; the assertions below would measure nothing"
        )
        #expect(gate.contains("allowsMarkdownImageInsertion"), "the gate offers Paste at a refusing host")
        let flagIndex = try #require(gate.range(of: "allowsMarkdownImageInsertion")?.lowerBound)
        let boardIndex = try #require(gate.range(of: "UIPasteboard.general.hasImages")?.lowerBound)
        #expect(flagIndex < boardIndex, "the pasteboard is read before the flag, raising the paste banner needlessly")
    }

    /// The wire from the host down to the view, which is the link T-478 had to add on macOS and
    /// which did not exist on iOS at all. Both passes are asserted: `updateUIView` matters because
    /// quick create flips its policy with the sheet's mode while the same text view stays alive.
    @Test func theMobileRepresentableThreadsTheHostsImagePolicyIntoTheTextView() throws {
        let editor = try strippedSource("Cadence/iOS/iOSMarkdownEditor.swift")
        let surface = try strippedSource("Cadence/iOS/iOSMarkdownEditingSurface.swift")

        let made = try #require(
            CadenceSourceScan.functionBody(named: "makeUIView", in: editor),
            "makeUIView() could not be read; the assertions below would measure nothing"
        )
        #expect(made.contains("textView.allowsMarkdownImageInsertion = allowsImageInsertion"))

        let updated = try #require(
            CadenceSourceScan.functionBody(named: "updateUIView", in: editor),
            "updateUIView() could not be read; the assertions below would measure nothing"
        )
        #expect(
            updated.contains("allowsMarkdownImageInsertion = allowsImageInsertion"),
            "the policy is set once at creation, so quick create keeps the mode it opened in"
        )

        #expect(
            surface.contains("allowsImageInsertion: allowsImageInsertion"),
            "the editing surface does not hand its own flag to the representable"
        )
    }

    /// The three files above are never compiled by this target and are read as text. A reader that
    /// returned an empty string would satisfy every `#require` above by failing loudly, but a
    /// stripper that silently returned the raw file would not — so both are pinned.
    @Test func theMobilePasteAffordanceScanReachesTheFilesItClaimsTo() throws {
        for path in [
            "Cadence/iOS/iOSMarkdownTextView.swift",
            "Cadence/iOS/iOSMarkdownEditor.swift",
            "Cadence/iOS/iOSMarkdownEditingSurface.swift"
        ] {
            let raw = try CadenceSourceScan.sourceFile(path)
            #expect(raw.count > 1_000, "\(path) read as \(raw.count) characters; that is not the file")

            let stripped = CadenceSourceScan.strippingComments(raw)
            #expect(stripped != raw, "\(path) lost no comment text; the stripper did not run")
            #expect(stripped.count == raw.count)
        }
    }
}
#endif
