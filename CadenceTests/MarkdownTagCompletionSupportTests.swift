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
        // Eight tag rows, led by the Create row no tag's slug answers ([[T-14472]]).
        #expect(choices.count == 9)
        #expect(choices.first == .create(TagSupport.displayName(for: "proj")))
        #expect(choices.dropFirst().allSatisfy { if case .existing = $0 { true } else { false } })

        let archived = MarkdownTagPickerChoice.choices(query: "old", suggestions: pool)
        #expect(archived == [.create("old"), .existing(suggestion("Project Old", archived: true))])
    }

    /// [[T-14472]]: the Mac popover's Return applies the first row, so `#work` + Return in a store
    /// holding `homework` wrote `#homework`. With no tag carrying the query's slug the first row is
    /// the Create row -- Return writes what was typed -- and the partial match stays one row down.
    @Test func aPartialMatchNoLongerLeadsAndTheCreateRowIsOfferedBesideIt() {
        let pool = [suggestion("homework"), suggestion("party")]
        #expect(MarkdownTagPickerChoice.choices(query: "work", suggestions: pool)
            == [.create("work"), .existing(suggestion("homework"))])
        #expect(MarkdownTagPickerChoice.choices(query: "art", suggestions: pool)
            == [.create("art"), .existing(suggestion("party"))])
    }

    /// An exact match ranks first even when the catalogue order puts a longer tag ahead of it, and
    /// is promoted before the eight-row cap, so it cannot fall past the eighth row.
    @Test func anExactMatchRanksFirstAndSurvivesTheCap() {
        let homework = suggestion("homework")
        let work = suggestion("work")
        #expect(MarkdownTagPickerChoice.choices(query: "work", suggestions: [homework, work])
            == [.existing(work), .existing(homework)])
        #expect(MarkdownTagPickerChoice.choices(query: "Work", suggestions: [homework, work]).first == .existing(work))

        let crowd = (0..<9).map { suggestion("a\($0)") }
        let exact = suggestion("a")
        let choices = MarkdownTagPickerChoice.choices(query: "a", suggestions: crowd + [exact])
        #expect(choices.count == 8)
        #expect(choices.first == .existing(exact))
        #expect(!choices.contains(.create("a")), "a Create row is offered over a tag that already carries the slug")
    }

    /// An archived tag carrying the slug is the exact match -- restored when chosen -- and, as in
    /// the task pickers (`creationDecision` puts `archived` first), no Create row is offered for it.
    @Test func anArchivedExactMatchLeadsAndOffersNoCreateRow() {
        let archived = suggestion("work", archived: true)
        #expect(MarkdownTagPickerChoice.choices(query: "work", suggestions: [suggestion("homework"), archived])
            == [.existing(archived), .existing(suggestion("homework"))])
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
