#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// [[T-13901]]: applying a template to a whole note — the iOS template menu, the Mac's empty-body
/// placeholder and Actions popover, the Mac's Task Notes pane — through
/// `CadenceNoteTemplateInsertionSupport.contentByApplying`.
@MainActor
struct CadenceNoteTemplateApplyTests {
    /// What the list `+` and Notepad's New Note write into a note nobody has named ([[T-733]]).
    private let seededNameless = "# \n\n"

    /// A `---` line of its own — a frontmatter fence. The brief's table separator is `| --- |`.
    private func hasFence(_ text: String) -> Bool {
        text.components(separatedBy: "\n").contains { $0.trimmingCharacters(in: .whitespaces) == "---" }
    }

    private var projectBrief: NoteTemplate {
        get throws { try #require(NoteTemplateLibrary.defaultTemplate(id: "project-brief")) }
    }

    @Test func aNewNamelessNoteIsBlankForTheListAndThePlaceholder() {
        #expect(NotesListVisibility.isBlankBody(seededNameless, displayTitle: "Untitled"))
        #expect(NotesListVisibility.isBlankBody(seededNameless, displayTitle: "Notepad"))
        #expect(NotesListVisibility.isBlankBody("# Kickoff\n\n", displayTitle: "Kickoff"))
        #expect(!NotesListVisibility.isBlankBody("# Kickoff\n\nAgenda", displayTitle: "Kickoff"))
        #expect(!NotesListVisibility.isBlankBody("#hashtag", displayTitle: "Untitled"))
    }

    /// Before: `"#\n\n---\ntags: [project]…"` — a stray empty heading, the template's block drawn
    /// as rules and YAML, and a note still called Untitled.
    @Test func aTemplateFillsANewNamelessNoteVerbatim() throws {
        let template = try projectBrief
        let content = CadenceNoteTemplateInsertionSupport.contentByApplying(
            template,
            to: seededNameless,
            displayTitle: "Untitled"
        )

        #expect(content == template.body)
        let split = MarkdownMetadataParser.splitFrontmatter(in: content)
        #expect(split.frontmatter.contains("tags: [project]"))
        #expect(!hasFence(split.body))
    }

    @Test func aTemplateAppendedBelowTextLeavesItsBlockBehind() throws {
        let template = try projectBrief
        let content = CadenceNoteTemplateInsertionSupport.contentByApplying(
            template,
            to: "# Kickoff\n\nAgenda first.\n",
            displayTitle: "Kickoff"
        )

        #expect(content.hasPrefix("# Kickoff\n\nAgenda first.\n\n# Project Brief\n"))
        #expect(!hasFence(content))
        #expect(!content.contains("tags: [project]"))
    }

    @Test func aTaggedNoteKeepsItsOwnBlockAndGainsNoSecond() throws {
        let template = try projectBrief
        let tagged = "---\ntags: [\"research\"]\n---\n\n# \n\n"
        let content = CadenceNoteTemplateInsertionSupport.contentByApplying(
            template,
            to: tagged,
            displayTitle: "Untitled"
        )

        let split = MarkdownMetadataParser.splitFrontmatter(in: content)
        #expect(split.frontmatter.contains("research"))
        #expect(!hasFence(split.body))
        #expect(!split.body.contains("tags:"))
        #expect(split.body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("# Project Brief"))
    }

    @Test func aTemplateWithoutABlockStillAppendsAsBefore() {
        let template = NoteTemplate(id: "plain", title: "Plain", subtitle: "", body: "## Next\n- item\n")
        #expect(
            CadenceNoteTemplateInsertionSupport.contentByApplying(template, to: "Some text  \n", displayTitle: "Untitled")
                == "Some text\n\n## Next\n- item\n"
        )
        #expect(
            CadenceNoteTemplateInsertionSupport.contentByApplying(template, to: "", displayTitle: "Untitled")
                == template.body
        )
    }

    /// **Source shape.** The two Mac panes apply templates inside a view; read from source that
    /// they hand the whole note to the shared rule rather than splicing `template.body` themselves.
    @Test func theMacPanesApplyThroughTheSharedRule() throws {
        for path in [
            "Cadence/macOS/Views/NoteEditorPane.swift",
            "Cadence/macOS/Views/ListNotesSupportViews.swift"
        ] {
            let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            let apply = try #require(
                CadenceSourceScan.declarationBody("private func applyTemplate(_ template: NoteTemplate)", in: code),
                "\(path) has no applyTemplate"
            )
            #expect(apply.contains("CadenceNoteTemplateInsertionSupport.contentByApplying("), "\(path)")
            #expect(!apply.contains("template.body"), "\(path) splices the template itself again")
        }
    }
}
#endif
