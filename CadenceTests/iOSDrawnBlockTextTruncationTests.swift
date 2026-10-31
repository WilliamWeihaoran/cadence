import Foundation
import Testing
@testable import Cadence

/// [[T-9320]]: text the iOS note editor draws into a one-line rect of a raster block — the task
/// card's title and chips, the image block's caption — word-wrapped by default, and the second
/// line was clipped away, so a long title or caption stopped at a word boundary with no ellipsis.
/// Those files compile only for iOS, so this reads the source on the Mac leg; the drawing itself
/// needs an attended look ([[T-9321]]).
struct iOSDrawnBlockTextTruncationTests {

    private func body(_ name: String, in path: String) throws -> String {
        let source = try CadenceSourceScan.sourceFile(path)
        return try #require(CadenceSourceScan.functionBody(named: name, in: source), "no func \(name) in \(path)")
    }

    @Test func theTaskCardTitleAndChipsTruncateRatherThanWrap() throws {
        let path = "Cadence/iOS/iOSMarkdownTaskEmbedLayoutInfo.swift"
        #expect(try body("drawTitle", in: path).contains(".paragraphStyle: Self.truncatingParagraph"))
        #expect(try body("drawChip", in: path).contains("attributes[.paragraphStyle] = Self.truncatingParagraph"))
        #expect(try body("drawSubtaskTitle", in: path).contains("attributes[.paragraphStyle] = Self.truncatingParagraph"))
        let source = try CadenceSourceScan.sourceFile(path)
        #expect(source.contains("paragraph.lineBreakMode = .byTruncatingTail"))
    }

    @Test func theImageCaptionTruncatesRatherThanWraps() throws {
        let render = try body("renderedBlock", in: "Cadence/iOS/iOSMarkdownImageLayoutInfo.swift")
        #expect(render.contains("paragraph.lineBreakMode = .byTruncatingTail"))
        #expect(render.contains(".paragraphStyle: paragraph"))
    }
}
