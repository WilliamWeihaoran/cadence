import Foundation
import Testing
@testable import Cadence

/// **T-844.** Four count strings were wrong at exactly one: "1 selected tasks"
/// (`FocusLogSessionPopovers`), "1 tasks" (`FocusSidebarSupportViews`), "Collapsed, 1 notes"
/// (`CadenceNotesListSupport`), and "1 milestones" / "1 habits" (`iOSFeatureViews`). One shared
/// `CadencePluralization.phrase` now backs all four, plus the two pre-existing private `line`
/// helpers on `CadenceListDeletionSummary` and `CadenceNoteActionSupport` that already computed
/// the same thing by hand.
struct CadencePluralizationTests {
    /// The primitive itself, at the three counts that discriminate singular from plural: zero,
    /// one, and two.
    @Test func phraseIsSingularAtExactlyOne() throws {
        #expect(CadencePluralization.phrase(0, singular: "task", plural: "tasks") == "0 tasks")
        #expect(CadencePluralization.phrase(1, singular: "task", plural: "tasks") == "1 task")
        #expect(CadencePluralization.phrase(2, singular: "task", plural: "tasks") == "2 tasks")

        // A singular/plural pair that is not a bare "+s", so the test cannot pass by the helper
        // silently appending a letter rather than reading the arguments it was given.
        #expect(CadencePluralization.phrase(0, singular: "milestone", plural: "milestones") == "0 milestones")
        #expect(CadencePluralization.phrase(1, singular: "milestone", plural: "milestones") == "1 milestone")
        #expect(CadencePluralization.phrase(2, singular: "milestone", plural: "milestones") == "2 milestones")
    }

    /// The four call sites T-844 named, each read as text: the ungrammatical literal is gone and
    /// the shared helper is what supplies the count and noun now.
    @Test func theFourNamedSitesReadTheSharedHelper() throws {
        let cases: [(path: String, needle: String, retiredLiteral: String)] = [
            (
                "Cadence/macOS/Views/FocusLogSessionPopovers.swift",
                #"CadencePluralization\.phrase\(selectedTasks\.count, singular: "selected task", plural: "selected tasks"\)"#,
                #""\#(1) selected tasks""#
            ),
            (
                "Cadence/macOS/Views/FocusSidebarSupportViews.swift",
                #"CadencePluralization\.phrase\(bundle\.sortedTasks\.count, singular: "task", plural: "tasks"\)"#,
                #""\#(1) tasks""#
            ),
            (
                "Cadence/Shared/CadenceNotesListSupport.swift",
                #"CadencePluralization\.phrase\(noteCount, singular: "note", plural: "notes"\)"#,
                "Collapsed, \\(noteCount) notes\""
            ),
            (
                "Cadence/iOS/iOSFeatureViews.swift",
                #"CadencePluralization\.phrase\(summary\.activeGoalCount, singular: "milestone", plural: "milestones"\)"#,
                "\\(summary.activeGoalCount) milestones /"
            ),
        ]

        for testCase in cases {
            let source = try CadenceCommitSurfaceScan.scanned(testCase.path)
            #expect(
                CadenceSourceScan.matchCount(testCase.needle, in: source) == 1,
                "\(testCase.path) does not read the shared pluralisation helper the way T-844 expects"
            )
            #expect(
                !source.contains(testCase.retiredLiteral),
                "\(testCase.path) still types the retired ungrammatical literal"
            )
        }

        // The iOS habits half of the same call, pinned separately: one function returns both
        // halves, and a fix that repaired only milestones would still read green above.
        let goalViews = try CadenceCommitSurfaceScan.scanned("Cadence/iOS/iOSFeatureViews.swift")
        #expect(
            CadenceSourceScan.matchCount(
                #"CadencePluralization\.phrase\(summary\.activeHabitCount, singular: "habit", plural: "habits"\)"#,
                in: goalViews
            ) == 1
        )
    }

    /// The two pre-existing near-copies of this exact function now call through rather than keep
    /// their own ternary — the duplication T-844's doc comment names, closed rather than left for
    /// a fifth site to repeat.
    @Test func theTwoPriorPrivateCopiesNowDelegate() throws {
        for path in [
            "Cadence/Shared/CadenceListDeletionSummary.swift",
            "Cadence/Shared/CadenceNoteActionSupport.swift",
        ] {
            let source = try CadenceCommitSurfaceScan.scanned(path)
            #expect(
                CadenceSourceScan.matchCount(
                    #"CadencePluralization\.phrase\(count, singular: singular, plural: plural\)"#,
                    in: source
                ) == 1,
                "\(path)'s private line(_:_:_:) no longer delegates to the shared helper"
            )
            #expect(
                CadenceSourceScan.matchCount(#"count == 1 \? singular : plural"#, in: source) == 0,
                "\(path) still hand-rolls the ternary the shared helper exists to replace"
            )
        }
    }
}
