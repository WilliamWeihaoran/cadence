import Foundation
import Testing
@testable import Cadence

/// [[T-8761]]: the `#` tag picker's rows, shared by the macOS popover and the iOS strip.
@MainActor
struct MarkdownTagCompletionSupportTests {
    private func suggestion(_ name: String, archived: Bool = false) -> MarkdownTagSuggestion {
        MarkdownTagSuggestion(
            name: name,
            slug: TagSupport.slug(for: name),
            desc: "",
            colorHex: "#4C8DFF",
            isArchived: archived
        )
    }

    @Test func aHashAfterSpaceOpensATokenAndAHeadingDoesNot() throws {
        let text = "Plan #wor"
        let context = try #require(MarkdownTagCompletionTokenSupport.context(
            in: text,
            selection: NSRange(location: (text as NSString).length, length: 0)
        ))
        #expect(context.query == "wor")
        #expect(context.range == NSRange(location: 5, length: 4))

        #expect(MarkdownTagCompletionTokenSupport.context(in: "# Heading", selection: NSRange(location: 2, length: 0)) == nil)
        #expect(MarkdownTagCompletionTokenSupport.context(in: "abc#x", selection: NSRange(location: 5, length: 0)) == nil)
        #expect(MarkdownTagCompletionTokenSupport.context(in: "#abc", selection: NSRange(location: 1, length: 3)) == nil)
    }

    @Test func aBareHashOffersEveryLiveTagAndNoArchivedOne() {
        let choices = MarkdownTagPickerChoice.choices(
            query: "",
            suggestions: [suggestion("Work"), suggestion("Old", archived: true), suggestion("Home")]
        )
        #expect(choices == [.existing(suggestion("Work")), .existing(suggestion("Home"))])
    }

    @Test func aQueryMatchesNameOrSlugIncludingArchivedAndCapsAtEight() {
        let pool = (0..<12).map { suggestion("Proj\($0)") } + [suggestion("Project Old", archived: true)]
        let choices = MarkdownTagPickerChoice.choices(query: "proj", suggestions: pool)
        #expect(choices.count == 8)

        let archived = MarkdownTagPickerChoice.choices(query: "old", suggestions: pool)
        #expect(archived == [.existing(suggestion("Project Old", archived: true))])
    }

    @Test func anUnmatchedQueryOffersOneCreateRowAndSymbolsOfferNothing() {
        let pool = [suggestion("Work")]
        #expect(MarkdownTagPickerChoice.choices(query: "errands", suggestions: pool)
            == [.create(TagSupport.displayName(for: "errands"))])
        #expect(MarkdownTagPickerChoice.choices(query: "", suggestions: []).isEmpty)
        #expect(MarkdownTagPickerChoice.choices(query: "--", suggestions: pool).isEmpty)
    }

    @Test func resolvingRestoresAnArchivedTagAndARefusedCreateWritesNothing() {
        var created: [String] = []
        let live = suggestion("Work")
        let resolvedLive = MarkdownTagPickerChoice.existing(live).resolve { name in
            created.append(name)
            return nil
        }
        #expect(resolvedLive == live)
        #expect(created.isEmpty)

        let restored = suggestion("Old")
        let resolvedArchived = MarkdownTagPickerChoice.existing(suggestion("Old", archived: true)).resolve { name in
            created.append(name)
            return restored
        }
        #expect(resolvedArchived == restored)
        #expect(created == ["Old"])

        #expect(MarkdownTagPickerChoice.create("New").resolve { _ in nil } == nil)
        #expect(MarkdownTagCompletionTokenSupport.replacement(for: live) == "#work")
    }

    /// Both platforms draw the rows `MarkdownTagPickerChoice.choices` returns, so one query offers
    /// the same tags on the Mac popover and the iOS strip ([[T-8201]]): neither keeps its own filter.
    @Test func bothPlatformsTakeTheirTagRowsFromTheOneSharedList() throws {
        let mac = try CadenceSourceScan.sourceFile("Cadence/macOS/Editor/MarkdownSlashCommandSupport.swift")
        let iOS = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSMarkdownEditingSurface.swift")
        for source in [mac, iOS] {
            #expect(source.contains("MarkdownTagPickerChoice.choices("))
            #expect(!source.contains("localizedCaseInsensitiveContains(querySlug)"))
        }
        #expect(iOS.contains("iOSMarkdownTagCompletionStrip("))
    }
}
