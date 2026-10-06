import CoreGraphics
import Foundation
import Testing
@testable import Cadence

/// macOS Today's panel had five chips on one row and three section headings, and none of them read
/// a metrics type (`docs/TODO.md` T-597).
///
/// Two shapes, one cause. The Cancelled chip set its own `10` and `6/3` while the four chips beside
/// it — the do-date pill, the due-date pill, the bundle badge, the estimate chip — all read
/// `CadenceTaskRowMetrics.desktop.secondaryFontSize` at `4/2`; and two *adjacent* section headings
/// were padded identically except for one point of bottom inset, over a gutter typed out as a bare
/// `16` at six sites in two files. iOS puts every one of these in `CadenceTodaySectionMetrics`,
/// keyed on layout. This is that shape for the Mac.
///
/// The value assertions and the source assertions are both here because either alone goes quietly
/// green: a value test cannot see a *sixth* chip added with its own literals, and a source test
/// cannot see the shared figure being retuned.
struct CadenceTasksPanelMetricsTests {
    private static func panelSource() throws -> String {
        CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TasksPanel.swift")
        )
    }

    private static func sectionSource() throws -> String {
        CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TasksPanelSectionViews.swift")
        )
    }

    // MARK: - T-1432(3): the title outranks its own decoration

    /// **The owner photographed a Today row whose title read `check fo…`** — about ten characters —
    /// beside three metadata chips, one of which had wrapped onto three lines (`51` / `days` /
    /// `ago`) while the two others were truncated mid-glyph. Every flexible child of the row's one
    /// `HStack` sat at the same layout priority, so the stack divided the row between the title and
    /// each chip's `Text` in roughly equal shares. The title is the only part of a row that
    /// identifies its task.
    ///
    /// Three claims, and each one is a separate way the defect comes back:
    ///
    /// 1. the title carries `.layoutPriority(1)`, so it is laid out before the decoration;
    /// 2. the trailing decoration is **one** child of the row's stack — a `ViewThatFits` — rather
    ///    than four siblings, because four siblings cannot shed as a group;
    /// 3. the due-date chip's `Text` is `.lineLimit(1)`, which is what makes wrapping impossible
    ///    rather than merely unlikely.
    ///
    /// Source-scanned because SwiftUI's stack allocation is not reachable from a unit test: there
    /// is no seam that reports which subview won the width.
    @Test func theRowsTitleIsLaidOutBeforeItsMetadata() throws {
        let row = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TasksPanelComponents.swift")
        )
        let body = try #require(
            CadenceSourceScan.declarationBody("struct MacTaskRow: View", in: row),
            "non-vacuity: MacTaskRow is gone or its braces do not balance"
        )

        // 1. The title, and only the title, is promoted.
        #expect(body.contains(".layoutPriority(1)"))
        #expect(body.components(separatedBy: ".layoutPriority(").count - 1 == 1)
        let title = try #require(body.range(of: "Text(TaskTitleSupport.displayTitle(task.title"))
        #expect(
            String(body[title.lowerBound...].prefix(400)).contains(".layoutPriority(1)"),
            "the row's promoted subview is no longer its title"
        )

        // 2. The decoration is one shedding child, not four siblings.
        #expect(body.contains("ViewThatFits(in: .horizontal)"))
        #expect(body.contains("metadataStrip"))
        // Two wide readings and one narrow one. Counted over the call spellings rather than the
        // name, so the declaration itself is not one of the three.
        #expect(
            body.components(separatedBy: "metadataRow(showsEstimate: true").count - 1 == 2,
            "the strip no longer offers two progressively narrower wide readings"
        )
        #expect(
            body.components(separatedBy: "metadataRow(showsEstimate: false, showsBundle: false)").count - 1 == 1,
            "the strip has no last-resort reading to shed down to"
        )

        // 3. The chip that wrapped cannot wrap.
        let dueChip = try #require(
            CadenceSourceScan.declarationBody("private var dueDateBadgeList: some View", in: row)
        )
        #expect(dueChip.contains("Text(DateFormatters.relativeDate(from: task.dueDate))"))
        #expect(dueChip.contains(".lineLimit(1)"))
    }

    // MARK: - The row's fifth chip

    /// The four chips this one sits beside all read the same two figures. `.desktop` exists so they
    /// do not drift, and the one chip that never read it was drawing a point smaller and two points
    /// wider than the rest of the row.
    @Test func theCancelledChipIsDrawnLikeTheFourChipsBesideIt() throws {
        #expect(CadenceTaskRowMetrics.desktop.secondaryFontSize == 11)

        let row = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TasksPanelComponents.swift")
        )

        // Non-vacuity: the right file, past the comment stripper, still drawing the chip.
        #expect(row.contains("struct MacTaskRow: View"))
        let chip = try #require(row.range(of: #"Text("Cancelled")"#))
        let window = String(row[chip.lowerBound...].prefix(400))

        #expect(window.contains("size: metrics.secondaryFontSize"))
        // T-617 hoisted the plate into `CadenceTaskChipPadding`; the chip still draws 4/2, and that
        // it still *reads the same name as the four beside it* is what this line is about.
        #expect(window.contains(".padding(.horizontal, CadenceTaskChipPadding.desktopHorizontal)"))
        #expect(window.contains(".padding(.vertical, CadenceTaskChipPadding.desktopVertical)"))
        #expect(!window.contains("size: 10"))
        #expect(!window.contains(".padding(.horizontal, 6)"))
        #expect(!window.contains(".padding(.vertical, 3)"))

        // Counted rather than only present: five chips read the secondary size now (the do-date
        // pill spells it twice, once on the hidden `Text` that reserves its width), and a sixth
        // chip arriving with its own literal has to change this number to land.
        #expect(
            CadenceSourceScan.matchCount("size: metrics\\.secondaryFontSize", in: row) == 6
        )
        #expect(CadenceSourceScan.matchCount("size: 10", in: row) == 0)
    }

    // MARK: - The chip plate, both platforms in one place

    /// **T-617.** The macOS row typed its chip plate inline — `4` horizontal, `2` vertical — at
    /// **four** sites in `TasksPanelComponents`: the Cancelled pill, the do-date pill, the due-date
    /// pill and the estimate chip. (`docs/TODO.md` said five and the file's own comment names the
    /// bundle badge as a fifth; the badge draws no background, so it has no plate and no inset.)
    /// iOS had already named the same measurement, on `iOSTaskAttributeChipSize` — which is two
    /// homes for one thing, the shape `CadenceTaskRowMetrics.desktop` exists to close.
    ///
    /// So the padding is stated once, in one shared type, **per platform**. The two numbers are
    /// deliberately different and this hoist changed no pixel: nobody has put the two chips side by
    /// side, and converging them would be a visual change nobody reviewed. Naming them together is
    /// what makes the next divergence an edit here rather than a fifth literal there.
    ///
    /// Value and source assertions both, for the reason at the top of this file: a value test
    /// cannot see a fifth chip spelled inline, and a source test cannot see the figure retuned.
    @Test func bothPlatformsStateTheirChipPlateInOnePlace() throws {
        #expect(CadenceTaskChipPadding.desktopHorizontal == 4)
        #expect(CadenceTaskChipPadding.desktopVertical == 2)
        #expect(CadenceTaskChipPadding.iOSStandardHorizontal == 9)
        #expect(CadenceTaskChipPadding.iOSRowHorizontal == 7)

        // One home is not one value. If these ever become equal it should be because someone
        // looked at both chips and decided so, not because a hoist quietly merged them.
        #expect(CadenceTaskChipPadding.desktopHorizontal != CadenceTaskChipPadding.iOSRowHorizontal)
        #expect(CadenceTaskChipPadding.iOSRowHorizontal < CadenceTaskChipPadding.iOSStandardHorizontal)

        let row = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TasksPanelComponents.swift")
        )
        #expect(row.contains("struct MacTaskRow: View"), "non-vacuity: wrong file read")

        // The call sites read the name. Counted exactly, and each one also named below: a value-only
        // assertion stays green while a fifth chip spells `4` and `2` out again.
        #expect(
            CadenceSourceScan.matchCount(#"CadenceTaskChipPadding\.desktopHorizontal"#, in: row) == 4
        )
        #expect(
            CadenceSourceScan.matchCount(#"CadenceTaskChipPadding\.desktopVertical"#, in: row) == 4
        )
        #expect(CadenceSourceScan.matchCount(#"\.padding\(\.horizontal, 4\)"#, in: row) == 0)
        #expect(CadenceSourceScan.matchCount(#"\.padding\(\.vertical, 2\)"#, in: row) == 0)

        // Named, so a count that still adds to four while one chip drifts back cannot pass. The
        // four anchors are in file order, so each region runs from its own chip to the next one and
        // the regions do not overlap — one read of each figure in each, no chip covering another.
        let chips = [
            #"Text("Cancelled")"#,
            "private var doDatePill",
            "private var dueDateBadgeList",
            "struct MacTaskRowEstimateChip",
        ]
        var cursor = row.startIndex
        var bounds: [String.Index] = []
        for chip in chips {
            let found = try #require(
                row.range(of: chip, range: cursor..<row.endIndex),
                "\(chip) is no longer drawn by this row, or moved above the chip before it"
            )
            bounds.append(found.lowerBound)
            cursor = found.upperBound
        }
        for (offset, chip) in chips.enumerated() {
            let end = offset + 1 < bounds.count ? bounds[offset + 1] : row.endIndex
            let region = String(row[bounds[offset]..<end])
            #expect(
                CadenceSourceScan.matchCount(#"CadenceTaskChipPadding\.desktopHorizontal"#, in: region) == 1,
                "\(chip) does not read the shared horizontal inset exactly once"
            )
            #expect(
                CadenceSourceScan.matchCount(#"CadenceTaskChipPadding\.desktopVertical"#, in: region) == 1,
                "\(chip) does not read the shared vertical inset exactly once"
            )
        }

        // The other half of the one home: iOS reads it too, or the type is a macOS field wearing a
        // shared name.
        let mobile = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskDetailComponents.swift")
        )
        #expect(mobile.contains("enum iOSTaskAttributeChipSize"), "non-vacuity: wrong file read")
        #expect(
            CadenceSourceScan.matchCount(#"CadenceTaskChipPadding\.iOSStandardHorizontal"#, in: mobile) == 1
        )
        #expect(
            CadenceSourceScan.matchCount(#"CadenceTaskChipPadding\.iOSRowHorizontal"#, in: mobile) == 1
        )
        #expect(!mobile.contains("case .standard: return 9"))
        #expect(!mobile.contains("case .row: return 7"))
    }

    // MARK: - T-1503: one header row, and the corner each control stands in

    /// **The owner asked for three moves and they were one change.** Today's task column spent two
    /// header rows — the day over `Today <n>` with the capture `+` floated trailing, and a second
    /// row under it holding the Sort pill and nothing else. `todayPanelHeaderHeight` is the band
    /// **all three** of Today's columns reserve so their dividers meet at one line, so that second
    /// row was charged to the notes and timeline columns too, which had nothing to put in it. What
    /// the owner photographed was the consequence in a pane with no sort pill at all: the dead gap
    /// between the notes column's tab strip and its markdown toolbar.
    ///
    /// **It is one constant, not three** — that is the finding, and it is why the third part of the
    /// ticket is a single line. Each panel is asserted to read the name exactly once, so a column
    /// that goes back to typing its own figure fails here rather than quietly unaligning a divider.
    ///
    /// **80 is the notes column's measured header**, not a guess: `NSHostingView.fittingSize` at
    /// both 300pt and 440pt gives notes 49 + a 30pt tab strip = 79, tasks 68 (pill or no pill), and
    /// the timeline 49. One band has to be the tallest column's, and the tallest is now 79.
    ///
    /// Value and source both, for the reason at the top of this file: the value alone cannot see a
    /// fourth column typing `100`, and the source alone cannot see the band retuned back up.
    @Test func todaysThreeColumnsShareOneHeaderBandAndItIsTheShorterOne() throws {
        #expect(todayPanelHeaderHeight == 80)

        for path in [
            "Cadence/macOS/Views/NotePanel.swift",
            "Cadence/macOS/Views/TasksPanel.swift",
            "Cadence/macOS/Views/SchedulePanel.swift",
        ] {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            #expect(code.contains("useStandardHeaderHeight"), "non-vacuity: \(path) read as the wrong file")
            #expect(
                CadenceSourceScan.matchCount("todayPanelHeaderHeight", in: code) == 1,
                "\(path) does not read the shared band exactly once"
            )
            #expect(
                CadenceSourceScan.matchCount(#"height: 100(?![0-9.])"#, in: code) == 0,
                "\(path) types a header band of its own"
            )
        }
    }

    /// The pill took the corner the `+` vacated, and the row that carried the pill is gone rather
    /// than merely emptied — an `HStack` left in place with its one child removed is how the band
    /// would quietly need its 20pt back.
    ///
    /// **The chip is still built by the panel**, in the header's trailing slot rather than in a row
    /// of its own. That is not incidental: `CadenceTodayUnificationTests` counts
    /// `CadenceEnumPickerBadge(` in `TasksPanel.swift` to pin that Today offers one chip and has
    /// not gone back to the retired `TaskSortField` vocabulary, and a header that *built* the chip
    /// would have moved that call out from under the count. So `TasksPanelHeader` takes a slot.
    ///
    /// **The pill keeps its label.** A glyph-only sort control would have to be hovered to answer
    /// the one question it exists to answer, and the width is there: the pill is ~90pt with its own
    /// `minimumScaleFactor`, against the ~120pt `+ New Task` pill that was cut down to a glyph for
    /// crowding the date at the task column's 300pt minimum.
    @Test func todaysSortPillIsInTheHeadersTrailingSlotAndTheSecondRowIsGone() throws {
        let panel = try Self.panelSource()
        #expect(panel.contains("struct TasksPanel"), "non-vacuity: wrong file read")
        #expect(
            !panel.contains("private var controlsBar"),
            "Today's header has a second row again, and all three columns are paying for it"
        )
        let header = try #require(
            CadenceSourceScan.functionBody(named: "headerSection", in: panel),
            "TasksPanel.headerSection moved or was renamed"
        )
        // In the header's trailing slot, and nowhere else in the panel: the second row is the one
        // thing this whole change is for.
        #expect(
            header.contains(#"CadenceEnumPickerBadge(title: "Sort", selection: $localSortMode)"#),
            "Today's Sort chip is not in its header's trailing slot"
        )
        #expect(header.contains("if enableControls, options.showsSort"))
        #expect(
            CadenceSourceScan.matchCount(#"CadenceEnumPickerBadge\("#, in: panel) == 1,
            "the panel draws a second chip somewhere outside its header"
        )

        let support = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TasksPanelSupportViews.swift")
        )
        let row = try #require(
            CadenceSourceScan.declarationBody("struct TasksPanelHeader<Trailing: View>: View", in: support),
            "non-vacuity: TasksPanelHeader is gone, un-slotted, or its braces do not balance"
        )
        #expect(row.contains("@ViewBuilder let trailing: Trailing"))
        // The slot is forwarded, not decided here.
        #expect(!row.contains("CadenceEnumPickerBadge"), "the header builds Today's chip itself")
        // And the corner holds one control: the capture button left, and took its environment.
        #expect(!row.contains("Image(systemName:"), "the header draws a glyph control of its own again")
        #expect(!row.contains("TaskCreationManager"), "the header still reaches the composer directly")
    }

    /// **The `+` is the page's, and it is the macOS floating button that already existed.**
    /// `FloatingNewTaskButton` is what `TasksPageView` and `ListTasksView` already capture through;
    /// `iOSFloatingCreateTaskButton` is the same pair's iOS half and is unreachable from a
    /// `#if os(macOS)` file. Nothing was invented for Today, which is the rule T-1412 spent a whole
    /// ticket restoring for the tag chip.
    ///
    /// The seed is pinned too: the header button this replaces opened the composer with today's do
    /// date filled in, and a move that dropped that would be a behaviour change wearing a layout
    /// change's clothes.
    @Test func todaysCaptureButtonIsThePagesFloatingOneAndNotASecondSpelling() throws {
        let page = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TodayView.swift")
        )
        #expect(page.contains("struct TodayView: View"), "non-vacuity: wrong file read")
        #expect(CadenceSourceScan.matchCount(#"\.floatingNewTaskButton \{"#, in: page) == 1)
        #expect(page.contains("doDateKey: DateFormatters.todayKey()"), "the move dropped the day seed")
        #expect(!page.contains("Image(systemName:"), "Today spells a second capture circle of its own")
        #expect(
            page.contains("bottomClearance: layout == .tasksOnly ? FloatingNewTaskButton.scrollClearance : 0"),
            "the task column can be buried under the page's own button on the one layout where it is the page"
        )

        // The button states its own footprint rather than leaving the clearance to be guessed at.
        #expect(
            FloatingNewTaskButton.scrollClearance
                == FloatingNewTaskButton.diameter + FloatingNewTaskButton.edgeInset
        )
        #expect(FloatingNewTaskButton.scrollClearance == 78)
        let root = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/macOSRootSupportViews.swift")
        )
        let button = try #require(
            CadenceSourceScan.declarationBody("struct FloatingNewTaskButton: View", in: root),
            "non-vacuity: FloatingNewTaskButton is gone or its braces do not balance"
        )
        #expect(
            !button.contains(".padding(.trailing, 24)"),
            "the edge inset is typed again beside the constant that states it"
        )
        #expect(!button.contains("width: 54"), "the diameter is typed again beside the constant that states it")
    }

    // MARK: - The panel's headings

    /// **Two adjacent headings, one point apart.** The intent groups closed at 5 and the Completed
    /// group under them at 6, on the same page, in the same file. Neither number carried a reason,
    /// so 6 wins on the only count available: `.padding(.bottom, 6)` stands at five sites under
    /// `Cadence/macOS/` against one for `5`.
    @Test func thePanelsTwoSectionHeadingsAreOneHeading() throws {
        #expect(TasksPanelMetrics.sectionHeaderTopInset == 16)
        #expect(TasksPanelMetrics.sectionHeaderBottomInset == 6)
        #expect(TasksPanelMetrics.sectionHeaderTopInset > TasksPanelMetrics.sectionHeaderBottomInset)

        let sections = try Self.sectionSource()
        #expect(sections.contains("struct TasksPanelIntentSectionView: View"))
        #expect(sections.contains("struct TasksPanelCompletedSectionView: View"))

        // Two headings, both reading both figures.
        #expect(
            CadenceSourceScan.matchCount("TasksPanelMetrics\\.sectionHeaderTopInset", in: sections) == 2
        )
        #expect(
            CadenceSourceScan.matchCount("TasksPanelMetrics\\.sectionHeaderBottomInset", in: sections) == 2
        )
        #expect(!sections.contains(".padding(.bottom, 5)"))
        #expect(!sections.contains(".padding(.bottom, 6)"))
        #expect(!sections.contains(".padding(.top, 16)"))
    }

    /// The gutter, at all six sites that were typing it: two headings, the controls bar, the
    /// overdue heading, and the two overdue card stacks — plus the row inset, which is the same
    /// number *by rule* rather than by coincidence.
    @Test func thePanelStatesItsGutterOnce() throws {
        #expect(TasksPanelMetrics.horizontalInset == 16)

        let panel = try Self.panelSource()
        #expect(panel.contains("struct TasksPanel"))
        // **This was a count, and the count was wrong three times in two days** -- 4, then 5 when
        // [[T-869]] added a reorder-failure notice, then 2 when [[T-1042]]'s regroup removed the
        // sections that read it. Each move was a legitimate change failing a test that pinned a
        // number instead of a rule. What the rule actually says is *nothing retypes the gutter*, and
        // that is the assertion below; the panel merely has to read the constant at least once, so
        // the sweep is not vacuous.
        #expect(
            CadenceSourceScan.matchCount("TasksPanelMetrics\\.horizontalInset", in: panel) >= 1,
            "the panel no longer reads its own gutter constant, so the literal check below proves nothing"
        )
        #expect(!panel.contains(".padding(.horizontal, 16)"))

        let sections = try Self.sectionSource()
        // Three: the two headings, and the row inset that is documented as matching them.
        #expect(
            CadenceSourceScan.matchCount("TasksPanelMetrics\\.horizontalInset", in: sections) == 3
        )
        #expect(!sections.contains(".padding(.horizontal, 16)"))
        #expect(!sections.contains("todayRowLeadingInset: CGFloat = 16"))
    }

    /// **And it is deliberately not the list detail's**, which is the half of the ticket that is a
    /// judgement rather than a hoist. `TaskListDisplayMetrics.headerHorizontalInset` is 24 over rows
    /// indented 52 to clear their own leading furniture; the panel's rows start at `MacTaskRow`'s
    /// own horizontal padding, so a 24pt heading over them would be indented from the rows it heads
    /// — the defect `CadencePageHeaderMetrics` keeps its own gutter to avoid.
    @Test func thePanelGutterIsThePanesAndNotThePages() {
        let row = CadenceTaskRowMetrics.desktop.horizontalPadding

        #expect(TasksPanelMetrics.horizontalInset < TaskListDisplayMetrics.headerHorizontalInset)
        #expect(abs(TasksPanelMetrics.horizontalInset - row) <= 2, "the heading sits over its rows")
        #expect(
            TaskListDisplayMetrics.headerHorizontalInset - row > 2,
            "the list detail's inset stopped clearing its own furniture; re-decide the panel's"
        )
    }

    // MARK: - T-680: three dead `allTasks` parameters

    /// `TasksPanelCompletedSectionView.allTasks` was a stored property no line of `body` read.
    /// Swift does not warn on an unread stored property, so it survived every green run; only a
    /// source scan can see it. Scoped to the one call site rather than the whole file, because
    /// `TasksPanel` legitimately threads its own `allTasks` into `TasksPanelDerivedState` and
    /// `TasksPanelDropCoordinator` two call sites away, and a whole-file needle would not
    /// distinguish "removed from the section view" from "never had one to begin with".
    @Test func thePanelsCompletedSectionNoLongerCarriesTheDeadAllTasksParameter() throws {
        let panel = try Self.panelSource()
        let completedSection = try #require(
            CadenceSourceScan.functionBody(named: "completedSection", in: panel),
            "TasksPanel.completedSection moved or was renamed"
        )
        #expect(completedSection.contains("TasksPanelCompletedSectionView("))
        #expect(
            !completedSection.contains("allTasks:"),
            "TasksPanel still threads allTasks into TasksPanelCompletedSectionView"
        )

        let sections = try Self.sectionSource()
        let completedView = try #require(
            CadenceSourceScan.declarationBody("struct TasksPanelCompletedSectionView: View", in: sections)
        )
        #expect(
            !completedView.contains("let allTasks:"),
            "TasksPanelCompletedSectionView still declares the dead allTasks stored property"
        )
    }

    // MARK: - T-1504: an environment value nobody reads

    /// **`TasksPanel` held `@Environment(TaskCreationManager.self)` and no line of it read the
    /// value.** Swift does not warn on an unread stored property, so nothing but a source scan can
    /// see it. It does not crash — an `@Environment` value that is never read is never resolved —
    /// which is exactly why it survived: it costs nothing at runtime and states a dependency the
    /// panel does not have, so every host of it reads as needing a create manager installed. Same
    /// shape as the dead `allTasks` parameter above.
    ///
    /// The relation, not just the deletion: Today's `+` is the page's, not the panel's
    /// (`todaysCaptureButtonIsThePagesFloatingOneAndNotASecondSpelling`), so the frame that
    /// presents the create sheet is `TodayView` — it must still declare the value **and call it**.
    /// Deleting the line from the wrong file of the two leaves this red.
    @Test func thePanelDoesNotHoldTheCreateManagerItNeverAsksAnythingOf() throws {
        let panel = try Self.panelSource()
        #expect(panel.contains("struct TasksPanel: View"), "non-vacuity: wrong file read")
        #expect(
            CadenceSourceScan.matchCount(#"TaskCreationManager"#, in: panel) == 0,
            "TasksPanel still reaches for a create manager no line of it uses"
        )

        let today = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TodayView.swift")
        )
        #expect(today.contains("struct TodayView"), "non-vacuity: wrong file read")
        #expect(
            CadenceSourceScan.matchCount(
                #"@Environment\(TaskCreationManager\.self\)"#,
                in: today
            ) == 1,
            "Today no longer declares the create manager its floating + presents through"
        )
        #expect(
            CadenceSourceScan.matchCount(#"taskCreationManager\.present\("#, in: today) == 1,
            "Today declares the create manager without calling it — the defect, moved one file over"
        )
    }

    /// The same defect, two more sites in the list detail page: `ListTasksGroupSectionView` and
    /// `ListTasksCompletedSectionView` both carried an `allTasks` no body read. Removing the
    /// parameter also retired `ListTasksView`'s `@Query private var allTasks` in
    /// `ListDetailComponents.swift` — it existed only to feed these two call sites, so once they
    /// stopped reading it, it was a live SwiftData query firing every body pass for nothing.
    @Test func theListDetailPageNoLongerCarriesTheDeadAllTasksParameterOrItsQuery() throws {
        let support = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/ListDetailSupportViews.swift")
        )
        for declaration in [
            "struct ListTasksGroupSectionView: View",
            "struct ListTasksCompletedSectionView: View",
        ] {
            let body = try #require(CadenceSourceScan.declarationBody(declaration, in: support))
            #expect(!body.contains("let allTasks:"), "\(declaration) still declares the dead allTasks parameter")
        }

        let components = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/ListDetailComponents.swift")
        )
        let body = try #require(CadenceSourceScan.declarationBody("var body: some View", in: components))
        #expect(body.contains("ListTasksGroupSectionView("))
        #expect(body.contains("ListTasksCompletedSectionView("))
        #expect(
            !body.contains("allTasks:"),
            "ListDetailComponents still threads allTasks into the list section views"
        )
        #expect(
            !components.contains("@Query(sort: \\AppTask.createdAt, order: .reverse) private var allTasks"),
            "ListTasksView's allTasks query has no reader left and should have gone with the parameter"
        )
    }

    // MARK: - T-681: `List` row modifiers inside a `LazyVStack`

    /// `TasksPanelIntentSectionView`'s header used to chain `.listRowBackground(Color.clear)` and
    /// `.listRowSeparator(.hidden)` — both `List` row modifiers — but `TasksPanel` draws every
    /// section inside `ScrollView { LazyVStack(pinnedViews: .sectionHeaders) }`, where a `List` row
    /// modifier is a no-op. Pinned against the container claim itself, not assumed: a future
    /// `TasksPanel` that switches back to a real `List` would make the removal wrong, and this
    /// would catch it.
    ///
    /// **Not a sweep.** `TaskListDisplayRow` carries the identical pair and keeps them: its other
    /// caller, `ListTasksCompletedSectionView`, sits inside `ListDetailComponents`'s real `List`,
    /// where the same two modifiers are load-bearing. Both halves are asserted so a future change
    /// cannot fix one file by breaking the other.
    @Test func onlyTheSectionHeaderInsideTheLazyVStackLostItsListRowModifiers() throws {
        let panel = try Self.panelSource()
        #expect(
            panel.contains("ScrollView {") && panel.contains("LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders)"),
            "TasksPanel no longer draws its sections in a LazyVStack; re-decide whether the header may regain the modifiers"
        )

        let sections = try Self.sectionSource()
        let intentView = try #require(
            CadenceSourceScan.declarationBody("struct TasksPanelIntentSectionView: View", in: sections)
        )
        #expect(
            !intentView.contains(".listRowBackground("),
            "TasksPanelIntentSectionView's header still carries a no-op List row modifier"
        )
        #expect(
            !intentView.contains(".listRowSeparator("),
            "TasksPanelIntentSectionView's header still carries a no-op List row modifier"
        )
        #expect(intentView.contains(".dropDestination(for: String.self)"), "the header's real drop target went with the no-ops")

        let listDetail = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/ListDetailSupportViews.swift")
        )
        let displayRow = try #require(
            CadenceSourceScan.declarationBody("struct TaskListDisplayRow: View", in: listDetail)
        )
        #expect(
            displayRow.contains(".listRowBackground(Color.clear)"),
            "TaskListDisplayRow lost the modifier its List caller (ListTasksCompletedSectionView) needs"
        )
        #expect(
            displayRow.contains(".listRowSeparator(.hidden)"),
            "TaskListDisplayRow lost the modifier its List caller (ListTasksCompletedSectionView) needs"
        )
        let completedSectionView = try #require(
            CadenceSourceScan.declarationBody("struct ListTasksCompletedSectionView: View", in: listDetail)
        )
        #expect(
            completedSectionView.contains("TaskListDisplayRow("),
            "self-check: TaskListDisplayRow's other caller moved out of this file"
        )
        let components = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/ListDetailComponents.swift")
        )
        #expect(
            components.contains("List {"),
            "self-check: ListDetailComponents.swift's real List is what makes the row's modifiers load-bearing"
        )
    }

    // MARK: - T-2084: the task-group header's accent bar

    /// **The owner had the vertical colour bars removed and the space reclaimed**, in the sidebar
    /// and here: *"remove the vertical colored bars next to the titles of lists. i think these
    /// colors are make the page very distracting."* Nothing replaces this one — not a grey bar, not
    /// a dot — and the colour itself stays a concept everywhere it is chosen or shown.
    ///
    /// **This bar was not the sidebar's.** The sidebar's two were `.overlay`s and consumed no
    /// layout width, so removing them moved nothing. This one was the first child of an
    /// `HStack(spacing: 10)`, so taking it out pulls every header on Today, All Tasks, Inbox and
    /// list detail **13pt leftward**. That is the reclaimed space, and it is asserted here rather
    /// than left to a reading of the diff, because the figure it has to stay consistent with is the
    /// hairline below the header: that rule is anchored to the chevron's trailing edge, so it moved
    /// by the same 13 (34 → 21) and a future change that restores one without the other would put
    /// the rule to the right of the title it underlines.
    ///
    /// The `accent` parameter is pinned absent on both of the header's initialisers and at all five
    /// call sites. It was not left inert: a parameter that is accepted and never drawn is how a
    /// deleted decoration grows back, and the four colour fields that fed it — on the list-detail
    /// group, on the All Tasks section, on Today's intent section and on the freeze snapshot — were
    /// write-only the moment this `RoundedRectangle` went, so they went with it.
    @Test func theTaskGroupHeaderDrawsNoAccentBarAndTakesNoAccent() throws {
        let listDetail = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/ListDetailSupportViews.swift")
        )
        let header = try #require(
            CadenceSourceScan.declarationBody("struct TaskListGroupHeader<LeadingContent: View>: View", in: listDetail)
        )
        #expect(header.contains("chevron.right"), "non-vacuity: the disclosure chevron left this declaration")
        #expect(
            !header.contains("RoundedRectangle(cornerRadius: 2"),
            "TaskListGroupHeader draws the 3x22pt accent bar again"
        )
        #expect(!header.contains("accent"), "TaskListGroupHeader takes an accent again")
        #expect(
            header.contains(".padding(.leading, 21)"),
            "the header's hairline is no longer inset to the chevron's trailing edge — 21 is 34 minus the bar's 3pt and its 10pt of spacing"
        )

        // The `EmptyView` convenience initialiser lives in an extension outside that declaration,
        // and so do the two call sites in this file, so the whole file is swept as well.
        #expect(
            listDetail.contains("extension TaskListGroupHeader where LeadingContent == EmptyView"),
            "self-check: the convenience initialiser moved out of this file"
        )
        for path in [
            "Cadence/macOS/Views/ListDetailSupportViews.swift",
            "Cadence/macOS/Views/TasksListView.swift",
            "Cadence/macOS/Views/InboxSupportViews.swift",
            "Cadence/macOS/Views/TasksPanelSectionViews.swift",
            "Cadence/macOS/Views/TasksPanel.swift",
        ] {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            #expect(source.contains("TaskListGroupHeader") || source.contains("TasksPanelIntentSectionView"),
                    "non-vacuity: \(path) no longer takes part in drawing the task-group header")
            #expect(!source.contains("accent"), "\(path) threads an accent to the group header again")
        }
    }
}
