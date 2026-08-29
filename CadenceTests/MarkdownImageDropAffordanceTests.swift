import Foundation
import Testing
#if os(macOS)
import AppKit
#endif
@testable import Cadence

#if os(macOS)
/// **What the pointer promises over a dropped image** (T-478).
///
/// `MarkdownEditor.allowsImageInsertion` closes four image doors — the toolbar's photo button, the
/// `/image` command, the paste and the drop — but it only reached the first three. The drop was
/// *safe*: `onCreateMarkdownImages` returned `[]`, `insertMarkdownImages` answered `false`, and
/// `performDragOperation` fell through to `super`. It was not *honest*: `draggingEntered` answered
/// `.copy` for any image payload, so a host that had already declined images showed the copy badge
/// right up until the drop did nothing.
///
/// These exercise the decision, not the AppKit plumbing. `NSDraggingInfo` is a protocol with a
/// dozen members none of which this rule reads, so the rule is split into
/// `markdownImageDropOperation(for:)` and driven with a **private** pasteboard — the same reason
/// `MarkdownImagePasteTests` owns its boards rather than writing `NSPasteboard.general`, which
/// would destroy whatever the person running the suite had copied.
@MainActor
struct MarkdownImageDropAffordanceTests {

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

    private func dropPasteboard(_ name: String) -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name("com.haoranwei.Cadence.tests.drop.\(name)"))
        board.clearContents()
        return board
    }

    /// A bitmap dragged out of another app: TIFF and nothing else.
    private func draggedBitmap(_ name: String) -> NSPasteboard {
        let board = dropPasteboard(name)
        board.setData(makeImage().tiffRepresentation!, forType: .tiff)
        return board
    }

    /// A PNG dragged out of Finder: a file URL, no bitmap. This is the case `.fileURL` keeps
    /// admitting even at a refusing host, so it is the one the operation rule has to answer for.
    private func draggedImageFile(_ name: String, filename: String) throws -> (NSPasteboard, URL) {
        let board = dropPasteboard(name)
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
        let rep = NSBitmapImageRep(data: makeImage().tiffRepresentation!)!
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        _ = board.writeObjects([url as NSURL])
        return (board, url)
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
        textView.allowsMarkdownImageInsertion = allowsImages
        return textView
    }

    // MARK: - The verdict the pointer draws

    @Test func anAcceptingHostClaimsADraggedBitmapAsACopy() {
        let textView = makeTextView(allowsImages: true)
        #expect(textView.markdownImageDropOperation(for: draggedBitmap("accept.bitmap")) == .copy)
    }

    /// The defect, stated the way the user met it: same payload, same editor, at the host that has
    /// already dropped its photo button and its `/image` entry.
    @Test func aRefusingHostDoesNotClaimADraggedBitmap() {
        let textView = makeTextView(allowsImages: false)
        #expect(textView.markdownImageDropOperation(for: draggedBitmap("refuse.bitmap")) == nil)
    }

    @Test func aRefusingHostDoesNotClaimADraggedImageFileEither() throws {
        let (board, url) = try draggedImageFile("refuse.file", filename: "drop-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let accepting = makeTextView(allowsImages: true)
        let refusing = makeTextView(allowsImages: false)
        // Both halves together: the file case is only interesting because the accepting host does
        // claim it, which is what makes the refusing host's `nil` a decision rather than a gap.
        #expect(accepting.markdownImageDropOperation(for: board) == .copy)
        #expect(refusing.markdownImageDropOperation(for: board) == nil)
    }

    /// A drag with no image in it was never this view's to claim, at either host — `super` answers,
    /// exactly as before. Without this the fix could have been "claim nothing", which would take
    /// ordinary text drops with it.
    @Test func aDragWithNoImagePayloadIsLeftToAppKitAtBothHosts() {
        let board = dropPasteboard("textonly")
        board.setString("just words", forType: .string)
        #expect(makeTextView(allowsImages: true).markdownImageDropOperation(for: board) == nil)
        #expect(makeTextView(allowsImages: false).markdownImageDropOperation(for: board) == nil)
    }

    /// Hosts that never mention the flag are untouched — every note, document and task-notes editor
    /// in the app, which is all but two of them.
    @Test func aTextViewAcceptsImagesUntilAHostSaysOtherwise() {
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
    }

    // MARK: - The types AppKit is told about

    @Test func anAcceptingHostRegistersTheImageDragTypes() {
        let textView = makeTextView(allowsImages: true)
        textView.registerMarkdownDraggedTypes()
        #expect(textView.registeredDraggedTypes.contains(.tiff))
        #expect(textView.registeredDraggedTypes.contains(.png))
        #expect(textView.registeredDraggedTypes.contains(.fileURL))
    }

    /// The second half of the fix: a refusing host stops advertising the bitmap types at all, so a
    /// dragged screenshot never reaches `draggingEntered` and the pointer shows the no-drop cursor
    /// rather than a copy badge that gets withdrawn.
    ///
    /// `.fileURL` deliberately stays on both paths. It is not image-specific, and the operation
    /// rule above already answers for the file case.
    @Test func aRefusingHostRegistersNoBitmapDragTypes() {
        let textView = makeTextView(allowsImages: false)
        textView.registerMarkdownDraggedTypes()
        #expect(textView.registeredDraggedTypes.contains(.tiff) == false)
        #expect(textView.registeredDraggedTypes.contains(.png) == false)
        #expect(textView.registeredDraggedTypes.contains(.fileURL))
    }

    // MARK: - The wire from the host down to the view

    /// `configure(_:context:)` is a `NSViewRepresentable` update pass; nothing headless can run it.
    /// This is the one link in the chain that has to be read rather than exercised, and without it
    /// every test above could pass on a text view no host ever sets the flag on.
    @Test func theRepresentableThreadsTheHostsImagePolicyIntoTheTextView() throws {
        let source = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Editor/MarkdownEditorView.swift")
        )
        let body = try #require(CadenceSourceScan.functionBody(named: "configure", in: source))
        #expect(body.contains("textView.allowsMarkdownImageInsertion = allowsImageInsertion"))
        #expect(body.contains("textView.registerMarkdownDraggedTypes()"))
        // The unconditional registration is gone, not merely shadowed by a later call.
        #expect(CadenceSourceScan.matchCount("registerForDraggedTypes", in: body) == 0)
    }

    /// And that the flag arrives from the host rather than defaulting inside the representable.
    @Test func theEditorHandsItsImagePolicyToTheRepresentable() throws {
        let source = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Editor/MarkdownEditorView.swift")
        )
        #expect(source.contains("allowsImageInsertion: allowsImageInsertion"))
    }
}
#endif
