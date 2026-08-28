import Foundation
import SwiftData
import Testing
@testable import Cadence

/// iPhone Today shipped with no sort chip and no way to show Completed while iPad Today had both,
/// and the compact view still *read* `showCompleted` — a binding nothing on screen could write.
/// The options a surface offers are now stated once, per surface, with no size class involved;
/// these pin that they stay stated once.
///
/// `Cadence/iOS/` is inside `#if os(iOS)` and invisible to this macOS-built target, so what can be
/// asserted here is the value both widths read. That is deliberately where the decision lives.
struct CadenceTaskSurfaceOptionsTests {
    @Test func todayOffersBothControlsJustLikeEveryOtherTaskSurface() {
        let today = CadenceTaskSurfaceOptions.options(for: .today)

        #expect(today.showsSort)
        #expect(today.showsCompletedToggle)
    }

    /// The sweep's actual claim: no surface is a special case, so no *width* of a surface can be
    /// one either. If a future surface earns an exception it will fail here, which is the point —
    /// the exception has to be written down for both widths at once.
    @Test func everyTaskSurfaceOffersTheSameChromeControls() {
        for surface in CadenceTaskSurface.allCases {
            let options = CadenceTaskSurfaceOptions.options(for: surface)

            #expect(options.showsSort, "\(surface.rawValue) lost its sort control")
            #expect(options.showsCompletedToggle, "\(surface.rawValue) lost its completed toggle")
        }
    }

    // MARK: - The list chip

    /// Every Inbox row carried a chip reading "Inbox" — the chip's job is to say which list a task
    /// is in, and on the Inbox page the answer is the page title. It started rendering for
    /// container-less tasks for a good reason (otherwise the tasks most in need of filing were the
    /// only ones that could not be filed from their row); that reason is about the row, and this is
    /// where it does not apply.
    @Test func theInboxDoesNotNameItselfOnEveryRow() {
        #expect(CadenceTaskSurfaceOptions.showsContainerChip(on: .inbox) == false)
        #expect(CadenceTaskSurfaceOptions.options(for: .inbox).showsContainerChip == false)
    }

    /// The same defect one screen over: a list's own Tasks tab would name that list on every row.
    /// It was already passing `false` at both widths by hand; this is what stops the hand-written
    /// answer and the table's answer drifting apart.
    @Test func aListsOwnPageDoesNotNameItselfOnEveryRow() {
        #expect(CadenceTaskSurfaceOptions.showsContainerChip(on: .listDetail) == false)
    }

    /// The mixed surfaces keep it. Today and All Tasks draw rows from every list at once, so the
    /// chip is both the answer to "which list" and the control for changing it — suppressing it
    /// there would be the regression the chip was added to fix.
    @Test func theSurfacesThatMixListsStillNameThem() {
        #expect(CadenceTaskSurfaceOptions.showsContainerChip(on: .today))
        #expect(CadenceTaskSurfaceOptions.showsContainerChip(on: .allTasks))
    }

    /// The point of putting this in `Shared/`: a surface has **one** answer, which both the compact
    /// and the regular layout of that surface read. `Cadence/iOS/` is invisible to this target, so
    /// what is pinned here is that there is only one value to read.
    @Test func everySurfaceHasExactlyOneAnswerForTheListChip() {
        for surface in CadenceTaskSurface.allCases {
            #expect(
                CadenceTaskSurfaceOptions.options(for: surface).showsContainerChip
                    == CadenceTaskSurfaceOptions.showsContainerChip(on: surface),
                "\(surface.rawValue) reports the list chip two different ways"
            )
        }
    }

    // MARK: - The completed cap

    /// Today, Inbox and list detail capped their completed list at 12 while All Tasks capped it at
    /// 24, so the same finished task was listed on one screen and silently dropped on another.
    @Test func theCompletedListIsCappedAtOneSharedLimit() {
        let tasks = Array(0..<200)

        #expect(CadenceTaskSurfaceOptions.completedRows(from: tasks, tier: .touch).count == CadenceTaskSurfaceOptions.completedRowLimit)
        #expect(CadenceTaskSurfaceOptions.completedRows(from: tasks, tier: .touch) == Array(0..<CadenceTaskSurfaceOptions.completedRowLimit))
    }

    /// The cap must never *add* to, reorder, or drop from a list that is already short enough —
    /// the completed section on a quiet day is a handful of rows and has to be all of them.
    @Test func aShorterCompletedListIsPassedThroughUntouched() {
        #expect(CadenceTaskSurfaceOptions.completedRows(from: [Int](), tier: .touch).isEmpty)
        #expect(CadenceTaskSurfaceOptions.completedRows(from: [7, 3, 9], tier: .touch) == [7, 3, 9])

        let exactlyAtTheLimit = Array(0..<CadenceTaskSurfaceOptions.completedRowLimit)
        #expect(CadenceTaskSurfaceOptions.completedRows(from: exactlyAtTheLimit, tier: .touch) == exactlyAtTheLimit)
    }

    /// The limit is the larger of the two that shipped, so unifying could not hide work a screen
    /// used to show.
    @Test func theSharedLimitIsNoSmallerThanEitherCapItReplaced() {
        #expect(CadenceTaskSurfaceOptions.completedRowLimit >= 24)
    }

    // MARK: - The desktop tier

    /// **The Mac's logbook is uncapped, and that is a decision rather than an oversight (T-290).**
    /// Nothing in the suite named `.desktop` until this test, so the tier could quietly start
    /// returning 24 — a ceiling on the only place a Mac lists finished work at all, under a header
    /// that goes on stating the true total — with every other test still green.
    @Test func theDesktopTierListsEveryCompletedRow() {
        #expect(CadenceTaskSurfaceOptions.completedRowLimit(for: .desktop) == nil)

        let manyFinishedTasks = Array(0..<200)
        #expect(CadenceTaskSurfaceOptions.completedRows(from: manyFinishedTasks, tier: .desktop) == manyFinishedTasks)
        #expect(CadenceTaskSurfaceOptions.completedRows(from: manyFinishedTasks, tier: .desktop).count == 200)
    }

    /// One tier caps and the other does not, and they are not two spellings of one answer. Written
    /// over `allCases` so a third tier cannot arrive without saying which of the two it is.
    @Test func exactlyOneTierCapsItsCompletedList() {
        let capped = CadenceTaskSurfaceTier.allCases.filter {
            CadenceTaskSurfaceOptions.completedRowLimit(for: $0) != nil
        }

        #expect(capped == [.touch])
        #expect(CadenceTaskSurfaceOptions.completedRowLimit(for: .touch) == CadenceTaskSurfaceOptions.completedRowLimit)

        let manyFinishedTasks = Array(0..<200)
        #expect(
            CadenceTaskSurfaceOptions.completedRows(from: manyFinishedTasks, tier: .desktop).count
                > CadenceTaskSurfaceOptions.completedRows(from: manyFinishedTasks, tier: .touch).count
        )
    }

    /// The desktop tier is not a second name for "no cap applied": it goes through the same
    /// function, so a list short enough for either tier comes back identical on both.
    @Test func bothTiersPassAShortCompletedListThroughUntouched() {
        for tier in CadenceTaskSurfaceTier.allCases {
            #expect(CadenceTaskSurfaceOptions.completedRows(from: [7, 3, 9], tier: tier) == [7, 3, 9])
            #expect(CadenceTaskSurfaceOptions.completedRows(from: [Int](), tier: tier).isEmpty)
        }
    }

    // MARK: - T-386, the touch tier's remainder

    /// **What the cap withholds is now a number the surface can say.**
    ///
    /// The phone drew 24 rows out of 40 and had nothing to render the other 16 with, so its options
    /// bar said 40, its section header said 24, and the screen contradicted itself. The rows and
    /// the remainder come from the same uncapped array here, which is what makes them add up.
    @Test func theTouchCapNamesTheRowsItWithholds() {
        let fortyFinishedTasks = Array(0..<40)

        #expect(CadenceTaskSurfaceOptions.completedRows(from: fortyFinishedTasks, tier: .touch).count == 24)
        #expect(CadenceTaskSurfaceOptions.hiddenCompletedCount(from: fortyFinishedTasks, tier: .touch) == 16)

        // Shown plus hidden is the whole section — the property the two disagreeing counts broke.
        let shown = CadenceTaskSurfaceOptions.completedRows(from: fortyFinishedTasks, tier: .touch).count
        let hidden = CadenceTaskSurfaceOptions.hiddenCompletedCount(from: fortyFinishedTasks, tier: .touch) ?? 0
        #expect(shown + hidden == fortyFinishedTasks.count)
    }

    /// `nil`, not `0`: there is no "+0 more" line, and a section that lists everything renders
    /// nothing extra. Asserted at the boundary and on the tier that never caps.
    @Test func aSectionThatListsEverythingHidesNothing() {
        #expect(CadenceTaskSurfaceOptions.hiddenCompletedCount(from: [Int](), tier: .touch) == nil)
        #expect(CadenceTaskSurfaceOptions.hiddenCompletedCount(from: [7, 3, 9], tier: .touch) == nil)

        let exactlyAtTheLimit = Array(0..<CadenceTaskSurfaceOptions.completedRowLimit)
        #expect(CadenceTaskSurfaceOptions.hiddenCompletedCount(from: exactlyAtTheLimit, tier: .touch) == nil)

        let oneOver = Array(0...CadenceTaskSurfaceOptions.completedRowLimit)
        #expect(CadenceTaskSurfaceOptions.hiddenCompletedCount(from: oneOver, tier: .touch) == 1)

        // The Mac is uncapped, so it withholds nothing however long the logbook gets.
        #expect(CadenceTaskSurfaceOptions.hiddenCompletedCount(from: Array(0..<200), tier: .desktop) == nil)
    }

    /// The caption states both numbers, so the header's total and the rows you can count are
    /// reconciled on screen rather than left to disagree.
    @Test func theOverflowCaptionSaysHowManyOfHowManyAreShown() {
        #expect(CadenceTaskSurfaceOptions.overflowCaption(shown: 24, total: 40) == "Showing 24 of 40")

        // Nothing hidden, nothing said — including the equal case, which is where a `>=`/`>` slip
        // would print "Showing 24 of 24".
        #expect(CadenceTaskSurfaceOptions.overflowCaption(shown: 24, total: 24) == nil)
        #expect(CadenceTaskSurfaceOptions.overflowCaption(shown: 0, total: 0) == nil)
        #expect(CadenceTaskSurfaceOptions.overflowCaption(shown: 40, total: 24) == nil)
    }

    /// The caption and the cap are the same decision, read end to end: a 40-task section shows 24,
    /// says so, and the number it says matches the rows it drew.
    @Test func theCaptionAgreesWithTheRowsTheTouchTierActuallyDraws() throws {
        let fortyFinishedTasks = Array(0..<40)
        let rows = CadenceTaskSurfaceOptions.completedRows(from: fortyFinishedTasks, tier: .touch)
        let hidden = try #require(CadenceTaskSurfaceOptions.hiddenCompletedCount(from: fortyFinishedTasks, tier: .touch))

        let caption = try #require(
            CadenceTaskSurfaceOptions.overflowCaption(shown: rows.count, total: rows.count + hidden)
        )

        #expect(caption == "Showing 24 of 40")
        #expect(caption.contains("\(rows.count)"))
        #expect(caption.contains("\(fortyFinishedTasks.count)"))
    }

    /// The Mac lists every finished task, so it has no caption to draw — the tier difference
    /// reaches the copy, not just the row count.
    @Test func theDesktopTierNeverDrawsAnOverflowCaption() {
        let manyFinishedTasks = Array(0..<200)
        let rows = CadenceTaskSurfaceOptions.completedRows(from: manyFinishedTasks, tier: .desktop)
        let hidden = CadenceTaskSurfaceOptions.hiddenCompletedCount(from: manyFinishedTasks, tier: .desktop) ?? 0

        #expect(hidden == 0)
        #expect(CadenceTaskSurfaceOptions.overflowCaption(shown: rows.count, total: rows.count + hidden) == nil)
    }

    /// The Mac's two task pages name the surface they are, which is what lets `TasksListView` ask
    /// the shared table instead of deciding its chrome inline.
    @Test func theMacsTaskPagesNameTheSurfaceTheyAre() {
        #expect(CadenceTasksPageScope.allCases.map(\.surface) == [.allTasks, .inbox])
    }
}

/// Copy that appears on more than one screen. Each of these was written out at both call sites and
/// drifted; the constants are what stop a third spelling appearing.
struct CadenceEmptyStateCopyTests {
    /// The iPad spelling read "on iPad or Mac", omitting the device most of these rows are read on.
    @Test func theAllTasksEmptyStateNamesEveryPlatformTheAppRunsOn() {
        for platform in ["iPhone", "iPad", "Mac"] {
            #expect(
                CadenceEmptyStateCopy.allTasksSubtitle.contains(platform),
                "\(platform) is missing from the All Tasks empty state"
            )
        }
    }

    @Test func sharedEmptyStateCopyIsPresentAndDistinct() {
        let subtitles = [
            CadenceEmptyStateCopy.inboxSubtitle,
            CadenceEmptyStateCopy.allTasksSubtitle,
            CadenceEmptyStateCopy.focusSubtitle
        ]

        #expect(subtitles.allSatisfy { !$0.isEmpty })
        #expect(Set(subtitles).count == subtitles.count)
    }
}

// MARK: - T-290: the macOS half

/// **The desktop half of T-290, which had no test at all.**
///
/// `CadenceTaskSurfaceOptions` shipped with eight iOS readers and, after the fix, four macOS ones —
/// and nothing in the suite named `.desktop`. Three reverting mutations passed clean: the tier
/// could return `24`, `TasksListView` could hand a Mac the phone's cap, and the row could go back
/// to gating its list chip on `!task.containerName.isEmpty`. The value half of that is pinned in
/// `CadenceTaskSurfaceOptionsTests` above, where it can be asserted as a value.
///
/// What is left here needs source: `Cadence/macOS/Views/` is inside `#if os(macOS)` and *is*
/// compiled by this target, but the three call sites are `private` computed properties on `View`
/// structs that cannot be built without a `ModelContainer` and an environment, so which tier they
/// ask for is not reachable as a value. Each scan is scoped to **one function body** rather than to
/// a struct-and-everything-after-it — the struct-shaped slice is what let a second copy of a
/// mutation hide behind the first.
@MainActor
struct CadenceDesktopTaskSurfaceTests {

    /// All three macOS logbooks ask for the desktop tier, and none of them re-rolls a cap of its
    /// own. `TasksListView` passing `.touch` is a one-word edit that no test could see.
    @Test func theMacsThreeLogbooksAskForTheDesktopTier() throws {
        let sites: [(path: String, declaration: String)] = [
            ("Cadence/macOS/Views/TasksListView.swift", "private var completedTasks: [AppTask]"),
            ("Cadence/macOS/Views/ListDetailComponents.swift", "private var doneTasks: [AppTask]"),
            (
                "Cadence/macOS/Views/TasksPanel.swift",
                "private func completedSection(derived: TasksPanelDerivedState) -> some View"
            )
        ]

        for site in sites {
            let code = try desktopSurfaceStrippingComments(desktopSurfaceSourceFile(site.path))
            let body = try cadenceFunctionBody(site.declaration, in: code)

            #expect(body.contains("CadenceTaskSurfaceOptions.completedRows("), "\(site.path) stopped asking")
            #expect(body.contains("tier: .desktop"), "\(site.path) stopped asking for the desktop tier")
            #expect(body.contains("tier: .touch") == false, "\(site.path) hands a Mac the phone's cap")
            #expect(body.contains(".prefix(") == false, "\(site.path) re-rolls a cap of its own")
        }
    }

    /// Where the Mac's chrome answers come from. `scope.surface` and `surface` are what keep the
    /// answer attached to a surface; a page that starts deciding inline is how T-290 happened.
    @Test func theMacsTaskPagesTakeTheirChromeFromTheSurface() throws {
        let listCode = try desktopSurfaceStrippingComments(
            desktopSurfaceSourceFile("Cadence/macOS/Views/TasksListView.swift")
        )
        let listOptions = try cadenceFunctionBody("private var options: CadenceTaskViewOptions", in: listCode)
        #expect(listOptions.contains("CadenceTaskSurfaceOptions.options(for: scope.surface)"))

        let panelCode = try desktopSurfaceStrippingComments(
            desktopSurfaceSourceFile("Cadence/macOS/Views/TasksPanel.swift")
        )
        let panelOptions = try cadenceFunctionBody("private var options: CadenceTaskViewOptions", in: panelCode)
        #expect(panelOptions.contains("CadenceTaskSurfaceOptions.options(for: surface)"))

        let completed = try cadenceFunctionBody(
            "private func completedSection(derived: TasksPanelDerivedState) -> some View",
            in: panelCode
        )
        #expect(completed.contains("showsContainer: options.showsContainerChip"))
    }

    /// **The row does not re-decide the chip, and the whole of its answer is the surface's flag.**
    ///
    /// Asserted as an exact normalized spelling rather than as "contains `showsContainer`", because
    /// the mutation that survived was an *addition*: `showsContainer && !task.containerName.isEmpty`
    /// contains `showsContainer` too. Anything ANDed on fails this.
    @Test func theMacRowLeavesTheListChipToTheSurface() throws {
        let raw = try desktopSurfaceSourceFile("Cadence/macOS/Views/TasksPanelComponents.swift")
        let code = try desktopSurfaceStrippingComments(raw)
        // The stripper ran, and it blanks rather than deletes.
        #expect(code != raw)
        #expect(code.count == raw.count)

        let row = try cadenceFunctionBody("struct MacTaskRow: View", in: code)
        let normalized = desktopSurfaceCollapsingWhitespace(row)

        #expect(normalized.contains("private var showsListContextChip: Bool { showsContainer }"))
        // Declared once and read once: a second copy cannot carry a different answer.
        #expect(row.components(separatedBy: "showsListContextChip").count - 1 == 2)
        // Non-vacuity: this is the row that draws the chip, and the flag is what gates it.
        #expect(normalized.contains("if showsListContextChip { ContainerPickerBadge("))
        // The gate that made an Inbox task the one task with no picker is gone from the row, in
        // any property it could be smuggled back through.
        #expect(row.contains("containerName") == false, "the row is deciding the chip again")
    }

    /// **The decision, stated as a value: an Inbox task is exactly the task the old Mac gate
    /// suppressed.** `containerName` is `area?.name ?? project?.name ?? ""`, so it is empty for a
    /// task with neither — which is what "in the Inbox" means. Gating the chip on
    /// `!containerName.isEmpty` therefore hid the picker from the only tasks that needed filing,
    /// on the two surfaces where filing them is the point. So an Inbox task on macOS Today and All
    /// Tasks now draws a chip where it drew none, and that is intended: the chip is the list
    /// *picker*, and `ContainerPickerBadge` renders the real name `Inbox` for an unset container.
    @Test func anInboxTaskIsTheOneTheOldMacGateWouldHaveSuppressed() {
        let inboxTask = AppTask(title: "Unfiled")

        #expect(inboxTask.area == nil)
        #expect(inboxTask.project == nil)
        #expect(inboxTask.containerName.isEmpty)

        // The old row-level gate, spelled out here so the behaviour it produced is readable.
        let oldMacRowGate = !inboxTask.containerName.isEmpty
        #expect(oldMacRowGate == false)

        // And what the surface says instead, which is what the row now reads.
        #expect(CadenceTaskSurfaceOptions.showsContainerChip(on: .today))
        #expect(CadenceTaskSurfaceOptions.showsContainerChip(on: .allTasks))
        // Unchanged where the page already names the list: the Inbox page still does not.
        #expect(CadenceTaskSurfaceOptions.showsContainerChip(on: .inbox) == false)
    }

    /// The stripper these scans read through, checked against the case that would matter silently:
    /// a `//` inside a URL is not a comment, and blanking one would take the rest of that line —
    /// including any needle after it — with it.
    @Test func theCommentStripperBlanksCommentsAndKeepsURLs() throws {
        let raw = """
        let site = "https://example.com/path" // trailing note
        let kept = 1
        /* block
           note */
        let alsoKept = 2
        """
        let stripped = try desktopSurfaceStrippingComments(raw)

        #expect(stripped != raw)
        #expect(stripped.count == raw.count)
        #expect(stripped.contains("https://example.com/path"))
        #expect(stripped.contains("let kept = 1"))
        #expect(stripped.contains("let alsoKept = 2"))
        #expect(stripped.contains("trailing note") == false)
        #expect(stripped.contains("block") == false)
    }
}

private func desktopSurfaceRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func desktopSurfaceSourceFile(_ relativePath: String) throws -> String {
    try String(
        contentsOf: desktopSurfaceRepositoryRoot().appendingPathComponent(relativePath),
        encoding: .utf8
    )
}

/// Blanks `//` and `/* */` comments to spaces of equal length, so an offset never shifts and a
/// length comparison stays meaningful. The `(?<!:)` is not decoration: without it the `//` in a
/// URL literal is read as a comment and everything after it on that line disappears from the scan.
private func desktopSurfaceStrippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["(?<!:)//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(
                range,
                with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound))
            )
        }
    }
    return result
}

/// Collapses every run of whitespace to one space, so a one-line body can be asserted exactly
/// without the assertion depending on how the file happens to be indented.
private func desktopSurfaceCollapsingWhitespace(_ source: String) -> String {
    source.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

// MARK: - T-386: the touch half

/// **The iOS half of T-386, which no value can reach.**
///
/// `Cadence/iOS/` is inside `#if os(iOS)` and invisible to this macOS-built target, so "the header
/// counts the whole section and the rows say how many of it they are" is only assertable as source.
/// The values behind it — `hiddenCompletedCount(from:tier:)` and `overflowCaption(shown:total:)` —
/// are pinned as values in `CadenceTaskSurfaceOptionsTests` above; what is left here is that the
/// three phone surfaces and the component actually ask for them.
///
/// Each scan is scoped to **one declaration**, and every one of them asserts the stripper ran, so a
/// renamed or emptied file cannot report agreement by finding nothing.
struct CadenceTouchCompletedSectionTests {

    /// The group counts what the section holds, not what it drew, and draws the caption that
    /// explains the difference. `count: tasks.count` is the exact spelling that made the header
    /// disagree with the options bar above it.
    @Test func theTouchGroupCountsTheWholeSectionAndSaysWhatItIsShowing() throws {
        let raw = try desktopSurfaceSourceFile("Cadence/iOS/iOSTaskGroupSection.swift")
        let code = try desktopSurfaceStrippingComments(raw)
        // The stripper ran, and it blanks rather than deletes.
        #expect(code != raw)
        #expect(code.count == raw.count)

        let section = try cadenceFunctionBody("struct iOSTaskGroupSection: View", in: code)
        let normalized = desktopSurfaceCollapsingWhitespace(section)

        // The remainder arrives from the call site rather than being re-derived here.
        #expect(normalized.contains("var hiddenCount: Int?"))
        #expect(normalized.contains("private var totalCount: Int { tasks.count + (hiddenCount ?? 0) }"))

        // The header counts the section, and the old spelling is gone.
        #expect(normalized.contains("count: totalCount"))
        #expect(section.contains("count: tasks.count") == false, "the header counts the capped array again")

        // And the difference is stated on screen, in the shared wording.
        #expect(normalized.contains("CadenceTaskSurfaceOptions.overflowCaption( shown: tasks.count, total: totalCount )"))
        // Non-vacuity: this is the component that draws the rows the caption is about.
        #expect(normalized.contains("ForEach(tasks) { task in"))
    }

    /// All three phone surfaces hand the group the remainder, and each one derives it from the
    /// **same uncapped array** it passes to `completedRows`. A site that capped first and counted
    /// second would report zero hidden rows on every screen.
    @Test func everyTouchCompletedSectionPassesTheRemainderFromTheSameList() throws {
        let sites: [(path: String, declaration: String)] = [
            ("Cadence/iOS/iOSTodayTaskSections.swift", "private var groupStack: some View"),
            ("Cadence/iOS/iOSTaskCollectionPage.swift", "private var groupStack: some View"),
            ("Cadence/iOS/iOSListDetailView.swift", "private var sectionStack: some View"),
        ]

        for site in sites {
            let raw = try desktopSurfaceSourceFile(site.path)
            let code = try desktopSurfaceStrippingComments(raw)
            #expect(code != raw, "\(site.path): the stripper read nothing")
            #expect(code.count == raw.count)

            let body = try cadenceFunctionBody(site.declaration, in: code)

            // Two spellings are allowed: the plain overload, and the `revealing:` one T-375 added
            // so a deep-linked row survives the cap. Both must derive from the *same* uncapped
            // `completedTasks` this site also counts, which is the property this test is about —
            // pinning the one-line form instead would fail the moment a second caller needs an
            // argument, which is exactly what happened when T-375 and T-386 landed together.
            let asksForCappedRows =
                body.contains("CadenceTaskSurfaceOptions.completedRows(from: completedTasks, tier: .touch)")
                || (body.contains("CadenceTaskSurfaceOptions.completedRows(")
                    && body.contains("from: completedTasks")
                    && body.contains("tier: .touch"))
            #expect(asksForCappedRows, "\(site.path) stopped asking for the capped rows")
            #expect(
                body.contains("hiddenCount: CadenceTaskSurfaceOptions.hiddenCompletedCount(from: completedTasks, tier: .touch)"),
                "\(site.path) draws a capped list without saying how much it cut"
            )
            #expect(body.contains(".prefix(") == false, "\(site.path) re-rolls a cap of its own")
        }
    }

    /// **The pointer a reader follows has to lead somewhere.** `completedRowLimit(for:)` sent the
    /// next reader to "docs/TODO.md T-291" for a decision that is not there: T-291 is closed,
    /// archived, and was about ordering inside a list cascade. The decision is T-386's.
    @Test func theCompletedCapPointsAtTheTicketItsBehaviourCameFrom() throws {
        let raw = try desktopSurfaceSourceFile("Cadence/Shared/CadenceTaskSurfaceOptions.swift")

        // Non-vacuity: this is the file that holds the cap, comments and all — the scan reads the
        // prose here, so it must not strip it.
        #expect(raw.contains("static func completedRowLimit(for tier: CadenceTaskSurfaceTier) -> Int?"))
        #expect(raw.contains("T-290"), "the file lost the ticket that decided the desktop tier")

        #expect(raw.contains("T-291") == false, "the cap still points at a closed, unrelated ticket")
        #expect(raw.contains("T-386"), "the cap does not name the ticket that decided it")
    }
}
