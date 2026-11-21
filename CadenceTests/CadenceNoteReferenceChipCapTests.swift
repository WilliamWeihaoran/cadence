import Foundation
import Testing
@testable import Cadence

/// **T-18816.** A note's reference strip caps a chip at one figure on both platforms. The Mac strip
/// lays its chips in a horizontal `ScrollView`, which proposes no width, so `ReferenceChip`'s title
/// `lineLimit` had nothing to truncate against: a long-titled task drew as one chip as wide as its
/// title, its deadline past the pane edge and every later chip off-screen, while iOS's
/// `iOSMarkdownSuggestionPill` capped the same chip at 220pt. Both now read
/// `NoteReferenceChipMetrics.maximumContentWidth`. Source-text pins, because the Mac view is
/// `private` and `Cadence/iOS/` does not compile into this macOS-hosted target.
@MainActor
struct CadenceNoteReferenceChipCapTests {
    private static func compactBody(_ declaration: String, in path: String) throws -> String {
        let file = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
        return try #require(
            CadenceSourceScan.declarationBody(declaration, in: file),
            "could not read \(declaration)"
        ).filter { !$0.isWhitespace }
    }

    private static let capFrame = ".frame(maxWidth:NoteReferenceChipMetrics.maximumContentWidth,alignment:.leading)"

    @Test func theSharedCapIsTheFigureIOSAlreadyDrew() {
        #expect(NoteReferenceChipMetrics.maximumContentWidth == 220)
    }

    @Test func theMacReferenceChipIsCappedSoItsTitleTruncatesAroundTheDeadline() throws {
        let body = try Self.compactBody(
            "private struct ReferenceChip: View",
            in: "Cadence/macOS/Views/NoteReferenceSupportViews.swift"
        )
        #expect(CadenceSourceScan.matchCount(NSRegularExpression.escapedPattern(for: Self.capFrame), in: body) == 1,
                "the chip must cap its content at the shared figure")
        // A bare `maxWidth` is flexible upward; the fixed size is what makes it a cap.
        #expect(body.contains(Self.capFrame + ".fixedSize(horizontal:true,vertical:false)"))
        #expect(body.contains(".lineLimit(1).truncationMode(.tail)"), "the title is what truncates")
        #expect(body.contains(".fixedSize().layoutPriority(1)"), "the deadline keeps its width")
    }

    @Test func theIOSReferencePillReadsTheSameFigure() throws {
        let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSMarkdownAccessoryViews.swift"))
            .filter { !$0.isWhitespace }
        let pill = try #require(code.components(separatedBy: "privatestructiOSMarkdownSuggestionPill<").dropFirst().first,
                                "could not find iOSMarkdownSuggestionPill")
        let pillBody = try #require(pill.components(separatedBy: "structiOSMarkdownReferenceCompletionChoice").first)
        #expect(pillBody.contains(Self.capFrame), "iOS must read the shared cap rather than restate it")
        #expect(!pillBody.contains("maxWidth:220"), "the figure is restated instead of shared")
    }
}
