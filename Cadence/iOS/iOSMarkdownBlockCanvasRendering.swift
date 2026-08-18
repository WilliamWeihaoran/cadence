#if os(iOS)
import UIKit

extension NSAttributedString.Key {
    /// A pre-rendered canvas to paint over a hidden run — a table, a fenced code block, a divider,
    /// an image, a task embed, a quote bar, a checkbox.
    /// `nonisolated` because the layout manager reads it from a `nonisolated` drawing override; it
    /// is an immutable key, so there is nothing here for the main actor to protect.
    nonisolated static let cadenceMarkdownBlockCanvas = NSAttributedString.Key("CadenceMarkdownBlockCanvas")
}

/// What `cadenceMarkdownBlockCanvas` carries.
///
/// **Why this exists at all.** Every rendered block in the iOS editor used to be an
/// `NSTextAttachment` hung on the block's first *existing* character, with the rest of the run
/// hidden behind it. That does not draw. TextKit only turns an attachment into a glyph where the
/// text actually contains the attachment character `U+FFFC`; setting `.attachment` on an ordinary
/// `|`, backtick or `-` reserves nothing and paints nothing. The paragraph style still reserved the
/// canvas's height, so a table, a code block and a divider each rendered as a tall empty gap with
/// one stray source character floating in it. Confirmed by painting a canvas pure red and seeing no
/// red at all.
///
/// Inserting real `U+FFFC` characters was the other way out, and it is the wrong one here: the
/// editor maps storage ranges onto markdown offsets everywhere — hidden-range caret snapping,
/// rendered-block deletion, reference hit-testing — and every one of those mappings assumes the
/// storage string *is* the note.
///
/// So the canvas becomes a decoration the layout manager paints, which is the approach the macOS
/// editor already takes for its table rows (`MarkdownEditorInteractionSupport.drawTableRows`). The
/// source run is hidden, the paragraph style reserves the height, and
/// `iOSMarkdownBlockCanvasLayoutManager` draws the image into the space that reserved.
final class iOSMarkdownBlockCanvas: NSObject {
    let image: UIImage
    /// `true` for a canvas that owns its whole line — table, code block, divider, image, task
    /// embed. It is drawn against the line fragment, which is the box the paragraph style sized.
    /// `false` for an inline marker — a quote bar or a checkbox — which is drawn at the glyph it
    /// replaces, inside a line whose other text still shows.
    let isBlock: Bool
    /// Nudge from the natural position, matching the `bounds.origin.y` the attachments used to set.
    let yOffset: CGFloat
    /// Left inset for a block canvas, so it lines up with the text column rather than the container
    /// edge.
    let leadingInset: CGFloat

    init(image: UIImage, isBlock: Bool, yOffset: CGFloat, leadingInset: CGFloat = 0) {
        self.image = image
        self.isBlock = isBlock
        self.yOffset = yOffset
        self.leadingInset = leadingInset
        super.init()
    }

    /// Where a block canvas is painted, in text-container coordinates.
    ///
    /// **The one definition of "where the card is".** The layout manager draws from it and
    /// `iOSMarkdownEditor` hit-tests against it, so the card you tap is the card you see — the same
    /// arrangement the macOS editor already has, where `drawTaskEmbeds` and `taskEmbedHit` both go
    /// through `MarkdownTaskEmbedDrawing.cardRect`.
    ///
    /// Hit testing used to derive its own rect from `boundingRect(forGlyphRange:in:)` over the
    /// run's first character. Every character of a rendered block is hidden at 0.1pt, so that rect
    /// was a tenth of a point wide: a tap anywhere on a task-embed card except its extreme leading
    /// edge missed the card entirely and fell through to the text view, which placed a caret.
    ///
    /// `nonisolated` because it is pure geometry over its arguments, and both callers need it:
    /// the hit test runs on the main actor, the drawing pass does not (see the layout manager).
    nonisolated static func blockRect(inLineFragment fragment: CGRect, size: CGSize, leadingInset: CGFloat, yOffset: CGFloat) -> CGRect {
        // Centred in the box the paragraph style reserved, so a canvas that came out a few points
        // shorter than its reservation does not sit against the top edge.
        CGRect(
            x: fragment.minX + leadingInset,
            y: fragment.minY + max(0, (fragment.height - size.height) / 2) + yOffset,
            width: size.width,
            height: size.height
        )
    }
}

/// Paints `cadenceMarkdownBlockCanvas` runs after the glyphs beneath them.
///
/// Requires TextKit 1 — `iOSMarkdownTextView` builds its stack explicitly for that reason.
///
/// `NSLayoutManager` is nonisolated in UIKit, but the project builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so this subclass and every member of it is
/// main-actor isolated by default — and a main-actor override of a nonisolated declaration is an
/// error in Swift 6 language mode. All three overrides below are therefore declared `nonisolated`,
/// matching what they override, and each is trivially safe: the class has no instance stored
/// properties, and `drawGlyphs` reads only `textStorage`, the layout manager's own geometry, the
/// immutable `iOSMarkdownBlockCanvas` value it finds in an attribute run, and draws its image into
/// the context TextKit has already made current. Unlike the macOS `drawBackground` blocked by
/// [T-105], no pass here reads or writes any text-view state.
final class iOSMarkdownBlockCanvasLayoutManager: NSLayoutManager {
    /// Breathing room between an inline marker and the text it introduces.
    nonisolated private static let inlineMarkerGap: CGFloat = 6

    nonisolated override init() {
        super.init()
    }

    nonisolated required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    nonisolated override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)

        guard let storage = textStorage else { return }

        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(.cadenceMarkdownBlockCanvas, in: charRange, options: []) { value, range, _ in
            guard let canvas = value as? iOSMarkdownBlockCanvas, range.length > 0 else { return }
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }

            let fragment = self.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            let size = canvas.image.size
            let rect: CGRect

            if canvas.isBlock {
                rect = iOSMarkdownBlockCanvas.blockRect(
                    inLineFragment: fragment,
                    size: size,
                    leadingInset: canvas.leadingInset,
                    yOffset: canvas.yOffset
                )
                .offsetBy(dx: origin.x, dy: origin.y)
            } else {
                // The marker's glyph is hidden and therefore ~zero-width, so its location is where
                // the line's *text* now starts — draw there and the bar or checkbox sits on top of
                // the first letter. It goes in the head indent instead, immediately before the
                // text, which is the space the `> ` or `- [ ] ` prefix used to occupy.
                let location = self.location(forGlyphAt: glyphRange.location)
                let x = max(0, fragment.minX + location.x - size.width - Self.inlineMarkerGap)

                // Centred on the **first line's** box, not sat on the baseline.
                //
                // Resting the marker's bottom edge on the baseline is the obvious placement and it
                // reads wrong: a 16pt circle beside ~11pt of lowercase text then occupies the whole
                // ascender zone and floats above the words. The line fragment is the box the text
                // actually fills, so centring in it puts the circle level with the text.
                //
                // `lineFragmentRect` for this glyph is the run's *first* line, so a checklist item
                // that wraps keeps its marker beside the first line rather than drifting to the
                // middle of the paragraph.
                let y = fragment.minY + (fragment.height - size.height) / 2 - canvas.yOffset
                rect = CGRect(x: origin.x + x, y: origin.y + y, width: size.width, height: size.height)
            }

            canvas.image.draw(in: rect)
        }
    }
}
#endif
