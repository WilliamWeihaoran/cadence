import Foundation
import Testing
@testable import Cadence

/// **[[T-12292]] — an editable tag strip folds to the width it is offered; it never widens its host.**
///
/// On a portrait iPad (834pt) a note with three tags made the Notes header wider than the window:
/// `iOSNoteTagControl` was `.fixedSize()` with a fixed limit of two chips, so it reported one width
/// whatever it was offered, and the header's fixed-size row reported its ideal width to a `VStack`
/// that centred the whole two-column shell on it. The fold decision is
/// `CadenceTagStripCollapse.candidateLimits`, asserted directly; the iOS views that draw from it
/// are `#if os(iOS)`, so those halves are source scans over `codeOnly`.
struct CadenceTagStripCollapseTests {

    // MARK: - The rule

    @Test func theCandidatesRunFromTheCapDownToTheBadgeAloneOneChipAtATime() {
        #expect(CadenceTagStripCollapse.candidateLimits(tagCount: 3) == [3, 2, 1, 0])
        #expect(CadenceTagStripCollapse.candidateLimits(tagCount: 7) == [3, 2, 1, 0],
                "more tags than the cap: the widest row is still the cap")
        #expect(CadenceTagStripCollapse.candidateLimits(tagCount: 2) == [2, 1, 0],
                "fewer tags than the cap: no candidate repeats a row")
        #expect(CadenceTagStripCollapse.candidateLimits(tagCount: 1) == [1, 0])
        #expect(CadenceTagStripCollapse.candidateLimits(tagCount: 0) == [0])
        #expect(CadenceTagStripCollapse.candidateLimits(tagCount: 5, cap: 1) == [1, 0])
    }

    /// A relation over every small input rather than a table: the last candidate is the badge alone
    /// (a narrow host always has a row it can take), the first never exceeds the tags or the cap,
    /// and the list is strictly descending (`ViewThatFits` draws the WIDEST row that fits only if
    /// it is tried first, and a repeated count is a candidate measured twice).
    @Test func everyCandidateListEndsAtTheBadgeAndDescendsStrictly() {
        for cap in 0...4 {
            for count in 0...6 {
                let limits = CadenceTagStripCollapse.candidateLimits(tagCount: count, cap: cap)
                #expect(limits.last == 0, "cap \(cap), \(count) tags: no badge-only row")
                #expect(limits.first == min(cap, count), "cap \(cap), \(count) tags")
                #expect(zip(limits, limits.dropFirst()).allSatisfy { $0 == $1 + 1 },
                        "cap \(cap), \(count) tags: \(limits)")
            }
        }
        #expect(CadenceTagStripCollapse.candidateLimits(tagCount: -1) == [0])
    }

    /// One cap for both platforms: the question is width, and width is what `ViewThatFits` measures.
    @Test func theEditableCapIsThree() {
        #expect(CadenceTagStripCollapse.editableStripCap == 3)
    }

    // MARK: - Both platforms draw from it

    @Test func theIOSNoteTagControlFoldsThroughTheSharedRuleAndIsNotHorizontallyFixed() throws {
        let control = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSNoteTagControl.swift")
        )
        let controlBody = try #require(
            CadenceSourceScan.declarationBody("struct iOSNoteTagControl: View", in: control)
        )
        #expect(
            CadenceSourceScan.matchCount(
                #"ViewThatFits\(in: \.horizontal\) \{\s*ForEach\(CadenceTagStripCollapse\.candidateLimits\(tagCount: tags\.count\), id: \\\.self\)"#,
                in: controlBody
            ) == 1,
            "the chips no longer fold through the shared rule"
        )
        #expect(CadenceSourceScan.matchCount(#"chipLimit"#, in: controlBody) == 0,
                "a fixed per-placement limit is back")
        let body = try #require(CadenceSourceScan.declarationBody("var body: some View", in: controlBody))
        #expect(CadenceSourceScan.matchCount(#"\.fixedSize\(horizontal: false, vertical: true\)"#, in: body) == 1)
        #expect(CadenceSourceScan.matchCount(#"\.fixedSize\(\)"#, in: body) == 0,
                "the control is fixed horizontally again, so it cannot fold to its host's width")
    }

    @Test func theMacSelectedTagStripFoldsThroughTheSameRule() throws {
        let mac = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TagPickerSupportViews.swift")
        )
        let strip = try #require(
            CadenceSourceScan.declarationBody("private struct AdaptiveSelectedTagStrip: View", in: mac)
        )
        #expect(
            CadenceSourceScan.matchCount(
                #"ForEach\(CadenceTagStripCollapse\.candidateLimits\(tagCount: tags\.count\), id: \\\.self\)"#,
                in: strip
            ) == 1
        )
        #expect(CadenceSourceScan.matchCount(#"selectedTagRow\(limit: (min|0)"#, in: strip) == 0,
                "a hand-listed set of limits is back beside the shared rule")
    }

    /// The header takes the width it is offered: `minWidth: 0` is what makes the frame a clamp —
    /// with `maxWidth` alone a flexible frame reports a wider child's width, which is the overflow
    /// that moved the page. And the chips sit at the title's priority, above the `Spacer`.
    @Test func theIOSNotesHeaderClampsToItsContainerAndGivesTheChipsTheSlack() throws {
        let notes = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSNotesView.swift"))
        let header = try #require(
            CadenceSourceScan.declarationBody(
                "private struct iOSNotesHeader<Title: View, Trailing: View>: View", in: notes
            )
        )
        let body = try #require(CadenceSourceScan.declarationBody("var body: some View", in: header))
        #expect(
            CadenceSourceScan.matchCount(
                #"trailing\(\)\s*\}(\s*\.padding\([^\n]*\))+\s*\.frame\(minWidth: 0, maxWidth: \.infinity, alignment: \.leading\)"#,
                in: body
            ) == 1,
            "the header row can report more width than it was offered again"
        )
        #expect(
            CadenceSourceScan.matchCount(
                #"iOSNoteTagControl\(note: note, isEditorFocused: \$isEditorFocused\) \{ tagFailureNotice = \$0 \}\s*\.layoutPriority\(1\)"#,
                in: notes
            ) == 1,
            "the header's spacer splits the slack with the chips again"
        )
    }
}
