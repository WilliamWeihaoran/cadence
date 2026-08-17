import Foundation
import Testing
@testable import Cadence

/// What the iOS task row reads out of a task, now that the row shows a day instead of a timeline
/// slot and lists its unfinished subtasks instead of counting all of them.
///
/// Both live in `Shared/` rather than beside the row: everything under `Cadence/iOS/` is inside
/// `#if os(iOS)` and invisible to this macOS-built target.
@MainActor
struct CadenceTaskRowPresentationTests {
    private func task(scheduled: String, startMin: Int) -> AppTask {
        let task = AppTask(title: "T")
        task.scheduledDate = scheduled
        task.scheduledStartMin = startMin
        return task
    }

    private func subtask(_ title: String, order: Int, isDone: Bool = false) -> Subtask {
        let subtask = Subtask(title: title)
        subtask.order = order
        subtask.isDone = isDone
        return subtask
    }

    /// The row's do-date chip says the **day** and never the slot. `scheduledDateLabel` — which the
    /// list-detail summary and the markdown accessory still read — folds the slot in, and the two
    /// must not converge: a chip reading "3 days ago at 9:30 AM – 10 AM" was three times the width
    /// of its neighbours and pushed the row's metadata onto a second line.
    @Test func theRowsDoDateLabelIsADayEvenWhenTheTaskHasATimelineSlot() {
        let todayKey = DateFormatters.todayKey()
        let scheduled = task(scheduled: todayKey, startMin: 570)

        #expect(CadenceTaskPresentationSupport.scheduledDayLabel(for: scheduled) == "Today")

        // The slot is still readable — just not from the row.
        let withSlot = CadenceTaskPresentationSupport.scheduledDateLabel(for: scheduled)
        #expect(withSlot != CadenceTaskPresentationSupport.scheduledDayLabel(for: scheduled))
        #expect(withSlot.contains("9:30"))
    }

    @Test func theRowsDoDateLabelIsTheSameDayWithOrWithoutASlot() {
        let todayKey = DateFormatters.todayKey()

        #expect(
            CadenceTaskPresentationSupport.scheduledDayLabel(for: task(scheduled: todayKey, startMin: 570))
                == CadenceTaskPresentationSupport.scheduledDayLabel(for: task(scheduled: todayKey, startMin: -1))
        )
    }

    /// Unfinished only, in `order`. A finished subtask says nothing a row needs to carry, and the
    /// tally that used to report one ("1/3") is gone.
    @Test func rowSubtasksAreUnfinishedOnlyAndInOrder() {
        let task = AppTask(title: "T")
        task.subtasks = [
            subtask("Third", order: 2),
            subtask("Done", order: 1, isDone: true),
            subtask("First", order: 0)
        ]

        #expect(CadenceTaskPresentationSupport.unfinishedSubtasks(for: task).map(\.title) == ["First", "Third"])
    }

    @Test func rowSubtasksAreEmptyWhenThereAreNoneAndWhenTheyAreAllDone() {
        let none = AppTask(title: "T")
        #expect(CadenceTaskPresentationSupport.unfinishedSubtasks(for: none).isEmpty)

        let allDone = AppTask(title: "T")
        allDone.subtasks = [subtask("A", order: 0, isDone: true), subtask("B", order: 1, isDone: true)]
        #expect(CadenceTaskPresentationSupport.unfinishedSubtasks(for: allDone).isEmpty)

        // The tally the rows replaced still reports the finished ones, because the inspector's
        // "Subtasks" heading reads it.
        #expect(CadenceTaskPresentationSupport.subtaskProgress(for: allDone)?.compactLabel == "2/2")
    }

    /// **Capped, and this test used to assert the opposite.** Uncapped was the first decision and it
    /// was reversed after being seen on a phone: one row with four unfinished subtasks stood ~290pt
    /// and iPhone Today fell from about five visible tasks to two and a half, so a checklist on one
    /// task hid the rest of the day. The row still *names* what is left rather than counting it —
    /// which is what the old `0/3` chip got wrong — it just stops naming at the limit and says how
    /// many remain. See `CadenceRowSubtaskCapTests` for the boundary cases.
    @Test func rowSubtasksStopAtTheLimitAndCountTheRest() {
        let task = AppTask(title: "T")
        task.subtasks = (0..<12).map { subtask("S\($0)", order: $0) }

        let rows = CadenceTaskPresentationSupport.unfinishedSubtasks(for: task)
        #expect(rows.count == CadenceTaskPresentationSupport.rowSubtaskLimit)
        #expect(rows.first?.title == "S0")
        #expect(CadenceTaskPresentationSupport.hiddenSubtaskCount(for: task) == 12 - CadenceTaskPresentationSupport.rowSubtaskLimit)
    }
}

struct CadenceTaskPresentationSupportTests {
    @Test func plainPreviewUsesDisplayTextForCadenceReferences() {
        let markdown = """
        ## Plan
        - [ ] Review [[task:22222222-2222-2222-2222-222222222222|Ship iOS notes]]
        See [[note:11111111-1111-1111-1111-111111111111|Project Notes]]
        """

        let preview = CadenceTaskPresentationSupport.plainPreviewText(from: markdown)

        #expect(preview == "Plan Review Ship iOS notes See Project Notes")
    }

    @Test func plainPreviewNormalizesIOSNativeListMarkers() {
        let markdown = """
        • Capture inbox
        ○ Draft note
        ✓ Review note
        """

        let preview = CadenceTaskPresentationSupport.plainPreviewText(from: markdown)

        #expect(preview == "Capture inbox Draft note Review note")
    }

    @Test func markdownPreviewRemovesCommonInlineSyntax() {
        let markdown = """
        # Meeting Notes
        - [x] Ship **live preview**
        See [docs](https://example.com) and `inline code`
        """

        let preview = CadenceMarkdownPresentationSupport.plainPreviewText(from: markdown, limit: 80)

        #expect(preview == "Meeting Notes Ship live preview See docs and inline code")
    }

    @Test func markdownPreviewUsesImageAltTextForInlineImages() {
        let markdown = """
        Capture ![Whiteboard](cadence-image://22222222-2222-2222-2222-222222222222) after standup.
        """

        let preview = CadenceMarkdownPresentationSupport.plainPreviewText(from: markdown)

        #expect(preview == "Capture Whiteboard after standup.")
    }

    @Test func markdownPreviewNormalizesMarkdownInsideLinkLabels() {
        let markdown = """
        Read [**Design** `API`](https://example.com) before planning.
        """

        let preview = CadenceMarkdownPresentationSupport.plainPreviewText(from: markdown)

        #expect(preview == "Read Design API before planning.")
    }

    @Test func markdownPreviewNormalizesNestedInlineMarkdown() {
        let markdown = """
        - [ ] **Review `API` and [docs](https://example.com)**
        """

        let preview = CadenceMarkdownPresentationSupport.plainPreviewText(from: markdown)

        #expect(preview == "Review API and docs")
    }

    @Test func markdownPreviewUsesSharedParserForRichBlocks() {
        let markdown = """
        # _Launch_ Notes
        > Review __copy__ with [[note:11111111-1111-1111-1111-111111111111|Design Notes]]

        ![Screenshot](cadence-image://22222222-2222-2222-2222-222222222222)

        [[task:33333333-3333-3333-3333-333333333333|Finish TestFlight checklist]]

        | Area | Owner |
        | --- | --- |
        | iOS | William |
        """

        let preview = CadenceMarkdownPresentationSupport.plainPreviewText(from: markdown)

        #expect(preview == "Launch Notes Review copy with Design Notes Screenshot Finish TestFlight checklist Area Owner iOS William")
    }

    @Test func markdownPreviewPreservesCodeContentWithoutFenceMarkers() {
        let markdown = """
        Before
        ```swift
        let cadence = "iOS"
        ```
        After
        """

        let preview = CadenceMarkdownPresentationSupport.plainPreviewText(from: markdown)

        #expect(preview == #"Before let cadence = "iOS" After"#)
    }
}

/// The row's subtask cap.
///
/// Uncapped shipped first and was measured on a phone: one row with four unfinished subtasks stood
/// ~290pt and iPhone Today fell from about five visible tasks to two and a half. These pin the
/// number as a decision rather than a literal, and pin that the list and the overflow count are
/// derived from the same source so they cannot disagree about what "more" means.
@MainActor
struct CadenceRowSubtaskCapTests {
    private func task(unfinished: Int, finished: Int = 0) -> AppTask {
        let task = AppTask(title: "Parent")
        var subtasks: [Subtask] = []
        for index in 0..<unfinished {
            let subtask = Subtask(title: "open \(index)")
            subtask.order = index
            subtask.isDone = false
            subtasks.append(subtask)
        }
        for index in 0..<finished {
            let subtask = Subtask(title: "done \(index)")
            subtask.order = unfinished + index
            subtask.isDone = true
            subtasks.append(subtask)
        }
        task.subtasks = subtasks
        return task
    }

    @Test func aShortChecklistIsShownWholeAndClaimsNoOverflow() {
        let short = task(unfinished: 2)
        #expect(CadenceTaskPresentationSupport.unfinishedSubtasks(for: short).count == 2)
        #expect(CadenceTaskPresentationSupport.hiddenSubtaskCount(for: short) == nil)
    }

    /// Exactly at the limit must not claim "+0 more" — the row draws nothing rather than a line
    /// announcing that nothing is hidden.
    @Test func exactlyTheLimitHidesNothing() {
        let atLimit = task(unfinished: CadenceTaskPresentationSupport.rowSubtaskLimit)
        #expect(CadenceTaskPresentationSupport.unfinishedSubtasks(for: atLimit).count == CadenceTaskPresentationSupport.rowSubtaskLimit)
        #expect(CadenceTaskPresentationSupport.hiddenSubtaskCount(for: atLimit) == nil)
    }

    @Test func aLongChecklistIsCappedAndCountsTheRest() {
        let long = task(unfinished: 7)
        #expect(CadenceTaskPresentationSupport.unfinishedSubtasks(for: long).count == CadenceTaskPresentationSupport.rowSubtaskLimit)
        #expect(CadenceTaskPresentationSupport.hiddenSubtaskCount(for: long) == 7 - CadenceTaskPresentationSupport.rowSubtaskLimit)
    }

    /// The shown rows and the overflow count come from one filtered, sorted source, so finished
    /// subtasks cannot inflate the "+N more" beyond what opening the task would reveal.
    @Test func finishedSubtasksCountTowardsNeitherTheListNorTheOverflow() {
        let mixed = task(unfinished: 5, finished: 4)
        #expect(CadenceTaskPresentationSupport.allUnfinishedSubtasks(for: mixed).count == 5)
        #expect(CadenceTaskPresentationSupport.unfinishedSubtasks(for: mixed).allSatisfy { !$0.isDone })
        #expect(CadenceTaskPresentationSupport.hiddenSubtaskCount(for: mixed) == 5 - CadenceTaskPresentationSupport.rowSubtaskLimit)
    }

    @Test func theCappedRowsAreTheFirstOnesInOrder() {
        let long = task(unfinished: 6)
        let shown = CadenceTaskPresentationSupport.unfinishedSubtasks(for: long)
        #expect(shown.map(\.order) == Array(0..<CadenceTaskPresentationSupport.rowSubtaskLimit))
    }
}

/// The iOS task row's measurements, which used to come from **two** axes — the width it was drawn
/// at and an `iOSTaskRowDensity` each call site chose for itself. On a phone that meant Today's
/// rows and Inbox's rows, one tab of the same tab bar apart, disagreed: one-line titles against
/// two-line titles, 64 characters of notes preview against 80.
///
/// `Cadence/iOS/` is inside `#if os(iOS)` and invisible to this macOS-built target, so the metrics
/// live in `Shared/` — which is also what makes "there is only one axis" assertable at all.
struct CadenceTaskRowMetricsTests {
    /// The defect T-78 named, pinned as its inverse: the title line limit is one number, so no
    /// surface and no width can shorten it. Break this to 1 and iPhone Today goes back to
    /// truncating titles its neighbouring tabs wrap.
    @Test func aTaskTitleGetsTheSameNumberOfLinesEverywhere() {
        #expect(CadenceTaskRowMetrics.titleLineLimit == 2)
    }

    /// The row varies by width and by nothing else. `metrics(isRegularWidth:)` is total over its
    /// only input, so the two results below are the complete set of row shapes the app has — if a
    /// third ever appears it will have to come from a new parameter, and this stops one being added
    /// silently.
    @Test func thereAreExactlyTwoRowShapesAndWidthPicksBetweenThem() {
        #expect(CadenceTaskRowMetrics.metrics(isRegularWidth: true) == CadenceTaskRowMetrics.regularWidth)
        #expect(CadenceTaskRowMetrics.metrics(isRegularWidth: false) == CadenceTaskRowMetrics.compactWidth)
        #expect(CadenceTaskRowMetrics.regularWidth != CadenceTaskRowMetrics.compactWidth)
    }

    /// A wider row is never the tighter of the two. The old axis managed exactly this inversion:
    /// `.compact` allowed 80 characters of notes preview while `.regular` allowed 64 at the same
    /// width, so the phone's Today row said *less* of the title and *more* of the note about it.
    @Test func theWiderRowIsRoomierOnEveryAxisItVaries() {
        let wide = CadenceTaskRowMetrics.regularWidth
        let narrow = CadenceTaskRowMetrics.compactWidth

        #expect(wide.horizontalPadding > narrow.horizontalPadding)
        #expect(wide.verticalPadding > narrow.verticalPadding)
        #expect(wide.contentSpacing > narrow.contentSpacing)
        #expect(wide.summarySpacing > narrow.summarySpacing)
        #expect(wide.badgeSpacing > narrow.badgeSpacing)
        #expect(wide.completionGlyphSize > narrow.completionGlyphSize)
        #expect(wide.secondaryFontSize > narrow.secondaryFontSize)
        #expect(wide.secondaryLineLimit >= narrow.secondaryLineLimit)
        #expect(wide.notesPreviewLimit > narrow.notesPreviewLimit)
    }

    /// The completion glyph has to leave room for the 44pt touch target the row expands it to —
    /// `iOSExpandedHitArea((44 - glyph) / 2)` goes negative if a glyph ever exceeds it.
    @Test func theCompletionGlyphAlwaysFitsInsideItsTouchTarget() {
        for metrics in [CadenceTaskRowMetrics.regularWidth, CadenceTaskRowMetrics.compactWidth] {
            #expect(metrics.completionGlyphSize > 0)
            #expect(metrics.completionGlyphSize <= 44)
            #expect(metrics.completionGlyphSize >= CadenceTaskRowMetrics.completionCircleDiameter)
        }
    }
}
