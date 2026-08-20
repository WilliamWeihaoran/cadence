#if os(macOS)
import AppKit
import SwiftData
import Testing
@testable import Cadence

/// How a stored display width and a stored pixel aspect become a rendered box, and what a resize
/// drag resolves to.
///
/// **Why this suite exists.** Images in notes were rendering vertically squashed on iOS. The cause
/// was one line: the iOS renderer finished its sizing with
/// `CGSize(width: width, height: min(max(96, width * aspect), 520))` — a floor and a ceiling
/// applied to the height while the width stayed where it was, so any picture taller than 520pt at
/// its laid-out width was flattened to fit and any picture shorter than 96pt was stretched to fill.
/// A 1170 × 2532 phone screenshot at 326pt wide wants 705pt and got 520: 74% of its height. macOS
/// had the same shape of bug in the other direction (`max(60, width * aspect)`), which stretched
/// wide banners.
///
/// None of that arithmetic had a test. It is pure, it is four lines, and both platforms' editors
/// draw from it — so this suite pins it at both ends and at the degenerate inputs, and then pins it
/// again through the **macOS render path**, where the numbers actually reach a pixel.
@MainActor
struct MarkdownImageSizingTests {
    private static let portraitScreenshot = CGSize(width: 1_170, height: 2_532)   // aspect 2.164
    private static let landscapePhoto = CGSize(width: 4_032, height: 3_024)       // aspect 0.75
    private static let wideBanner = CGSize(width: 1_600, height: 100)             // aspect 0.0625

    private func aspect(_ size: CGSize) -> CGFloat { size.height / size.width }

    // MARK: - The aspect itself

    @Test func aspectRatioIsHeightOverWidth() {
        #expect(MarkdownImageAssetService.aspectRatio(pixelSize: CGSize(width: 1_600, height: 900)) == 0.5625)
        #expect(MarkdownImageAssetService.aspectRatio(pixelSize: CGSize(width: 100, height: 400)) == 4)
    }

    /// `MarkdownImageAsset.pixelWidth`/`pixelHeight` default to `0` — a CloudKit requirement, and
    /// what a row synced from a build that never wrote them arrives holding. `renderAsset` used to
    /// read `max(pixelWidth, 1)`, which turned that into a 1 × 1 aspect: a **square**, not a
    /// squash, but a picture drawn as the wrong shape either way.
    @Test func aspectRatioFallsBackWhenThePixelSizeIsMissingOrDegenerate() {
        let fallback = MarkdownImageAssetService.fallbackAspectRatio
        #expect(MarkdownImageAssetService.aspectRatio(pixelSize: .zero) == fallback)
        #expect(MarkdownImageAssetService.aspectRatio(pixelSize: CGSize(width: 640, height: 0)) == fallback)
        #expect(MarkdownImageAssetService.aspectRatio(pixelSize: CGSize(width: 0, height: 360)) == fallback)
        #expect(MarkdownImageAssetService.aspectRatio(pixelSize: CGSize(width: -640, height: 360)) == fallback)
        // Not 1:1 — the value the old `max(_, 1)` produced.
        #expect(MarkdownImageAssetService.aspectRatio(pixelSize: .zero) != 1)
    }

    /// The stored size wins when it is usable; the decoded bitmap answers when it is not. The
    /// bitmap cannot be wrong about its own shape, so a row with no pixel size still renders
    /// correctly instead of falling back to a generic 16:9.
    @Test func resolvedPixelSizePrefersTheStoredSizeAndFallsBackToTheBitmap() {
        let decoded = CGSize(width: 800, height: 200)

        #expect(
            MarkdownImageAssetService.resolvedPixelSize(storedWidth: 640, storedHeight: 360, decoded: decoded)
                == CGSize(width: 640, height: 360)
        )
        #expect(MarkdownImageAssetService.resolvedPixelSize(storedWidth: 0, storedHeight: 0, decoded: decoded) == decoded)
        // A half-written row is not half-trusted.
        #expect(MarkdownImageAssetService.resolvedPixelSize(storedWidth: 640, storedHeight: 0, decoded: decoded) == decoded)
        #expect(MarkdownImageAssetService.resolvedPixelSize(storedWidth: 0, storedHeight: 0, decoded: .zero) == .zero)
    }

    /// An asset created through the normal path decodes back to the aspect it was created at, all
    /// the way through `renderAsset` — the function every editor calls to get something drawable.
    @Test func renderAssetCarriesTheRealPixelAspect() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let source = NSImage(size: NSSize(width: 300, height: 900))
        source.lockFocus()
        Theme.nsBlue.setFill()
        NSRect(x: 0, y: 0, width: 300, height: 900).fill()
        source.unlockFocus()

        let asset = try #require(MarkdownImageAssetService.createAsset(from: source, in: context))
        let rendered = try #require(MarkdownImageAssetService.renderAsset(for: asset.id, in: [asset]))
        #expect(abs(aspect(rendered.pixelSize) - 3) < 0.01)

        // And with the stored size wiped — the CloudKit-default case — the decoded bitmap still
        // reports 1:3 rather than the 1:1 square `max(_, 1)` produced.
        asset.pixelWidth = 0
        asset.pixelHeight = 0
        let repaired = try #require(MarkdownImageAssetService.renderAsset(for: asset.id, in: [asset]))
        #expect(abs(aspect(repaired.pixelSize) - 3) < 0.01)
    }

    // MARK: - fittedSize

    /// The regression. A tall picture laid out at a phone's content width keeps its aspect exactly;
    /// under the old ceiling it came back 520pt tall at the same width.
    @Test func aTallImageKeepsItsAspectAtAPhoneContentWidth() {
        let size = MarkdownImageAssetService.fittedSize(
            displayWidth: 520,
            pixelSize: Self.portraitScreenshot,
            maxWidth: 326
        )
        #expect(size.width == 326)
        #expect(abs(size.height - 326 * aspect(Self.portraitScreenshot)) < 0.001)
        // The number the bug produced, named so the test says what it is guarding.
        #expect(size.height > 520)
    }

    /// The other half of the same bug, on macOS: a height *floor* stretched a wide banner. 1600×100
    /// at 520pt wide is 32.5pt tall, and `max(60, …)` drew it 85% too tall.
    @Test func aWideImageIsNotStretchedToAMinimumHeight() {
        let size = MarkdownImageAssetService.fittedSize(
            displayWidth: 520,
            pixelSize: Self.wideBanner,
            maxWidth: 900
        )
        #expect(size.width == 520)
        #expect(abs(size.height - 32.5) < 0.001)
    }

    /// Aspect is preserved across the whole range of widths a user can drag to, not only at the
    /// default — a sizing function that happened to be right at one width and wrong either side of
    /// it would pass a single-point test.
    @Test func aspectIsPreservedAtEveryWidth() {
        for pixelSize in [Self.portraitScreenshot, Self.landscapePhoto, Self.wideBanner] {
            for width in stride(from: 120.0, through: 1_200.0, by: 60.0) {
                let size = MarkdownImageAssetService.fittedSize(
                    displayWidth: width,
                    pixelSize: pixelSize,
                    maxWidth: 2_000
                )
                #expect(abs(aspect(size) - aspect(pixelSize)) < 0.0001, "width \(width), pixels \(pixelSize)")
            }
        }
    }

    /// The text column, not the stored width, is the ceiling when the column is narrower — and the
    /// height comes down with it rather than staying where it was.
    @Test func theContentWidthCapsTheStoredWidthAndTheHeightFollows() {
        let full = MarkdownImageAssetService.fittedSize(
            displayWidth: 520,
            pixelSize: Self.landscapePhoto,
            maxWidth: 900
        )
        let narrow = MarkdownImageAssetService.fittedSize(
            displayWidth: 520,
            pixelSize: Self.landscapePhoto,
            maxWidth: 260
        )
        #expect(full.width == 520)
        #expect(narrow.width == 260)
        #expect(abs(narrow.height / full.height - 260 / 520) < 0.0001)
    }

    /// A width below the persisted minimum is raised to it, so a render never disagrees with what
    /// `setDisplayWidth` would have stored.
    @Test func fittedSizeFloorsAtTheMinimumDisplayWidth() {
        let size = MarkdownImageAssetService.fittedSize(
            displayWidth: 10,
            pixelSize: Self.landscapePhoto,
            maxWidth: 900
        )
        #expect(size.width == MarkdownImageAssetService.minDisplayWidth)
    }

    /// When the safety ceiling on height is reached the **width comes down with it**. That is the
    /// whole difference between this and the bug: the old code held the width and cut the height.
    @Test func theHeightCeilingNarrowsTheWidthInsteadOfFlatteningTheImage() {
        let pixelSize = CGSize(width: 100, height: 1_000)   // aspect 10
        let size = MarkdownImageAssetService.fittedSize(
            displayWidth: 500,
            pixelSize: pixelSize,
            maxWidth: 900,
            maxHeight: 1_000
        )
        #expect(size.height == 1_000)
        #expect(abs(size.width - 100) < 0.001)
        #expect(abs(aspect(size) - 10) < 0.0001)
    }

    /// A missing pixel size still produces a usable box rather than a zero, a NaN or a square.
    @Test func fittedSizeSurvivesAMissingPixelSize() {
        let size = MarkdownImageAssetService.fittedSize(displayWidth: 400, pixelSize: .zero, maxWidth: 900)
        #expect(size.width == 400)
        #expect(size.height > 0)
        #expect(size.height.isFinite)
        #expect(abs(aspect(size) - MarkdownImageAssetService.fallbackAspectRatio) < 0.0001)
    }

    @Test func fittedSizeSurvivesNonFiniteInputs() {
        let size = MarkdownImageAssetService.fittedSize(
            displayWidth: .nan,
            pixelSize: CGSize(width: 640, height: 360),
            maxWidth: .infinity
        )
        #expect(size.width.isFinite)
        #expect(size.height.isFinite)
        #expect(size.width > 0)
    }

    // MARK: - The drag → width resolution

    /// Both ends of the clamp and the middle. `resolvedDisplayWidth` is what the macOS mouse drag
    /// and the iOS pan both compute, so a drag that runs off either end of the range stops at it
    /// rather than writing a width the renderer then has to defend against.
    @Test func aResizeDragResolvesToAClampedWidth() {
        let minimum = MarkdownImageAssetService.minDisplayWidth
        let maximum = MarkdownImageAssetService.maxDisplayWidth

        // Middle: travel is added, not ignored.
        #expect(MarkdownImageAssetService.resolvedDisplayWidth(startWidth: 300, translation: 120) == 420)
        #expect(MarkdownImageAssetService.resolvedDisplayWidth(startWidth: 300, translation: -120) == 180)
        // No movement is no change.
        #expect(MarkdownImageAssetService.resolvedDisplayWidth(startWidth: 300, translation: 0) == 300)
        // Upper end.
        #expect(MarkdownImageAssetService.resolvedDisplayWidth(startWidth: 1_100, translation: 5_000) == maximum)
        #expect(MarkdownImageAssetService.resolvedDisplayWidth(startWidth: maximum, translation: 1) == maximum)
        // Lower end — dragging left past the minimum stops there and does not go negative.
        #expect(MarkdownImageAssetService.resolvedDisplayWidth(startWidth: 200, translation: -5_000) == minimum)
        #expect(MarkdownImageAssetService.resolvedDisplayWidth(startWidth: minimum, translation: -1) == minimum)
        // A garbage translation leaves the width alone rather than poisoning it with NaN.
        #expect(MarkdownImageAssetService.resolvedDisplayWidth(startWidth: 300, translation: .nan) == 300)
    }

    /// A drag never changes the shape of the picture — only how much room it takes. Resolving a
    /// width and rendering it is the full round trip both platforms perform on every drag sample.
    @Test func draggingChangesSizeButNeverAspect() throws {
        let pixelSize = Self.portraitScreenshot
        var widths: [CGFloat] = []
        for travel in stride(from: -600.0, through: 900.0, by: 75.0) {
            let width = MarkdownImageAssetService.resolvedDisplayWidth(startWidth: 400, translation: travel)
            let size = MarkdownImageAssetService.fittedSize(
                displayWidth: width,
                pixelSize: pixelSize,
                maxWidth: 1_400
            )
            #expect(abs(aspect(size) - aspect(pixelSize)) < 0.0001, "travel \(travel)")
            widths.append(size.width)
        }
        // And the drag actually moved through a range of widths, so the assertion above is not
        // vacuously true of a function that returns one constant.
        let widest = try #require(widths.max())
        let narrowest = try #require(widths.min())
        #expect(widest - narrowest > 500)
    }

    /// The persisted write goes through the same clamp the drag resolver does.
    @Test func setDisplayWidthAndTheDragResolverAgree() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let image = NSImage(size: NSSize(width: 800, height: 400))
        image.lockFocus()
        Theme.nsBlue.setFill()
        NSRect(x: 0, y: 0, width: 800, height: 400).fill()
        image.unlockFocus()
        let asset = try #require(MarkdownImageAssetService.createAsset(from: image, in: context))

        for (start, travel) in [(300.0, 5_000.0), (300.0, -5_000.0), (300.0, 90.0)] {
            let resolved = MarkdownImageAssetService.resolvedDisplayWidth(startWidth: start, translation: travel)
            MarkdownImageAssetService.setDisplayWidth(start + travel, for: asset.id, in: [asset])
            #expect(CGFloat(asset.displayWidth) == resolved)
        }
    }

    // MARK: - The rendered card (the shape the iOS editor draws and hit-tests)

    /// `MarkdownImageBlockLayout` is the iOS card geometry, kept outside `#if os(iOS)` precisely so
    /// it is reachable from this macOS-built target. The picture inside the card keeps the aspect.
    @Test func theRenderedCardKeepsThePictureAspectAndPadsAroundIt() {
        let layout = MarkdownImageBlockLayout.make(
            displayWidth: 520,
            pixelSize: Self.portraitScreenshot,
            maxWidth: 326,
            hasCaption: false
        )
        #expect(abs(aspect(layout.imageRect.size) - aspect(Self.portraitScreenshot)) < 0.0001)
        #expect(layout.canvasSize.width == layout.imageRect.width + MarkdownImageBlockLayout.horizontalPadding * 2)
        #expect(layout.canvasSize.height == layout.imageRect.height + MarkdownImageBlockLayout.verticalPadding * 2)
        #expect(layout.captionRect.height == 0)
    }

    @Test func aCaptionAddsHeightToTheCardWithoutChangingThePicture() {
        let bare = MarkdownImageBlockLayout.make(
            displayWidth: 400,
            pixelSize: Self.landscapePhoto,
            maxWidth: 900,
            hasCaption: false
        )
        let captioned = MarkdownImageBlockLayout.make(
            displayWidth: 400,
            pixelSize: Self.landscapePhoto,
            maxWidth: 900,
            hasCaption: true
        )
        #expect(captioned.imageRect == bare.imageRect)
        #expect(
            captioned.canvasSize.height - bare.canvasSize.height
                == MarkdownImageBlockLayout.captionBlockHeight
        )
        #expect(captioned.captionRect.height > 0)
        #expect(captioned.captionRect.minY > captioned.imageRect.maxY)
        #expect(captioned.captionRect.maxY <= captioned.canvasSize.height)
    }

    /// A finger is not a cursor. The drawn grip is small enough not to cover the picture; the area
    /// that *accepts* the touch is at least the 44pt platform floor, and it is centred on the grip
    /// so what you aim at is what you hit.
    @Test func theResizeHandleHasARealTouchTarget() {
        let layout = MarkdownImageBlockLayout.make(
            displayWidth: 400,
            pixelSize: Self.landscapePhoto,
            maxWidth: 900,
            hasCaption: false
        )
        #expect(layout.handleHitRect.width >= 44)
        #expect(layout.handleHitRect.height >= 44)
        #expect(abs(layout.handleHitRect.midX - layout.handleRect.midX) < 0.001)
        #expect(abs(layout.handleHitRect.midY - layout.handleRect.midY) < 0.001)
        // The grip is drawn inside the picture, at its trailing-bottom corner.
        #expect(layout.imageRect.contains(layout.handleRect))
        #expect(layout.handleRect.maxX < layout.imageRect.maxX)
        #expect(layout.handleRect.maxY < layout.imageRect.maxY)
    }

    /// The touch target still reaches 44pt on the narrowest picture the app allows — a 120pt-wide
    /// image would otherwise get a handle sized to fit inside it.
    @Test func theTouchTargetSurvivesTheNarrowestImage() {
        let layout = MarkdownImageBlockLayout.make(
            displayWidth: MarkdownImageAssetService.minDisplayWidth,
            pixelSize: Self.landscapePhoto,
            maxWidth: 900,
            hasCaption: false
        )
        #expect(layout.handleHitRect.width >= 44)
        #expect(layout.isResizeHandle(localPoint: CGPoint(x: layout.handleRect.midX, y: layout.handleRect.midY)))
    }

    /// The hit test the iOS pan runs at touch-down: yes on the grip, no on the rest of the picture.
    /// If this said yes everywhere, dragging anywhere on an image would resize it instead of
    /// scrolling the note.
    @Test func onlyTheHandleStartsAResize() {
        let layout = MarkdownImageBlockLayout.make(
            displayWidth: 520,
            pixelSize: Self.landscapePhoto,
            maxWidth: 900,
            hasCaption: false
        )
        #expect(layout.isResizeHandle(localPoint: CGPoint(x: layout.handleRect.midX, y: layout.handleRect.midY)))
        // Top-left of the picture, and the middle of it: both plain content.
        #expect(!layout.isResizeHandle(localPoint: CGPoint(x: layout.imageRect.minX + 4, y: layout.imageRect.minY + 4)))
        #expect(!layout.isResizeHandle(localPoint: CGPoint(x: layout.imageRect.midX, y: layout.imageRect.minY + 10)))
        // Outside the card entirely.
        #expect(!layout.isResizeHandle(localPoint: CGPoint(x: -50, y: -50)))
    }

    // MARK: - Through the macOS render path

    /// `MarkdownImageLayoutInfo.fittedSize` is what `MarkdownStylist.applyImageBlock` reserves line
    /// height with and what `CadenceTextView.drawMarkdownImages` draws with. Testing the service
    /// function alone would leave this free to grow its own arithmetic again — which is exactly how
    /// the two platforms drifted apart in the first place.
    @Test func theMacEditorsImageLayoutDerivesHeightFromTheAspect() {
        let info = MarkdownImageLayoutInfo(
            id: UUID(),
            altText: "",
            image: nil,
            displayWidth: 520,
            pixelSize: Self.portraitScreenshot
        )
        let fitted = info.fittedSize(maxWidth: 326)
        #expect(fitted.width == 326)
        #expect(abs(aspect(fitted) - aspect(Self.portraitScreenshot)) < 0.0001)
        #expect(
            fitted == MarkdownImageAssetService.fittedSize(
                displayWidth: 520,
                pixelSize: Self.portraitScreenshot,
                maxWidth: 326
            )
        )
    }

    /// **The end-to-end guard.** A real `CadenceTextView` is laid out and drawn offscreen, and the
    /// rect the image was actually painted into is read back out of the hit-rect cache the draw
    /// pass writes. That rect is what a click, a resize-handle grab and the user's eyes all see.
    ///
    /// This is the test the brief asked for: it fails if *the render path* stops deriving height
    /// from the stored aspect, not merely if a helper does. A helper can stay correct while nothing
    /// calls it.
    @Test func theDrawnImageRectHasTheStoredAspect() throws {
        for pixelSize in [Self.portraitScreenshot, Self.landscapePhoto, Self.wideBanner] {
            let id = UUID()
            let textView = Self.makeTextView(imageID: id, pixelSize: pixelSize, displayWidth: 300)
            let rep = try #require(textView.bitmapImageRepForCachingDisplay(in: textView.bounds))
            textView.cacheDisplay(in: textView.bounds, to: rep)

            let drawn = try #require(textView.markdownImageRects[id], "no image was drawn for \(pixelSize)")
            #expect(drawn.width == 300)
            #expect(
                abs(aspect(drawn.size) - aspect(pixelSize)) < 0.0001,
                "drawn \(drawn.size) for pixels \(pixelSize)"
            )
        }
    }

    /// The line fragment the styler reserves has to contain the rect the draw pass paints, or a
    /// partial redraw clips the image. Both come from `fittedSize`, so a change that broke the
    /// aspect in one and not the other would show up here as an overflow.
    @Test func theReservedLineHeightContainsTheDrawnImage() throws {
        let id = UUID()
        let pixelSize = Self.portraitScreenshot
        let textView = Self.makeTextView(imageID: id, pixelSize: pixelSize, displayWidth: 300)
        let rep = try #require(textView.bitmapImageRepForCachingDisplay(in: textView.bounds))
        textView.cacheDisplay(in: textView.bounds, to: rep)

        let drawn = try #require(textView.markdownImageRects[id])
        let storage = try #require(textView.textStorage)
        let range = (textView.string as NSString).range(of: "![photo](cadence-image://\(id.uuidString))")
        let paragraph = try #require(
            storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
        )
        #expect(paragraph.minimumLineHeight >= drawn.height)
        #expect(
            abs(paragraph.minimumLineHeight - (drawn.height + MarkdownDecorationGeometry.imageLinePadding)) < 0.001
        )
    }

    // MARK: - Fixture

    private static func makeTextView(imageID: UUID, pixelSize: CGSize, displayWidth: CGFloat) -> CadenceTextView {
        let storage = NSTextStorage()
        let layoutManager = CadenceLayoutManager()
        let container = NSTextContainer(
            containerSize: NSSize(width: CGFloat(560 - 36), height: .greatestFiniteMagnitude)
        )
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)

        let textView = CadenceTextView(
            frame: NSRect(x: 0, y: 0, width: 560, height: 2_400),
            textContainer: container
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.isEditable = true
        textView.isRichText = true
        textView.backgroundColor = Theme.nsBg
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.font = MarkdownStylist.baseFont
        textView.typingAttributes = MarkdownStylist.baseAttributes

        // A small stand-in bitmap: the *stored* pixel size is what the sizing reads, and
        // allocating a real 4032 x 3024 backing store three times over costs more than it proves.
        let bitmap = NSImage(size: NSSize(width: 64, height: 64))
        bitmap.lockFocus()
        Theme.nsBlue.setFill()
        NSRect(origin: .zero, size: bitmap.size).fill()
        bitmap.unlockFocus()

        textView.markdownImageAssets = [
            imageID: MarkdownImageRenderAsset(
                id: imageID,
                image: bitmap,
                displayWidth: displayWidth,
                pixelSize: pixelSize
            )
        ]
        textView.string = """
        Above.

        ![photo](cadence-image://\(imageID.uuidString))

        Below.
        """
        MarkdownStylist.apply(to: textView)
        textView.layoutManager?.ensureLayout(for: container)
        return textView
    }
}
#endif
