import Foundation
import SwiftData
import Testing
@testable import Cadence

/// [[T-14761]]: a tag named in a script with no ASCII letter or digit is its own tag.
///
/// Every such name used to collapse to the one fallback slug `"tag"`, so `工作` and `学习` were the
/// same tag: Settings refused the second as a duplicate of the first, a task picker attached the
/// first when the second was typed, and frontmatter resolved one to the other.
@MainActor
struct TagScriptSlugTests {
    @Test func namesInOtherScriptsGetDistinctSlugsAndASCIISlugsDoNotMove() {
        let cjkWork = TagSupport.slug(for: "工作")
        let cjkStudy = TagSupport.slug(for: "学习")
        let cyrillic = TagSupport.slug(for: "Работа")
        #expect(cjkWork != cjkStudy)
        #expect(cjkWork != "tag" && cjkStudy != "tag" && cyrillic != "tag")
        #expect(cyrillic == TagSupport.slug(for: "работа"), "case still folds outside ASCII")
        #expect(TagSupport.slug(for: "家 务") == "家-务")
        // Idempotent, which `stableSlug` and the import's identity rely on.
        for slug in [cjkWork, cjkStudy, cyrillic, "家-务"] {
            #expect(TagSupport.slug(for: slug) == slug)
        }
        // Every name with an ASCII letter or digit keeps the slug it always had.
        #expect(TagSupport.slug(for: " Bug Fix ") == "bug-fix")
        #expect(TagSupport.slug(for: "Café") == "cafe")
        #expect(TagSupport.slug(for: "工作 2026") == "2026")
        #expect(TagSupport.slug(for: "--") == "tag")
        #expect(TagSupport.slug(for: "") == "tag")
    }

    @Test func settingsCanCreateASecondTagNamedInAnotherScript() throws {
        let existing = Cadence.Tag(name: "工作")
        switch TagSupport.creationDecision(for: "学习", in: [existing]) {
        case .creatable(let name, let slug):
            #expect(name == "学习")
            #expect(slug == TagSupport.slug(for: "学习"))
        default:
            Issue.record("学习 was refused beside 工作")
        }
        if case .duplicate(let match) = TagSupport.creationDecision(for: "工作", in: [existing]) {
            #expect(match === existing)
        } else {
            Issue.record("the same name was not reported as a duplicate")
        }
    }

    @Test func typingAnotherScriptNameNoLongerAttachesTheFirstTag() throws {
        let context = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let work = Cadence.Tag(name: "工作", order: 0)
        context.insert(work)

        let resolved = try #require(TagSupport.resolveTags(named: ["学习"], in: context))
        #expect(resolved.count == 1)
        #expect(resolved.first !== work, "学习 resolved to 工作")
        #expect(resolved.first?.name == "学习")
        #expect(try context.fetch(FetchDescriptor<Cadence.Tag>()).count == 2)
    }

    /// The legacy half: a row written before the fix stored `"tag"` under the name `工作`. Its own
    /// name must still resolve to it rather than mint a second `工作`, and a new script name must
    /// not resolve to it.
    @Test func aRowStoredUnderTheOldFallbackSlugStillAnswersToItsName() throws {
        let context = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let legacy = Cadence.Tag(name: "工作", slug: "tag", order: 0)
        context.insert(legacy)

        let same = try #require(TagSupport.resolveTags(named: ["工作"], in: context))
        #expect(same.count == 1 && same.first === legacy, "the legacy row's own name minted a duplicate")
        #expect(try context.fetch(FetchDescriptor<Cadence.Tag>()).count == 1)

        let other = try #require(TagSupport.resolveTags(named: ["学习"], in: context))
        #expect(other.first !== legacy)

        if case .duplicate(let match) = TagSupport.creationDecision(for: "工作", in: [legacy]) {
            #expect(match === legacy)
        } else {
            Issue.record("Settings would create a second 工作 beside the legacy row")
        }
    }

    /// The note editor's `#` picker writes `#<slug>` into prose, and the inline grammar is ASCII,
    /// so a tag it cannot spell is not offered -- neither a new-style row nor a legacy `"tag"` row
    /// whose name is `工作` (offering that one would write `#tag`, a different tag).
    @Test func theInlinePickerOffersOnlyTagsItCanSpell() {
        let ascii = Cadence.Tag(name: "Work", order: 0)
        let script = Cadence.Tag(name: "学习", order: 1)
        let legacy = Cadence.Tag(name: "工作", slug: "tag", order: 2)
        let literal = Cadence.Tag(name: "tag", order: 3)

        let offered = MarkdownTagSuggestion.suggestions(from: [ascii, script, legacy, literal]).map(\.name)
        #expect(offered == ["Work", "tag"])
        #expect(TagSupport.canBeMentionedInline(ascii))
        #expect(!TagSupport.canBeMentionedInline(script))
        #expect(!TagSupport.canBeMentionedInline(legacy))
    }
}
