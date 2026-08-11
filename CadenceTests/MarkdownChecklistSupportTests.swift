import Foundation
import Testing
@testable import Cadence

struct MarkdownChecklistSupportTests {
    @Test func parsesGithubChecklistLines() throws {
        let info = try #require(MarkdownChecklistSupport.lineInfo(in: "  - [x] Ship the editor"))

        #expect(info.isDone)
        #expect(info.content == "Ship the editor")
        #expect(info.markerRange == NSRange(location: 0, length: 8))
    }

    @Test func parsesLegacyChecklistLines() throws {
        let info = try #require(MarkdownChecklistSupport.lineInfo(in: "\t✓ Review notes"))

        #expect(info.isDone)
        #expect(info.content == "Review notes")
        #expect(info.stateRange == NSRange(location: 1, length: 1))
    }

    @Test func togglesGithubChecklistLines() {
        #expect(MarkdownChecklistSupport.toggledLine("- [ ] Draft") == "- [x] Draft")
        #expect(MarkdownChecklistSupport.toggledLine("- [X] Draft") == "- [ ] Draft")
        #expect(MarkdownChecklistSupport.toggledLine("* [x] Draft") == "* [ ] Draft")
    }

    @Test func togglesLegacyChecklistLines() {
        #expect(MarkdownChecklistSupport.toggledLine("○ Draft") == "● Draft")
        #expect(MarkdownChecklistSupport.toggledLine("● Draft") == "○ Draft")
        #expect(MarkdownChecklistSupport.toggledLine("✓ Draft") == "○ Draft")
    }

    /// The macOS editor toggles by splicing one character into an `NSTextStorage`, so it needs the
    /// range and the replacement rather than a rebuilt line. It used to derive the replacement
    /// itself by comparing a raw UTF-16 code point.
    @Test func reportsTheOneCharacterEditThatTogglesALine() throws {
        let legacy = try #require(MarkdownChecklistSupport.toggledState(in: "  ○ Draft"))
        #expect(legacy.stateRange == NSRange(location: 2, length: 1))
        #expect(legacy.replacement == "●")

        let done = try #require(MarkdownChecklistSupport.toggledState(in: "✓ Draft"))
        #expect(done.stateRange == NSRange(location: 0, length: 1))
        #expect(done.replacement == "○")

        let github = try #require(MarkdownChecklistSupport.toggledState(in: "- [ ] Draft"))
        #expect(github.stateRange == NSRange(location: 3, length: 1))
        #expect(github.replacement == "x")

        #expect(MarkdownChecklistSupport.toggledState(in: "Plain line") == nil)
    }

    @Test func togglesLineInsideMarkdownText() {
        let text = "Intro\n- [ ] First\n○ Second"

        #expect(MarkdownChecklistSupport.toggledText(text, lineIndex: 1) == "Intro\n- [x] First\n○ Second")
        #expect(MarkdownChecklistSupport.toggledText(text, lineIndex: 2) == "Intro\n- [ ] First\n● Second")
        #expect(MarkdownChecklistSupport.toggledText(text, lineIndex: 0) == nil)
    }
}
