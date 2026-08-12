import Foundation
import Testing
@testable import Cadence

struct MarkdownReferenceDisplaySupportTests {
    @Test func plainWikiLinkDisplaysItsLabelAsANote() {
        let display = MarkdownReferenceDisplaySupport.display(forWikiLabel: "Project Notes")

        #expect(display.kind == .note)
        #expect(display.displayText == "Project Notes")
        #expect(display.hiddenPrefixUTF16Length == 0)
    }

    @Test func noteReferenceDisplaysTitleWithoutStoredIdentifier() {
        let display = MarkdownReferenceDisplaySupport.display(
            forWikiLabel: "note:11111111-1111-1111-1111-111111111111|Project Notes"
        )

        #expect(display.kind == .note)
        #expect(display.displayText == "Project Notes")
        #expect(display.hiddenPrefixUTF16Length > 0)
        #expect(display.target.referenceID == UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        #expect(display.target.title == "Project Notes")
    }

    @Test func taskReferenceDisplaysTitleWithoutStoredIdentifier() {
        let display = MarkdownReferenceDisplaySupport.display(
            forWikiLabel: "task:22222222-2222-2222-2222-222222222222|Ship iOS notes"
        )

        #expect(display.kind == .task)
        #expect(display.displayText == "Ship iOS notes")
        #expect(display.hiddenPrefixUTF16Length > 0)
        #expect(display.target.referenceID == UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        #expect(display.target.title == "Ship iOS notes")
    }

    @Test func renderedMarkdownUsesDisplayLabelsForCadenceReferences() {
        let markdown = "Review [[task:22222222-2222-2222-2222-222222222222|Ship iOS notes]] and [[note:11111111-1111-1111-1111-111111111111|Project Notes]]."

        let segments = MarkdownReferenceDisplaySupport.inlineSegments(in: markdown)

        #expect(segments.map(\.text).joined() == "Review Ship iOS notes and Project Notes.")
        #expect(segments.compactMap { $0.target?.kind } == [.task, .note])
    }

    @Test func inlineSegmentsPreserveReferenceTargets() {
        let markdown = "Review [[task:22222222-2222-2222-2222-222222222222|Ship iOS notes]] today."

        let segments = MarkdownReferenceDisplaySupport.inlineSegments(in: markdown)

        #expect(segments.count == 3)
        #expect(segments[0].text == "Review ")
        #expect(segments[1].text == "Ship iOS notes")
        #expect(segments[1].target?.kind == .task)
        #expect(segments[1].target?.referenceID == UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        #expect(segments[2].text == " today.")
    }

    @Test func referenceRangesPointAtVisibleDisplayText() throws {
        let markdown = "Review [[task:22222222-2222-2222-2222-222222222222|Ship iOS notes]] today."

        let reference = try #require(MarkdownReferenceDisplaySupport.referenceRanges(in: markdown).first)
        let visibleLocation = (markdown as NSString).range(of: "Ship iOS notes").location
        let hiddenLocation = (markdown as NSString).range(of: "task:").location

        #expect(NSLocationInRange(visibleLocation, reference.displayRange))
        #expect(!NSLocationInRange(hiddenLocation, reference.displayRange))
        #expect(MarkdownReferenceDisplaySupport.target(atUTF16Location: visibleLocation, in: markdown)?.kind == .task)
        #expect(MarkdownReferenceDisplaySupport.target(atUTF16Location: hiddenLocation, in: markdown) == nil)
        #expect(MarkdownReferenceDisplaySupport.target(
            atUTF16Location: hiddenLocation,
            in: markdown,
            includesHiddenSyntax: true
        )?.kind == .task)
    }

    @Test func referenceTargetsRoundTripThroughInternalURL() throws {
        let target = MarkdownReferenceDisplayTarget(
            kind: .note,
            referenceID: UUID(uuidString: "11111111-1111-1111-1111-111111111111"),
            title: "Project Notes"
        )

        let url = try #require(MarkdownReferenceDisplaySupport.url(for: target))
        let roundTrip = try #require(MarkdownReferenceDisplaySupport.target(from: url))

        #expect(roundTrip == target)
    }

    @Test func taskReferenceTargetsRoundTripThroughInternalURLWithEscapedTitle() throws {
        let target = MarkdownReferenceDisplayTarget(
            kind: .task,
            referenceID: UUID(uuidString: "22222222-2222-2222-2222-222222222222"),
            title: "Ship iOS notes & markdown"
        )

        let url = try #require(MarkdownReferenceDisplaySupport.url(for: target))
        let roundTrip = try #require(MarkdownReferenceDisplaySupport.target(from: url))

        #expect(roundTrip == target)
    }
}
