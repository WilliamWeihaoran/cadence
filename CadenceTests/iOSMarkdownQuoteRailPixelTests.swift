import Foundation
import Testing
#if os(iOS)
import SwiftUI
import UIKit
#endif

@testable import Cadence

#if os(iOS)
/// The iOS quote rail in real UIKit pixels ([[T-19923]]): the live styler's attributed string drawn
/// by the editor's own `iOSMarkdownBlockCanvasLayoutManager`, the path `iOSNoteExportService` takes.
///
/// The rail used to be measured from the block's first glyph. A block opening `> - [ ] todo` put
/// that glyph at the quote indent PLUS the checklist's content indent, so on `Cadence-iPhone15` the
/// rail ran through the centre of every top-level box and across a plain quote line's first letter,
/// while nested boxes, further right, sat clear. Every drawn thing in the block must sit right of
/// the rail, and the rail must not move with the line that opens the block.
@Suite @MainActor
struct iOSMarkdownQuoteRailPixelTests {
    private struct Render {
        let image: UIImage
        /// Pixel columns holding the rail's blue.
        let railColumns: ClosedRange<Int>
        /// The leftmost pixel column holding anything else drawn: a box's stroke, a glyph.
        let firstContentColumn: Int
    }

    private static let width: CGFloat = 360

    private static func render(_ markdown: String, name: String) throws -> Render {
        let styled = iOSMarkdownStyler.attributedString(
            for: markdown, imageAssets: [], taskEmbeds: [:], contentWidth: width
        )
        let storage = NSTextStorage(attributedString: styled)
        let layout = iOSMarkdownBlockCanvasLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        let size = CGSize(width: width + 20, height: ceil(used.height) + 20)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let background = UIColor(Theme.bg)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            background.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let glyphs = layout.glyphRange(for: container)
            layout.drawBackground(forGlyphRange: glyphs, at: CGPoint(x: 10, y: 10))
            layout.drawGlyphs(forGlyphRange: glyphs, at: CGPoint(x: 10, y: 10))
        }
        let frames = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scratchpad/fix1708b/frames", isDirectory: true)
        try? FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        try? image.pngData()?.write(to: frames.appendingPathComponent("pixel-\(name).png"))

        let cg = try #require(image.cgImage)
        let w = cg.width, h = cg.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let bitmap = try #require(CGContext(
            data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        bitmap.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let bg = (bytes[0], bytes[1], bytes[2])
        var rail: [Int] = []
        var content: [Int] = []
        for x in 0..<w {
            var isRail = false, isContent = false
            for y in 0..<h {
                let i = (y * w + x) * 4
                let (r, g, b) = (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
                if abs(r - Int(bg.0)) + abs(g - Int(bg.1)) + abs(b - Int(bg.2)) < 24 { continue }
                // The rail is Theme.blue at 0.78 over the background, blue above red even in its
                // anti-aliased edge columns; the boxes and the muted text are grey, b close to r.
                if b - r > 15 { isRail = true } else { isContent = true }
            }
            if isRail { rail.append(x) }
            if isContent { content.append(x) }
        }
        let lo = try #require(rail.min(), "positive control: \(name) drew a rail")
        let firstContent = try #require(content.min(), "positive control: \(name) drew its content")
        return Render(image: image, railColumns: lo...(try #require(rail.max())), firstContentColumn: firstContent)
    }

    @Test func theRailSitsLeftOfEveryBoxAndPlainQuoteLineWhicheverLineOpensTheBlock() throws {
        let boxFirst = try Self.render(
            "> - [ ] todo\n> - [ ] top\n>   - [ ] nested\n> a plain quote line\n>   plain text",
            name: "box-first"
        )
        let plainFirst = try Self.render(
            "> a plain quote line\n> - [ ] todo\n> - [ ] top\n>   - [ ] nested\n>   plain text",
            name: "plain-first"
        )
        #expect(boxFirst.railColumns.count <= 10, "non-vacuity: one 3pt rail at 2x, not a wash of blue")
        #expect(boxFirst.railColumns == plainFirst.railColumns,
                "the rail does not move with the line that opens the block")
        #expect(boxFirst.railColumns.upperBound < boxFirst.firstContentColumn,
                "every box and every glyph sits right of the rail")
        #expect(plainFirst.railColumns.upperBound < plainFirst.firstContentColumn)
    }
}
#endif
