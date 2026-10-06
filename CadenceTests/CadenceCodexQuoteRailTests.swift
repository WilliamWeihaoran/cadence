import Foundation
import CoreGraphics
import Testing
#if os(macOS)
import AppKit
#endif
@testable import Cadence

@MainActor
struct CadenceCodexQuoteRailTests {
    private func taggedQuotes(_ markdown: String) -> NSMutableAttributedString {
        let storage = NSMutableAttributedString(string: markdown)
        for line in MarkdownSourceLines.lines(in: markdown) {
            guard let quote = MarkdownQuoteSupport.lineInfo(in: line.text) else { continue }
            storage.addAttribute(.cadenceMarkdownQuoteDepth, value: quote.depth,
                                 range: iOSMarkdownQuoteRailLayout.taggedRange(for: line.range, storageLength: storage.length))
        }
        return storage
    }

    @Test func adjacentParagraphsIncludingAnEmptyQuotedLineAreOneRun() {
        for markdown in ["> First\n> Second\n> Third", "> First\n>\n> Third", "> First\r\n> Second", "> \u{1F600} First\n> Second"] {
            let storage = taggedQuotes(markdown)
            #expect(iOSMarkdownQuoteRailLayout.runs(in: storage, intersecting: NSRange(location: 0, length: storage.length))
                    == [iOSMarkdownQuoteRailLayout(depth: 1, range: NSRange(location: 0, length: storage.length))])
        }
    }

    @Test func unquotedSeparatorsAndDepthChangesKeepBlocksSeparate() {
        for markdown in ["> First\n\n> Second", "> First\nProse\n> Second", "> First\n>> Nested\n> Second"] {
            let storage = taggedQuotes(markdown)
            let runs = iOSMarkdownQuoteRailLayout.runs(in: storage, intersecting: NSRange(location: 0, length: storage.length))
            #expect(runs.count == (markdown.contains(">> Nested") ? 3 : 2))
            #expect(runs.first?.range == NSRange(location: 0, length: 8))
            #expect(runs.last?.range == NSRange(location: (markdown as NSString).range(of: "> Second").location, length: 8))
        }
    }

    @Test func partialRedrawRecoversTheWholeBlockDespiteOtherAttributeBoundaries() {
        let storage = taggedQuotes("> First\n> Second\n> Third")
        let second = (storage.string as NSString).range(of: "Second")
        storage.addAttribute(.cadenceMarkdownHidden, value: true, range: NSRange(location: 0, length: 2))
        storage.addAttribute(.cadenceMarkdownHighlight, value: true, range: second)
        let expected = [iOSMarkdownQuoteRailLayout(depth: 1, range: NSRange(location: 0, length: storage.length))]
        #expect(iOSMarkdownQuoteRailLayout.runs(in: storage, intersecting: second) == expected)
        #expect(iOSMarkdownQuoteRailLayout.runs(in: storage, intersecting: NSRange(location: 0, length: storage.length)) == expected)
        #expect(iOSMarkdownQuoteRailLayout.runs(in: storage, intersecting: NSRange(location: storage.length, length: 0)).isEmpty)
    }

    @Test func hiddenFrontmatterDoesNotGrowAQuoteRail() {
        let storage = taggedQuotes("> metadata")
        let full = NSRange(location: 0, length: storage.length)
        storage.addAttribute(.cadenceMarkdownFrontmatter, value: true, range: full)
        #expect(iOSMarkdownQuoteRailLayout.runs(in: storage, intersecting: full).isEmpty)
    }

    @Test func railSpansWrappingParagraphSpacingAndLargerLineHeights() {
        for lineHeight in [18.0, 24, 42, 64] {
            let run = iOSMarkdownQuoteRailLayout(depth: 1, range: NSRange(location: 0, length: 1))
            let first = CGRect(x: 5, y: 12, width: 320, height: lineHeight)
            let last = CGRect(x: 5, y: 12 + lineHeight * 5 + 16, width: 320, height: lineHeight)
            let bars = run.barRects(firstFragment: first, lastFragment: last, markerLocation: CGPoint(x: 18, y: 0))
            #expect(bars == [CGRect(x: 9, y: 13, width: 3, height: lineHeight * 6 + 14)])
            #expect(bars[0].contains(CGPoint(x: 10, y: first.maxY + 4)))
        }
    }

    @Test func nestedRailsKeepTheirGutterAndSpanTheSameHeight() {
        let run = iOSMarkdownQuoteRailLayout(depth: 3, range: NSRange(location: 0, length: 1))
        let first = CGRect(x: 5, y: 10, width: 320, height: 20)
        let last = CGRect(x: 5, y: 80, width: 320, height: 20)
        #expect(run.barRects(firstFragment: first, lastFragment: last, markerLocation: CGPoint(x: 42, y: 0)) == [
            CGRect(x: 25, y: 11, width: 3, height: 88),
            CGRect(x: 29, y: 11, width: 3, height: 88),
            CGRect(x: 33, y: 11, width: 3, height: 88)
        ])
    }

    /// Wiring only: UIKit is not executed by the macOS test target.
    @Test func mobileStylerAndDrawingPassUseTheContinuousRail() throws {
        let instrument = try CadenceScanInstrument(
            "mobile quote rail wiring",
            fires: "func applyQuoteLine() { storage.addAttribute(.cadenceMarkdownQuoteDepth, value: quote.depth, range: iOSMarkdownQuoteRailLayout.taggedRange(for: lineRange, storageLength: storage.length)); hide(storage, quote.prefixRange.shifted(by: lineStart)) }",
            andNotOn: "func applyQuoteLine() { applyQuoteAttachment(storage, markerRange: quote.prefixRange, depth: quote.depth) } // iOSMarkdownQuoteRailLayout.taggedRange(for: lineRange, storageLength: storage.length)",
            by: { source in
                let code = CadenceSourceScan.codeOnly(source)
                guard let body = CadenceSourceScan.functionBody(named: "applyQuoteLine", in: code) else { return false }
                return body.contains(".cadenceMarkdownQuoteDepth") && body.contains("value: quote.depth")
                    && body.contains("iOSMarkdownQuoteRailLayout.taggedRange(for: lineRange, storageLength: storage.length)")
                    && body.contains("hide(storage, quote.prefixRange.shifted(by: lineStart))")
                    && !body.contains("applyQuoteAttachment")
            }
        )
        let path = "Cadence/iOS/iOSMarkdownStylingLineSupport.swift"
        let read = CadenceSourceScan.strippedSourceReader()
        #expect(try instrument.sweep([path], atLeast: 1, including: path, read: read) == [path])
        let quoteStyle = try #require(CadenceSourceScan.functionBody(named: "applyQuoteLine", in: CadenceSourceScan.codeOnly(try read(path))))
        #expect(quoteStyle.contains("paragraph.minimumLineHeight = baseFont.lineHeight"),
                "an empty hidden quote prefix still reserves a readable line at the current text size")
        let drawing = CadenceSourceScan.codeOnly(try read("Cadence/iOS/iOSMarkdownBlockCanvasRendering.swift"))
        let glyphs = try #require(CadenceSourceScan.functionBody(named: "drawGlyphs", in: drawing))
        #expect(glyphs.contains("drawQuoteRails(in: charRange, storage: storage, origin: origin)"))
        let rails = try #require(CadenceSourceScan.functionBody(named: "drawQuoteRails", in: drawing))
        #expect(rails.contains("iOSMarkdownQuoteRailLayout.runs(in: storage, intersecting: charRange)"))
        #expect(rails.contains("lineFragmentRect(forGlyphAt: NSMaxRange(glyphs) - 1"))
        #expect(rails.contains("run.barRects(firstFragment: first, lastFragment: last, markerLocation: location)"))
        #expect(rails.contains("UIBezierPath(roundedRect:"))
        #expect(rails.contains(".fill()"))
    }

    #if os(macOS)
    private func macTextView(_ markdown: String, width: CGFloat = 420) -> CadenceTextView {
        let storage = NSTextStorage()
        let layout = CadenceLayoutManager()
        let container = NSTextContainer(containerSize: CGSize(width: width - 36, height: 1000))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        let view = CadenceTextView(frame: CGRect(x: 0, y: 0, width: width, height: 600), textContainer: container)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.isEditable = true
        view.isRichText = true
        view.backgroundColor = Theme.nsBg
        view.textContainerInset = CGSize(width: 18, height: 18)
        view.font = MarkdownStylist.baseFont
        view.typingAttributes = MarkdownStylist.baseAttributes
        view.string = markdown
        MarkdownStylist.apply(to: view)
        layout.ensureLayout(for: container)
        return view
    }

    @Test func macOSAlreadyJoinsAdjacentQuotesAndKeepsAnUnquotedBreak() throws {
        let view = macTextView("> First\n> Second\n> Third\n\n> Separate")
        let storage = try #require(view.textStorage)
        let runs = iOSMarkdownQuoteRailLayout.runs(in: storage, intersecting: NSRange(location: 0, length: storage.length))
        #expect(runs.map(\.depth) == [1, 1])
        #expect(runs[0].range == NSRange(location: 0, length: 25))
    }

    /// Real AppKit pixels, not an inference from the attribute grouping.
    @Test func macOSQuoteRailHasNoInteriorGapsAcrossParagraphsOrWrapping() throws {
        for width in [CGFloat(180), 420] {
            let view = macTextView("> First quote paragraph with enough text to wrap at a narrow width.\n> Second quote paragraph.\n> Third quote paragraph.", width: width)
            let layout = try #require(view.layoutManager)
            let container = try #require(view.textContainer)
            let glyphs = NSRange(location: 0, length: layout.numberOfGlyphs)
            var lineRect = layout.boundingRect(forGlyphRange: glyphs, in: container)
            lineRect.origin.x = 18 + container.lineFragmentPadding
            lineRect = lineRect.offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
            let rail = MarkdownDecorationGeometry.quoteBarRect(
                backgroundRect: MarkdownDecorationGeometry.quoteBackgroundRect(lineRect: lineRect, depth: 1), depth: 1)
            #expect(rail.height > 60, "non-vacuity: the block spans multiple paragraphs")
            let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            let scale = CGFloat(rep.pixelsWide) / view.bounds.width
            let x = Int(rail.midX * scale)
            #expect(x >= 0 && x < rep.pixelsWide, "non-vacuity: the fixture includes the actual editor gutter")
            let blue = try #require(Theme.nsBlue.usingColorSpace(.deviceRGB))
            var paintedRows: [Int] = []
            for y in 0..<rep.pixelsHigh {
                let pixel = try #require(rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let delta = max(abs(pixel.redComponent - blue.redComponent),
                                abs(pixel.greenComponent - blue.greenComponent), abs(pixel.blueComponent - blue.blueComponent))
                if delta < 0.14 { paintedRows.append(y) }
            }
            let first = try #require(paintedRows.first, "positive control: the rail actually drew")
            let last = try #require(paintedRows.last)
            #expect(paintedRows.count == last - first + 1, "no missing painted rows inside the quote rail")
            #expect(CGFloat(paintedRows.count) >= (rail.height - 4) * scale,
                    "a short per-paragraph dash cannot pass by being continuous on its own")
        }
    }

    @Test func macOSPartialQuoteRedrawMatchesTheFullRail() throws {
        let view = macTextView("> First paragraph.\n> Second paragraph.\n> Third paragraph.")
        let layout = try #require(view.layoutManager)
        let container = try #require(view.textContainer)
        var lineRect = layout.boundingRect(forGlyphRange: NSRange(location: 0, length: layout.numberOfGlyphs), in: container)
        lineRect.origin.x = 18 + container.lineFragmentPadding
        lineRect = lineRect.offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
        let rail = MarkdownDecorationGeometry.quoteBarRect(
            backgroundRect: MarkdownDecorationGeometry.quoteBackgroundRect(lineRect: lineRect, depth: 1), depth: 1)
        let blue = try #require(Theme.nsBlue.usingColorSpace(.deviceRGB))
        var bands = 0
        for top in stride(from: rail.minY + 4, through: rail.maxY - 8, by: 4) {
            let band = CGRect(x: 0, y: top, width: view.bounds.width, height: 4)
            let rep = try #require(view.bitmapImageRepForCachingDisplay(in: band))
            view.cacheDisplay(in: band, to: rep)
            let scale = CGFloat(rep.pixelsWide) / band.width
            let x = Int(rail.midX * scale)
            #expect(x >= 0 && x < rep.pixelsWide)
            #expect(rep.pixelsHigh > 0)
            var painted = 0
            for y in 0..<rep.pixelsHigh {
                let pixel = try #require(rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let delta = max(abs(pixel.redComponent - blue.redComponent),
                                abs(pixel.greenComponent - blue.greenComponent), abs(pixel.blueComponent - blue.blueComponent))
                if delta < 0.14 { painted += 1 }
            }
            #expect(painted == rep.pixelsHigh, "a dirty band inside a quote must not introduce new rounded ends")
            bands += 1
        }
        #expect(bands > 10, "non-vacuity: redraw bands cross paragraph boundaries")
    }
    #endif
}
