import Foundation
import Testing
@testable import Cadence

struct MarkdownInlinePreviewSupportTests {
    @Test func segmentsPreservePlainMarkdownAndReferenceTargets() throws {
        let taskID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let markdown = "**Review** [[task:\(taskID.uuidString)|Ship iOS notes]] today."

        let segments = MarkdownInlinePreviewSupport.segments(in: markdown)

        #expect(segments.count == 3)
        #expect(segments[0] == MarkdownInlinePreviewSegment(text: "**Review** ", target: nil))
        #expect(segments[0].shouldParseMarkdown)
        #expect(segments[1].text == "Ship iOS notes")
        #expect(segments[1].target?.kind == .task)
        #expect(segments[1].target?.referenceID == taskID)
        #expect(!segments[1].shouldParseMarkdown)
        #expect(segments[2] == MarkdownInlinePreviewSegment(text: " today.", target: nil))
    }

    @Test func renderedRunsRemoveCadenceReferenceStorageSyntax() throws {
        let noteID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let markdown = "Open [[note:\(noteID.uuidString)|Project Notes]] after `standup`."

        // `runs` is what both preview renderers consume, so assert the reader-visible string there.
        let runs = MarkdownInlinePreviewSupport.runs(in: markdown)
        #expect(runs.map(\.text).joined() == "Open Project Notes after standup.")
        #expect(runs.first { $0.target != nil }?.text == "Project Notes")
        #expect(runs.first { $0.target != nil }?.target?.referenceID == noteID)

        // Segments keep the surrounding markdown for the styler to parse; only the reference
        // storage syntax is resolved away.
        #expect(
            MarkdownInlinePreviewSupport.segments(in: markdown).map(\.text).joined()
                == "Open Project Notes after `standup`."
        )
    }

    @Test func runsExposeCadenceInlineTraitsAndLinks() {
        let runs = MarkdownInlinePreviewSupport.runs(
            in: "**Bold** *Italic* ***Both*** ~~Gone~~ ==Marked== `code` #cadence [Site](https://example.com)"
        )

        #expect(runs == [
            MarkdownInlinePreviewRun(text: "Bold", traits: .bold),
            MarkdownInlinePreviewRun(text: " "),
            MarkdownInlinePreviewRun(text: "Italic", traits: .italic),
            MarkdownInlinePreviewRun(text: " "),
            MarkdownInlinePreviewRun(text: "Both", traits: [.bold, .italic]),
            MarkdownInlinePreviewRun(text: " "),
            MarkdownInlinePreviewRun(text: "Gone", traits: .strikethrough),
            MarkdownInlinePreviewRun(text: " "),
            MarkdownInlinePreviewRun(text: "Marked", traits: .highlight),
            MarkdownInlinePreviewRun(text: " "),
            MarkdownInlinePreviewRun(text: "code", traits: .inlineCode),
            MarkdownInlinePreviewRun(text: " "),
            MarkdownInlinePreviewRun(text: "#cadence", traits: .tag),
            MarkdownInlinePreviewRun(text: " "),
            MarkdownInlinePreviewRun(text: "Site", linkURL: "https://example.com")
        ])
    }

    @Test func runsExposeUnderscoreEmphasisTraits() {
        let runs = MarkdownInlinePreviewSupport.runs(
            in: "__Bold__ _Italic_ ___Both___ keep_snake_case"
        )

        #expect(runs == [
            MarkdownInlinePreviewRun(text: "Bold", traits: .bold),
            MarkdownInlinePreviewRun(text: " "),
            MarkdownInlinePreviewRun(text: "Italic", traits: .italic),
            MarkdownInlinePreviewRun(text: " "),
            MarkdownInlinePreviewRun(text: "Both", traits: [.bold, .italic]),
            MarkdownInlinePreviewRun(text: " keep_snake_case")
        ])
    }

    @Test func runsKeepCadenceReferencesAsInteractiveTargets() throws {
        let taskID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let runs = MarkdownInlinePreviewSupport.runs(in: "Open [[task:\(taskID.uuidString)|Ship iOS notes]] now")

        #expect(runs.count == 3)
        #expect(runs[0] == MarkdownInlinePreviewRun(text: "Open "))
        #expect(runs[1].text == "Ship iOS notes")
        #expect(runs[1].target?.kind == .task)
        #expect(runs[1].target?.referenceID == taskID)
        #expect(runs[2] == MarkdownInlinePreviewRun(text: " now"))
    }

    @Test func runsUseImageAltTextForInlineCadenceImages() {
        let imageID = "33333333-3333-3333-3333-333333333333"
        let runs = MarkdownInlinePreviewSupport.runs(
            in: "See ![Sketch](cadence-image://\(imageID)) and ![](cadence-image://\(imageID))"
        )

        #expect(runs == [
            MarkdownInlinePreviewRun(text: "See "),
            MarkdownInlinePreviewRun(text: "Sketch", traits: .image),
            MarkdownInlinePreviewRun(text: " and "),
            MarkdownInlinePreviewRun(text: "Image", traits: .image)
        ])
    }

    @Test func runsNormalizeMarkdownInsideLinkLabels() {
        let runs = MarkdownInlinePreviewSupport.runs(
            in: "Open [**Docs** and `API`](https://example.com) today"
        )

        #expect(runs == [
            MarkdownInlinePreviewRun(text: "Open "),
            MarkdownInlinePreviewRun(text: "Docs and API", linkURL: "https://example.com"),
            MarkdownInlinePreviewRun(text: " today")
        ])
    }

    @Test func runsNormalizeNestedInlineMarkdownInsideEmphasis() {
        let runs = MarkdownInlinePreviewSupport.runs(
            in: "**Review `API` and [Docs](https://example.com)** then ==mark ~~old~~=="
        )

        #expect(runs == [
            MarkdownInlinePreviewRun(text: "Review API and Docs", traits: .bold),
            MarkdownInlinePreviewRun(text: " then "),
            MarkdownInlinePreviewRun(text: "mark old", traits: .highlight)
        ])
    }

    @Test func runsPreserveLiteralContentInsideInlineCode() {
        let runs = MarkdownInlinePreviewSupport.runs(
            in: "`**not bold** [raw](https://example.com)`"
        )

        #expect(runs == [
            MarkdownInlinePreviewRun(text: "**not bold** [raw](https://example.com)", traits: .inlineCode)
        ])
    }
}
