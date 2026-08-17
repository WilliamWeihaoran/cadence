import Foundation
import Testing
@testable import Cadence

/// What a note-index row shows for a note that embeds a task.
///
/// `MarkdownTaskEmbedTitleCacheTests` pins the resolution itself; this pins the shape the iOS note
/// rows actually use — resolve the text, then excerpt it — and it exists because `[[task:UUID|Title]]`
/// reaches an excerpt through **two** unrelated renderers. A standalone reference on its own line is
/// a `.taskEmbed` block and is excerpted from `MarkdownTaskEmbedReference.title`; the same reference
/// mid-sentence is an inline link and is excerpted from `MarkdownReferenceDisplaySupport`'s display
/// text. Both read the cached title, so a fix aimed at either one leaves the other stale, and the
/// only reason one call covers both is that resolution happens on the string before the parse.
///
/// These are the row bodies of `iOSMeetingNoteRow` and `iOSMarkdownNoteReferenceRow` with the view
/// removed — those live under `#if os(iOS)` and the macOS-built test target cannot see them.
struct MarkdownTaskEmbedPreviewTitleTests {
    private static let taskID = UUID(uuidString: "2C4E6A80-1B3D-4F57-9E11-A2B3C4D5E6F7")!
    private static let deletedID = UUID(uuidString: "9D8C7B6A-5E4F-4A3B-8C2D-1E0F9A8B7C6D")!

    private func reference(_ id: UUID, _ title: String) -> String {
        "[[task:\(id.uuidString)|\(title)]]"
    }

    /// Exactly what the two iOS note rows do.
    private func rowPreview(_ content: String, titles: [UUID: String], limit: Int? = nil) -> String {
        CadenceMarkdownPresentationSupport.plainPreviewText(
            from: MarkdownTaskEmbedTitleCache.resolving(content, titles: titles),
            limit: limit
        )
    }

    // MARK: - The card spelling

    @Test func aStandaloneEmbedIsExcerptedUnderTheTasksCurrentTitle() {
        let content = """
        Standup

        \(reference(Self.taskID, "Draft the brief"))
        """

        let preview = rowPreview(content, titles: [Self.taskID: "Draft the Q3 brief"])

        #expect(preview == "Standup Draft the Q3 brief")
    }

    /// The row excerpts the title, never the reference syntax — a resolved embed must still parse
    /// as one, or the excerpt would leak `[[task:` and a UUID into a two-line summary.
    @Test func aResolvedEmbedNeverLeaksItsSyntaxIntoTheExcerpt() {
        let preview = rowPreview(
            reference(Self.taskID, "Old name"),
            titles: [Self.taskID: "New name"]
        )

        #expect(preview == "New name")
    }

    // MARK: - The inline spelling

    /// The gap this test exists for: mid-sentence references are not `.taskEmbed` blocks at all,
    /// so the card renderer never sees them and a fix there does nothing here.
    @Test func anInlineReferenceIsExcerptedUnderTheTasksCurrentTitle() {
        let content = "Blocked on \(reference(Self.taskID, "Draft the brief")) until Friday."

        let preview = rowPreview(content, titles: [Self.taskID: "Draft the Q3 brief"])

        #expect(preview == "Blocked on Draft the Q3 brief until Friday.")
    }

    @Test func anInlineReferenceInsideAListItemResolvesToo() {
        let content = "- follow up on \(reference(Self.taskID, "Old name"))"

        let preview = rowPreview(content, titles: [Self.taskID: "New name"])

        #expect(preview.contains("follow up on New name"))
        #expect(!preview.contains("Old name"))
    }

    /// Both spellings in one note, which is the realistic case and the one that would have exposed
    /// a half-fix: the card branch and the inline branch have to agree.
    @Test func bothSpellingsOfTheSameTaskAgreeInOneExcerpt() {
        let content = """
        \(reference(Self.taskID, "Old name"))

        See \(reference(Self.taskID, "Old name")) above.
        """

        let preview = rowPreview(content, titles: [Self.taskID: "New name"])

        #expect(!preview.contains("Old name"))
        #expect(preview.components(separatedBy: "New name").count == 3)
    }

    // MARK: - Fallback and non-embedding notes

    /// A task that no longer exists is absent from the index, and its cached title is the only name
    /// that reference has left — the same rule the missing card draws by.
    @Test func aDeletedTasksReferenceKeepsItsCachedTitleInTheExcerpt() {
        let content = "Ship it: \(reference(Self.deletedID, "Gone forever"))"

        let preview = rowPreview(content, titles: [Self.taskID: "Irrelevant"])

        #expect(preview.contains("Gone forever"))
    }

    /// The cheap gate is a performance property, not a nicety: these rows re-render constantly and
    /// most notes embed nothing, so a note with no `[[task:` must come back byte-identical without
    /// a regex pass.
    @Test func aNoteWithNoEmbedsIsNotRewrittenBeforeExcerpting() {
        let content = "# Retro\n\nWent well. See [[Last Week]] and #shipping."

        #expect(
            MarkdownTaskEmbedTitleCache.resolving(content, titles: [Self.taskID: "Anything"]) == content
        )
        #expect(rowPreview(content, titles: [Self.taskID: "Anything"]) == rowPreview(content, titles: [:]))
    }

    /// The row's own limit still applies to the resolved text, so a longer live title truncates
    /// rather than pushing the excerpt past its budget.
    @Test func theExcerptLimitAppliesAfterResolution() {
        let content = "Now: \(reference(Self.taskID, "Short"))"

        let preview = rowPreview(
            content,
            titles: [Self.taskID: "A considerably longer replacement title"],
            limit: 12
        )

        #expect(preview.count <= 12)
        #expect(preview.hasPrefix("Now: A consi"))
    }
}
