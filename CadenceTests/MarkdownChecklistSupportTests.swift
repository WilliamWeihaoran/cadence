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

    @Test func togglesLineInsideMarkdownText() {
        let text = "Intro\n- [ ] First\n○ Second"

        #expect(MarkdownChecklistSupport.toggledText(text, lineIndex: 1) == "Intro\n- [x] First\n○ Second")
        #expect(MarkdownChecklistSupport.toggledText(text, lineIndex: 2) == "Intro\n- [ ] First\n● Second")
        #expect(MarkdownChecklistSupport.toggledText(text, lineIndex: 0) == nil)
    }
}
