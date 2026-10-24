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

    /// The call sites T-844 named, each read as text: the ungrammatical literal is gone and the
    /// shared helper is what supplies the count and noun now. It named four; [[T-3170]] deleted
    /// two of them — `BundleLogSessionPopover`'s "N selected tasks" and `FocusBundleSidebar`'s
    /// "N tasks" — with Block Focus.
    @Test func thenamedSitesReadTheSharedHelper() throws {
        let cases: [(path: String, needle: String, retiredLiteral: String)] = [
            (
                "Cadence/Shared/CadenceNotesListSupport.swift",
                #"CadencePluralization\.phrase\(noteCount, singular: "note", plural: "notes"\)"#,
                "Collapsed, \\(noteCount) notes\""
            ),
            // **The two `iOSFeatureViews.swift` entries left with [[T-5002]]**, which deleted the
            // file: T-844's "1 milestones" and "1 habits" were `iOSGoalDetail`'s summary line, and
            // the page that drew it is gone. The helper they were converged onto is exercised by
            // value at the top of this suite and by its three surviving call sites below.
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

        // Non-vacuity: the scan really reads source rather than returning an empty string for a
        // path that is no longer there — the failure mode [[T-5002]]'s deletions make reachable.
        #expect(
            try CadenceCommitSurfaceScan.scanned("Cadence/Shared/CadenceNotesListSupport.swift").count > 500
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

    /// **T-4980.** Six more count strings were wrong at one, each now spelled by a formatter this
    /// suite can call: the large Today widget's footer ("1 tasks in view"), iOS's "+N more"
    /// subtask button for VoiceOver ("Show 1 more subtasks"), the iOS Markdown task embed's header
    /// ("0/1 subtasks"), the macOS goal card's list chip ("1 lists"), the capture card's
    /// after-count stepper ("1 occurrences"), and the macOS goal header's filtered count
    /// ("0 of 1 milestones"). Zero, one and two for each, so dropping a singular branch goes red.
    @Test func theT4980FormattersAgreeWithTheirCount() throws {
        func widget(_ total: Int) -> String {
            CadenceTodayWidgetSnapshot(
                date: Date(), dateKey: "2026-10-22", state: .ready, statusMessage: nil,
                totalCount: total, overdueCount: 0, dueTodayCount: 0, scheduledTodayCount: 0, tasks: []
            ).tasksInViewLabel
        }
        #expect(widget(0) == "0 tasks in view")
        #expect(widget(1) == "1 task in view")
        #expect(widget(2) == "2 tasks in view")

        #expect(CadenceTaskPresentationSupport.moreSubtasksAccessibilityLabel(hidden: 1) == "Show 1 more subtask")
        #expect(CadenceTaskPresentationSupport.moreSubtasksAccessibilityLabel(hidden: 2) == "Show 2 more subtasks")

        #expect(CadenceSubtaskProgress(completed: 0, total: 1).label == "0/1 subtask")
        #expect(CadenceSubtaskProgress(completed: 1, total: 1).label == "1/1 subtask")
        #expect(CadenceSubtaskProgress(completed: 1, total: 2).label == "1/2 subtasks")

        #expect(GoalLinkPresentation.linkedListCountLabel(0) == "0 lists")
        #expect(GoalLinkPresentation.linkedListCountLabel(1) == "1 list")
        #expect(GoalLinkPresentation.linkedListCountLabel(2) == "2 lists")

        // The stepper floor is 1, and a stored 0 is clamped to it rather than shown.
        #expect(CadenceTaskRecurrenceEndPresentation.endCountStepperLabel(0) == "1 occurrence")
        #expect(CadenceTaskRecurrenceEndPresentation.endCountStepperLabel(1) == "1 occurrence")
        #expect(CadenceTaskRecurrenceEndPresentation.endCountStepperLabel(2) == "2 occurrences")

        // **T-4980's GoalMissionGroup.milestoneCountLabel block left with [[T-5002]]**, which
        // deleted `GoalsSupportViews.swift` and the group struct in it. T-5200's `#if os(macOS)`
        // fence around it went too: the fence existed only because the subject was macOS-only.
        // The "N of M" shape it measured is `CadencePluralization.phrase`, asserted by value above.
    }

    /// The call sites the T-4980 formatters replaced read them, and the retired literals are gone.
    @Test func theT4980SitesReadTheirFormatters() throws {
        let cases: [(path: String, needle: String, retired: String)] = [
            ("CadenceWidgets/TodayTasksWidgetView.swift", "Text(entry.snapshot.tasksInViewLabel)", "totalCount) tasks in view\")"),
            ("Cadence/iOS/iOSTaskViews.swift", "CadenceTaskPresentationSupport.moreSubtasksAccessibilityLabel(hidden: hidden)", "more subtasks\")"),
            ("Cadence/iOS/iOSMarkdownPreview.swift", "CadenceSubtaskProgress(completed: task.completedSubtaskCount, total: task.subtaskTotalCount).label", "subtaskTotalCount) subtasks\")"),
            // The two `GoalLinkPresentation.linkedListCountLabel` readers — macOS's
            // `GoalsSupportViews.swift` and iOS's `iOSFeatureDetailViews.swift` — left with
            // [[T-5002]]. The formatter itself still has readers and is asserted by value above.
            ("Cadence/Shared/Components/CadenceScheduleCaptureCard.swift", "CadenceTaskRecurrenceEndPresentation.endCountStepperLabel(draft.seriesEndCount)", "seriesEndCount)) occurrences\""),
        ]
        for testCase in cases {
            let source = try CadenceCommitSurfaceScan.scanned(testCase.path)
            #expect(source.contains(testCase.needle), "\(testCase.path) does not read its T-4980 formatter")
            #expect(!source.contains(testCase.retired), "\(testCase.path) still types the retired literal")
        }
    }
}
