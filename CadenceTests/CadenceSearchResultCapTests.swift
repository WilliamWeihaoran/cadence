import Foundation
import Testing

@testable import Cadence

/// T-3089: a capped search section ends with a row that says how many matches it is withholding
/// and reveals them in place.
///
/// The cap itself is deliberately untouched — mobile still lists 24 per section while a query is
/// live and 8 when idle. What is being pinned is that the number is *stated*, that the stated
/// number is the real remainder, and that tapping it yields all of it.
@Suite struct CadenceSearchResultCapTests {
    @Test func aCappedSearchSectionDrawsTheCapAndNamesTheExactRemainder() {
        #expect(CadenceSearchResultCap.visibleCount(total: 62, cap: 24, isExpanded: false) == 24)
        #expect(CadenceSearchResultCap.hiddenCount(total: 62, cap: 24, isExpanded: false) == 38)
        #expect(CadenceSearchResultCap.continuationLabel(hidden: 38) == "38 more results")
    }

    /// The whole point of the affordance: expanding yields everything, not another capful.
    @Test func expandingASectionRevealsEveryRemainingMatchAtOnce() {
        #expect(CadenceSearchResultCap.visibleCount(total: 62, cap: 24, isExpanded: true) == 62)
        #expect(CadenceSearchResultCap.hiddenCount(total: 62, cap: 24, isExpanded: true) == nil)
        // Far past two capfuls, so "it just takes 24 more" would be visible here.
        #expect(CadenceSearchResultCap.visibleCount(total: 500, cap: 24, isExpanded: true) == 500)
    }

    /// A section that fits draws no row at all, rather than a "0 more results" one.
    @Test func aSearchSectionThatListsEverythingOffersNoContinuation() {
        #expect(CadenceSearchResultCap.visibleCount(total: 24, cap: 24, isExpanded: false) == 24)
        #expect(CadenceSearchResultCap.hiddenCount(total: 24, cap: 24, isExpanded: false) == nil)
        #expect(CadenceSearchResultCap.hiddenCount(total: 3, cap: 24, isExpanded: false) == nil)
        #expect(CadenceSearchResultCap.continuationLabel(hidden: 0) == nil)
        #expect(CadenceSearchResultCap.continuationLabel(hidden: -2) == nil)
    }

    /// One withheld match is the case a naive `"\(n) more results"` gets wrong, and it is reachable
    /// by typing one more character into a query that matched 25.
    @Test func oneWithheldMatchReadsAsOneResultRatherThanOneResults() {
        #expect(CadenceSearchResultCap.continuationLabel(hidden: 1) == "1 more result")
        #expect(CadenceSearchResultCap.continuationLabel(hidden: 2) == "2 more results")
        #expect(CadenceSearchResultCap.hiddenCount(total: 25, cap: 24, isExpanded: false) == 1)
    }

    /// Degenerate inputs clamp rather than going negative or reading off the end of an array —
    /// `visibleCount` is used as a `prefix` length.
    @Test func theSearchCapClampsRatherThanTrustingItsInputs() {
        #expect(CadenceSearchResultCap.visibleCount(total: -4, cap: 24, isExpanded: false) == 0)
        #expect(CadenceSearchResultCap.visibleCount(total: 10, cap: -3, isExpanded: false) == 0)
        #expect(CadenceSearchResultCap.hiddenCount(total: 10, cap: -3, isExpanded: false) == 10)
        #expect(CadenceSearchResultCap.hiddenCount(total: -4, cap: 24, isExpanded: false) == nil)
    }

    /// The drawn rows and the stated remainder always account for the whole match list, at every
    /// size either side of the cap. This is the "N rows under a count of M" failure the completed
    /// sections already had to be corrected for.
    @Test func theDrawnRowsAndTheStatedRemainderAlwaysAccountForEveryMatch() {
        for total in 0...60 {
            for cap in [0, 1, 8, 14, 24] {
                for expanded in [false, true] {
                    let visible = CadenceSearchResultCap.visibleCount(total: total, cap: cap, isExpanded: expanded)
                    let hidden = CadenceSearchResultCap.hiddenCount(total: total, cap: cap, isExpanded: expanded) ?? 0
                    #expect(visible + hidden == total)
                    #expect(visible <= total)
                    if !expanded {
                        #expect(visible <= cap)
                    }
                }
            }
        }
    }

    /// The mobile search surface asks the shared type for all three numbers, and the continuation
    /// it hands the group is built from the same `hidden` the label names.
    ///
    /// `Cadence/iOS/` is behind `#if os(iOS)` and this target builds on macOS, so this is the only
    /// way to read it.
    @Test func mobileSearchSectionsRouteTheirCapThroughTheSharedType() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSearchView.swift")
        let code = CadenceSourceScan.codeOnly(raw)
        #expect(code != raw, "nothing was stripped, so the scan read raw text")
        #expect(code.count == raw.count, "the stripper changed the source's length")

        let body = try #require(
            CadenceSourceScan.functionBody(named: "resultSection", in: code),
            "could not read iOSSearchView.resultSection"
        )
        #expect(body.contains("CadenceSearchResultCap.visibleCount("))
        #expect(body.contains("CadenceSearchResultCap.hiddenCount("))
        #expect(body.contains("CadenceSearchResultCap.continuationLabel("))
        #expect(body.contains("iOSSearchResultContinuation("))
        // The cap is read once, from the surface's own property, rather than retyped beside each
        // of the two calls that must agree about it.
        #expect(CadenceSourceScan.matchCount(#"cap: sectionResultCap"#, in: body) == 2)
        // The old silent truncation.
        #expect(CadenceSourceScan.matchCount(#"prefix\(isSearching \? 24 : 8\)"#, in: body) == 0)
    }

    /// The caps themselves are unchanged. T-3089 was not asked to unify or retune them, and a
    /// change that quietly moved 24 would be a different ticket wearing this one's clothes.
    @Test func mobileSearchStillListsTwentyFourPerSectionAndEightWhenIdle() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSearchView.swift")
        let code = CadenceSourceScan.codeOnly(raw)
        #expect(code != raw)

        let body = try #require(
            CadenceSourceScan.declarationBody("private var sectionResultCap: Int", in: code),
            "could not read iOSSearchView.sectionResultCap"
        )
        #expect(body.contains("isSearching ? 24 : 8"))
    }

    /// An expansion belongs to one result set. A section left expanded across a new query would
    /// hand the next search an uncapped list nobody asked for — which is the defect this ticket
    /// fixed, in reverse.
    @Test func expandingASectionDoesNotSurviveANewQueryOrScope() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSearchView.swift")
        let code = CadenceSourceScan.codeOnly(raw)
        #expect(code != raw)

        let identity = try #require(
            CadenceSourceScan.declarationBody("private var resultSetIdentity: String", in: code),
            "could not read iOSSearchView.resultSetIdentity"
        )
        #expect(identity.contains("trimmedQuery"))
        #expect(identity.contains("scope.rawValue"))
        #expect(identity.contains("includeCompletedTasks"))

        #expect(CadenceSourceScan.matchCount(#"onChange\(of: resultSetIdentity\)"#, in: code) == 1)
        #expect(CadenceSourceScan.matchCount(#"expandedSections\.removeAll\(\)"#, in: code) == 1)
    }

    /// The group draws the row it was handed, and only when it was handed one.
    @Test func theSearchResultGroupDrawsTheContinuationRowInsideItsOwnCard() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSearchSupportViews.swift")
        let code = CadenceSourceScan.codeOnly(raw)
        #expect(code != raw)
        #expect(code.count == raw.count)

        let body = try #require(
            CadenceSourceScan.declarationBody("struct iOSSearchResultGroup<Row: View>", in: code),
            "could not read iOSSearchResultGroup"
        )
        #expect(body.contains("var continuation: iOSSearchResultContinuation?"))
        #expect(body.contains("iOSSearchMoreResultsRow(continuation: continuation)"))
        // Drawn under a rule, inside the results card, not floating beside it.
        #expect(body.contains("index < count - 1 || continuation != nil"))

        let rowBody = try #require(
            CadenceSourceScan.declarationBody("private struct iOSSearchMoreResultsRow", in: code),
            "could not read iOSSearchMoreResultsRow"
        )
        #expect(rowBody.contains("Button(action: continuation.reveal)"))
        // A tap target, not a caption.
        #expect(rowBody.contains("minHeight: 44"))
    }
}
