import Foundation
import SwiftData
import Testing
@testable import Cadence

/// [[T-14763]]: the inline `#tag` grammar reads letters and digits in every script, not only
/// ASCII, so a tag named `工作` or `Работа` ([[T-14761]] made it its own tag) has an inline
/// spelling: highlighted, swept into a tag, offered and completed by the `#` picker, and written
/// by a rename that still resolves. The ASCII rows and the exclusions -- headings, `C#`, `##`,
/// URL fragments, a body that starts with `_` or `-` -- are pinned beside them.
@MainActor
struct InlineTagScriptGrammarTests {
    private func names(_ content: String) -> [String] {
        MarkdownMetadataParser.inlineTagNames(in: content)
    }

    private func highlighted(_ markdown: String) -> [String] {
        let ns = markdown as NSString
        return MarkdownInlineMarkerRanges.hashtagRanges(in: markdown).map { ns.substring(with: $0) }
    }

    @Test func proseInChineseAndCyrillicIsSweptAsTags() {
        #expect(names("Plan #工作 today") == ["工作"])
        #expect(names("План #работа на завтра") == ["работа"])
        #expect(names("#工作，然后 #学习。") == ["工作", "学习"], "full-width punctuation ends a tag")
        #expect(names("काम #काम ok") == ["काम"], "a combining vowel sign stays inside the tag")
        #expect(names("rare #𠀋字 glyph") == ["𠀋字"], "a letter outside the BMP is one letter")
        #expect(names("mixed #2026年 and #work工作") == ["2026年", "work工作"])
    }

    @Test func theExclusionsHoldInEveryScript() {
        #expect(names("# 工作") == [], "a heading is not a tag")
        #expect(names("# Title") == [])
        #expect(names("今天#工作") == [], "a letter before the # is a word, not a tag")
        #expect(names("C# and id_#4 and é#x") == [])
        #expect(names("e\u{301}#x") == [], "a combining mark before the # belongs to the word")
        #expect(names("#_工作 #-работа") == [], "a body still starts with a letter or digit")
        #expect(names("see https://example.com/#工作 and [a](#работа)") == [])
        #expect(names("`#工作` stays code") == [])
        #expect(names("```\n#工作\n```") == [])
        // `##` was a tag before this change and still is, in either script.
        #expect(names("##work") == ["work"])
        #expect(names("##工作") == ["工作"])
        // An emoji is not a letter.
        #expect(names("#🔥 hot") == [])
    }

    @Test func theEditorHighlightsTheSameTagsTheSweepReads() {
        #expect(highlighted("Plan #工作 and #работа, #work") == ["#工作", "#работа", "#work"])
        #expect(highlighted("今天#工作 C#") == [])
    }

    @Test func aNoteMentioningAScriptTagIsSweptOntoThatTag() throws {
        let context = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let work = Cadence.Tag(name: "工作", order: 0)
        context.insert(work)
        let note = Note(kind: .daily, title: "Today", content: "Follow up on #工作 and #Работа")
        context.insert(note)

        #expect(TagSupport.syncNoteTagsFromMarkdown(note, in: context))
        let tags = note.tags ?? []
        #expect(tags.count == 2)
        #expect(tags.contains { $0 === work }, "#工作 did not resolve to the existing 工作 tag")
        #expect(tags.contains { $0.name == "Работа" })
    }

    @Test func aRenameIntoAScriptNameWritesAMentionThatStillResolves() throws {
        let context = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let note = Note(kind: .daily, title: "Today", content: "Follow up on #work today")
        context.insert(note)
        TagSupport.syncNoteTagsFromMarkdown(note, in: context)
        let work = try #require(note.tags?.first)

        #expect(TagSupport.inlineTagBody(for: "工作") == "工作")
        #expect(TagSupport.inlineTagBody(for: "Работа") == "Работа")
        #expect(TagSupport.inlineTagBody(for: "Day Job") == "day-job", "a space still falls back to the slug")

        _ = TagSupport.rename(work, to: "工作", rewritingInlineMentions: true)
        #expect(note.content == "Follow up on #工作 today")
        // The sweep reads the rewritten mention back as the renamed tag: no change, no new row.
        #expect(!TagSupport.syncNoteTagsFromMarkdown(note, in: context))
        #expect(note.tags?.first === work)
        #expect(try context.fetch(FetchDescriptor<Cadence.Tag>()).count == 1)
    }

    @Test func theCompletionTokenReadsAScriptQuery() throws {
        func context(_ text: String) -> MarkdownTagCompletionContext? {
            MarkdownTagCompletionTokenSupport.context(
                in: text,
                selection: NSRange(location: (text as NSString).length, length: 0)
            )
        }
        let cjk = try #require(context("Plan #工"))
        #expect(cjk.query == "工")
        #expect(cjk.range == NSRange(location: 5, length: 2))
        #expect(try #require(context("План #раб")).query == "раб")
        #expect(try #require(context("x #काम")).query == "काम")
        let astral = try #require(context("x #𠀋"))
        #expect(astral.query == "𠀋")
        #expect(astral.range.length == 3, "the surrogate pair is walked as one letter")
        #expect(try #require(context("x #ab")).query == "ab", "ASCII unchanged")

        #expect(context("今天#工") == nil, "a letter before the # is a word, as the sweep reads it")
        #expect(context("x ##工") == nil)
        #expect(context("e\u{301}#x") == nil, "a combining mark before the # belongs to the word")
        #expect(context("# 工") == nil)
    }

    @Test func thePickerOffersAndCreatesAScriptTag() {
        let study = MarkdownTagSuggestion.tag(Cadence.Tag(name: "学习"))
        let choices = MarkdownTagPickerChoice.choices(query: "学", suggestions: [study])
        #expect(choices.first == .create("学"))
        #expect(choices.contains(.existing(study)))
        #expect(MarkdownTagPickerChoice.choices(query: "学习", suggestions: [study]) == [.existing(study)])
        #expect(MarkdownTagCompletionTokenSupport.replacement(for: study) == "#学习")
    }
}
