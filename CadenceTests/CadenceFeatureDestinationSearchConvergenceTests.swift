import Foundation
import Testing
@testable import Cadence

/// **One "what is in here" sentence per page, read by both search surfaces.**
///
/// T-1782: `CadenceFeatureDestination.searchSummary` was drawn in exactly one place — the third
/// line of an iOS search Pages row — while macOS's Cmd+K drew a `baseSubtitle` of its own for the
/// same pages, and the two disagreed about **seven of the nine** rows the palette has. Today read
/// "Daily dashboard and timeline" there and "Tasks, notes, and schedule" here; Notes "Workspace
/// notes" against "Daily, weekly, and permanent notes". Both strings were matched against, so the
/// words a query had to use to find a page differed by platform too.
///
/// **The rule was checked before anything was unified, and it does not decide this.** Page headers
/// do not describe the page the reader is already on, but search rows, pickers and empty states may
/// keep subtitles — and both of these are search *rows*. So the standing rule permits two registers
/// without requiring them. What decides it is that `baseSubtitle` was a **contents** line for all
/// nine entries, which is what `searchSummary` is, and that two of them were already `searchSummary`
/// verbatim because [[T-1701]] took them *from* the palette.
///
/// **Why these live in their own file rather than beside `CadenceFeatureDestinationCopyTests`.**
/// That suite holds the *pair* on one destination apart — subtitle against summary, the T-1701
/// contract. This one is about the two platforms agreeing, which is a different claim about the same
/// strings; and the file that declares that suite was leased to another agent while this landed.
///
/// **The enforcement is that there is nowhere left to put a second opinion**, not that two lists
/// currently agree. `GlobalSearchPageDefinition` stores one thing — the destination — and derives
/// its label, its subtitle and its aliases, exactly as T-258 deleted its stored `icon` rather than
/// leaving it stored-and-equal. A test that merely *compared* two stored lists would be green the
/// day somebody edited both, which is how the two agreed about Inbox and Goals and disagreed about
/// the other seven.
struct CadenceFeatureDestinationSearchConvergenceTests {

    /// **The behaviour.** Every row Cmd+K draws in its Pages section says what the destination says
    /// is in that page — the same sentence the iOS search row draws on its third line.
    ///
    /// Asserted through `pageResults`, which is the function that builds the row, rather than
    /// against the catalog: the subtitle a reader sees is assembled there (it is where the
    /// "• Hidden from sidebar" suffix is appended), so the catalog agreeing is not the claim.
    @Test func everyPaletteRowDrawsItsDestinationsOwnContentsSentence() {
        let rows = GlobalSearchDataSupport.pageResults(
            query: "",
            hiddenTabs: [],
            sidebarTabColorsRaw: ""
        )
        // Non-vacuity: a loop over nothing passes, and so does a lookup that never hits.
        #expect(rows.count == GlobalSearchPageDefinition.all.count)
        #expect(rows.count >= 9, "read \(rows.count) palette page rows")

        var matched = 0
        for page in GlobalSearchPageDefinition.all {
            let row = rows.first { $0.id == "page-\(page.feature.title)" }
            #expect(row != nil, "\(page.feature.rawValue) produced no palette row")
            guard let row else { continue }
            matched += 1
            #expect(
                row.subtitle == page.feature.searchSummary,
                "the palette says \"\(row.subtitle)\" about \(page.feature.rawValue) and the destination says \"\(page.feature.searchSummary)\" (T-1782)"
            )
            #expect(row.title == page.feature.title)
        }
        #expect(matched == GlobalSearchPageDefinition.all.count)

        // The suffix is still appended to that sentence rather than replacing it, so converging
        // the copy did not quietly drop the one thing the palette's own string was doing.
        let hidden = GlobalSearchDataSupport.pageResults(
            query: "",
            hiddenTabs: [.focus],
            sidebarTabColorsRaw: ""
        ).first { $0.id == "page-Focus" }
        #expect(hidden?.subtitle == "\(CadenceFeatureDestination.focus.searchSummary) • Hidden from sidebar")
    }

    /// **The enforcement, which is that there is nowhere left to put a second opinion.** The
    /// catalog stores one fact per row — the destination — and every string it used to carry is
    /// derived. A test that merely *compared* two stored lists would be green the day somebody
    /// edited both, which is how the two lists agreed about Inbox and Goals and disagreed about
    /// the other seven.
    ///
    /// Counted as a relation between the entry count and the literal count rather than against a
    /// fixed nine, so a tenth page is covered the day it is added.
    @Test func thePalettesPageCatalogStoresNothingButTheDestination() throws {
        let source = try CadenceCommitSurfaceScan.scanned(
            "Cadence/macOS/Views/GlobalSearchSupportViews.swift"
        )
        let definition = try #require(
            CadenceSourceScan.declarationBody("struct GlobalSearchPageDefinition", in: source),
            "GlobalSearchPageDefinition no longer reads as a declaration this scan can scope to"
        )
        #expect(
            CadenceSourceScan.matchCount(#"\n    let [a-zA-Z]+:"#, in: definition) == 1,
            "GlobalSearchPageDefinition stores something besides the destination again (T-1782)"
        )
        #expect(
            CadenceSourceScan.matchCount(#"let feature: CadenceFeatureDestination"#, in: definition) == 1,
            "GlobalSearchPageDefinition no longer stores the destination it is about"
        )

        let catalog = try #require(
            CadenceSourceScan.declarationBody("extension GlobalSearchPageDefinition", in: source),
            "the Pages catalog no longer reads as an extension this scan can scope to"
        )
        let entries = CadenceSourceScan.matchCount(#"\.init\(feature: \."#, in: catalog)
        #expect(
            entries == GlobalSearchPageDefinition.all.count,
            "scanned \(entries) catalog entries against \(GlobalSearchPageDefinition.all.count) rows"
        )
        #expect(
            CadenceSourceScan.matchCount(#"\""#, in: catalog) == 0,
            "the Pages catalog types a string again, and every string it used to type was a second answer to a question CadenceFeatureDestination already answers (T-1782)"
        )
    }

    /// **The words a query has to use no longer depend on the platform.** Cmd+K matched against its
    /// own per-page `aliases` and iOS against `searchAliases`, so five words reached a page on one
    /// platform and nothing on the other. They were folded into `searchKeywords` rather than
    /// dropped, and this is the half of T-1782 that says nothing stopped being findable.
    @Test func theWordsThatReachAPageAreTheSameOnBothPlatforms() {
        let strandedOnTheDesktop: [(CadenceFeatureDestination, [String])] = [
            (.today, ["dashboard", "daily"]),
            (.goals, ["targets", "stages"]),
            (.notes, ["docs"]),
            (.allTasks, ["tasks", "all"]),
            (.calendar, ["schedule", "events"])
        ]
        for (destination, words) in strandedOnTheDesktop {
            for word in words {
                #expect(
                    destination.searchAliases.localizedCaseInsensitiveContains(word),
                    "\"\(word)\" no longer reaches \(destination.rawValue), and it reached it from Cmd+K before T-1782"
                )
                #expect(
                    GlobalSearchDataSupport.pageResults(
                        query: word,
                        hiddenTabs: [],
                        sidebarTabColorsRaw: ""
                    ).contains { $0.id == "page-\(destination.title)" },
                    "the palette no longer finds \(destination.rawValue) for \"\(word)\" (T-1782)"
                )
            }
        }

        // The control: a word no page claims finds none of them, so the assertions above are not
        // passing because everything matches everything.
        #expect(
            GlobalSearchDataSupport.pageResults(
                query: "zzqqx",
                hiddenTabs: [],
                sidebarTabColorsRaw: ""
            ).isEmpty
        )
    }
}
