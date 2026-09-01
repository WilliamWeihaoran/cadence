import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// Today, unified across macOS, iPad and iPhone.
///
/// **Two kinds of test here, and the second kind is the point.** Pinning
/// `CadenceTaskPresentationSupport.rowTagLimit == 3` proves the shared figure is right; it proves
/// nothing about anybody *using* it. T-161 is the standing example — a committed fix was reverted
/// with all tests green, because the tests pinned a helper while nothing observed the call sites.
/// So every decision below also gets a call-site test that reads the real source and fails the
/// moment a platform goes back to its own copy.
///
/// Source-text assertions are the only tool available for the iOS half: `Cadence/iOS/` is entirely
/// inside `#if os(iOS)` and this target builds for macOS, so there is no iOS symbol to reference.
/// The precedent is `NoteEditorPerformanceRegressionTests` and `CadenceSharedBoardChromeTests`.
struct CadenceTodayUnificationTests {

    // MARK: - Sections: Overdue, then the day's lists

    /// **"Planned Today" is gone from the product, not merely unselected** (T-305). On the Today
    /// page "today" is the page, so a heading restating it carried no information — the standing
    /// page-header rule, one level down. The four-bucket enum survives only as the vocabulary a
    /// dropped `+` speaks, and it carries no titles for anything to draw.
    @Test func todayNoLongerHeadsAGroupWithTheNameOfThePage() throws {
        #expect(CadenceTodayTaskGroupKind.allCases.count == 4)
        // "Due Today" is deliberately **not** in this list: it is still a live heading on the
        // Calendar board's date grouping and on the habits list, where it names a date on a page
        // that is not scoped to one. It was only ever wrong on Today.
        #expect(try liveTextOccurrences(of: "Planned Today") == 0)
        #expect(try liveTextOccurrences(of: "Past Do") == 0)
        // The self-check the two above need: a scan that finds nothing passes every absence
        // assertion ever written. "Overdue" is a string this app definitely still ships.
        #expect(try liveTextOccurrences(of: "Overdue") > 0)
        // The one date-shaped heading that stays, and stays at the top.
        #expect(CadenceTodayPresentationSupport.overdueSectionTitle == "Overdue")
    }

    /// **The T-161 test for the sections.** Both platforms' Today must derive its groups from the
    /// one shared function. Revert either to a local list of the same predicates — which is exactly
    /// what macOS's `todayDateSections` was — and this fails; pinning `todayGroups` itself would
    /// not have noticed.
    ///
    /// macOS called it **twice**: once for the sections it draws, and once for
    /// `currentFrozenFlatSectionSnapshot`, which had to describe the same sections. That second
    /// function carried a doc comment reading "Currently unreferenced" — it was kept as the
    /// counterpart to `currentFrozenListGroupSnapshot`, and that counterpart was `.byDoDate`'s.
    /// Both went in T-487, so the "two call sites that must agree" were a live one and a dead one,
    /// and the count is 1. The count stays **exact** rather than "contains": that is what would
    /// catch a second, local list of the same predicates growing back beside the shared call.
    @Test func everyTodaySurfaceGroupsThroughTheSharedQuery() throws {
        try expectCallSites(
            of: "CadenceTaskQuerySupport.todayGroups",
            at: [
                "Cadence/macOS/Views/TasksPanel.swift": 1,
                "Cadence/iOS/iOSTodayView.swift": 1,
            ]
        )
        // And both hand it the contexts the sidebar order is derived from. A host that passed `[]`
        // would fall back to alphabetical list groups on one platform while the other used sidebar
        // order — the same day, two orders. macOS's needle is the two-argument tail because
        // `contexts: contexts` alone is seven other section views on that file.
        try expectCallSites(
            of: "todayKey: todayKey, contexts: contexts",
            at: ["Cadence/macOS/Views/TasksPanel.swift": 1]
        )
        try expectCallSites(
            of: "contexts: contexts",
            at: ["Cadence/iOS/iOSTodayView.swift": 1]
        )
    }

    /// The accents go with the names: a group that says "Overdue" in `Theme.red` on one platform
    /// and in neutral `Theme.dim` on another is two different statements. The tint travels **on the
    /// group** now — a list group is its list's colour — so what has to be pinned is that neither
    /// host decides the tint for itself.
    @Test func bothPlatformsTintTheirTodayGroupsFromTheGroupItself() throws {
        try expectCallSites(
            of: "group.accent",
            at: [
                "Cadence/macOS/Views/TasksPanel.swift": 1,
                "Cadence/iOS/iOSTodayTaskSections.swift": 1,
            ]
        )
        // Overdue's red is decided once, where the group is built.
        try expectCallSites(
            of: "CadenceTodayPresentationSupport.overdueSectionAccent",
            at: ["Cadence/Shared/CadenceTaskQuerySupport.swift": 1]
        )
    }

    /// And a row under a header that already prints its list's name does not repeat it in a chip.
    /// Both hosts `&&` the surface's answer with the group's own.
    @Test func neitherHostRepeatsTheListNameOnEveryRowOfAListGroup() throws {
        try expectCallSites(
            of: "group.showsContainerChip",
            at: [
                "Cadence/macOS/Views/TasksPanel.swift": 1,
                "Cadence/iOS/iOSTodayTaskSections.swift": 1,
            ]
        )
    }

    /// macOS's Today by-list grouping is gone, not merely unselected. The section builder and the
    /// second spelling of the four buckets both have to be absent — a `todayDateSections` left in
    /// place behind a picker nobody can reach is the same fork with a longer fuse.
    @Test func theRetiredMacOSTodayGroupingsAreGone() throws {
        try expectNoLiveMention(of: "todayListSections")
        try expectNoLiveMention(of: "todayDateSections")
        try expectNoLiveMention(of: "todayControlledSections")
    }

    /// The day's finished work is headed and tinted the same on every Today. macOS said
    /// "Completed" over a predicate that only ever held tasks completed *today*, which described a
    /// logbook it was not showing.
    @Test func bothPlatformsHeadTheirCompletedGroupWithTheSharedTitle() throws {
        #expect(CadenceTodayPresentationSupport.completedSectionTitle == "Completed Today")

        try expectCallSites(
            of: "CadenceTodayPresentationSupport.completedSectionTitle",
            at: [
                "Cadence/macOS/Views/TasksPanelSectionViews.swift": 1,
                "Cadence/iOS/iOSTodayTaskSections.swift": 1,
            ]
        )
        try expectCallSites(
            of: "CadenceTodayPresentationSupport.completedSectionAccent",
            at: [
                "Cadence/macOS/Views/TasksPanelSectionViews.swift": 1,
                "Cadence/iOS/iOSTodayTaskSections.swift": 1,
            ]
        )
    }

    /// And the empty day says one thing. macOS's "Due-today and do-today tasks will appear here"
    /// restated the page's scope where the shared subtitle names the next thing to do.
    @Test func bothPlatformsDrawTheSameEmptyToday() throws {
        try expectCallSites(
            of: "CadenceTodayPresentationSupport.emptyTitle",
            at: [
                "Cadence/macOS/Views/TasksPanel.swift": 1,
                "Cadence/iOS/iOSTodayCompactViews.swift": 1,
            ]
        )
        try expectCallSites(
            of: "CadenceTodayPresentationSupport.emptySubtitle",
            at: [
                "Cadence/macOS/Views/TasksPanel.swift": 1,
                "Cadence/iOS/iOSTodayCompactViews.swift": 1,
            ]
        )
    }

    // MARK: - The group heading

    /// 10 wins, and it is the app's one eyebrow size rather than a number chosen for this row. iOS
    /// drew its group count at 11pt above a 10pt eyebrow — the same exception `7e5459c` closed for
    /// the board column header, in a second place. A count is already demoted by weight and by the
    /// capsule around it and must not also be *bigger* than the label it counts.
    @Test func theGroupCountIsTheAppsOneEyebrowSize() {
        #expect(CadenceTaskGroupHeadingMetrics.countSize == 10)
        #expect(CadenceTaskGroupHeadingMetrics.countSize == SectionEyebrowLabel.fontSize)
        #expect(CadenceTaskGroupHeadingMetrics.countSize == CadencePageHeaderMetrics.metrics(role: .page, surface: .desktop).eyebrowSize)
    }

    /// One capsule fill for the whole app. iOS's group badge drew 0.11 and the page header 0.12 —
    /// the same drift `CadencePageHeaderMetrics.countFillOpacity` was written to settle, repeated
    /// one component along.
    @Test func theGroupCountReusesTheAppsOneCapsuleFill() {
        #expect(CadencePageHeaderMetrics.countFillOpacity == 0.12)
    }

    /// **This pin was T-161's and it is stale — the decision it encoded has been reversed (T-605).**
    ///
    /// It asserted that macOS Today and iOS Today both drew `CadenceTaskGroupHeading`, one call
    /// site each. That was the right answer to the question T-161 asked (*do the two Todays look
    /// the same?*) and the wrong answer to the question that turned out to matter more: **macOS
    /// Today was the only task surface on its own platform drawing that heading.** All Tasks, Inbox
    /// and list detail draw `TaskListGroupHeader` — 3×22pt accent bar, 14pt bold sentence case,
    /// split overdue/regular counts — so cross-platform agreement was being bought with a
    /// three-against-one split inside the desktop app. The user's decision moves Today, and the
    /// number below is not bumped: the call site is **gone**, and the assertion now says which
    /// header each platform draws rather than that they draw the same one.
    ///
    /// **The resulting divergence is deliberate. Do not re-file it as drift** — the reasoning is on
    /// `TasksPanelIntentSectionView` and on `CadenceTaskGroupHeading` itself, and this test is the
    /// third place it is written down so that a future convergence sweep meets an argument rather
    /// than a bare inconsistency.
    @Test func eachPlatformsTodayDrawsItsOwnPlatformsGroupHeading() throws {
        // iOS keeps the shared eyebrow, and is the only caller of it that this pins.
        try expectCallSites(
            of: "CadenceTaskGroupHeading",
            at: [
                "Cadence/macOS/Views/TasksPanelSectionViews.swift": 0,
                "Cadence/iOS/iOSTaskGroupSection.swift": 1,
            ]
        )

        // macOS Today draws the header its three siblings draw — twice: the intent groups and the
        // Completed group. Counted, so a change that converts one and leaves the other fails here
        // rather than shipping a page with two headings on it again.
        try expectCallSites(
            of: "TaskListGroupHeader(",
            at: [
                "Cadence/macOS/Views/TasksPanelSectionViews.swift": 2,
                "Cadence/macOS/Views/TasksListView.swift": 2,
                "Cadence/macOS/Views/InboxSupportViews.swift": 1,
            ]
        )

        // And the retired wrapper is gone rather than merely unused — a chevron-plus-eyebrow row
        // left in the file is the same fork with a longer fuse.
        try expectNoLiveMention(of: "TasksPanelIntentSectionHeader")

        // The rule that did *not* fork: both headings still ask one function whether a count may be
        // drawn at all, so the divergence is in the drawing and not in the semantics.
        #expect(!CadenceTaskGroupHeadingMetrics.showsCapsule(for: nil))
        #expect(CadenceTaskGroupHeadingMetrics.showsCapsule(for: 0))
        try expectCallSites(
            of: "CadenceTaskGroupHeadingMetrics.showsCapsule",
            at: [
                "Cadence/Shared/Components/CadenceTaskGroupHeading.swift": 1,
                "Cadence/macOS/Views/ListDetailSupportViews.swift": 1,
            ]
        )
    }

    /// **Today gains the split counts, from the same two functions the other three surfaces call.**
    ///
    /// Not a fifth copy of "how many of these are late": `TasksPanelSupport.overdueCount` and
    /// `.regularCount` both exclude completed tasks, which is the drift `ListDetailComponents` was
    /// caught in once already — a ticked-off task with a past due date counted as overdue on one
    /// screen and not on the other two.
    @Test func todaysGroupsSplitTheirCountsThroughTheSharedPair() throws {
        let overdue = TasksPanelSupport.overdueCount(in: [], todayKey: "2026-08-31")
        #expect(overdue == nil, "an empty group must not claim to be zero days late")
        #expect(TasksPanelSupport.regularCount(in: [], todayKey: "2026-08-31") == 0)

        let sections = try strippingComments(
            sourceFile("Cadence/macOS/Views/TasksPanelSectionViews.swift")
        )
        #expect(sections.contains("struct TasksPanelIntentSectionView: View"), "non-vacuity")
        #expect(sections.contains("TasksPanelSupport.overdueCount(in: tasks, todayKey: todayKey)"))
        #expect(sections.contains("TasksPanelSupport.regularCount(in: tasks, todayKey: todayKey)"))

        // The Completed group deliberately does **not** take the split: it counts open work, so on
        // a group where every row is done it would report "0 tasks" over a list of finished ones.
        // `count:` is the convenience init, and `TasksListCompletedSectionView` takes it too.
        #expect(
            CadenceSourceScan.matchCount(#"count: tasks\.count"#, in: sections) == 1,
            "the Completed group no longer heads itself with a single number"
        )
    }

    // MARK: - The row: iOS wins

    /// Three, and iOS had it. `MacTaskRow` capped at two for the same strip of the same chips on
    /// the same task, and macOS's strip already collapses itself through `ViewThatFits` when the
    /// column is genuinely narrow — so the lower cap was hiding a tag the row had room for.
    @Test func bothRowsShowTheSameNumberOfTags() throws {
        #expect(CadenceTaskPresentationSupport.rowTagLimit == 3)

        try expectCallSites(
            of: "CadenceTaskPresentationSupport.rowTagLimit",
            at: [
                "Cadence/macOS/Views/TasksPanelComponents.swift": 1,
                "Cadence/iOS/iOSTaskViews.swift": 1,
            ]
        )
    }

    /// **The estimate chip crosses to macOS.** `docs/CLAUDE_REFERENCE.md` records that the old
    /// always-loaded guide once called the absence deliberate — "the row has **no** estimate
    /// control" — which is what kept the gap open through two row passes; the user overturned it.
    /// Both rows open the one shared picker, which is the same `EstimatePickerPopoverContent` the
    /// inspector and the kanban card open.
    @Test func bothRowsCarryAnEstimateChipOverTheSharedPicker() throws {
        try expectCallSites(
            of: "MacTaskRowEstimateChip",
            at: ["Cadence/macOS/Views/TasksPanelComponents.swift": 2]
        )
        try expectCallSites(
            of: "iOSTaskRowEstimateChip",
            at: [
                "Cadence/iOS/iOSTaskViews.swift": 1,
                "Cadence/iOS/iOSTaskRowActionViews.swift": 1,
            ]
        )
        try expectCallSites(
            of: "EstimatePickerPopoverContent",
            at: [
                "Cadence/macOS/Views/TasksPanelComponents.swift": 1,
                "Cadence/iOS/iOSTaskRowActionViews.swift": 1,
            ]
        )
        // Same label on both, rather than one row saying "45m" and the other "45 min".
        try expectCallSites(
            of: "CadenceTaskPresentationSupport.estimateLabel",
            at: [
                "Cadence/macOS/Views/TasksPanelComponents.swift": 1,
                "Cadence/iOS/iOSTaskRowActionViews.swift": 1,
            ]
        )
    }

    /// `MacTaskRow`'s documented performance constraint, and the reason the estimate chip is its
    /// own `View` struct rather than three lines inline: the row itself must **not** observe
    /// `TaskCompletionAnimationManager`, because that manager ticks at display-link rate during a
    /// completion animation and an observation on the row re-renders every visible row's whole
    /// content. Only `TaskCompletionButton` and `TaskRowBackground` may hold it.
    ///
    /// Same shape as `NoteEditorPerformanceRegressionTests`: a constraint nothing else can express,
    /// pinned by reading the file.
    @Test func theTaskRowStillDoesNotObserveTheCompletionAnimationManager() throws {
        let source = try strippingComments(sourceFile("Cadence/macOS/Views/TasksPanelComponents.swift"))
        let environments = source.components(separatedBy: "@Environment(TaskCompletionAnimationManager.self)").count - 1
        #expect(environments == 2, "expected exactly the two extracted sub-views to observe the animation manager")

        for owner in ["MacTaskRow", "MacTaskRowEstimateChip"] {
            let body = try declarationBody(of: owner, in: "Cadence/macOS/Views/TasksPanelComponents.swift")
            #expect(
                !body.contains("TaskCompletionAnimationManager"),
                "\(owner) observes TaskCompletionAnimationManager — every visible row will re-render on animation ticks"
            )
        }
    }

    /// **Today's rows are the shared row, at the panel's own insets (T-608).**
    ///
    /// `TasksPanelSectionViews` re-implemented `TaskListInteractiveRow` line for line — the
    /// `.draggable`, the `.dropDestination` with its `isTargeted:` write-back, the 2pt top
    /// indicator, the 0.15s `.easeInOut` on `dragOverTaskID`, and the asymmetric insert/remove
    /// transition — while the shared row had taken `leadingInset`/`trailingInset` as parameters the
    /// whole time.
    ///
    /// **This test is deliberately not "the shared row is called".** The shared row's *default*
    /// leading inset is the list detail's 52, which clears furniture Today's rows do not have, so a
    /// call site that converges and forgets the argument indents Today's rows by 52 under a heading
    /// at 16 — the "header indented from its rows" defect inverted. So the insets are named at the
    /// call site and counted here, and the value assertions below say why those two numbers are not
    /// interchangeable.
    ///
    /// **The convergence was not a no-op, and this records the one thing that changed.** Today
    /// overlaid the indicator on the *unpadded* row and padded the result, so the indicator was
    /// inset twice — 32pt from the pane's leading edge over a row whose content starts at 16.
    /// `TaskListInteractiveRow` overlays the *padded* row, so the indicator starts where the row it
    /// points at starts. That ordering is pinned below, because it is the only way "same behaviour"
    /// would have been a lie.
    @Test func todaysRowsAreTheSharedInteractiveRowAtThePanelsOwnInsets() throws {
        // The two numbers, and why naming the argument is load-bearing: an omitted `leadingInset:`
        // silently means 52.
        #expect(TasksPanelMetrics.horizontalInset == 16)
        #expect(TaskListDisplayMetrics.taskTrailingInset == 12)
        #expect(TaskListDisplayMetrics.taskLeadingInset == 52)
        #expect(
            TasksPanelMetrics.horizontalInset != TaskListDisplayMetrics.taskLeadingInset,
            "the shared row's default leading inset is no longer distinguishable from Today's"
        )

        let sections = "Cadence/macOS/Views/TasksPanelSectionViews.swift"
        let listDetail = "Cadence/macOS/Views/ListDetailSupportViews.swift"

        // The call sites below name `todayRowLeadingInset`, so its *definition* has to be pinned
        // too — otherwise retuning it to the list detail's 52 passes every assertion here while
        // moving every row on the page.
        #expect(
            try strippingComments(sourceFile(sections))
                .contains("private let todayRowLeadingInset: CGFloat = TasksPanelMetrics.horizontalInset")
        )

        // MARK: one construction of the row itself, app-wide
        //
        // The strongest form of "the copy is gone": after the convergence, `MacTaskRow` is built at
        // exactly one site in `Cadence/`, inside `TaskListDisplayRow`. A fifth surface that wants a
        // task row has to reach that component or change this number on purpose. The `> 0`
        // self-check below is what keeps a scan that reads nothing from passing the `== 1`.
        #expect(try liveTextOccurrences(of: "MacTaskRow(") == 1)
        #expect(try liveTextOccurrences(of: "TaskListDisplayRow(") > 0, "self-check: the scan reads code")

        // MARK: the intent groups — the interactive row, insets named
        let intent = try declarationBody(of: "TasksPanelIntentSectionView", in: sections)
        #expect(intent.contains("var body: some View"), "non-vacuity: empty declaration slice")
        #expect(occurrences(of: "TaskListInteractiveRow(", in: intent) == 1)
        #expect(occurrences(of: "leadingInset: todayRowLeadingInset", in: intent) == 1)
        #expect(
            occurrences(of: "trailingInset: TaskListDisplayMetrics.taskTrailingInset", in: intent) == 1
        )

        // The five behaviours that were re-implemented here, each named rather than counted in
        // aggregate. `dropDestination` is the exception and stays at exactly one: the *section
        // header* still accepts a dropped task, and only the row's copy went.
        for reimplementation in [
            "MacTaskRow(",
            ".draggable(",
            "isTargeted:",
            "Rectangle()",
            ".animation(.easeInOut(duration: 0.15)",
            ".transition(.asymmetric(",
        ] {
            #expect(
                !intent.contains(reimplementation),
                "TasksPanelIntentSectionView re-implements \(reimplementation) instead of using the shared row"
            )
        }
        #expect(
            occurrences(of: ".dropDestination(for: String.self)", in: intent) == 1,
            "the group header's own drop target is gone, or a row's has grown back"
        )

        // MARK: the Completed group — the display row plus a drag, the shape All Tasks uses
        let completed = try declarationBody(of: "TasksPanelCompletedSectionView", in: sections)
        #expect(completed.contains("var body: some View"), "non-vacuity: empty declaration slice")
        #expect(occurrences(of: "TaskListDisplayRow(", in: completed) == 1)
        #expect(occurrences(of: "leadingInset: todayRowLeadingInset", in: completed) == 1)
        #expect(
            occurrences(of: "trailingInset: TaskListDisplayMetrics.taskTrailingInset", in: completed) == 1
        )
        #expect(
            occurrences(of: ".draggable(taskDragPayload(task))", in: completed) == 1,
            "the day's finished rows stopped being draggable"
        )
        for reimplementation in ["MacTaskRow(", ".transition(.asymmetric("] {
            #expect(
                !completed.contains(reimplementation),
                "TasksPanelCompletedSectionView re-implements \(reimplementation)"
            )
        }

        // MARK: the shared row still does all of it — otherwise "converged" only means "deleted"
        let display = try declarationBody(of: "TaskListDisplayRow", in: listDetail)
        let interactive = try declarationBody(of: "TaskListInteractiveRow", in: listDetail)
        #expect(display.contains("MacTaskRow(task: task"), "non-vacuity: empty declaration slice")
        #expect(occurrences(of: ".padding(.leading, leadingInset)", in: display) == 1)
        #expect(occurrences(of: ".padding(.trailing, trailingInset)", in: display) == 1)
        #expect(display.contains(".transition(.asymmetric("))
        #expect(interactive.contains(".draggable(taskDragPayload(task))"))
        #expect(interactive.contains(".dropDestination(for: String.self)"))
        #expect(interactive.contains("isTargeted:"))
        #expect(interactive.contains(".animation(.easeInOut(duration: 0.15), value: dragOverTaskID)"))

        // MARK: and the indicator is inset once, over the padded row
        //
        // One `.padding(.leading, leadingInset)` in the interactive row, and it is the
        // *indicator's own*, applied after the overlay opens. Re-pad the row here — the shape
        // Today had — and this becomes two, which is the double inset spelled out.
        #expect(occurrences(of: ".padding(.leading, leadingInset)", in: interactive) == 1)
        let rowCall = try #require(interactive.range(of: "TaskListDisplayRow("))
        let overlay = try #require(interactive.range(of: ".overlay(alignment: .top)"))
        let indicatorInset = try #require(interactive.range(of: ".padding(.leading, leadingInset)"))
        #expect(rowCall.upperBound < overlay.lowerBound)
        #expect(
            overlay.upperBound < indicatorInset.lowerBound,
            "the indicator is no longer drawn over the already-padded row"
        )
    }

    // MARK: - The header: no identity tile, anywhere

    /// **The user's call, and it reversed the brief.** macOS was to gain iOS's identity tile; what
    /// landed instead is that neither platform has one. A rounded glyph square at the top of a page
    /// names the page you are already looking at — the deleted subtitle's argument, one row up.
    ///
    /// The parameter is *deleted*, not left inert. A dead parameter that still compiles is how
    /// `subtitle` survived long enough to need removing three separate times.
    @Test func neitherPageHeaderTakesAnIdentityTile() throws {
        let desktop = try declarationBody(of: "DesktopPageHeader", in: "Cadence/macOS/Views/macOSRootSupportViews.swift")
        let mobile = try declarationBody(of: "iOSPageHeader", in: "Cadence/iOS/iOSFeatureComponents.swift")

        for (name, body) in [("DesktopPageHeader", desktop), ("iOSPageHeader", mobile)] {
            #expect(!body.contains("systemImage"), "\(name) still takes a systemImage")
            #expect(!body.contains("IconTile"), "\(name) still draws an identity tile")
        }
    }

    /// And no wrapper may reintroduce one behind the two header views' backs. These five decide
    /// nothing about appearance by design, so a tile parameter on any of them is a tile.
    @Test func noPageHeaderWrapperReintroducesTheTile() throws {
        let wrappers: [(String, String)] = [
            ("PanelHeader", "Cadence/macOS/Views/TodaySupportViews.swift"),
            ("CommitmentPageHeader", "Cadence/macOS/Views/CommitmentSharedViews.swift"),
            ("CadenceSettingsHeader", "Cadence/Shared/CadenceSettingsSharedViews.swift"),
            ("iOSPanelHeader", "Cadence/iOS/iOSTaskViews.swift"),
            ("iOSCompactPageHeader", "Cadence/iOS/iOSFeatureComponents.swift"),
            ("iOSSettingsPageHeader", "Cadence/iOS/iOSSettingsComponents.swift"),
        ]

        for (name, path) in wrappers {
            let body = try declarationBody(of: name, in: path)
            #expect(!body.contains("systemImage"), "\(name) passes a systemImage to its header again")
            #expect(!body.contains("IconTile"), "\(name) draws its own identity tile")
        }
    }

    /// **Today's three columns name themselves once each (T-602).**
    ///
    /// The task column was fixed first: `TASKS / Today` became the date over `Today`, because an
    /// eyebrow naming the column above a title naming the page is the header-describes-its-own-page
    /// rule one row down. The other two still read `NOTES / <active tab>` and `SCHEDULE / Timeline`
    /// — the second of which named one column twice in two different words, while the first
    /// repeated the tab strip eight lines below it with the live tab already lit.
    ///
    /// Neither column had a second fact to promote the way the task column had the date, so both
    /// dropped the eyebrow instead of inventing one. iPad went further and draws no header on these
    /// two panes at all; it can, because `iPadTodayInspectorSwitcher` names them. macOS's three
    /// columns stand side by side with nothing else naming them, so the title stays.
    @Test func todaysNoteAndScheduleColumnsNameThemselvesOnce() throws {
        let notes = try strippingComments(sourceFile("Cadence/macOS/Views/NotePanel.swift"))
        let schedule = try strippingComments(sourceFile("Cadence/macOS/Views/SchedulePanelShellViews.swift"))

        // Non-vacuity: these really are the two files that host Today's other two column headers.
        #expect(notes.contains("struct NotePanel"))
        #expect(schedule.contains("struct SchedulePanelHeader"))

        #expect(notes.contains("PanelHeader(title: \"Notes\")"))
        #expect(schedule.contains("PanelHeader(title: \"Timeline\")"))

        for (name, source) in [("NotePanel", notes), ("SchedulePanelShellViews", schedule)] {
            #expect(
                !source.contains("PanelHeader(eyebrow:"),
                "\(name) puts an eyebrow back over a title that already names the column"
            )
        }

        // The notes column's title was the active tab's own name, which the strip below already
        // draws. Nothing computes a header title there any more.
        #expect(!notes.contains("headerTitle"))
    }

    /// **T-615.** The timeline sidebar named the timeline twice. `RootTimelineSidebarPane` titles
    /// itself "Today Timeline" and then hosts the standard `SchedulePanel`, which draws its own
    /// "Timeline" header directly underneath. Before T-602 it was three times — the `SCHEDULE`
    /// eyebrow made a third — and dropping the eyebrow left the remaining pair.
    ///
    /// The pane keeps its title and the hosted panel drops its heading, because the header rule is
    /// about the page the user is already on and the outer title has already said it. The panel's
    /// own divider goes with the header: the pane draws that rule itself, so keeping both would
    /// leave two hairlines with nothing between them.
    ///
    /// **The pin that matters is the three other hosts.** Today's schedule column, the focus screen
    /// and the focus sidebar each host the same panel with nothing above naming it, so each must
    /// still draw its own header — dropping the heading unconditionally would have left three
    /// unnamed columns to fix one named twice. `.hosted` is opt-in, and it is opt-in at exactly one
    /// call site in the app.
    @Test func theTimelinePaneNamesItselfOnceAndTheOtherHostsStillNameThemselves() throws {
        #expect(SchedulePanelPresentation.standard.drawsOwnHeader)
        #expect(SchedulePanelPresentation.compact.drawsOwnHeader)
        #expect(!SchedulePanelPresentation.hosted.drawsOwnHeader)

        let pane = try strippingComments(sourceFile("Cadence/macOS/Views/macOSRootSupportViews.swift"))
        #expect(pane.contains("struct RootTimelineSidebarPane: View"), "non-vacuity: wrong file read")
        #expect(pane.contains(#"Text("Today Timeline")"#), "the pane stopped naming itself")
        #expect(pane.contains("SchedulePanel(presentation: .hosted)"))

        let panel = try strippingComments(sourceFile("Cadence/macOS/Views/SchedulePanel.swift"))
        #expect(panel.contains("struct SchedulePanel: View"), "non-vacuity: wrong file read")
        #expect(
            panel.contains("if presentation.drawsOwnHeader {"),
            "the panel draws its header unconditionally again"
        )

        // The three that must still draw one, named one at a time with the construction each uses.
        let namedHosts = [
            ("Cadence/macOS/Views/TodayView.swift", "SchedulePanel(useStandardHeaderHeight: true)"),
            ("Cadence/macOS/Views/FocusView.swift", "SchedulePanel(presentation: .compact)"),
            ("Cadence/macOS/Views/FocusSidebarSupportViews.swift", "SchedulePanel(presentation: .compact)"),
        ]
        for (path, construction) in namedHosts {
            let source = try strippingComments(sourceFile(path))
            #expect(source.contains(construction), "\(path) no longer hosts the panel this way")
            #expect(
                !source.contains(".hosted"),
                "\(path) dropped a heading with nothing above it naming the column"
            )
        }

        // And nowhere else. `iOSSchedulePanel(` contains this needle as a substring, so the
        // lookbehind is load-bearing rather than decorative.
        let hostsThePanel = try CadenceScanInstrument(
            "hosts SchedulePanel",
            fires: "                SchedulePanel(useStandardHeaderHeight: true)\n",
            andNotOn: "            iOSSchedulePanel()\n",
            by: { CadenceSourceScan.matchCount(#"(?<![A-Za-z])SchedulePanel\("#, in: $0) > 0 }
        )
        let headerless = try CadenceScanInstrument(
            "hosts SchedulePanel headerless",
            fires: "            SchedulePanel(presentation: .hosted)\n",
            andNotOn: "            SchedulePanel(presentation: .compact)\n",
            by: { $0.contains("SchedulePanel(presentation: .hosted)") }
        )
        let read = CadenceSourceScan.strippedSourceReader()
        let files = try CadenceSourceScan.swiftFiles(under: "Cadence")
        let hosts = try hostsThePanel.sweep(
            files,
            atLeast: 400,
            including: "Cadence/macOS/Views/macOSRootSupportViews.swift",
            read: read
        )
        #expect(
            hosts == [
                "Cadence/macOS/Views/FocusSidebarSupportViews.swift",
                "Cadence/macOS/Views/FocusView.swift",
                "Cadence/macOS/Views/TodayView.swift",
                "Cadence/macOS/Views/macOSRootSupportViews.swift",
            ],
            "the app hosts SchedulePanel from \(hosts)"
        )
        let silenced = try headerless.sweep(
            files,
            atLeast: 400,
            including: "Cadence/macOS/Views/macOSRootSupportViews.swift",
            read: read
        )
        #expect(silenced == ["Cadence/macOS/Views/macOSRootSupportViews.swift"])
    }

    /// The metrics that fed the tile go with it — a size table entry nothing reads is the same
    /// hazard as the parameter, and this one carried a role×surface ramp that would read as live.
    /// `tileGlyphRatio` and `tileFillOpacity` **stay**: `CommitmentIconTile` reads both for the
    /// tiles inside rows, cards and pickers, which are not page identity.
    @Test func theHeaderTileMetricsAreGoneAndTheTileVocabularyIsNot() throws {
        let source = try strippingComments(sourceFile("Cadence/Shared/CadencePageHeaderMetrics.swift"))
        #expect(!source.contains("tileSize"))
        #expect(source.contains("tileGlyphRatio"))
        #expect(source.contains("tileFillOpacity"))
        #expect(CadencePageHeaderMetrics.tileGlyphRatio == 0.44)
        #expect(CadencePageHeaderMetrics.tileFillOpacity == 0.14)
    }

    /// Three tiers, still — dropping the tile is not a reason to fold macOS into `.regular`. The
    /// title ramp is the whole finding behind the third tier and it is untouched.
    @Test func theSurfaceRampSurvivesTheTileRemoval() {
        #expect(CadencePageHeaderSurface.allCases.count == 3)
        #expect(CadencePageHeaderMetrics.metrics(role: .page, surface: .desktop).titleSize == 22)
        #expect(CadencePageHeaderMetrics.metrics(role: .pane, surface: .desktop).titleSize == 16)
    }

    /// **The T-161 test for the header.** Today's task column on every platform heads itself with
    /// the day and the day's summary, through the one `eyebrowDetail` slot. macOS read `TASKS /
    /// Today` — an eyebrow naming the column and a title naming the page, neither of which the day
    /// changes.
    @Test func everyTodayHeaderCarriesTheDayAndItsSummary() throws {
        try expectCallSites(
            of: "eyebrowDetail: summary",
            at: [
                "Cadence/macOS/Views/TasksPanelSupportViews.swift": 1,
                "Cadence/iOS/iPadTodaySupportViews.swift": 1,
                "Cadence/iOS/iOSTodayCompactViews.swift": 1,
            ]
        )
        try expectCallSites(
            of: "DateFormatters.longDate.string",
            at: [
                "Cadence/macOS/Views/TasksPanelSupportViews.swift": 1,
                "Cadence/iOS/iOSTodayView.swift": 1,
                "Cadence/iOS/iOSTodayCompactViews.swift": 1,
            ]
        )
    }

    /// The summary itself is one derivation. macOS was computing no summary at all; the risk now is
    /// that it grows its own rather than calling the shared one.
    @Test func everyTodayDerivesItsSummaryOnce() throws {
        try expectCallSites(
            of: "CadenceTodayPresentationSupport.summary",
            at: [
                "Cadence/macOS/Views/TasksPanel.swift": 1,
                "Cadence/iOS/iOSTodayView.swift": 1,
            ]
        )
    }

    // MARK: - The scan itself

    /// The absence assertions above are only worth anything if the scan actually reads files, and a
    /// scan that silently returns nothing passes every one of them. This is the test that stops
    /// them going vacuous.
    @Test func theSourceScanActuallyReachesBothPlatformsSourceInTodayUnification() throws {
        let files = try swiftFiles(under: "Cadence")

        #expect(files.count > 300, "the source scan found \(files.count) files and cannot be doing its job")
        #expect(files.contains("Cadence/macOS/Views/TasksPanel.swift"))
        #expect(files.contains("Cadence/iOS/iOSTodayTaskSections.swift"))
        #expect(files.contains("Cadence/Shared/Components/CadenceTaskGroupHeading.swift"))
    }

    /// And `declarationBody` has to actually find a body — an empty slice would pass every
    /// `!contains` above. The two header views are the ones those assertions depend on.
    @Test func theDeclarationSlicerActuallyFindsTheHeaderBodies() throws {
        let desktop = try declarationBody(of: "DesktopPageHeader", in: "Cadence/macOS/Views/macOSRootSupportViews.swift")
        let mobile = try declarationBody(of: "iOSPageHeader", in: "Cadence/iOS/iOSFeatureComponents.swift")

        #expect(desktop.contains("eyebrowDetail"))
        #expect(desktop.contains("countBadge"))
        #expect(mobile.contains("eyebrowDetail"))
        #expect(mobile.contains("iOSPageHeaderCountBadge"))
    }
}

/// **T-305: what Today's groups actually are, pinned by value.**
///
/// One seeded day, and the assertions name the groups it produces and the order of the rows inside
/// them. The two are pinned separately on purpose: the grouping rule and the sort inside a group
/// are different decisions, and a test that folded them together could not tell you which one
/// broke.
///
/// A real `ModelContainer` rather than bare model objects, because the whole point of the change is
/// that a group *is* a list — which means area/project/context relationships have to be live.
@MainActor
struct CadenceTodayListGroupingTests {
    private let todayKey = "2026-08-11"
    private let yesterdayKey = "2026-08-10"

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: CadenceSchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// Two contexts, three lists, and the sidebar order is deliberately **not** alphabetical:
    /// Work's Admin and Launch come before Home's Errands, so an implementation that sorted list
    /// groups by name would produce Admin / Errands / Launch and fail.
    private struct Day {
        let modelContext: ModelContext
        let contexts: [Context]
        let admin: Area
        let launch: Project
        let errands: Area
        var tasks: [AppTask]
    }

    private func seedDay() throws -> Day {
        let modelContext = try makeContext()

        let work = Context(name: "Work")
        work.order = 0
        let home = Context(name: "Home")
        home.order = 1
        modelContext.insert(work)
        modelContext.insert(home)

        let admin = Area(name: "Admin", context: work)
        admin.order = 1
        let errands = Area(name: "Errands", context: home)
        errands.order = 0
        let launch = Project(name: "Launch", context: work)
        launch.order = 0
        modelContext.insert(admin)
        modelContext.insert(errands)
        modelContext.insert(launch)

        // `order` ascends with creation so the sort's tie-break is readable rather than incidental.
        var order = 0
        func task(
            _ title: String,
            due: String = "",
            scheduled: String = "",
            area: Area? = nil,
            project: Project? = nil
        ) -> AppTask {
            let task = AppTask(title: title)
            task.dueDate = due
            task.scheduledDate = scheduled
            task.area = area
            task.project = project
            task.order = order
            order += 1
            modelContext.insert(task)
            return task
        }

        let tasks = [
            task("Ship the beta", due: "2026-08-09", project: launch),
            task("Pay the invoice", due: yesterdayKey, area: admin),
            task("Draft the notes", scheduled: todayKey, project: launch),
            task("Review the spec", due: todayKey, project: launch),
            task("Buy milk", scheduled: todayKey, area: errands),
            task("Call the plumber", due: todayKey),
            task("File receipts", scheduled: todayKey, area: admin),
        ]

        return Day(
            modelContext: modelContext,
            contexts: [work, home],
            admin: admin,
            launch: launch,
            errands: errands,
            tasks: tasks
        )
    }

    private func groups(for day: Day) -> [CadenceTodayTaskGroup] {
        CadenceTaskQuerySupport.todayGroups(
            from: CadenceTaskQuerySupport.activeTodayTasks(
                from: day.tasks,
                todayKey: todayKey,
                sortMode: .listOrder
            ),
            todayKey: todayKey,
            contexts: day.contexts
        )
    }

    // MARK: - The grouping

    /// **The decision, by value.** Overdue first — the one date-shaped group left, because a missed
    /// deadline outranks where the work lives — and then one group per list in sidebar order, with
    /// the unfiled task's Inbox at the head of them.
    ///
    /// Membership is asserted as sets here so this test says nothing about the order *within* a
    /// group; that is the next test's job, and keeping them apart is what lets a broken sort and a
    /// broken grouping be told apart.
    @Test func todayIsOverdueAndThenTheDaysListsInSidebarOrder() throws {
        let day = try seedDay()
        let produced = groups(for: day)

        #expect(produced.map(\.title) == ["Overdue", "Inbox", "Admin", "Launch", "Errands"])

        let membership = produced.map { Set($0.tasks.map(\.title)) }
        #expect(membership == [
            ["Ship the beta", "Pay the invoice"],
            ["Call the plumber"],
            ["File receipts"],
            ["Review the spec", "Draft the notes"],
            ["Buy milk"],
        ])

        // Not one row lost or duplicated between the flat day and its groups.
        #expect(produced.flatMap { $0.tasks.map(\.id) }.count == 7)
        #expect(Set(produced.flatMap { $0.tasks.map(\.id) }) == Set(day.tasks.map(\.id)))
    }

    /// A group is identified by its list, not by its position, so a collapse state and a `ForEach`
    /// survive the day changing shape around them.
    @Test func aListGroupIsIdentifiedByTheListItIsFor() throws {
        let day = try seedDay()
        let produced = groups(for: day)

        #expect(produced.map(\.identity) == [
            .overdue,
            .list(key: "inbox"),
            .list(key: "a_\(day.admin.id.uuidString)"),
            .list(key: "p_\(day.launch.id.uuidString)"),
            .list(key: "a_\(day.errands.id.uuidString)"),
        ])
        #expect(Set(produced.map(\.id)).count == produced.count)
    }

    /// **The open question, answered: a task with no list gets the Inbox group.**
    ///
    /// Not a nameless bucket at the foot of the page — that is "Planned Today" again in everything
    /// but the label, a group defined by what it is *not*. "Inbox" is what the sidebar, the Kanban
    /// board and macOS's own by-list grouping already call an unfiled task's home, it sits first
    /// there too, and — unlike a tail bucket — it is a real destination, so the header can accept a
    /// dropped `+`.
    @Test func aTaskWithNoListGetsTheInboxGroupAndTheInboxGroupLeadsTheLists() throws {
        let day = try seedDay()
        let produced = groups(for: day)

        let inbox = try #require(produced.first { $0.identity == .list(key: "inbox") })
        #expect(inbox.title == CadenceBoardCardMetadata.inboxLabel)
        #expect(inbox.tasks.map(\.title) == ["Call the plumber"])
        // Directly under Overdue, and ahead of every real list.
        #expect(produced.firstIndex { $0.id == inbox.id } == 1)
        // The list *and* the day — see `aListGroupHeaderOffersItsListToADroppedPlusAndOverdueOffersNothing`.
        #expect(CadenceTaskDropSupport.dropKey(forGroup: inbox.dropIdentity) == "list:inbox|date:today")
    }

    // MARK: - The sort inside a group

    /// **Where the deleted date axis went.** Nothing re-sorts inside `todayGroups`; the caller's
    /// order survives, and the caller's order leads with `todayRank`. So Launch reads "Review the
    /// spec" (due today) before "Draft the notes" (merely planned for today) without a heading
    /// saying so, and Overdue keeps the flat day's order too.
    ///
    /// Mutate the rank and this fails while the grouping test above stays green.
    @Test func theOrderInsideAGroupIsTheCallersTodayRankedSort() throws {
        let day = try seedDay()
        let produced = groups(for: day)

        let launch = try #require(produced.first { $0.identity == .list(key: "p_\(day.launch.id.uuidString)") })
        #expect(launch.tasks.map(\.title) == ["Review the spec", "Draft the notes"])

        let overdue = try #require(produced.first { $0.identity == .overdue })
        #expect(overdue.tasks.map(\.title) == ["Ship the beta", "Pay the invoice"])

        // And the grouping is a stable partition of exactly that array: every group's rows appear
        // in the same relative order they had in the flat day.
        let flat = CadenceTaskQuerySupport.activeTodayTasks(
            from: day.tasks,
            todayKey: todayKey,
            sortMode: .listOrder
        )
        let flatIndex = Dictionary(uniqueKeysWithValues: flat.enumerated().map { ($0.element.id, $0.offset) })
        for group in produced {
            let positions = group.tasks.compactMap { flatIndex[$0.id] }
            #expect(positions == positions.sorted(), "\(group.title) reordered its rows")
        }
    }

    /// **One today-rank, and both platforms lead their Today sort with it.**
    ///
    /// A due date outranks a do date, the way every other Today rule has it. macOS used to spell
    /// its own rank inside `TasksPanel` with the middle two tests in the other order, so a task due
    /// today and planned for yesterday read as past-do there and as due-today on iOS.
    @Test func oneTodayRankAndADueDateOutranksADoDate() throws {
        let today = "2026-08-11"
        func rank(due: String = "", scheduled: String = "") -> Int {
            let task = AppTask(title: "t")
            task.dueDate = due
            task.scheduledDate = scheduled
            return CadenceTaskQuerySupport.todayRank(task, todayKey: today)
        }

        #expect(rank(due: "2026-08-09") == 0)
        #expect(rank(scheduled: "2026-08-10") == 1)
        #expect(rank(due: today) == 2)
        #expect(rank(scheduled: today) == 3)
        #expect(rank() == 4)
        // The case the two spellings disagreed on.
        #expect(rank(due: today, scheduled: "2026-08-10") == 2)
    }

    /// **The T-161 test for the rank**, and for the condition that used to make macOS's copy
    /// unreachable. `TodayView` builds its panel with `enableControls: true`, so a rank gated on
    /// `!enableControls` never ran — which was survivable while four date headings carried the
    /// urgency the sort had dropped, and is not now that Today groups by list.
    @Test func macOSTodayLeadsItsSortWithTheSharedRank() throws {
        try expectCallSites(
            of: "CadenceTaskQuerySupport.todayRank",
            at: ["Cadence/macOS/Views/TasksPanel.swift": 1]
        )
        #expect(try liveTextOccurrences(of: "mode == .todayOverview && !enableControls") == 0)
        // The self-check the absence above needs — a scan that reads nothing passes every `== 0`.
        // It used to be `mode == .todayOverview`, which no longer appears in live source: T-487
        // deleted `.byDoDate`, so nothing tests the mode with `==` any more. `case .todayOverview`
        // is the same fact spelled the way the surviving `switch`es spell it.
        #expect(try liveTextOccurrences(of: "case .todayOverview") > 0)
        #expect(try liveTextOccurrences(of: "mode == .todayOverview") == 0)
    }

    // MARK: - The rollover banner

    /// **What makes the roll-over feel like it did something.** While the banner is up, the tasks it
    /// is offering are withheld from the grouped list — so a list whose only work today is
    /// yesterday's leftovers has no group at all. Confirming the roll makes that group appear, with
    /// the task in it, instead of moving the row between two date-shaped buckets.
    @Test func aRolledOverTaskJoinsItsListsGroupRatherThanASecondDateBucket() throws {
        let modelContext = try makeContext()
        let home = Context(name: "Home")
        home.order = 0
        let errands = Area(name: "Errands", context: home)
        modelContext.insert(home)
        modelContext.insert(errands)

        let leftover = AppTask(title: "Water the plants")
        leftover.scheduledDate = yesterdayKey
        leftover.area = errands
        modelContext.insert(leftover)

        let all = [leftover]
        let pastDo = CadenceTodayRolloverSupport.pastDoTasks(from: all, todayKey: todayKey)
        #expect(pastDo.map(\.title) == ["Water the plants"])

        func todayGroups(noticeVisible: Bool) -> [CadenceTodayTaskGroup] {
            CadenceTaskQuerySupport.todayGroups(
                from: CadenceTodayRolloverSupport.groupedTasks(
                    from: CadenceTaskQuerySupport.activeTodayTasks(
                        from: all,
                        todayKey: todayKey,
                        sortMode: .listOrder
                    ),
                    withholding: pastDo,
                    isNoticeVisible: noticeVisible
                ),
                todayKey: todayKey,
                contexts: [home]
            )
        }

        // Banner up: the row is in the banner and nowhere else, so Errands has no group.
        #expect(todayGroups(noticeVisible: true).isEmpty)

        try CadenceTodayRolloverSupport.rollOver(pastDo, todayKey: todayKey, modelContext: modelContext)
        #expect(leftover.scheduledDate == todayKey)

        // Rolled: it is in its list, and the page has grown a list group rather than a date one.
        let after = todayGroups(noticeVisible: false)
        #expect(after.map(\.title) == ["Errands"])
        let group = try #require(after.first)
        #expect(group.tasks.map(\.title) == ["Water the plants"])
        #expect(group.identity == CadenceTodayGroupIdentity.list(key: "a_\(errands.id.uuidString)"))
    }

    // MARK: - What a group offers, and what its rows say

    /// Overdue is drawn from every list at once, so its rows are the only ones on Today that still
    /// need a chip naming where the work lives. A list group's header already prints the name.
    @Test func onlyOverdueRowsStillNameTheirList() throws {
        let day = try seedDay()
        let produced = groups(for: day)

        #expect(produced.map(\.showsContainerChip) == [true, false, false, false, false])
    }

    /// Overdue is defined by a day that has gone by, so its header seeds nothing and does not light
    /// up. A list group is a list and says so — in the same `list:` spelling `assignTask` parses,
    /// which is why the key comes from `CadenceTaskDropSupport.containerKey` rather than being
    /// re-spelled by the grouping.
    ///
    /// **And it says the day as well** (T-337). Today's headers used to be date-shaped, so a `+`
    /// dropped anywhere on this page produced work that stayed on it. Once the page groups by list,
    /// a header offering only its list would create a task that was filed correctly and then
    /// vanished from the page it was dropped on — so a Today list group is `.todayList`, which
    /// resolves to the joined key. The seed is what the assertion is really about: a key-shape
    /// check alone would pass against a resolver that read `date:today` and dropped it.
    @Test func aListGroupHeaderOffersItsListAndTodayToADroppedPlusAndOverdueOffersNothing() throws {
        let day = try seedDay()
        let produced = groups(for: day)

        let overdue = try #require(produced.first { $0.identity == .overdue })
        #expect(CadenceTaskDropSupport.dropKey(forGroup: overdue.dropIdentity) == nil)

        let launch = try #require(produced.first { $0.title == "Launch" })
        let key = try #require(CadenceTaskDropSupport.dropKey(forGroup: launch.dropIdentity))
        #expect(key == "list:p_\(day.launch.id.uuidString)|date:today")

        let seed = CadenceTaskDropSupport.seed(forDropKey: key, todayKey: todayKey)
        #expect(seed.container == .project(day.launch.id))
        #expect(seed.doDateKey == todayKey)
        // A do date, not a due date: Today's list groups are what you have *planned*, and a due
        // date is a commitment the header never made.
        #expect(seed.dueDateKey.isEmpty)
    }

    /// The order of the list groups is the sidebar's, and `TasksPanelSupport.listGroups` — All
    /// Tasks' by-list mode — reads the same function, so the two by-list surfaces cannot present
    /// their groups in different orders.
    @Test func listGroupOrderIsTheSidebarOrderWithInboxFirst() throws {
        let day = try seedDay()

        #expect(CadenceTaskQuerySupport.listGroupOrder(contexts: day.contexts) == [
            "inbox",
            "a_\(day.admin.id.uuidString)",
            "p_\(day.launch.id.uuidString)",
            "a_\(day.errands.id.uuidString)",
        ])
    }

    /// A task holding both an area and a project is grouped under the **project**, which is
    /// `CadenceTaskDropSupport.listKey(for:)`'s rule: the more specific container is where the rest
    /// of the UI already shows it.
    @Test func aTaskHoldingBothContainersIsGroupedUnderTheProject() throws {
        let day = try seedDay()
        let repaired = day.tasks[0]
        repaired.area = day.admin

        #expect(CadenceTaskQuerySupport.listGroupKey(for: repaired) == "p_\(day.launch.id.uuidString)")
    }
}

/// **macOS Today speaks iOS's sort vocabulary now (T-606), and the swap had to be non-destructive.**
///
/// macOS had two chips — Sort (Custom / Date / Priority) × Order (Ascending / Descending) — and iOS
/// one control naming five modes. Only "Priority" was common, and macOS's "Date" did not say *which*
/// date on a page whose whole vocabulary is do-date vs due-date. The decision was to adopt iOS's
/// named set and fold direction into it.
///
/// The hazard is that both halves were persisted (`todaySortField` / `todaySortDirection`) and this
/// project has no `SchemaMigrationPlan`, so a stored value that no longer decodes must land
/// somewhere defined rather than crash or silently re-sort. These tests are that guarantee, and the
/// comparator-equivalence pair below is the evidence for the mapping: they compare the *old*
/// comparator against the *new* one over a fixture set rather than trusting the two labels to mean
/// the same thing.
struct CadenceTodaySortVocabularyTests {

    // MARK: - The mapping

    /// Every retiring `TaskSortField`, mapped — and mapped **exhaustively**, so a field added later
    /// cannot fall through to the default unnoticed.
    @Test func everyRetiredMacOSSortFieldMapsOntoANamedMode() {
        let mapped = TaskSortField.allCases.map {
            CadenceTaskSortMode.migratedFromMacOSTodaySortField($0.rawValue)
        }
        #expect(mapped == [.listOrder, .doDate, .priority])
        #expect(TaskSortField.allCases.map(\.rawValue) == ["Custom", "Date", "Priority"])
    }

    /// **The fallback, which is the whole point of the ticket.** Nil, empty, the *other*
    /// vocabulary's raw values, and a string from no vocabulary at all: every one lands on a
    /// defined mode instead of crashing or resetting to iOS's default.
    @Test func anUnrecognisedStoredSortValueLandsOnTheMacOSDefault() {
        #expect(CadenceTaskSortMode.macOSTodayDefault == .doDate)

        let unrecognised: [String?] = [
            nil,
            "",
            "date",                       // right vocabulary, wrong case
            "doDate",                     // the *new* vocabulary in the *old* key
            "Newest",                     // a mode macOS never had
            "Ascending",                  // the Order chip's value in the Sort key
            "\u{1F600}"
        ]
        for raw in unrecognised {
            #expect(
                CadenceTaskSortMode.migratedFromMacOSTodaySortField(raw) == .doDate,
                "\(raw ?? "nil") did not fall back"
            )
        }
    }

    /// macOS keeps its **own** default rather than iOS's `.priority`, and deliberately: macOS Today
    /// shipped `Date` + `Ascending`, which is `.doDate`. Taking iOS's default would have re-sorted
    /// every user who never opened the chip — the exact silent re-sort this ticket forbids.
    @Test func macOSTodayKeepsItsOwnDefaultRatherThanIOSTodays() {
        #expect(CadenceTaskSortMode.macOSTodayDefault == .doDate)
        #expect(CadenceTaskSortMode.macOSTodayDefault != .priority)
    }

    // MARK: - The comparator evidence for the mapping

    /// **Three retiring settings sort identically under their replacement**, over a fixture built to
    /// exercise every branch: do-dated and undated, timed and untimed, four priorities, and ties
    /// that reach `fallbackPrecedes`.
    ///
    /// This is what proves the mapping rather than assuming it. `Date` is only a label; what it
    /// *does* is sort `AppTask.scheduledDate` — the do date — which is why `.doDate` and not
    /// `.dueDate` is the answer.
    @Test func theThreeMappedSettingsSortIdenticallyUnderTheirReplacement() {
        let tasks = Self.fixture()

        let equivalences: [(TaskSortField, TaskSortDirection, CadenceTaskSortMode)] = [
            (.custom, .ascending, .listOrder),
            (.custom, .descending, .listOrder),
            (.date, .ascending, .doDate),
            (.priority, .descending, .priority)
        ]

        for (field, direction, mode) in equivalences {
            let old = tasks.sorted { TaskOrdering.precedes($0, $1, field: field, direction: direction) }
            let new = tasks.sorted { CadenceTaskQuerySupport.sortTasks($0, $1, sortMode: mode) }
            #expect(
                old.map(\.title) == new.map(\.title),
                "\(field.rawValue) + \(direction.rawValue) != \(mode.title): \(old.map(\.title)) vs \(new.map(\.title))"
            )
        }
    }

    /// **And two do not, which is the cost of retiring the Order chip — recorded, not hidden.**
    ///
    /// iOS's set has no reversed do-date and no low-priority-first, so `Date` + `Descending` and
    /// `Priority` + `Ascending` fold onto the ascending-side mode and genuinely change what those
    /// users see. Neither was a default, so this reaches only a user who chose one. If this test
    /// ever goes green, either a reversed mode was added or the fold was quietly undone — both are
    /// decisions, and both should fail here first.
    @Test func theTwoUnmappableDirectionsAreKnownToReorderTheList() {
        let tasks = Self.fixture()

        func order(field: TaskSortField, direction: TaskSortDirection) -> [String] {
            tasks.sorted { TaskOrdering.precedes($0, $1, field: field, direction: direction) }.map(\.title)
        }
        func order(mode: CadenceTaskSortMode) -> [String] {
            tasks.sorted { CadenceTaskQuerySupport.sortTasks($0, $1, sortMode: mode) }.map(\.title)
        }

        #expect(order(field: .date, direction: .descending) != order(mode: .doDate))
        #expect(order(field: .priority, direction: .ascending) != order(mode: .priority))
    }

    // MARK: - What is on disk

    /// **The read path, end to end, against a throwaway defaults suite** — never
    /// `UserDefaults.standard`, which on this host is the test runner's own domain.
    ///
    /// Through `withTemporaryDefaults` rather than a hand-rolled suite: a name minted from
    /// `UUID()` strands one more preference plist in the app's own container on every run, which
    /// is T-516 and is guarded by
    /// `CadenceTestTargetHygieneTests.noTestInTheTargetNamesAUserDefaultsSuiteAfterAFreshUUID`.
    /// The helper derives the name from `#function`, so the cost stays at one file forever.
    @Test func theStoredSortModeWinsAndTheRetiredKeysAreTheFallback() throws {
        try withTemporaryDefaults("cadence.tests.todaySortMode") { defaults in
            func read() -> CadenceTaskSortMode {
                TasksPanel.storedSortMode(in: defaults, fallback: .macOSTodayDefault)
            }

            // Nothing stored at all — a fresh install, or a user who never opened the chip.
            #expect(read() == .doDate)

            // Only the retired keys: the pre-upgrade state, for every combination of them.
            defaults.set("Custom", forKey: TasksPanel.legacySortFieldDefaultsKey)
            defaults.set("Descending", forKey: TasksPanel.legacySortDirectionDefaultsKey)
            #expect(read() == .listOrder, "the retired direction must not change the mapping")

            defaults.set("Priority", forKey: TasksPanel.legacySortFieldDefaultsKey)
            #expect(read() == .priority)

            defaults.set("Date", forKey: TasksPanel.legacySortFieldDefaultsKey)
            #expect(read() == .doDate)

            // A retired value that decodes as neither vocabulary still produces a mode.
            defaults.set("Whatever", forKey: TasksPanel.legacySortFieldDefaultsKey)
            #expect(read() == .doDate)

            // The new key wins over the retired one once it exists.
            defaults.set("Custom", forKey: TasksPanel.legacySortFieldDefaultsKey)
            defaults.set(CadenceTaskSortMode.dueDate.rawValue, forKey: TasksPanel.sortModeDefaultsKey)
            #expect(read() == .dueDate)

            // …and an undecodable new key falls back through the retired one rather than crashing.
            defaults.set("notAMode", forKey: TasksPanel.sortModeDefaultsKey)
            #expect(read() == .listOrder)
        }
    }

    /// The retired keys are **read and never written**, so a build rolled back to the two chips
    /// still finds the preference it wrote. Deleting them would have been the destructive option in
    /// a project with no `SchemaMigrationPlan`.
    @Test func theRetiredKeysAreReadButNeverWrittenOrCleared() throws {
        let code = try strippingComments(sourceFile("Cadence/macOS/Views/TasksPanel.swift"))
        #expect(code.contains("legacySortFieldDefaultsKey"))
        #expect(!code.contains("removeObject"))
        #expect(code.components(separatedBy: "UserDefaults.standard.set").count - 1 == 1)
    }

    // MARK: - The chips themselves

    /// **One chip, and the Order chip is gone from Today.** The source pin exists for the T-161
    /// reason the rest of this file exists: the mapping tests above would stay green if the panel
    /// went back to reading `TaskSortField`.
    @Test func macOSTodayDrawsOneSortChipAndNoOrderChip() throws {
        let code = try strippingComments(sourceFile("Cadence/macOS/Views/TasksPanel.swift"))
        #expect(code.components(separatedBy: "CadenceEnumPickerBadge(").count - 1 == 1)
        #expect(!code.contains("\"Order\""))
        #expect(!code.contains("TaskSortField"))
        #expect(!code.contains("TaskSortDirection"))
        #expect(code.contains("CadenceTaskQuerySupport.sortTasks("))
    }

    /// The two chips survive on the surfaces this ticket did **not** touch — All Tasks, Inbox, and
    /// list detail — so a later sweep cannot read the pin above as "the Order chip is retired
    /// app-wide". `TaskSortField` and `TaskSortDirection` are still live persisted vocabulary
    /// there, which is why neither enum lost a case.
    @Test func theOtherMacOSSurfacesKeepTheTwoChipVocabulary() throws {
        for path in [
            "Cadence/macOS/Views/macOSRootSupportViews.swift",
            "Cadence/macOS/Views/ListDetailView.swift"
        ] {
            let code = try strippingComments(sourceFile(path))
            #expect(code.contains("\"Order\""), "\(path) lost its Order chip")
        }
        #expect(TaskSortField.allCases.count == 3)
        #expect(TaskSortDirection.allCases.count == 2)
    }

    /// A chip prints the mode's **title**, not its persisted raw value — `"Do Date"`, never
    /// `"doDate"`. The raw values are `ios.today.sortMode`'s on-disk spelling and could not be
    /// changed to labels without resetting every iOS user's preference, so the badge learned to ask
    /// instead.
    @Test func aSortChipPrintsTheModeTitleRatherThanItsPersistedRawValue() {
        #expect(CadenceTaskSortMode.doDate.rawValue == "doDate")
        #expect(CadenceTaskSortMode.doDate.pickerLabel == "Do Date")
        for mode in CadenceTaskSortMode.allCases {
            #expect(mode.pickerLabel == mode.title)
            #expect(!mode.pickerLabel.isEmpty)
        }
    }

    // MARK: - Fixture

    /// Deliberately tie-heavy and branch-heavy: two days plus undated work, timed and untimed rows
    /// on the same day, every priority, and pairs that agree until `fallbackPrecedes`.
    private static func fixture() -> [AppTask] {
        func task(
            _ title: String,
            scheduled: String = "",
            due: String = "",
            startMin: Int = -1,
            priority: TaskPriority = .none,
            order: Int
        ) -> AppTask {
            let task = AppTask(title: title)
            task.scheduledDate = scheduled
            task.dueDate = due
            task.scheduledStartMin = startMin
            task.priority = priority
            task.order = order
            task.createdAt = Date(timeIntervalSince1970: 1_700_000_000 + Double(order))
            return task
        }

        return [
            task("Alpha", scheduled: "2026-08-11", startMin: 540, priority: .high, order: 3),
            task("Bravo", scheduled: "2026-08-11", priority: .low, order: 1),
            task("Charlie", scheduled: "2026-08-12", startMin: 60, priority: .medium, order: 2),
            task("Delta", due: "2026-08-11", priority: .none, order: 5),
            task("Echo", scheduled: "2026-08-11", startMin: 60, priority: .none, order: 4),
            task("Foxtrot", priority: .high, order: 0),
            task("Golf", scheduled: "2026-08-12", priority: .low, order: 6)
        ]
    }
}

// MARK: - Source-reading helpers

/// Fails unless `name` appears exactly `count` times in each listed file.
///
/// **Exact counts, not "contains".** A file that reverts one of two call sites to a local copy
/// still "contains" the shared name, which is T-161 reproduced inside the test written to prevent
/// it. A count that has to be edited on purpose is the point.
private func expectCallSites(
    of name: String,
    at callSites: [String: Int],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    for (path, expected) in callSites {
        let code = try strippingComments(sourceFile(path))
        let actual = code.components(separatedBy: name).count - 1
        #expect(
            actual == expected,
            "\(path) mentions \(name) \(actual) times, expected \(expected)",
            sourceLocation: sourceLocation
        )
    }
}

/// How many times `needle` appears in an already-comment-stripped slice.
///
/// A literal count, not a regex: every needle it is asked for here is punctuation-heavy SwiftUI
/// chaining, and escaping those into a pattern is how a needle quietly stops matching.
private func occurrences(of needle: String, in source: String) -> Int {
    source.components(separatedBy: needle).count - 1
}

/// Fails if `name` appears anywhere in `Cadence/` as live code rather than inside a comment.
/// Comments are exempt so the tombstones explaining what was removed can stay.
private func expectNoLiveMention(
    of name: String,
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let pattern = "(?<![A-Za-z0-9_])\(name)(?![A-Za-z0-9_])"

    for path in try swiftFiles(under: "Cadence") {
        let code = try strippingComments(sourceFile(path))
        #expect(
            code.range(of: pattern, options: .regularExpression) == nil,
            "\(path) still refers to \(name)",
            sourceLocation: sourceLocation
        )
    }
}

/// How many times `text` appears in `Cadence/` as **live code** rather than inside a comment.
///
/// Returned rather than asserted so one helper serves both an absence assertion and the presence
/// self-check that keeps it from going vacuous. Unlike `expectNoLiveMention` it takes a literal, so
/// it can reach a user-facing string with a space in it; comments are exempt, so the tombstones
/// explaining what was removed can keep saying the words.
private func liveTextOccurrences(of text: String) throws -> Int {
    var total = 0
    var scanned = 0
    for path in try swiftFiles(under: "Cadence") {
        let raw = try sourceFile(path)
        let code = try strippingComments(raw)
        // The stripper blanks comments to spaces of equal length, so an unequal length would mean
        // it had eaten code — and a `<` guard would be red whatever the source said. See
        // `Cadence/Shared/AGENTS.md`.
        guard code.count == raw.count else {
            throw CadenceTodayScanFailure.strippingChangedLength(path)
        }
        scanned += 1
        total += code.components(separatedBy: text).count - 1
    }
    guard scanned > 300 else { throw CadenceTodayScanFailure.tooFewFiles(scanned) }
    return total
}

private enum CadenceTodayScanFailure: Error {
    case strippingChangedLength(String)
    case tooFewFiles(Int)
}

/// The source text of one top-level declaration, from its `struct`/`enum` line to the next
/// top-level declaration in the same file. Crude, and deliberately so: it over-reads rather than
/// under-reads at the tail, which can only make the `!contains` assertions above stricter.
private func declarationBody(of name: String, in path: String) throws -> String {
    let source = try strippingComments(sourceFile(path))
    let pattern = "(?m)^(?:public |private |internal |fileprivate |final |nonisolated )*(?:struct|enum|class|extension)\\s+\(name)\\b"
    guard let start = source.range(of: pattern, options: .regularExpression) else {
        Issue.record("\(path) does not declare \(name)")
        return ""
    }

    let rest = source[start.upperBound...]
    let nextPattern = "(?m)^(?:public |private |internal |fileprivate |final |nonisolated )*(?:struct|enum|class|extension)\\s"
    let end = rest.range(of: nextPattern, options: .regularExpression)?.lowerBound ?? rest.endIndex
    return String(rest[..<end])
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// `enumerator(atPath:)` rather than `enumerator(at:)`: the URL variant yields absolute paths, and
/// `#filePath` can name the repo through a symlinked prefix (`/tmp` against `/private/tmp` on an
/// isolated build tree) that `FileManager` resolves and the literal does not.
private func swiftFiles(under relativeDirectory: String) throws -> [String] {
    let directory = repositoryRoot().appendingPathComponent(relativeDirectory)
    guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else {
        return []
    }
    return enumerator.compactMap { element in
        guard let relativePath = element as? String, relativePath.hasSuffix(".swift") else { return nil }
        return "\(relativeDirectory)/\(relativePath)"
    }
}

private func sourceFile(_ relativePath: String) throws -> String {
    try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

/// Blanks out `//` line comments and `/* */` block comments so the assertions above read code
/// rather than prose.
private func strippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound)))
        }
    }
    return result
}
