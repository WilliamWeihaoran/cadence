import Foundation
import Testing
#if os(macOS)
import AppKit
#endif
@testable import Cadence

#if os(macOS)
/// The markdown editor's decoration draw order, rendered offscreen and measured.
///
/// Two of the editor's eight decoration passes moved off `CadenceLayoutManager` and onto
/// `CadenceTextView.drawBackground(in:)` so the layout manager's overrides could match the
/// nonisolated declarations they override (T-105). AppKit offers no main-actor hook *between* the
/// background pass and the glyph pass, so that move necessarily changed where the task-embed card
/// and the standalone image sit in the paint order — and nothing about that is visible to a unit
/// test that only reads geometry.
///
/// So these render the real view into a bitmap and compare pixels. They are the regression guard on
/// the three questions that kept the refactor unlanded: whether a multi-line selection still washes
/// out an embed card, whether anything drawn later (the selection highlight, and therefore the
/// caret) is still on top of the decorations, and whether deriving the glyph range from the dirty
/// rect leaves partial-redraw artefacts.
@MainActor
struct MarkdownEditorDrawOrderTests {
    private static let embedID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private static let imageID = UUID(uuidString: "66666666-7777-8888-9999-000000000000")!

    private static let markdown = """
    # Decoration order

    Prose above the embed.

    [[task:11111111-2222-3333-4444-555555555555|Write the release notes]]

    Prose between the embed and the image.

    ![image](cadence-image://66666666-7777-8888-9999-000000000000)

    Prose below the image.

    > A quote line.

    - [x] A checklist item

    Some `inline code` and ==a highlight== in one line.

    ---

    Trailing prose.
    """

    // MARK: - Fixture

    private func makeTextView() -> CadenceTextView {
        let storage = NSTextStorage()
        let layoutManager = CadenceLayoutManager()
        let containerWidth: CGFloat = 560 - 36
        let container = NSTextContainer(
            containerSize: NSSize(width: containerWidth, height: .greatestFiniteMagnitude)
        )
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)

        let textView = CadenceTextView(
            frame: NSRect(x: 0, y: 0, width: 560, height: 1200),
            textContainer: container
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.isEditable = true
        textView.isRichText = true
        textView.backgroundColor = Theme.nsBg
        textView.insertionPointColor = Theme.nsBlue
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.font = MarkdownStylist.baseFont
        textView.typingAttributes = MarkdownStylist.baseAttributes

        textView.markdownTaskEmbeds = [Self.embedID: Self.embedInfo]
        textView.markdownImageAssets = [Self.imageID: Self.imageAsset]
        textView.string = Self.markdown
        MarkdownStylist.apply(to: textView)
        textView.layoutManager?.ensureLayout(for: container)
        return textView
    }

    private static var embedInfo: MarkdownTaskEmbedRenderInfo {
        MarkdownTaskEmbedRenderInfo(
            id: embedID,
            title: "Write the release notes",
            statusRaw: TaskStatus.todo.rawValue,
            priorityRaw: TaskPriority.high.rawValue,
            sectionName: "",
            containerName: "Cadence",
            containerColorHex: Theme.blueHex,
            dueDate: "2030-04-18",
            scheduledDate: "",
            scheduledStartMin: -1,
            estimatedMinutes: 45,
            actualMinutes: 0,
            recurrenceRaw: TaskRecurrenceRule.none.rawValue,
            isDone: false,
            isCancelled: false,
            isMissing: false,
            subtasks: []
        )
    }

    private static var imageAsset: MarkdownImageRenderAsset {
        let size = NSSize(width: 320, height: 160)
        let image = NSImage(size: size)
        image.lockFocus()
        Theme.nsBlue.setFill()
        NSRect(origin: .zero, size: size).fill()
        Theme.nsText.setFill()
        NSRect(x: 20, y: 20, width: 120, height: 60).fill()
        image.unlockFocus()
        return MarkdownImageRenderAsset(id: imageID, image: image, displayWidth: 320, pixelSize: size)
    }

    private func render(_ textView: CadenceTextView, in rect: NSRect) -> NSBitmapImageRep {
        let rep = textView.bitmapImageRepForCachingDisplay(in: rect)!
        textView.cacheDisplay(in: rect, to: rep)
        return rep
    }

    private func selectionRange(from: String, throughEndOf: String) -> NSRange {
        let ns = Self.markdown as NSString
        let start = ns.range(of: from).location
        let end = NSMaxRange(ns.range(of: throughEndOf))
        return NSRange(location: start, length: end - start)
    }

    // MARK: - The two moved passes still run

    /// The passes write the hit-rect caches that clicking a card, a checkbox or a resize handle is
    /// measured against. If they stopped running from the view's hook, clicks would silently miss
    /// while everything still looked right.
    @Test func drawingTheViewPopulatesBothHitRectCaches() throws {
        let textView = makeTextView()
        textView.markdownTaskEmbedRects.removeAll()
        textView.markdownImageRects.removeAll()

        _ = render(textView, in: textView.bounds)

        let card = try #require(textView.markdownTaskEmbedRects[Self.embedID])
        let image = try #require(textView.markdownImageRects[Self.imageID])
        #expect(card.card.width > 0 && card.card.height > 0)
        #expect(card.checkbox.intersects(card.card))
        #expect(image.width > 0 && image.height > 0)
    }

    // MARK: - Question 1 / 2: what is drawn on top of the moved decorations

    /// A selection running from the prose above an embed to the prose below it still covers the
    /// card. The embed line is hidden by collapsing its glyphs, so the selection rect for its
    /// trailing newline spans the whole container — and that rect is drawn by the layout manager,
    /// i.e. *after* the view hook the card now draws from.
    ///
    /// This is also the answer to the insertion point: the caret is drawn no earlier than the
    /// selection highlight, so anything the highlight covers, the caret is on top of too.
    @Test func aSelectionSpanningAnEmbedIsStillDrawnOverTheCard() throws {
        let textView = makeTextView()
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        _ = render(textView, in: textView.bounds)
        let cardRect = try #require(textView.markdownTaskEmbedRects[Self.embedID]?.card)
        let probe = cardRect.insetBy(dx: 8, dy: 8)

        let plain = render(textView, in: probe)
        textView.setSelectedRange(selectionRange(from: "Prose above", throughEndOf: "Prose below the image."))
        let selected = render(textView, in: probe)

        #expect(Self.changedFraction(plain, selected) > 0.9)
    }

    /// The image is the one pass whose order against the selection highlight genuinely flipped, and
    /// it is unobservable: an image line keeps its glyphs at full size, so the only selection rect
    /// drawn on it is the trailing newline's, which starts past the reference text and lands to the
    /// right of the drawn image. The image renders the same whichever is drawn first.
    @Test func aSelectionSpanningAnImageDoesNotReachTheDrawnImage() throws {
        let textView = makeTextView()
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        _ = render(textView, in: textView.bounds)
        let imageRect = try #require(textView.markdownImageRects[Self.imageID])
        let probe = imageRect.insetBy(dx: 8, dy: 8)

        let plain = render(textView, in: probe)
        textView.setSelectedRange(selectionRange(from: "Prose above", throughEndOf: "Prose below the image."))
        let selected = render(textView, in: probe)

        #expect(Self.changedFraction(plain, selected) == 0)
    }

    // MARK: - Question 3: partial redraw

    /// The moved passes derive their glyph range from the dirty rect instead of being handed one,
    /// so a band redrawn on its own has to come out the same as that band inside a full redraw.
    /// It does, because both decorations are contained by the line fragment reserved for them —
    /// see `MarkdownDecorationGeometryTests`.
    @Test func redrawingOneBandMatchesTheSameBandOfAFullRedraw() {
        let textView = makeTextView()
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        let full = textView.bounds
        let reference = render(textView, in: full)

        var worst = 0
        var bandTop: CGFloat = 0
        let bandHeight: CGFloat = 24
        while bandTop < full.height {
            let band = NSRect(
                x: 0,
                y: bandTop,
                width: full.width,
                height: min(bandHeight, full.height - bandTop)
            )
            let partial = render(textView, in: band)
            worst = max(worst, Self.bandDifference(reference: reference, band: band, partial: partial, viewHeight: full.height))
            bandTop += bandHeight
        }

        // 1 is antialiasing rounding at a band edge, and is what the pre-refactor drawing order
        // measured too. Anything larger is a decoration clipped by the redraw.
        #expect(worst <= 1)
    }

    // MARK: - Pixel helpers

    private static func changedFraction(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> Double {
        guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh else { return .nan }
        var changed = 0
        var total = 0
        for y in 0..<a.pixelsHigh {
            for x in 0..<a.pixelsWide {
                total += 1
                if a.colorAt(x: x, y: y) != b.colorAt(x: x, y: y) { changed += 1 }
            }
        }
        return total == 0 ? 0 : Double(changed) / Double(total)
    }

    /// `cacheDisplay(in:to:)` does not document whether the rep it fills is top-down or bottom-up
    /// for a flipped view, and getting that backwards would fake a mismatch — so both mappings are
    /// measured and the smaller is returned. A real artefact is non-zero under both.
    private static func bandDifference(
        reference: NSBitmapImageRep,
        band: NSRect,
        partial: NSBitmapImageRep,
        viewHeight: CGFloat
    ) -> Int {
        let scale = Double(reference.pixelsHigh) / Double(viewHeight)
        let topDownOffset = Int(Double(band.minY) * scale)
        let bottomUpOffset = reference.pixelsHigh - Int(Double(band.maxY) * scale)
        var worstTopDown = 0
        var worstBottomUp = 0
        for y in 0..<partial.pixelsHigh {
            for x in 0..<partial.pixelsWide where x < reference.pixelsWide {
                guard let p = partial.colorAt(x: x, y: y) else { continue }
                let topDownY = y + topDownOffset
                if topDownY >= 0, topDownY < reference.pixelsHigh, let r = reference.colorAt(x: x, y: topDownY) {
                    worstTopDown = max(worstTopDown, channelDelta(p, r))
                }
                let bottomUpY = partial.pixelsHigh - 1 - y + bottomUpOffset
                if bottomUpY >= 0, bottomUpY < reference.pixelsHigh, let r = reference.colorAt(x: x, y: bottomUpY) {
                    worstBottomUp = max(worstBottomUp, channelDelta(p, r))
                }
            }
        }
        return min(worstTopDown, worstBottomUp)
    }

    private static func channelDelta(_ a: NSColor, _ b: NSColor) -> Int {
        max(
            abs(Int(a.redComponent * 255) - Int(b.redComponent * 255)),
            max(
                abs(Int(a.greenComponent * 255) - Int(b.greenComponent * 255)),
                abs(Int(a.blueComponent * 255) - Int(b.blueComponent * 255))
            )
        )
    }
}
#endif
