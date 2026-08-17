import Foundation
import Testing
@testable import Cadence

@MainActor
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

    /// Which spelling a line uses is a property of the line, not something each renderer should be
    /// re-deriving by testing a marker string against a `["○", "●", "✓"]` literal. The two render
    /// differently: GitHub syntax hides a six-character prefix and draws a box, the legacy glyph is
    /// one visible character styled in place.
    @Test func reportsWhichSpellingALineIsWrittenIn() throws {
        #expect(try #require(MarkdownChecklistSupport.lineInfo(in: "- [x] ship")).syntax == .github)
        #expect(try #require(MarkdownChecklistSupport.lineInfo(in: "  * [ ] ship")).syntax == .github)
        #expect(try #require(MarkdownChecklistSupport.lineInfo(in: "\t+ [X] ship")).syntax == .github)
        #expect(try #require(MarkdownChecklistSupport.lineInfo(in: "○ ship")).syntax == .legacy)
        #expect(try #require(MarkdownChecklistSupport.lineInfo(in: "  ✓ ship")).syntax == .legacy)
        #expect(try #require(MarkdownChecklistSupport.lineInfo(in: "● ship")).syntax == .legacy)
    }

    /// What pressing return inherits: the same spelling, box emptied. Answering a GitHub line with
    /// `○ ` used to put Cadence's glyph back into a document written in portable syntax one line
    /// at a time.
    @Test func emptiesAPrefixWithoutChangingItsSpelling() {
        #expect(MarkdownChecklistSupport.emptiedPrefix(in: "- [x] ") == "- [ ] ")
        #expect(MarkdownChecklistSupport.emptiedPrefix(in: "    * [X] ") == "    * [ ] ")
        #expect(MarkdownChecklistSupport.emptiedPrefix(in: "✓ ") == "○ ")
        #expect(MarkdownChecklistSupport.emptiedPrefix(in: "  ● ") == "  ○ ")
        #expect(MarkdownChecklistSupport.emptiedPrefix(in: "• ") == nil)
    }

    /// A checkbox typed into a Cadence bullet list is spelled `• [x] `, not `- [x] `: `- ` is
    /// rewritten to `• ` on the keystroke after it, and pressing return in a bullet list continues
    /// with `• `. While the matcher only accepted `[-*+]`, every one of those lines fell through to
    /// the plain-bullet branch and rendered as a bullet glyph with a literal `[x]` beside it — the
    /// reported "checkbox markers never render on iOS", which was a detection failure, not a
    /// drawing one.
    @Test func readsCadencesOwnBulletGlyphsAsCheckboxMarkers() throws {
        for line in ["• [x] ship", "◦ [x] ship", "▪ [x] ship", "– [x] ship", "  • [X] ship"] {
            let info = try #require(MarkdownChecklistSupport.lineInfo(in: line), "\(line) should be a checkbox")
            #expect(info.syntax == .github)
            #expect(info.isDone)
            #expect(info.content == "ship")
        }

        let todo = try #require(MarkdownChecklistSupport.lineInfo(in: "• [ ] ship"))
        #expect(!todo.isDone)
        #expect(MarkdownChecklistSupport.toggledLine("• [ ] ship") == "• [x] ship")
        #expect(MarkdownChecklistSupport.emptiedPrefix(in: "• [x] ") == "• [ ] ")
    }

    /// The widening above is to the *bullet* only. A bullet with no box is still a bullet, and a
    /// box with no space after the marker is not a list line at all.
    @Test func stillRequiresABoxAfterTheBullet() {
        #expect(MarkdownChecklistSupport.lineInfo(in: "• plain bullet") == nil)
        #expect(MarkdownChecklistSupport.lineInfo(in: "•[x] no space") == nil)
        #expect(MarkdownChecklistSupport.lineInfo(in: "Sales • [x] not at line start") == nil)
    }

    @Test func togglesLineInsideMarkdownText() {
        let text = "Intro\n- [ ] First\n○ Second"

        #expect(MarkdownChecklistSupport.toggledText(text, lineIndex: 1) == "Intro\n- [x] First\n○ Second")
        #expect(MarkdownChecklistSupport.toggledText(text, lineIndex: 2) == "Intro\n- [ ] First\n● Second")
        #expect(MarkdownChecklistSupport.toggledText(text, lineIndex: 0) == nil)
    }
}
