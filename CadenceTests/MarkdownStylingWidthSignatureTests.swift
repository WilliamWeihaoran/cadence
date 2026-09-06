import Foundation
import Testing
#if os(macOS)
import AppKit
#endif
@testable import Cadence

#if os(macOS)
/// **macOS records what its styling was computed against, and one reader acts on it** (T-1045).
///
/// `MarkdownEditorImageRelayoutTests` pins the *symptom* that made this necessary: a standalone
/// image whose reserved line height was derived from the editor's width at styling time, drawn
/// against the width at painting time, with prose landing on top of the picture whenever the two
/// disagreed. That defect is fixed. These tests pin the *mechanism* that keeps the next
/// width-dependent block from reintroducing it silently.
///
/// The mechanism is two halves and they are tested separately, because each is useless alone:
///
/// - `MarkdownStylist.apply` writes `CadenceTextView.markdownLayoutSignature` — a record with no
///   reader is exactly the hole this ticket names.
/// - `MarkdownStylist.refreshWidthDependentLayout(in:)` reads it, and is the only thing that does.
///   A reader that always says "stale" is a wrapper around the old unconditional call and proves
///   nothing, so the skipping half is measured against a deliberately sabotaged paragraph style
///   rather than against a document that happens to need no work.
@MainActor
struct MarkdownStylingWidthSignatureTests {
    private static let imageID = UUID(uuidString: "1B2C3D4E-5F60-7182-93A4-B5C6D7E8F9A0")!

    private static let markdown = """
    Prose above the image.

    ![banner](cadence-image://1B2C3D4E-5F60-7182-93A4-B5C6D7E8F9A0)

    Prose below the image.
    """

    private static let inset: CGFloat = 18

    private static func asset(displayWidth: CGFloat = MarkdownImageAssetService.defaultDisplayWidth) -> MarkdownImageRenderAsset {
        let size = NSSize(width: 640, height: 360)
        let image = NSImage(size: size)
        image.lockFocus()
        Theme.nsBlue.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return MarkdownImageRenderAsset(
            id: imageID,
            image: image,
            displayWidth: displayWidth,
            pixelSize: size
        )
    }

    // MARK: - Fixture

    /// A `CadenceTextView` at a chosen width, holding one standalone image, **not yet styled**.
    ///
    /// Deliberately without a scroll view: `MarkdownEditorScrollView.layout()` is the reader's one
    /// call site in the app, but calling the reader directly is what lets these tests say which of
    /// the two halves answered.
    private func makeTextView(width: CGFloat) -> CadenceTextView {
        let storage = NSTextStorage()
        let layoutManager = CadenceLayoutManager()
        let container = NSTextContainer(
            containerSize: NSSize(width: max(1, width - Self.inset * 2), height: CGFloat.greatestFiniteMagnitude)
        )
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)

        let textView = CadenceTextView(
            frame: NSRect(x: 0, y: 0, width: width, height: 600),
            textContainer: container
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: Self.inset, height: Self.inset)
        textView.markdownImageAssets = [Self.imageID: Self.asset()]
        textView.string = Self.markdown
        return textView
    }

    private func resize(_ textView: CadenceTextView, to width: CGFloat) {
        textView.setFrameSize(NSSize(width: width, height: textView.frame.height))
        textView.textContainer?.containerSize = NSSize(
            width: max(1, width - Self.inset * 2),
            height: CGFloat.greatestFiniteMagnitude
        )
    }

    private func imageLineRange(in textView: CadenceTextView) throws -> NSRange {
        let storage = try #require(textView.textStorage)
        var found: NSRange?
        storage.enumerateAttribute(
            .cadenceMarkdownImage,
            in: NSRange(location: 0, length: storage.length)
        ) { value, range, stop in
            guard value is MarkdownImageLayoutInfo else { return }
            found = range
            stop.pointee = true
        }
        return try #require(found)
    }

    private func reservedLineHeight(in textView: CadenceTextView) throws -> CGFloat {
        let storage = try #require(textView.textStorage)
        let range = try imageLineRange(in: textView)
        let style = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
        return try #require(style).minimumLineHeight
    }

    /// Replaces the image line's reserved height with a value no width could have produced.
    ///
    /// The lever every "did the gate actually skip?" assertion below pulls: after this, a refresh
    /// that runs leaves a height matching the current width, and one that is skipped leaves this.
    private func sabotageReservedHeight(in textView: CadenceTextView) throws {
        let storage = try #require(textView.textStorage)
        let range = try imageLineRange(in: textView)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 3
        paragraph.maximumLineHeight = 3
        storage.addAttribute(.paragraphStyle, value: paragraph, range: range)
    }

    // MARK: - The record

    /// The half that did not exist before T-1045: after styling, something holds the width that
    /// styling used.
    @Test func stylingRecordsTheContentWidthItWasComputedAgainst() throws {
        let textView = makeTextView(width: 640)
        #expect(textView.markdownLayoutSignature == nil)

        MarkdownStylist.apply(to: textView)

        let recorded = try #require(textView.markdownLayoutSignature)
        #expect(
            recorded.contentWidthBucket
                == MarkdownStyleSignature.bucket(for: MarkdownStylist.layoutContentWidth(of: textView))
        )
        // Not a constant dressed up as a measurement: a different width records a different bucket.
        let narrow = makeTextView(width: 320)
        MarkdownStylist.apply(to: narrow)
        #expect(try #require(narrow.markdownLayoutSignature).contentWidthBucket != recorded.contentWidthBucket)
    }

    /// The reported defect's own arithmetic, at the record level. SwiftUI styles the editor before
    /// it gives the representable a frame, so the first styling is computed against a content width
    /// of about one point — and the record is what makes that visible to the layout pass that
    /// follows instead of leaving it to be inferred.
    @Test func aStylingBeforeTheEditorHasAFrameRecordsTheUnusableWidthItUsed() throws {
        let textView = makeTextView(width: 0)
        MarkdownStylist.apply(to: textView)

        #expect(try #require(textView.markdownLayoutSignature).contentWidthBucket == 1)

        resize(textView, to: 640)
        #expect(MarkdownStylist.refreshWidthDependentLayout(in: textView) == true)
        #expect(try #require(textView.markdownLayoutSignature).contentWidthBucket > 1)
    }

    // MARK: - The reader

    /// At the width it was styled at, the reader does no work — and the sabotaged height proves the
    /// skip is the gate answering rather than the document happening to need nothing.
    @Test func anUnchangedWidthIsSkippedRatherThanReDerived() throws {
        let textView = makeTextView(width: 640)
        MarkdownStylist.apply(to: textView)
        try sabotageReservedHeight(in: textView)

        #expect(MarkdownStylist.refreshWidthDependentLayout(in: textView) == false)
        #expect(try reservedLineHeight(in: textView) == 3)

        // The work the gate declined is work there was to do: the ungated pass fixes it.
        #expect(MarkdownStylist.refreshImageBlockLayout(in: textView) == true)
        #expect(try reservedLineHeight(in: textView) > 3)
    }

    /// The width moving is what makes the reader act, and acting is what converges: a second pass
    /// at the same new width finds the record already advanced and declines.
    @Test func aWidthChangeIsWhatMakesTheReaderReDerive() throws {
        let textView = makeTextView(width: 320)
        MarkdownStylist.apply(to: textView)
        let narrowHeight = try reservedLineHeight(in: textView)

        resize(textView, to: 760)
        #expect(MarkdownStylist.refreshWidthDependentLayout(in: textView) == true)

        let widened = try reservedLineHeight(in: textView)
        #expect(widened > narrowHeight)

        // Exactly where a full restyle at this width lands, which is the contract without
        // restating any of the styler's literals.
        let restyled = makeTextView(width: 760)
        MarkdownStylist.apply(to: restyled)
        #expect(abs(widened - (try reservedLineHeight(in: restyled))) < 0.5)

        try sabotageReservedHeight(in: textView)
        #expect(MarkdownStylist.refreshWidthDependentLayout(in: textView) == false)
        #expect(try reservedLineHeight(in: textView) == 3)
    }

    /// A text view the stylist never recorded a signature for reads as *stale*, so the gate can
    /// only ever decline work it is sure about. This is the whole of the behaviour a plain
    /// `NSTextView` — the PDF export path, an offscreen render — keeps from before the gate existed.
    @Test func anUnrecordedTextViewIsRefreshedRatherThanSkipped() throws {
        let textView = makeTextView(width: 640)
        MarkdownStylist.apply(to: textView)
        try sabotageReservedHeight(in: textView)

        textView.markdownLayoutSignature = nil

        #expect(MarkdownStylist.refreshWidthDependentLayout(in: textView) == true)
        #expect(try reservedLineHeight(in: textView) > 3)
        // Still unrecorded afterwards: the refresh advances a record, it does not invent one, so
        // nothing here can start claiming a styling that never happened.
        #expect(textView.markdownLayoutSignature == nil)
    }

    // MARK: - What the reader may and may not claim

    /// The refresh advances the record's **width and nothing else**.
    ///
    /// It re-derives reserved heights; it is not a restyle. If it stamped the whole current
    /// signature, the record would claim the styling had also caught up with an image the user
    /// resized in between — and a future reader gating a full restyle on this value would then skip
    /// the one it needed. `MarkdownStyleSignature.advancingContentWidth(to:)` exists for this.
    @Test func theRefreshAdvancesTheRecordsWidthAndNothingElse() throws {
        let textView = makeTextView(width: 320)
        MarkdownStylist.apply(to: textView)
        let styled = try #require(textView.markdownLayoutSignature)

        // Something the styler has *not* been re-run over.
        textView.markdownImageAssets = [Self.imageID: Self.asset(displayWidth: 200)]
        resize(textView, to: 760)
        #expect(MarkdownStylist.refreshWidthDependentLayout(in: textView) == true)

        let advanced = try #require(textView.markdownLayoutSignature)
        #expect(advanced.contentWidthBucket != styled.contentWidthBucket)
        #expect(advanced.imageAssetRevision == styled.imageAssetRevision)
        #expect(advanced == styled.advancingContentWidth(to: MarkdownStylist.layoutContentWidth(of: textView)))

        // And the restyle that does happen is what moves the rest of it.
        MarkdownStylist.apply(to: textView)
        #expect(try #require(textView.markdownLayoutSignature).imageAssetRevision != styled.imageAssetRevision)
    }

    /// The macOS feed carries the raw-source escape, so the record cannot say two different
    /// stylings of the same note at the same width were the same one.
    @Test func theRecordSeparatesARevealedTableFromARenderedOne() throws {
        let textView = makeTextView(width: 640)
        MarkdownStylist.apply(to: textView)
        let rendered = try #require(textView.markdownLayoutSignature)

        textView.revealedTableAnchor = 24
        MarkdownStylist.apply(to: textView)
        #expect(try #require(textView.markdownLayoutSignature) != rendered)
    }
}
#endif
