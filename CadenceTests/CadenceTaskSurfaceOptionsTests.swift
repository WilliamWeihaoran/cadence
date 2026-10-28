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

    // MARK: - The completed list, uncapped on both tiers (T-2057)

    /// **The phone lists every finished task now (T-2057).** The owner's answer to "what should
    /// replace the count capsule as the signal that a group is capped" was *show every task in every
    /// group and let the page scroll*, so the touch tier's 24-row cap is gone and `.touch` answers
    /// what `.desktop` already did. Two thousand rows in, two thousand rows out, in order.
    @Test func theTouchTierListsEveryCompletedRow() {
        #expect(CadenceTaskSurfaceOptions.completedRowLimit(for: .touch) == nil)

        let aLongLogbook = Array(0..<2_000)
        #expect(CadenceTaskSurfaceOptions.completedRows(from: aLongLogbook, tier: .touch) == aLongLogbook)
        #expect(CadenceTaskSurfaceOptions.completedRows(from: aLongLogbook, tier: .touch).count == 2_000)
    }

    /// A list that is already short has to come back exactly as it went in — empty stays empty and
    /// nothing is reordered — which is what both tiers' pass-through guarantees.
    @Test func aShorterCompletedListIsPassedThroughUntouched() {
        #expect(CadenceTaskSurfaceOptions.completedRows(from: [Int](), tier: .touch).isEmpty)
        #expect(CadenceTaskSurfaceOptions.completedRows(from: [7, 3, 9], tier: .touch) == [7, 3, 9])
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

    /// **No tier caps, and the two tiers are one answer (T-2057).** This used to read "exactly one
    /// tier caps", with `.touch` the one. Written over `allCases` so a third tier cannot arrive
    /// capped without saying so here.
    @Test func noTierCapsItsCompletedList() {
        let capped = CadenceTaskSurfaceTier.allCases.filter {
            CadenceTaskSurfaceOptions.completedRowLimit(for: $0) != nil
        }
        #expect(capped.isEmpty, "a tier caps its completed list again: \(capped)")

        let manyFinishedTasks = Array(0..<200)
        #expect(
            CadenceTaskSurfaceOptions.completedRows(from: manyFinishedTasks, tier: .desktop)
                == CadenceTaskSurfaceOptions.completedRows(from: manyFinishedTasks, tier: .touch)
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

    // MARK: - T-386's remainder, which no tier has any more

    /// **Nothing withheld, on either tier, however long the logbook (T-2057).** This was T-386's
    /// "the touch cap names the rows it withholds", 24 shown and 16 hidden out of 40. With the cap
    /// gone every row is listed at every length, and T-2087 deleted the remainder and its caption.
    @Test func aSectionThatListsEverythingHidesNothing() {
        for tier in CadenceTaskSurfaceTier.allCases {
            for length in [0, 3, 24, 25, 40, 2_000] {
                let tasks = Array(0..<length)
                #expect(
                    CadenceTaskSurfaceOptions.completedRows(from: tasks, tier: tier).count == length,
                    "\(tier.rawValue) withholds rows from a \(length)-task section"
                )
            }
        }
    }

    /// The Mac's two task pages name the surface they are, which is what lets `TasksListView` ask
    /// the shared table instead of deciding its chrome inline.
    @Test func theMacsTaskPagesNameTheSurfaceTheyAre() {
        #expect(CadenceTasksPageScope.allCases.map(\.surface) == [.allTasks, .inbox])
    }

    /// **T-638. `"+N more"` is spelled in exactly one declaration, and this is what says so.**
    ///
    /// T-598(c) settled the *spelling* — unspaced, because `+3` is a signed quantity — and hoisted
    /// the four calendar sites that disagreed onto `moreLabel(hidden:)`. It left the eight sites
    /// that already agreed typing the literal, on the grounds that they agreed. Agreement is not a
    /// guard: `moreLabel` is interpolated by nature, so `CadenceSharedConstantReuseSweepTests`
    /// (which harvests non-interpolated `static let`s) cannot see it, and a thirteenth surface
    /// typing `"+\(n) more"` would have been caught by nothing at all. That gap is this sweep.
    ///
    /// **Two neighbouring lines are deliberately *not* this one, and the needle separates them
    /// without an exception list.** `MarkdownRenderedBlockTruncation.overflowLabel(unit:)` draws
    /// `"+ 4 more rows"` — spaced, pluralised, naming the unit that was cut, under a rendered table
    /// rather than beside a list of chips; `iOSTodaySchedulePanel` drew `"+3 more in Today"`,
    /// which named *where* the rest were, until T-1273 removed the stack it counted for. Both
    /// continue past the word `more` — the second is kept as a witness rather than dropped with
    /// its surface, because what it proves is a property of the *needle*, not of that file. Both
    /// anchored on the literal's closing quote, so neither can be swept up by a change to the list
    /// of files.
    ///
    /// The one file that may spell it is the one that declares it.
    @Test func onlyTheSharedHelperSpellsTheOverflowLine() throws {
        let declaration = "Cadence/Shared/CadenceTaskSurfaceOptions.swift"
        let needle = #""\+ ?\\\([^"]*\) more""#

        // The needle is not blind: it matches both spellings of this line, and neither of the two
        // sentences that merely start the same way.
        #expect(CadenceSourceScan.matchCount(needle, in: #"Text("+\(hidden) more")"#) == 1)
        #expect(CadenceSourceScan.matchCount(needle, in: #"Text("+ \(overflow) more")"#) == 1)
        #expect(
            CadenceSourceScan.matchCount(needle, in: #"return "+ \(count) more \(unit)s""#) == 0,
            "the needle swept up MarkdownRenderedBlockTruncation.overflowLabel(unit:)"
        )
        #expect(
            CadenceSourceScan.matchCount(needle, in: #"Text("+\(hidden) more in Today")"#) == 0,
            "the needle swept up iOSTodaySchedulePanel's line"
        )
        #expect(
            CadenceSourceScan.matchCount(
                needle,
                in: #"Text(CadenceTaskSurfaceOptions.moreLabel(hidden: hidden))"#
            ) == 0
        )

        let spellsItsOwnOverflowLine = try CadenceScanInstrument(
            "an overflow line spelled inline",
            fires: #"""
            Text("+\(hidden) more")
                .foregroundStyle(Theme.dim)
            """#,
            // The nearest negatives, all three at once: the line drawn through the helper, and the
            // two sentences that share its first four characters and are not it.
            andNotOn: #"""
            Text(CadenceTaskSurfaceOptions.moreLabel(hidden: hidden))
            Text("+\(tasks.count - visible.count) more in Today")
            return "+ \(overflowCount) more \(unit)\(overflowCount == 1 ? "" : "s")"
            """#,
            by: { CadenceSourceScan.matchCount(needle, in: CadenceSourceScan.strippingComments($0)) > 0 }
        )

        var paths = try CadenceSourceScan.swiftFiles(under: "Cadence")
        paths += try CadenceSourceScan.swiftFiles(under: "CadenceWidgets")
        let read = CadenceSourceScan.strippedSourceReader()

        // Non-vacuity that no `atLeast:` can supply: the walk reaches the one file that *does*
        // spell the line, and reads it as spelling it exactly once.
        #expect(
            CadenceSourceScan.matchCount(needle, in: try read(declaration)) == 1,
            "the sweep no longer reads moreLabel's own declaration"
        )

        let offenders = try spellsItsOwnOverflowLine.sweep(
            paths,
            // 560 app files plus the widget extension when this was written; a walk that collapses
            // is how an absence sweep passes forever.
            atLeast: 400,
            including: declaration,
            read: read
        ).filter { $0 != declaration }

        #expect(
            offenders.isEmpty,
            "overflow line spelled inline rather than through moreLabel(hidden:) in: \(offenders.joined(separator: ", "))"
        )
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
            (
                "Cadence/macOS/Views/TasksListView.swift",
                "private func completedTasks(in universe: [AppTask]) -> [AppTask]"
            ),
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
    // T-1269: one pass per pattern, in CadenceSourceScan. The spelling is pinned to
    // what this copy used, because correcting it is T-1270 and not this change.
    return CadenceSourceScan.strippingComments(source)
}

/// Collapses every run of whitespace to one space, so a one-line body can be asserted exactly
/// without the assertion depending on how the file happens to be indented.
private func desktopSurfaceCollapsingWhitespace(_ source: String) -> String {
    source.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

// MARK: - T-386: the touch half, and T-2087's deletion of its disclosure

/// **The iOS half of T-386, which no value can reach.**
///
/// `Cadence/iOS/` is inside `#if os(iOS)` and invisible to this macOS-built target, so what the
/// phone's completed sections draw is only assertable as source. T-386 made a capped section say
/// how much it cut; T-2057 removed the cap; T-2087 removed the disclosure that could then never
/// fire — a hidden-row count, the section's "true size", and a "Showing N of M" caption, threaded
/// from three call sites into two components. What is pinned here is that the chain stays gone
/// and the rows stay uncapped, so a cap cannot come back without its disclosure coming back too.
///
/// Each scan is scoped to **one declaration**, and every one of them asserts the stripper ran, so a
/// renamed or emptied file cannot report agreement by finding nothing.
struct CadenceTouchCompletedSectionTests {

    /// Neither iOS task-group component carries a remainder or a caption any more (T-2087), and
    /// neither header draws a count (T-2056). `count: tasks.count` is the exact spelling that made
    /// the header disagree with the options bar above it, back when the rows were capped.
    @Test func theTouchGroupsCarryNoCapDisclosure() throws {
        let raw = try desktopSurfaceSourceFile("Cadence/iOS/iOSTaskGroupSection.swift")
        let code = try desktopSurfaceStrippingComments(raw)
        // The stripper ran, and it blanks rather than deletes.
        #expect(code != raw)
        #expect(code.count == raw.count)

        for declaration in ["struct iOSTaskGroupSection: View", "struct iOSCompletedTasksSection: View"] {
            let section = try cadenceFunctionBody(declaration, in: code)
            // Non-vacuity: this is a component that draws the rows.
            #expect(section.contains("ForEach(tasks) { task in"), "\(declaration): wrong body read")

            #expect(!section.contains("hiddenCount"), "\(declaration) takes a remainder again")
            #expect(!section.contains("totalCount"), "\(declaration) derives a true size again")
            #expect(!section.contains("Showing"), "\(declaration) spells a cap caption again")
            #expect(!section.contains("count: tasks.count"), "\(declaration) counts its rows in a header")
        }
    }

    /// All three phone surfaces ask for their completed rows from the **same uncapped array**, and
    /// hand the section nothing else about them. A site that capped on its own would be T-290.
    @Test func everyTouchCompletedSectionAsksForItsRowsFromTheWholeList() throws {
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
            // so a deep-linked row is guaranteed listed.
            let asksForRows =
                body.contains("CadenceTaskSurfaceOptions.completedRows(from: completedTasks, tier: .touch)")
                || (body.contains("CadenceTaskSurfaceOptions.completedRows(")
                    && body.contains("from: completedTasks")
                    && body.contains("tier: .touch"))
            #expect(asksForRows, "\(site.path) stopped asking for its completed rows")
            #expect(body.contains("iOSCompletedTasksSection("), "\(site.path): non-vacuity")
            #expect(!body.contains("hiddenCount:"), "\(site.path) hands the section a remainder again")
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

// MARK: - T-2057: the touch row stack is lazy, because nothing caps it any more

/// **The half of T-2057 that made the uncap safe to land.** With no cap, All Tasks' or Inbox's
/// Completed group is the whole logbook, and `iOSTaskGroupSection` built its rows in a plain
/// `VStack` — so one tap of the Completed control on a store of 2,000 finished tasks built every
/// `iOSTaskRow` up front. The rows are a `LazyVStack` now.
///
/// **What these pin is source, and why that is the strongest thing this target can hold.**
/// `Cadence/iOS/` is inside `#if os(iOS)` and this target is built for macOS only, so no iOS view
/// can be hosted here and counted the way `CadenceCodexTaskListVirtualizationTests` counts the
/// Mac's rows. The row COUNT for this change was taken on `Cadence-iPhone15` with a temporary probe
/// and recorded in T-2057's ledger entry; what is pinned here is the shape that count depends on —
/// the row stack is lazy, at the spacing it had, and every scrolling host that puts it on a phone
/// is a `ScrollView` whose content is a `LazyVStack`, so the laziness is not swallowed by an eager
/// page around it.
struct CadenceTouchRowStackLazinessTests {
    private func code(_ path: String) throws -> String {
        let raw = try desktopSurfaceSourceFile(path)
        let code = try desktopSurfaceStrippingComments(raw)
        // The stripper ran, and it blanks rather than deletes.
        #expect(code != raw, "\(path): the stripper read nothing")
        #expect(code.count == raw.count)
        return code
    }

    private func occurrences(of pattern: String, in text: String) throws -> Int {
        try NSRegularExpression(pattern: pattern)
            .numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    /// The group's rows are one `LazyVStack(spacing: 7)` over `ForEach(tasks)`, and no eager
    /// `VStack(spacing: 7)` is left beside it. Same spacing, same (default, centred) alignment —
    /// the change is the one word.
    @Test func theGroupBuildsItsRowsInALazyStackAtTheSameSpacing() throws {
        let section = try cadenceFunctionBody(
            "struct iOSTaskGroupSection: View",
            in: try code("Cadence/iOS/iOSTaskGroupSection.swift")
        )
        let normalized = desktopSurfaceCollapsingWhitespace(section)

        #expect(
            normalized.contains("if !tasks.isEmpty { LazyVStack(spacing: 7) { ForEach(tasks) { task in iOSTaskRow("),
            "iOSTaskGroupSection no longer builds its rows in a LazyVStack(spacing: 7)"
        )
        #expect(try occurrences(of: #"LazyVStack\("#, in: section) == 1)
        #expect(
            try occurrences(of: #"(?<!Lazy)VStack\(spacing: 7\)"#, in: section) == 0,
            "an eager row stack is back in iOSTaskGroupSection"
        )
        // Non-vacuity: the group's own header-over-rows stack is still the eager one it was, and
        // it is the only other stack here.
        #expect(try occurrences(of: #"(?<!Lazy)VStack\(alignment: \.leading, spacing: 9\)"#, in: section) == 1)
        #expect(normalized.contains("iOSTaskGroupHeader("))
    }

    /// Every phone host that scrolls the group puts it inside `ScrollView { LazyVStack(...) }`. A
    /// lazy row stack inside an eager page is still built whole the moment the page is, which is
    /// the shape T-3004 found on the Mac. Named by host and by the exact opening it draws.
    ///
    /// **T-2088 moved the collection page's scrolling page one declaration down**, and this test
    /// follows it rather than being loosened. `body` is now the `ScrollViewReader` that gives the
    /// deep-link scroll its proxy, and `scrollBody(proxy:)` is the page it wraps — so the host is
    /// named by *that* declaration, and the wrapper is pinned below so the indirection cannot
    /// become a place an eager stack hides.
    @Test func everyCompactScrollHostOfTheGroupIsALazyPage() throws {
        let hosts: [(path: String, declaration: String, opening: String)] = [
            (
                "Cadence/iOS/iOSTaskCollectionPage.swift",
                "private func scrollBody(proxy: ScrollViewProxy) -> some View",
                "ScrollView { LazyVStack(alignment: .leading, spacing: metrics.stackSpacing) {"
            ),
            (
                "Cadence/iOS/iOSTodayCompactViews.swift",
                "var body: some View",
                "ScrollView { LazyVStack(alignment: .leading, spacing: 10) {"
            ),
            (
                "Cadence/iOS/iOSListDetailView.swift",
                "private var sectionStack: some View",
                "ScrollView { LazyVStack(alignment: .leading, spacing: iOSTaskCollectionMetrics.groupSpacing) {"
            ),
        ]

        for host in hosts {
            let body = try cadenceFunctionBody(host.declaration, in: try code(host.path))
            let normalized = desktopSurfaceCollapsingWhitespace(body)
            #expect(
                normalized.trimmingCharacters(in: .whitespaces).hasPrefix(host.opening),
                "\(host.path): \(host.declaration) no longer opens a lazy scrolling page"
            )
        }

        // T-2088: the collection page's `body` is the one wrapper over that page, and it is a
        // `ScrollViewReader` and nothing else — so the lazy page above is still the whole of what
        // the page draws, reached through exactly one indirection rather than an unknown number.
        let page = try cadenceFunctionBody(
            "var body: some View",
            in: try code("Cadence/iOS/iOSTaskCollectionPage.swift")
        )
        let normalizedPage = desktopSurfaceCollapsingWhitespace(page)
            .trimmingCharacters(in: .whitespaces)
        #expect(
            normalizedPage.hasPrefix("ScrollViewReader { proxy in"),
            "iOSTaskCollectionPage.body no longer opens the scroll reader: \(normalizedPage)"
        )
        #expect(
            normalizedPage.contains("scrollBody(proxy: proxy)"),
            "iOSTaskCollectionPage.body no longer hands its proxy to the lazy page: \(normalizedPage)"
        )
        #expect(
            !normalizedPage.contains("Stack("),
            "view content has moved into the wrapper, where an eager stack would not be checked above"
        )

        // And the groups those pages draw are the shared component, so the lazy stack above is the
        // one they get. The Today and collection pages reach it through their `groupStack`.
        //
        // **Today's count is 1, not 2, since T-3076**, and the missing one is Completed. That group
        // folds itself now — the owner asked for it always on the page and closed until tapped —
        // and `iOSTaskGroupSection` draws its heading unconditionally and owns no disclosure, so a
        // chevron row above it would print "Completed Today" twice. The laziness this test exists
        // for therefore has to be asserted of `iOSCompletedTasksSection` directly, below; an eager
        // stack there is the whole day's logbook built the moment the page is.
        for (path, expected) in [
            ("Cadence/iOS/iOSTaskCollectionPage.swift", 1),
            ("Cadence/iOS/iOSTodayTaskSections.swift", 1),
        ] {
            let groupStack = try cadenceFunctionBody("private var groupStack: some View", in: try code(path))
            #expect(try occurrences(of: #"iOSTaskGroupSection\("#, in: groupStack) == expected, "\(path)")
        }

        let today = try code("Cadence/iOS/iOSTodayTaskSections.swift")
        let todayGroupStack = try cadenceFunctionBody("private var groupStack: some View", in: today)
        #expect(todayGroupStack.contains("iOSCompletedTasksSection("), "Today's Completed group lost its section")
        // Since T-2090 the same section is All Tasks', Inbox's and a list's Tasks tab's, so the
        // laziness below is four surfaces' rather than Today's — and the collection page's count
        // above is 1, not 2, for the same reason Today's was.
        let completedRows = try cadenceFunctionBody(
            "private var rows: some View",
            in: try code("Cadence/iOS/iOSTaskGroupSection.swift")
        )
        #expect(
            desktopSurfaceCollapsingWhitespace(completedRows)
                .trimmingCharacters(in: .whitespaces)
                .hasPrefix("LazyVStack(spacing: 7) {"),
            "iOSCompletedTasksSection builds its rows eagerly"
        )
        #expect(completedRows.contains("iOSTaskRow("), "non-vacuity: wrong declaration read")
    }
}

// MARK: - T-285: the Mac stops writing its own empty-state words

/// **`CadenceEmptyStateCopy` had eight iOS readers and none on macOS.**
///
/// It exists because three pairs of screens said the same thing in different words, and the pair it
/// was least able to help was the one that never read it: the Inbox said "Inbox is clear / Capture
/// tasks here before scheduling or filing them." on the phone and "Inbox is empty / Unsorted tasks
/// and Apple Reminders appear here.\nCreate something to get started." on the Mac, and All Tasks
/// said "No active tasks / Tasks you create on iPhone, iPad, or Mac will collect here." against
/// "No tasks yet / Create a task to get started". One screen, four spellings, in an app whose two
/// surfaces sync to each other.
///
/// Worse than the words: `InboxEmptyStateView` was a **second `EmptyStateView`** — its own 72pt
/// tinted circle, its own 30pt light glyph, its own 16/13pt ramp — declared in a file whose only
/// caller, `TasksListView`, drew the shared component a dozen lines away in the same `switch`.
///
/// **Deliberately not in scope:** `FocusPickerSupportViews.emptyState`. A popover that is empty
/// *because the search matched nothing* is a different statement from a page that is empty because
/// there is no work. The popover's no-search branch reads `CadenceEmptyStateCopy.focusTitle` and
/// `focusSubtitle` since [[T-6003]]; its search branch keeps its own words, which those would be
/// wrong advice under.
@MainActor
struct CadenceDesktopEmptyStateConvergenceTests {

    /// The hand-rolled second empty state is **gone**, not merely unused. A `struct` that still
    /// compiles and nothing draws is how the page-header `subtitle` survived three deletions, and
    /// it is the failure mode a call-site count alone cannot see.
    @Test func theMacsSecondEmptyStateViewIsDeleted() throws {
        try t285ExpectNoLiveMention(of: "InboxEmptyStateView")

        // The tombstone stays: comments are stripped before the sweep, so the paragraph in
        // `InboxSupportViews.swift` recording what was there and why is exempt by construction.
        let inbox = try desktopSurfaceSourceFile("Cadence/macOS/Views/InboxSupportViews.swift")
        #expect(inbox.contains("InboxEmptyStateView"), "non-vacuity: the tombstone is unreadable")
        #expect(inbox.contains("T-285"), "the tombstone does not say which decision removed it")
    }

    /// One empty state for both scopes, drawn by the shared component, with its words and its glyph
    /// asked of the collection rather than decided here.
    ///
    /// The count is exact and it is **one**: two `EmptyStateView(` calls in this file is the shape
    /// the page had before — a shared one for All Tasks and a bespoke one for Inbox — re-created
    /// with the shared name on both.
    @Test func theMacsTaskPageDrawsOneEmptyStateFromTheSharedCopy() throws {
        let page = try desktopSurfaceStrippingComments(
            desktopSurfaceSourceFile("Cadence/macOS/Views/TasksListView.swift")
        )
        #expect(page.contains("struct TasksListView"), "non-vacuity: still the task page's file")

        #expect(
            page.components(separatedBy: "EmptyStateView(").count - 1 == 1,
            "the task page draws its empty state more than once"
        )
        for read in ["scope.collection.emptyTitle", "scope.collection.emptySubtitle", "scope.collection.emptyIcon"] {
            #expect(page.contains(read), "the empty state stopped reading \(read)")
        }

        // None of the four retired strings comes back at this call site, including as a fallback.
        for retired in ["No tasks yet", "Create a task to get started", "Inbox is empty"] {
            #expect(!page.contains(retired), "the desktop spelling \"\(retired)\" is back")
        }
    }

    /// The mapping the page reads exists on the scope, in both directions.
    ///
    /// Asserted through the source rather than as a value only because the *inverse* is what is
    /// new; `init(collection:)` has been there since T-163 and is checked as a value below.
    @Test func theScopeAndTheCollectionMapBothWays() throws {
        #expect(CadenceTasksPageScope(collection: .inbox) == .inbox)
        #expect(CadenceTasksPageScope(collection: .allTasks) == .all)

        let scope = try desktopSurfaceStrippingComments(
            desktopSurfaceSourceFile("Cadence/Shared/CadenceTasksPageScope.swift")
        )
        #expect(scope.contains("enum CadenceTasksPageScope"), "non-vacuity: still the scope's file")
        #expect(
            scope.contains("var collection: CadenceTaskCollection"),
            "the scope cannot name the collection it is showing"
        )
    }

    /// The words themselves, so a "convergence" that quietly rewrote the shared constants to the
    /// desktop's spelling still fails. The Inbox line says what to *do*; the desktop one described
    /// what the screen contains and then told the reader to create something, which is the floating
    /// "+" already on screen behind it.
    @Test func theSharedInboxCopyIsTheCaptureSentenceRatherThanTheDesktopParagraph() {
        #expect(CadenceEmptyStateCopy.inboxTitle == "Inbox is clear")
        #expect(CadenceEmptyStateCopy.inboxSubtitle == "Capture tasks here before scheduling or filing them.")
        #expect(!CadenceEmptyStateCopy.inboxSubtitle.contains("\n"), "an empty state's line is one line")

        // The collection is what the desktop page reads, so its answers are the ones that matter.
        #expect(CadenceTaskCollection.inbox.emptyTitle == CadenceEmptyStateCopy.inboxTitle)
        #expect(CadenceTaskCollection.inbox.emptySubtitle == CadenceEmptyStateCopy.inboxSubtitle)
        #expect(CadenceTaskCollection.allTasks.emptyTitle == CadenceEmptyStateCopy.allTasksTitle)
        #expect(CadenceTaskCollection.allTasks.emptySubtitle == CadenceEmptyStateCopy.allTasksSubtitle)

        // The glyph is the hollow twin of the header's, and both platforms now draw it.
        #expect(CadenceTaskCollection.inbox.emptyIcon == "tray")
        #expect(CadenceTaskCollection.allTasks.emptyIcon == "checklist")
    }

    /// The sweep behind `theMacsSecondEmptyStateViewIsDeleted` actually walks the tree.
    @Test func theEmptyStateSweepReachesTheFilesItClaimsTo() throws {
        let files = try t285SwiftFiles(under: "Cadence")
        #expect(files.count > 400, "walked \(files.count) files")
        #expect(files.contains("Cadence/macOS/Views/InboxSupportViews.swift"))
        #expect(files.contains("Cadence/Shared/Components/EmptyStateView.swift"))

        // A name that is definitely live must be found by the same sweep the absence assertion
        // uses, or that assertion is a statement about the enumerator.
        var liveHits = 0
        for path in files {
            let code = try desktopSurfaceStrippingComments(desktopSurfaceSourceFile(path))
            if code.range(of: "(?<![A-Za-z0-9_])EmptyStateView(?![A-Za-z0-9_])", options: .regularExpression) != nil {
                liveHits += 1
            }
        }
        #expect(liveHits >= 10, "the sweep found EmptyStateView in only \(liveHits) files")
    }
}

private func t285SwiftFiles(under relativeDirectory: String) throws -> [String] {
    let directory = desktopSurfaceRepositoryRoot().appendingPathComponent(relativeDirectory)
    guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else { return [] }
    return enumerator.compactMap { element in
        guard let relativePath = element as? String, relativePath.hasSuffix(".swift") else { return nil }
        return "\(relativeDirectory)/\(relativePath)"
    }
}

private func t285ExpectNoLiveMention(
    of name: String,
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let pattern = "(?<![A-Za-z0-9_])\(name)(?![A-Za-z0-9_])"
    for path in try t285SwiftFiles(under: "Cadence") {
        let code = try desktopSurfaceStrippingComments(desktopSurfaceSourceFile(path))
        #expect(
            code.range(of: pattern, options: .regularExpression) == nil,
            "\(path) still refers to the retired \(name)",
            sourceLocation: sourceLocation
        )
    }
}

// MARK: - T-2090: the completed toggle is deleted and the section folds itself

/// **The iPhone's Tasks page spent a whole row on two chips, and one of them is gone.**
///
/// Measured on a 393pt iPhone, `iOSTasksPageView.header` leaves 361pt and holds the back control,
/// "All Tasks" and the `All | Inbox` switcher, so neither chip of `iOSTaskViewOptionsBar` could
/// join it — the audit's two options came out ~128pt and ~17pt over. The owner rejected both:
/// *"i think we can remove the completed button cuz we can just make it a foldable title section
/// heading at the very bottom of the list. does that work? i think on mac os we have/had something
/// similar."* It does — `ListTasksCompletedSectionView` and `TasksPanelCompletedSectionView` head
/// macOS's completed rows with `TaskListGroupHeader`'s own collapse — so this is a port of an
/// existing shape that **deletes** a control rather than adding one, and Sort then fits alone.
///
/// Today reached that shape first (T-3076) as a Today-only section; these pin that all four iOS
/// task surfaces now share the one component, that no bar offers a completed chip any more, and
/// that the stored bit the chip used to write is still the fold and is still mirrored — which is
/// what makes this a deletion rather than a preference migration.
///
/// `Cadence/iOS/` is behind `#if os(iOS)` and invisible to this macOS-built target, so the shape
/// is read off the source. The preference half below is a real value check.
struct iOSCompletedDisclosureTests {

    /// Every touch surface that lists finished work draws the section unconditionally — the fold
    /// is the heading's, not the section's existence. A surface back behind `if showCompleted` is
    /// the defect this replaced: a section that does not exist until you find the chip.
    @Test func everyTouchTaskSurfaceDrawsItsCompletedSectionUnconditionally() throws {
        for path in [
            "Cadence/iOS/iOSTaskCollectionPage.swift",
            "Cadence/iOS/iOSListDetailView.swift",
            "Cadence/iOS/iOSTodayTaskSections.swift",
        ] {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            #expect(source.contains("iOSCompletedTasksSection("), "\(path) lost its completed section")
            #expect(!source.contains("if showCompleted"), "\(path)")
            #expect(!source.contains("if showsCompleted {"), "\(path)")
        }

        // One component, not four: the whole reason the Mac's shape is a port rather than a
        // parallel mechanism. Its own fold and its own rows, and nothing else local.
        let section = try #require(CadenceSourceScan.declarationBody(
            "struct iOSCompletedTasksSection: View",
            in: try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskGroupSection.swift")
        ))
        #expect(section.contains("@Binding var isExpanded: Bool"), "non-vacuity: wrong declaration read")
        let heading = try #require(section.range(of: "disclosure\n"))
        let fold = try #require(section.range(of: "if isExpanded {"))
        #expect(heading.lowerBound < fold.lowerBound, "the heading is behind the fold it controls")
    }

    /// The chip itself, at the one place it could come back and at the four that drew the bar.
    @Test func noTaskSurfaceOffersACompletedChip() throws {
        let bar = try #require(CadenceSourceScan.declarationBody(
            "struct iOSTaskViewOptionsBar: View",
            in: try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskViews.swift")
        ))
        #expect(bar.contains("showSortPicker"), "non-vacuity: wrong declaration read")
        #expect(!bar.contains("showCompleted"))
        #expect(!bar.contains("completedCount"))

        for path in [
            "Cadence/iOS/iOSTaskCollectionPage.swift",
            "Cadence/iOS/iOSListDetailView.swift",
            "Cadence/iOS/iOSTodayCompactViews.swift",
            "Cadence/iOS/iPadTodaySupportViews.swift",
        ] {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            #expect(source.contains("iOSTaskViewOptionsBar("), "non-vacuity: \(path)")
            #expect(!source.contains("completedCount:"), "\(path)")
            #expect(!source.contains("showsCompletedControl"), "\(path)")
        }
    }

    /// **Finished work is content, folded or not.** Both collection predicates read
    /// `!showsCompleted || completedTasks.isEmpty` while a chip decided whether the section
    /// existed; left alone, a page whose only work is done would call itself empty directly above
    /// a folded "Completed". Today made the same correction at T-3076.
    @Test func aFoldedCompletedSectionIsNotAnEmptyPage() throws {
        for (path, predicate) in [
            ("Cadence/iOS/iOSTaskCollectionPage.swift", "private var isEmpty: Bool"),
            ("Cadence/iOS/iOSListDetailView.swift", "private var isTaskColumnEmpty: Bool"),
        ] {
            let body = try #require(CadenceSourceScan.declarationBody(
                predicate,
                in: try CadenceSourceScan.sourceFile(path)
            ))
            #expect(body.contains("completedTasks.isEmpty"), "non-vacuity: \(path)")
            #expect(!body.contains("!showsCompleted"), "\(path)")
            #expect(!body.contains("!showCompleted"), "\(path)")
        }
    }

    /// **The stored bit is kept, and that is the answer to the sync question this ticket raised.**
    ///
    /// `LookPreference` records that an `allTasks.showCompleted` written by an iPhone is, to the
    /// Mac, an unknown pair it re-emits verbatim — so retiring the four keys would not have been a
    /// local change. It is not retired: the keys keep their meaning ("is the Completed section
    /// open"), the disclosure writes them where the chip used to, and the mirror table carries
    /// them exactly as before. Nothing on either platform's disk changes, which is why T-2090
    /// landed as a deletion with no migration.
    @Test func theFourStoredCompletedBitsSurviveTheChipThatWroteThem() {
        let keys = [
            CadencePreferenceKeys.iosTodayShowCompleted,
            CadencePreferenceKeys.iosAllTasksShowCompleted,
            CadencePreferenceKeys.iosInboxShowCompleted,
            CadencePreferenceKeys.iosListDetailShowCompleted,
        ]
        #expect(keys == [
            "ios.today.showCompleted",
            "ios.allTasks.showCompleted",
            "ios.inbox.showCompleted",
            "ios.listDetail.showCompleted",
        ])

        let mirrored = Set(CadenceLookPreferenceStore.mirrors(on: .iOS).map(\.defaultsKey))
        for key in keys {
            #expect(mirrored.contains(key), "\(key) fell out of the synced look")
        }
    }

    /// And the default is still `false` at every one of the four hosts, which is the whole of
    /// "always folded". A `true` here opens a page on somebody's entire logbook.
    @Test func everyTouchSurfaceStartsWithItsCompletedSectionFolded() throws {
        for (path, key) in [
            ("Cadence/iOS/iOSTodayView.swift", "iosTodayShowCompleted"),
            ("Cadence/iOS/iOSTaskCollectionViews.swift", "iosAllTasksShowCompleted"),
            ("Cadence/iOS/iOSInboxView.swift", "iosInboxShowCompleted"),
            ("Cadence/iOS/iOSListDetailView.swift", "iosListDetailShowCompleted"),
        ] {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            #expect(
                source.contains(
                    "@AppStorage(CadencePreferenceKeys.\(key)) private var showCompleted = false"
                ),
                "\(path) no longer starts folded"
            )
        }
    }
}
