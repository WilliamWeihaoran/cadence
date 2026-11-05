import Foundation
import Testing
#if os(macOS)
import AppKit
#endif
@testable import Cadence

struct MarkdownInsertionSupportTests {
    @Test func blockInsertionAddsTrailingNewlineAtEndOfDocument() {
        let insertion = MarkdownInsertionSupport.paddedBlockInsertion(
            "![Sketch](cadence-image://11111111-1111-1111-1111-111111111111)",
            in: "",
            selection: NSRange(location: 0, length: 0)
        )

        #expect(insertion == "![Sketch](cadence-image://11111111-1111-1111-1111-111111111111)\n")
    }

    @Test func blockInsertionPadsWhenInsertedInsideText() {
        let insertion = MarkdownInsertionSupport.paddedBlockInsertion(
            "![Sketch](cadence-image://11111111-1111-1111-1111-111111111111)",
            in: "Before after",
            selection: NSRange(location: 7, length: 0)
        )

        #expect(insertion == "\n\n![Sketch](cadence-image://11111111-1111-1111-1111-111111111111)\n\n")
    }

    @Test func blockInsertionDoesNotAddExtraBreaksBesideExistingNewlines() {
        let insertion = MarkdownInsertionSupport.paddedBlockInsertion(
            "![Sketch](cadence-image://11111111-1111-1111-1111-111111111111)",
            in: "Before\n\nAfter",
            selection: NSRange(location: 7, length: 0)
        )

        #expect(insertion == "![Sketch](cadence-image://11111111-1111-1111-1111-111111111111)\n")
    }

    /// The macOS editor used to compute this padding itself, reading one character either side of
    /// the selection without clamping it first. This is the clamping that copy lacked.
    @Test func blockInsertionClampsASelectionPastTheEndOfTheText() {
        let insertion = MarkdownInsertionSupport.paddedBlockInsertion(
            "---",
            in: "Before",
            selection: NSRange(location: 999, length: 12)
        )

        #expect(insertion == "\n\n---\n")
    }

    // MARK: - T-11492: a task-embed card's line

    private static let embed = "[[task:22222222-2222-2222-2222-222222222222|Replace the kitchen tap]]"
    private static let image = "![](cadence-image://95A46EEB-2AE6-4AC1-8E17-459DAA44221F)"
    private static let noteLink = "[[note:11111111-1111-1111-1111-111111111111|Project Notes]]"

    /// Every line of `text` that is a task reference standing alone, i.e. every card that draws.
    private static func cardLines(in text: String) -> [String] {
        text.components(separatedBy: "\n").filter { MarkdownTaskEmbedParser.standaloneTaskReference(in: $0) != nil }
    }

    /// What the iOS photos picker writes (`insertPickedImages` -> `.insertBlockMarkdown`), with
    /// the caret where `/task` leaves it: at the end of the embed's line. It used to go through raw
    /// `.insertMarkdown`, which appended the image to that line and the card stopped drawing.
    @Test func pickedImageAtTheEndOfAnEmbedLineLeavesTheCardOnItsOwnLine() {
        let text = "Intro\n\(Self.embed)\nAfter"
        let caret = ("Intro\n\(Self.embed)" as NSString).length
        let mutation = MarkdownFormatCommandSupport.apply(
            .insertBlockMarkdown(Self.image),
            text: text,
            selection: NSRange(location: caret, length: 0)
        )

        #expect(Self.cardLines(in: mutation.text) == [Self.embed])
        #expect(mutation.text.components(separatedBy: "\n").contains(Self.image))
        #expect(mutation.text == "Intro\n\(Self.embed)\n\n\(Self.image)\n\nAfter")
    }

    /// The same insertion with the caret at the START of the embed's line puts the image above it.
    @Test func pickedImageAtTheStartOfAnEmbedLineLeavesTheCardOnItsOwnLine() {
        let text = "\(Self.embed)\nAfter"
        let mutation = MarkdownFormatCommandSupport.apply(
            .insertBlockMarkdown(Self.image),
            text: text,
            selection: NSRange(location: 0, length: 0)
        )

        #expect(Self.cardLines(in: mutation.text) == [Self.embed])
        #expect(mutation.text == "\(Self.image)\n\n\(Self.embed)\nAfter")
    }

    /// A picked note link is inline everywhere else, but on a card's line it would turn the card
    /// into inline text just as the image did; there it gets its own line, at either end.
    @Test func pickedReferenceOnAnEmbedLineGetsItsOwnLineAtEitherEnd() {
        let text = Self.embed
        let atEnd = MarkdownFormatCommandSupport.apply(
            .insertReferenceMarkdown(Self.noteLink),
            text: text,
            selection: NSRange(location: (text as NSString).length, length: 0)
        )
        #expect(Self.cardLines(in: atEnd.text) == [Self.embed])
        #expect(atEnd.text == "\(Self.embed)\n\n\(Self.noteLink)\n")

        let atStart = MarkdownFormatCommandSupport.apply(
            .insertReferenceMarkdown(Self.noteLink),
            text: text,
            selection: NSRange(location: 0, length: 0)
        )
        #expect(Self.cardLines(in: atStart.text) == [Self.embed])
        #expect(atStart.text == "\(Self.noteLink)\n\n\(Self.embed)")
    }

    /// Off a card's line the reference stays inline, unchanged from before.
    @Test func pickedReferenceInOrdinaryTextStaysInline() {
        let mutation = MarkdownFormatCommandSupport.apply(
            .insertReferenceMarkdown(Self.noteLink),
            text: "Read this later",
            selection: NSRange(location: 5, length: 4)
        )
        #expect(mutation.text == "Read \(Self.noteLink) later")
        #expect(
            MarkdownInsertionSupport.blockPaddedInsertionIfOnTaskEmbedLine(
                Self.noteLink,
                in: "Read this later",
                selection: NSRange(location: 5, length: 0)
            ) == nil
        )
    }

    /// The macOS editor's inline-reference padding asks the same question before it pads with
    /// spaces, so both platforms answer the caret on a card's line identically.
    @Test func theTaskEmbedLineQuestionSeesTheCaretAtEitherEndOfTheLine() {
        let text = "Intro\n\(Self.embed)\nAfter"
        let lineStart = ("Intro\n" as NSString).length
        let lineEnd = lineStart + (Self.embed as NSString).length
        #expect(MarkdownInsertionSupport.selectionTouchesStandaloneTaskEmbedLine(in: text, selection: NSRange(location: lineStart, length: 0)))
        #expect(MarkdownInsertionSupport.selectionTouchesStandaloneTaskEmbedLine(in: text, selection: NSRange(location: lineEnd, length: 0)))
        #expect(!MarkdownInsertionSupport.selectionTouchesStandaloneTaskEmbedLine(in: text, selection: NSRange(location: 2, length: 0)))
        #expect(!MarkdownInsertionSupport.selectionTouchesStandaloneTaskEmbedLine(in: text, selection: NSRange(location: (text as NSString).length, length: 0)))
    }
}

#if os(macOS)
/// T-11492 on the macOS editor, through the real `CadenceTextView` doors rather than the helper:
/// the picker's note link (`insertMarkdownReference`) and an inserted image (`insertMarkdownImages`)
/// with the caret at the end of a task-embed card's line. One app, two platforms (T-8201): both
/// leave the card on a line of its own, as iOS does.
@MainActor
struct MarkdownInsertionTaskEmbedLineEditorTests {
    private static let embed = "[[task:22222222-2222-2222-2222-222222222222|Replace the kitchen tap]]"
    private static let noteLink = "[[note:11111111-1111-1111-1111-111111111111|Project Notes]]"

    private func makeTextView(text: String, caret: Int) -> CadenceTextView {
        let storage = NSTextStorage()
        let layoutManager = CadenceLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: 520, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        let textView = CadenceTextView(frame: NSRect(x: 0, y: 0, width: 560, height: 900), textContainer: container)
        textView.string = text
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        return textView
    }

    private func cardLines(in text: String) -> [String] {
        text.components(separatedBy: "\n").filter { MarkdownTaskEmbedParser.standaloneTaskReference(in: $0) != nil }
    }

    @Test func aPickedReferenceAtEitherEndOfAnEmbedLineLeavesTheCardOnItsOwnLine() {
        let text = "\(Self.embed)\nAfter"
        let atEnd = makeTextView(text: text, caret: (Self.embed as NSString).length)
        atEnd.insertMarkdownReference(Self.noteLink)
        #expect(cardLines(in: atEnd.string) == [Self.embed])
        #expect(atEnd.string.components(separatedBy: "\n").contains(Self.noteLink))

        let atStart = makeTextView(text: text, caret: 0)
        atStart.insertMarkdownReference(Self.noteLink)
        #expect(cardLines(in: atStart.string) == [Self.embed])
        #expect(atStart.string.components(separatedBy: "\n").contains(Self.noteLink))
    }

    @Test func aPickedReferenceInOrdinaryTextIsStillSpacePadded() {
        let textView = makeTextView(text: "Readlater", caret: 4)
        textView.insertMarkdownReference(Self.noteLink)
        #expect(textView.string == "Read \(Self.noteLink) later")
    }

    @Test func anImageAtTheEndOfAnEmbedLineLeavesTheCardOnItsOwnLine() {
        let asset = MarkdownImageAsset(data: Data([0x89, 0x50, 0x4E, 0x47]), mimeType: "image/png", pixelWidth: 1, pixelHeight: 1, displayWidth: 520)
        let textView = makeTextView(text: Self.embed, caret: (Self.embed as NSString).length)
        textView.insertMarkdownImages([asset])
        #expect(cardLines(in: textView.string) == [Self.embed])
        #expect(textView.string.components(separatedBy: "\n").contains(MarkdownImageAssetService.markdown(for: asset)))
    }
}
#endif
