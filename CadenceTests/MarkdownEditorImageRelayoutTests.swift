import Foundation
import Testing
#if os(macOS)
import AppKit
#endif
@testable import Cadence

#if os(macOS)
/// A standalone image's reserved line height has to follow the editor's width.
///
/// `MarkdownStylist.applyImageBlock` reserves the image's height on its own line fragment, and it
/// derives that height from `textView.bounds.width` **at the moment the note is styled**. The draw
/// pass (`CadenceTextView.drawMarkdownImages`) re-derives the same size from `bounds.width` **at
/// the moment it paints**. Those are the same number only while the editor keeps the width it was
/// styled at.
///
/// They diverge constantly in the real app, and always in the same direction:
///
/// - A `MarkdownEditorView` is styled from `updateNSView`, which SwiftUI runs *before* the
///   representable has been given its frame. `makeNSView` sizes the text view from
///   `scrollView.contentSize`, which is still zero then, so the first styling pass sees a ~1pt
///   content width and reserves ~19pt for a picture that will be drawn several hundred points tall
///   moments later, once `MarkdownEditorScrollView.layout()` hands the text view its real width.
/// - Dragging the sidebar divider, toggling a panel, or resizing the window re-lays out the
///   document at the new width without restyling it, so every image line keeps the height it
///   reserved at the old one.
///
/// The visible result is the reported one: prose sits on top of a picture, and the first keystroke
/// — which restyles through `textDidChange` — puts it right.
///
/// These tests pin the contract `applyImageBlock`'s own comment states: the reserved line height and
/// the drawn image are measured from one width, so the image is entirely contained by the fragment
/// it was given.
@MainActor
struct MarkdownEditorImageRelayoutTests {
    private static let imageID = UUID(uuidString: "0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9")!

    private static let markdown = """
    Prose above the image.

    ![banner](cadence-image://0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9)

    Prose below the image.
    """

    private static let inset: CGFloat = 18

    private static var imageAsset: MarkdownImageRenderAsset {
        let size = NSSize(width: 640, height: 360)
        let image = NSImage(size: size)
        image.lockFocus()
        Theme.nsBlue.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return MarkdownImageRenderAsset(
            id: imageID,
            image: image,
            displayWidth: MarkdownImageAssetService.defaultDisplayWidth,
            pixelSize: size
        )
    }

    // MARK: - Fixture

    /// The same object graph `MarkdownEditorView.makeNSView` builds, at a chosen scroll-view width.
    private func makeEditor(width: CGFloat) -> (scrollView: NSScrollView, textView: CadenceTextView) {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: 600))
        return (scrollView, install(in: scrollView, styling: true))
    }

    /// Everything `makeNSView` puts inside the scroll view, so the end-to-end test can install it
    /// into the real `MarkdownEditorScrollView` instead of a plain one.
    @discardableResult
    private func install(in scrollView: NSScrollView, styling: Bool) -> CadenceTextView {
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let contentSize = scrollView.contentSize
        let storage = NSTextStorage()
        let layoutManager = CadenceLayoutManager()
        let containerWidth = max(1, contentSize.width - Self.inset * 2)
        let container = NSTextContainer(
            containerSize: NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)
        )
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)

        let textView = CadenceTextView(
            frame: NSRect(x: 0, y: 0, width: contentSize.width, height: 0),
            textContainer: container
        )
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.isEditable = true
        textView.isRichText = true
        textView.backgroundColor = Theme.nsBg
        textView.textContainerInset = NSSize(width: Self.inset, height: Self.inset)
        textView.font = MarkdownStylist.baseFont
        textView.typingAttributes = MarkdownStylist.baseAttributes
        textView.markdownImageAssets = [Self.imageID: Self.imageAsset]
        textView.string = Self.markdown

        scrollView.documentView = textView
        guard styling else { return textView }
        MarkdownEditorScrollSupport.refreshLayout(in: scrollView)
        MarkdownStylist.apply(to: textView)
        MarkdownEditorScrollSupport.refreshLayout(in: scrollView)
        return textView
    }

    private func resize(_ scrollView: NSScrollView, to width: CGFloat) {
        scrollView.setFrameSize(NSSize(width: width, height: scrollView.frame.height))
        MarkdownEditorScrollSupport.refreshLayout(in: scrollView)
    }

    /// The image line's fragment, in the same view coordinates `markdownImageRects` is cached in.
    private func imageLineFragment(in textView: CadenceTextView) throws -> NSRect {
        let storage = try #require(textView.textStorage)
        let layoutManager = try #require(textView.layoutManager)
        let container = try #require(textView.textContainer)
        layoutManager.ensureLayout(for: container)

        var found: NSRect?
        storage.enumerateAttribute(
            .cadenceMarkdownImage,
            in: NSRange(location: 0, length: storage.length)
        ) { value, range, stop in
            guard value is MarkdownImageLayoutInfo else { return }
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: range.location)
            guard glyphIndex < layoutManager.numberOfGlyphs else { return }
            found = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            stop.pointee = true
        }
        return try #require(found).offsetBy(
            dx: textView.textContainerOrigin.x,
            dy: textView.textContainerOrigin.y
        )
    }

    /// The height the draw pass will paint at, from the width the view has right now.
    private func drawnImageHeight(in textView: CadenceTextView) -> CGFloat {
        let contentWidth = MarkdownDecorationGeometry.imageContentWidth(
            viewWidth: textView.bounds.width,
            textContainerInsetWidth: textView.textContainerInset.width
        )
        return MarkdownImageAssetService.fittedSize(
            displayWidth: Self.imageAsset.displayWidth,
            pixelSize: Self.imageAsset.pixelSize,
            maxWidth: contentWidth
        ).height
    }

    // MARK: - Tests

    /// The reported defect. Styled narrow — which is what every fresh editor does, because SwiftUI
    /// styles before it sizes — then widened, the fragment must grow with the picture.
    ///
    /// Two assertions, because either alone is weak. The inequality is absolute and is the thing
    /// the user sees: a fragment that cannot hold the picture is prose painted on top of it. The
    /// equality is relative and says the width-only refresh lands exactly where a full restyle at
    /// the same width lands, which is the contract without restating any of the styler's literals.
    @Test func wideningTheEditorReflowsTheImagesReservedHeight() throws {
        let (scrollView, textView) = makeEditor(width: 320)
        resize(scrollView, to: 760)

        let fragment = try imageLineFragment(in: textView)
        let drawn = drawnImageHeight(in: textView)
        #expect(
            fragment.height >= drawn + MarkdownDecorationGeometry.imageLinePadding - 0.5,
            "fragment \(fragment.height)pt cannot hold a \(drawn)pt image"
        )

        let restyled = try imageLineFragment(in: makeEditor(width: 760).textView)
        #expect(
            abs(fragment.height - restyled.height) < 0.5,
            "refreshed to \(fragment.height)pt where a restyle gives \(restyled.height)pt"
        )
    }

    /// Narrowing is the same bug with the sign flipped: the fragment must shrink back, or the note
    /// keeps a band of dead space where the wider picture used to be.
    @Test func narrowingTheEditorReflowsTheImagesReservedHeight() throws {
        let (scrollView, textView) = makeEditor(width: 760)
        let before = try imageLineFragment(in: textView)
        resize(scrollView, to: 320)

        let fragment = try imageLineFragment(in: textView)
        #expect(
            fragment.height < before.height - 0.5,
            "fragment stayed at \(fragment.height)pt after narrowing from \(before.height)pt"
        )

        let restyled = try imageLineFragment(in: makeEditor(width: 320).textView)
        #expect(
            abs(fragment.height - restyled.height) < 0.5,
            "refreshed to \(fragment.height)pt where a restyle gives \(restyled.height)pt"
        )
    }

    /// The user-visible form of the same fact, measured against the rect the draw pass actually
    /// cached: the picture is inside its own line fragment, so no other line's glyphs can land on
    /// it.
    @Test func aDrawnImageStaysInsideItsLineFragmentAfterAResize() throws {
        let (scrollView, textView) = makeEditor(width: 320)
        resize(scrollView, to: 760)

        textView.markdownImageRects.removeAll()
        let renderRect = NSRect(origin: .zero, size: textView.bounds.size)
        let rep = try #require(textView.bitmapImageRepForCachingDisplay(in: renderRect))
        textView.cacheDisplay(in: renderRect, to: rep)

        let imageRect = try #require(textView.markdownImageRects[Self.imageID])
        let fragment = try imageLineFragment(in: textView)
        #expect(
            fragment.insetBy(dx: 0, dy: -0.5).contains(imageRect),
            "image \(imageRect) escapes its fragment \(fragment)"
        )
    }

    /// The editor is styled before SwiftUI gives it a frame, so the very first layout pass is the
    /// one the user sees on a fresh launch. It has to land at the real width, with no edit.
    @Test func aFreshEditorStyledBeforeItWasSizedStillReservesTheRightHeight() throws {
        let scrollView = NSScrollView(frame: NSRect.zero)
        let storage = NSTextStorage()
        let layoutManager = CadenceLayoutManager()
        let container = NSTextContainer(
            containerSize: NSSize(width: 1, height: CGFloat.greatestFiniteMagnitude)
        )
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)

        let textView = CadenceTextView(frame: NSRect.zero, textContainer: container)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.isEditable = true
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: Self.inset, height: Self.inset)
        textView.font = MarkdownStylist.baseFont
        textView.typingAttributes = MarkdownStylist.baseAttributes
        textView.markdownImageAssets = [Self.imageID: Self.imageAsset]
        textView.string = Self.markdown
        scrollView.documentView = textView

        // Exactly the order `MarkdownEditorView` runs in: style, then get a frame.
        MarkdownStylist.apply(to: textView)
        scrollView.setFrameSize(NSSize(width: 760, height: 600))
        MarkdownEditorScrollSupport.refreshLayout(in: scrollView)

        let fragment = try imageLineFragment(in: textView)
        let drawn = drawnImageHeight(in: textView)
        #expect(
            fragment.height >= drawn + MarkdownDecorationGeometry.imageLinePadding - 0.5,
            "fragment \(fragment.height)pt cannot hold a \(drawn)pt image"
        )

        let restyled = try imageLineFragment(in: makeEditor(width: 760).textView)
        #expect(
            abs(fragment.height - restyled.height) < 0.5,
            "refreshed to \(fragment.height)pt where a restyle gives \(restyled.height)pt"
        )
    }

    /// Nothing above proves the app ever *reaches* the refresh: every test so far calls
    /// `MarkdownEditorScrollSupport.refreshLayout` by hand, and in the app the only caller on a
    /// width change is `MarkdownEditorScrollView.layout()`. So this one installs the real scroll
    /// view in a real window, widens the window, and lets AppKit run its own layout pass — no test
    /// code touches the editor between the resize and the measurement.
    @Test func theScrollViewsOwnLayoutPassReflowsTheImage() throws {
        let scrollView = MarkdownEditorScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 600))
        let textView = install(in: scrollView, styling: false)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        let contentView = try #require(window.contentView)
        scrollView.autoresizingMask = [.width, .height]
        contentView.addSubview(scrollView)
        contentView.layoutSubtreeIfNeeded()

        MarkdownStylist.apply(to: textView)
        let before = try imageLineFragment(in: textView)

        window.setContentSize(NSSize(width: 760, height: 600))
        contentView.layoutSubtreeIfNeeded()

        let fragment = try imageLineFragment(in: textView)
        let drawn = drawnImageHeight(in: textView)
        #expect(
            fragment.height > before.height + 0.5,
            "the layout pass left the fragment at \(fragment.height)pt"
        )
        #expect(
            fragment.height >= drawn + MarkdownDecorationGeometry.imageLinePadding - 0.5,
            "fragment \(fragment.height)pt cannot hold a \(drawn)pt image"
        )
    }

    /// The refresh must not look like an edit.
    ///
    /// It writes paragraph styles straight onto the text storage rather than through
    /// `shouldChangeText` / `didChangeText`, which is what keeps it out of the undo stack and out
    /// of `textDidChange`. If it went the other way, every window resize would look to
    /// `MarkdownEditorCoordinator` like the user had typed: the note's `updatedAt` would move and
    /// CloudKit would get a write, for a change that alters no character.
    @Test func aWidthChangeIsNotReportedAsATextEdit() throws {
        let (scrollView, textView) = makeEditor(width: 320)
        let recorder = TextChangeRecorder()
        textView.delegate = recorder

        resize(scrollView, to: 760)

        #expect(recorder.changes == 0)
        #expect(try imageLineFragment(in: textView).height > 300)
        textView.delegate = nil
    }

    /// The refresh converges. It runs from a layout pass, and a pass that rewrote a paragraph style
    /// every time would invalidate layout on every layout — so a second call at an unchanged width
    /// has to find nothing to do.
    @Test func refreshingTwiceAtOneWidthIsANoOp() throws {
        let (scrollView, textView) = makeEditor(width: 320)
        resize(scrollView, to: 760)

        #expect(MarkdownStylist.refreshImageBlockLayout(in: textView) == false)
    }
}

/// Counts the `textDidChange` callbacks `MarkdownEditorCoordinator` would have received.
@MainActor
private final class TextChangeRecorder: NSObject, NSTextViewDelegate {
    private(set) var changes = 0

    func textDidChange(_ notification: Notification) {
        changes += 1
    }
}
#endif
