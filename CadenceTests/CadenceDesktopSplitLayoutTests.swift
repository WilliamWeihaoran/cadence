import CoreGraphics
import Foundation
import Testing
@testable import Cadence

/// T-250: Today, Goals and Focus each declared more `HSplitView` minimum width than `CadenceApp`'s
/// 960pt window floor can pay, and an `HSplitView` reports none of it upward — so the window let
/// you reach a width at which `NSSplitView` laid out at the sum of its minimums and overflowed
/// **leading-aligned**, off the trailing edge.
///
/// Measured with `NSHostingView` probes reproducing each modifier chain verbatim, at the 960pt
/// floor with the sidebar at 220 / 264 (stored default) / 390 — 740 / 696 / 570 of pane:
///
///   - Today, `449 + 300 + 343` + 2 dividers: `449, 290, 0` — `449, 246, 0` — `449, 120, 0`.
///   - Goals, `560 + 340` + 1: the inspector was handed 340 and 179 / 135 / **9** of it was on
///     screen.
///   - Focus, `520 + 320` + 1: 219 / 175 / **49** of 320.
///
/// The tests below are about the arithmetic and about the call sites reading it, not about the
/// probe: what a unit test can hold is that the panes a width chooses always fit in it, and that
/// the three views ask before they draw.
struct CadenceDesktopSplitLayoutTests {

    // MARK: - The reachable widths

    /// The macOS pane is the window less the sidebar, and the sidebar is 220–390 with a stored
    /// default of 264 (`macOSRootShellViews.swift`) or hidden outright with `Cmd+O`.
    private static func panes(window: CGFloat) -> [(label: String, width: CGFloat)] {
        [
            ("sidebar 220", window - 220),
            ("sidebar 264 (stored)", window - 264),
            ("sidebar 390", window - 390),
            ("sidebar hidden", window),
        ]
    }

    /// The app's own floor, `CadenceApp.swift`'s `.frame(minWidth: 960)`.
    private static let windowFloor: CGFloat = 960
    /// The primary target, a MacBook Pro 14".
    private static let targetDisplayWidth: CGFloat = 1512

    // MARK: - The floors are the panes' own minimums, summed

    @Test
    func todaysFloorsAreTheSumOfItsThreePanesAndTheirDividers() {
        #expect(CadenceDesktopSplitLayout.todayThreePaneMinimumWidth == 1094)
        #expect(CadenceDesktopSplitLayout.todayTwoPaneMinimumWidth == 644)
        #expect(CadenceDesktopSplitLayout.todayLayout(paneWidth: 1094) == .notesTasksAndSchedule)
        #expect(CadenceDesktopSplitLayout.todayLayout(paneWidth: 1093) == .tasksAndSchedule)
        #expect(CadenceDesktopSplitLayout.todayLayout(paneWidth: 644) == .tasksAndSchedule)
        #expect(CadenceDesktopSplitLayout.todayLayout(paneWidth: 643) == .tasksOnly)
    }

    @Test
    func goalsAndFocusEachSplitAtTheSumOfTheirTwoPanes() {
        #expect(CadenceDesktopSplitLayout.goalsSplitMinimumWidth == 901)
        #expect(CadenceDesktopSplitLayout.goalsShowsInspector(paneWidth: 901))
        #expect(!CadenceDesktopSplitLayout.goalsShowsInspector(paneWidth: 900))

        #expect(CadenceDesktopSplitLayout.focusSplitMinimumWidth == 841)
        #expect(CadenceDesktopSplitLayout.focusShowsSidebar(paneWidth: 841))
        #expect(!CadenceDesktopSplitLayout.focusShowsSidebar(paneWidth: 840))
    }

    /// The iPad's task column is 440 and this one is 300, and they are not the same number by
    /// accident of drift: `CadenceTodayLayoutSupport.taskPaneMinWidth` is one of *two* panes with
    /// the day's whole task list in it, and this one is the middle of three. Pinned so a future
    /// "these should agree" pass has to argue with something.
    @Test
    func macOSTodaysTaskColumnIsNotTheIPadsAndDoesNotClaimToBe() {
        #expect(CadenceDesktopSplitLayout.todayTaskPaneMinWidth == 300)
        #expect(CadenceTodayLayoutSupport.taskPaneMinWidth == 440)
    }

    // MARK: - Whatever it draws, it fits

    /// The property the bug violated: if a page draws more than one pane, their declared minimums
    /// and the dividers between them must fit in the width that chose them. Swept rather than
    /// sampled, because the defect was invisible at the two widths anyone looked at.
    @Test
    func noWidthEverChoosesMorePanesThanItCanPayFor() {
        let divider = CadenceDesktopSplitLayout.paneDividerWidth
        var paneWidth: CGFloat = 200
        while paneWidth <= 2200 {
            switch CadenceDesktopSplitLayout.todayLayout(paneWidth: paneWidth) {
            case .notesTasksAndSchedule:
                let sum = CadenceDesktopSplitLayout.todayNotesPaneMinWidth
                    + CadenceDesktopSplitLayout.todayTaskPaneMinWidth
                    + CadenceDesktopSplitLayout.todaySchedulePaneMinWidth + divider * 2
                #expect(sum <= paneWidth, "Today drew three panes needing \(sum) in \(paneWidth)")
            case .tasksAndSchedule:
                let sum = CadenceDesktopSplitLayout.todayTaskPaneMinWidth
                    + CadenceDesktopSplitLayout.todaySchedulePaneMinWidth + divider
                #expect(sum <= paneWidth, "Today drew two panes needing \(sum) in \(paneWidth)")
            case .tasksOnly:
                break
            }

            if CadenceDesktopSplitLayout.goalsShowsInspector(paneWidth: paneWidth) {
                let sum = CadenceDesktopSplitLayout.goalListPaneMinWidth
                    + CadenceDesktopSplitLayout.goalInspectorPaneMinWidth + divider
                #expect(sum <= paneWidth, "Goals drew an inspector needing \(sum) in \(paneWidth)")
            }

            if CadenceDesktopSplitLayout.focusShowsSidebar(paneWidth: paneWidth) {
                let sum = CadenceDesktopSplitLayout.focusSessionPaneMinWidth
                    + CadenceDesktopSplitLayout.focusSidebarPaneMinWidth + divider
                #expect(sum <= paneWidth, "Focus drew a sidebar needing \(sum) in \(paneWidth)")
            }

            paneWidth += 1
        }
    }

    /// The three configurations the ticket measured. Every one of them used to draw a pane that was
    /// wholly or mostly off the right edge; none of them draws a pane it cannot pay for now.
    @Test
    func theAppsOwnMinimumWindowNoLongerOverflowsAnyOfTheThreePages() {
        for (label, paneWidth) in Self.panes(window: Self.windowFloor) where paneWidth < 960 {
            #expect(
                CadenceDesktopSplitLayout.todayLayout(paneWidth: paneWidth) != .notesTasksAndSchedule,
                "Today still draws three panes at the floor with \(label)"
            )
            #expect(
                !CadenceDesktopSplitLayout.goalsShowsInspector(paneWidth: paneWidth),
                "Goals still draws its inspector at the floor with \(label)"
            )
            #expect(
                !CadenceDesktopSplitLayout.focusShowsSidebar(paneWidth: paneWidth),
                "Focus still draws its sidebar at the floor with \(label)"
            )
        }
    }

    /// Dropping the notepad rather than the timeline is a measurement, not a preference: at the
    /// ordinary minimum pane — the 960 floor less the stored 264pt sidebar — `tasks + schedule`
    /// fits and `notes + tasks` does not. Had the other pair been chosen, Today would fold straight
    /// to one column at the width most likely to be reached.
    @Test
    func todayKeepsThePairThatFitsTheOrdinaryMinimumPane() {
        let ordinaryPane = Self.windowFloor - 264
        #expect(ordinaryPane == 696)
        #expect(CadenceDesktopSplitLayout.todayLayout(paneWidth: ordinaryPane) == .tasksAndSchedule)

        let notesAndTasks = CadenceDesktopSplitLayout.todayNotesPaneMinWidth
            + CadenceDesktopSplitLayout.todayTaskPaneMinWidth
            + CadenceDesktopSplitLayout.paneDividerWidth
        #expect(notesAndTasks == 750)
        #expect(notesAndTasks > ordinaryPane)
    }

    /// And the machine the app is actually used on is untouched: at 1512 every sidebar width, and
    /// the hidden sidebar, still draws every pane of all three pages.
    @Test
    func theTargetDisplayStillDrawsEveryPaneOfEveryPage() {
        for (label, paneWidth) in Self.panes(window: Self.targetDisplayWidth) {
            #expect(
                CadenceDesktopSplitLayout.todayLayout(paneWidth: paneWidth) == .notesTasksAndSchedule,
                "Today lost a pane at 1512 with \(label)"
            )
            #expect(CadenceDesktopSplitLayout.goalsShowsInspector(paneWidth: paneWidth), "\(label)")
            #expect(CadenceDesktopSplitLayout.focusShowsSidebar(paneWidth: paneWidth), "\(label)")
        }
    }

    /// Unmeasured answers with the fewest panes, for `CadenceSettingsTemplatesCardLayout`'s reason.
    @Test
    func anUnmeasuredWidthDrawsTheFallbackRatherThanTheSplit() {
        #expect(CadenceDesktopSplitLayout.todayLayout(paneWidth: 0) == .tasksOnly)
        #expect(!CadenceDesktopSplitLayout.goalsShowsInspector(paneWidth: 0))
        #expect(!CadenceDesktopSplitLayout.focusShowsSidebar(paneWidth: 0))
    }

    // MARK: - The call sites read the floors rather than re-typing them

    /// Every pane minimum the three views declare comes from `CadenceDesktopSplitLayout`. A view
    /// that types `449` again satisfies every assertion above on the day it is written and stops
    /// following the floor the next day — the failure
    /// `everyRegisteredFloorIsStillSpelledAsASumRatherThanTyped` catches one level up, applied here
    /// to the frames the sums are made of.
    @Test
    func theThreePagesDeclareTheirPaneMinimumsByReference() throws {
        let expectations: [(path: String, typed: [String], referenced: [String: Int])] = [
            ("Cadence/macOS/Views/TodayView.swift",
             ["minWidth: 449", "minWidth: 300", "minWidth: 343"],
             ["CadenceDesktopSplitLayout.todayNotesPaneMinWidth": 1,
              "CadenceDesktopSplitLayout.todayTaskPaneMinWidth": 1,
              "CadenceDesktopSplitLayout.todaySchedulePaneMinWidth": 1]),
            ("Cadence/macOS/Views/GoalsView.swift",
             ["minWidth: 560", "minWidth: 340"],
             ["CadenceDesktopSplitLayout.goalListPaneMinWidth": 1,
              "CadenceDesktopSplitLayout.goalInspectorPaneMinWidth": 2]),
            ("Cadence/macOS/Views/FocusView.swift",
             ["minWidth: 520", "minWidth: 320"],
             ["CadenceDesktopSplitLayout.focusSessionPaneMinWidth": 3,
              "CadenceDesktopSplitLayout.focusSidebarPaneMinWidth": 3]),
        ]

        for (path, typed, referenced) in expectations {
            let code = try desktopSplitStrippingComments(desktopSplitSource(path))
            for literal in typed {
                #expect(
                    desktopSplitOccurrences(of: literal, in: code) == 0,
                    "\(path) types `\(literal)` instead of reading the floor it has to agree with"
                )
            }
            for (reference, count) in referenced {
                #expect(
                    desktopSplitOccurrences(of: reference, in: code) == count,
                    "\(path) reads \(reference) \(desktopSplitOccurrences(of: reference, in: code)) times, expected \(count)"
                )
            }
        }
    }

    /// And each page asks before it draws. Focus is three splits — the active task layout, the
    /// active bundle layout and the idle picker — and all three carried the same pair of minimums,
    /// so a fix that reached only the first would leave two thirds of the page broken.
    @Test
    func eachSplitIsGatedOnTheWidthItWasHanded() throws {
        let gates: [(path: String, call: String, count: Int)] = [
            ("Cadence/macOS/Views/TodayView.swift",
             "CadenceDesktopSplitLayout.todayLayout(paneWidth:", 1),
            ("Cadence/macOS/Views/GoalsView.swift",
             "CadenceDesktopSplitLayout.goalsShowsInspector(", 1),
            ("Cadence/macOS/Views/FocusView.swift",
             "CadenceDesktopSplitLayout.focusShowsSidebar(paneWidth:", 3),
        ]

        for (path, call, count) in gates {
            let code = try desktopSplitStrippingComments(desktopSplitSource(path))
            #expect(
                desktopSplitOccurrences(of: call, in: code) == count,
                "\(path) calls \(call) \(desktopSplitOccurrences(of: call, in: code)) times, expected \(count)"
            )
            #expect(desktopSplitOccurrences(of: "GeometryReader", in: code) >= 1, "\(path)")
        }
    }

    /// The iPad half of the same decision (T-252): `iOSFeatureSplitLayout` is the one place all
    /// four regular-width split surfaces go through, so the gate belongs there rather than four
    /// times over — and the fallback is each surface's own one column, not a dropped chooser.
    @Test
    func theIPadSplitAsksTheSameQuestionInOnePlace() throws {
        let host = "Cadence/iOS/iOSFeatureComponents.swift"
        let code = try desktopSplitStrippingComments(desktopSplitSource(host))
        #expect(desktopSplitOccurrences(of: "CadenceRegularSplitLayout.supportsTwoPanes(", in: code) == 1)
        #expect(desktopSplitOccurrences(of: "narrow()", in: code) == 1)

        for path in [
            "Cadence/iOS/iOSFeatureViews.swift",
            "Cadence/iOS/iOSFocusView.swift",
            "Cadence/iOS/iOSListViews.swift",
        ] {
            let surface = try desktopSplitStrippingComments(desktopSplitSource(path))
            #expect(
                desktopSplitOccurrences(of: "CadenceRegularSplitLayout.supportsTwoPanes(", in: surface) == 0,
                "\(path) asks the gate itself instead of going through iOSFeatureSplitLayout"
            )
            #expect(
                desktopSplitOccurrences(of: "narrow:", in: surface) >= 1,
                "\(path) uses the split layout without supplying a one-column fallback"
            )
        }
    }

    // MARK: - Non-vacuity

    /// Every source assertion above is a count over a file read from disk, and a read that silently
    /// returns nothing makes the zero-expectations pass. Same guard, and same reason, as
    /// `CadencePaneWidthRuleHomesTests.theSourceScanActuallyReachesTheFilesItIsCounting`.
    @Test
    func theSourceScanActuallyReadsTheViewsItIsCounting() throws {
        for path in [
            "Cadence/macOS/Views/TodayView.swift",
            "Cadence/macOS/Views/GoalsView.swift",
            "Cadence/macOS/Views/FocusView.swift",
            "Cadence/iOS/iOSFeatureComponents.swift",
            "Cadence/iOS/iOSFeatureViews.swift",
            "Cadence/iOS/iOSFocusView.swift",
            "Cadence/iOS/iOSListViews.swift",
        ] {
            let code = try desktopSplitStrippingComments(desktopSplitSource(path))
            #expect(code.count > 400, "\(path) read as \(code.count) characters")
            #expect(desktopSplitOccurrences(of: "struct", in: code) >= 1, "\(path)")
        }
    }

    /// Proof the stripper runs, from a case in the tree rather than a synthetic one: the doc
    /// comment on `CadenceDesktopSplitLayout` names the arithmetic it no longer types, so raw
    /// source sees the literal and stripped source does not.
    @Test
    func theCommentStrippingIsActuallyStripping() throws {
        let path = "Cadence/Shared/CadenceRegularPaneLayout.swift"
        let raw = try desktopSplitSource(path)
        let stripped = try desktopSplitStrippingComments(raw)
        #expect(desktopSplitOccurrences(of: "1094", in: raw) >= 1)
        #expect(desktopSplitOccurrences(of: "1094", in: stripped) == 0)
    }
}

// MARK: - Source-reading helpers

/// Prefixed rather than shared, matching `CadencePaneWidthRuleHomesTests` and the three suites it
/// copies from: each file keeps its own `private` set.
private func desktopSplitRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func desktopSplitSource(_ relativePath: String) throws -> String {
    try String(
        contentsOf: desktopSplitRepositoryRoot().appendingPathComponent(relativePath),
        encoding: .utf8
    )
}

private func desktopSplitStrippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(
                range,
                with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound))
            )
        }
    }
    return result
}

private func desktopSplitOccurrences(of needle: String, in haystack: String) -> Int {
    haystack.components(separatedBy: needle).count - 1
}
