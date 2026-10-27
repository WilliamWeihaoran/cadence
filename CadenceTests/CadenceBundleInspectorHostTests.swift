import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **The iOS Block panel is gone, and this suite is what stops it coming back** ([[T-3170]]).
///
/// T-217 filed the defect this suite was built for: `iOSCalendarBundleDetailSheet` was presented by
/// the card that opened it — `@State showDetail` plus `.sheet(isPresented:)` on the Board's Block
/// card and on `iOSTimelineBundleBlock` — and both sat inside a `ForEach(bundles)` the surface had
/// already filtered by day, with Today's pane filtering the same block by *hour* on top of that. So
/// the panel's own Save moved the block out of the collection drawing it, SwiftUI removed the card,
/// and the sheet went with it. The fix was a host above both shells whose lifetime outlived any
/// card's.
///
/// The owner then removed the whole Block feature. There is no card, no panel, no host selection
/// and no pane-owned `.sheet(item: $selectedBundle)` left on iOS, so the ownership tests below are
/// inverted: they count the presenters and require the dictionary to be **empty**. An empty
/// dictionary is a weak assertion on its own, which is why `theSourceScanIsNotVacuousInBundleInspectorHost`
/// still holds the corpus and still names live text in each file it reads.
///
/// **Two tests here are NOT about the panel and are kept deliberately.**
/// `deletingABundleUnbundlesItsTasksInsteadOfDeletingThem` and
/// `deletingABundleClearsTheSameStaleCalendarLinkTheSettledPathClears` pin
/// `CadenceTaskMutationSupport.deleteBundle`'s `.nullify` loop and T-295's agreement between the
/// two endings. `TaskBundle` is still a `@Model` — build 22 shipped it and this project has no
/// `SchemaMigrationPlan` — so that mutation is still in the tree and still worth holding.
///
/// **Retired with the surfaces they pinned**, each named here rather than deleted silently:
/// `reschedulingABundleOutOfTheDayAndHourQueriesKeepsThePanelOpen` and
/// `deletingTheBundleUnderneathThePanelClosesItInBothPhasesOfTheDelete` (the panel's lifetime — the
/// same rule is held on the surviving subject by
/// `CadenceTaskInspectorHostTests.deletingTheTaskUnderneathTheInspectorClosesItInBothPhasesOfTheDelete`);
/// `theBundleHostDrawsThePanelOnlyInTheStayBranchOfTheSharedRule` and
/// `theRootAppliesTheBundleHostAboveBothShellsRatherThanInsideOne` (there is no branch and no
/// selection left to place).
@MainActor
struct CadenceBundleInspectorHostTests {

    // MARK: - The premise, retired with the panel

    // `reschedulingABundleOutOfTheDayAndHourQueriesKeepsThePanelOpen` and
    // `deletingTheBundleUnderneathThePanelClosesItInBothPhasesOfTheDelete` were declared here.
    //
    // Both pinned the *panel's* lifetime — that a block re-dated out of the day query kept its
    // sheet, and that a delete underneath it closed the sheet in both phases. [[T-3170]] deleted
    // the panel, so neither has a subject. `CadenceDetailPanelPresentation` itself is untouched and
    // is still pinned on the surviving subject by `CadenceTaskInspectorHostTests`:
    // `cancellingATaskLeavesTheModelForTheHostToKeepShowing` is the first test's shape and
    // `deletingTheTaskUnderneathTheInspectorClosesItInBothPhasesOfTheDelete` is the second's,
    // including [[T-1318]]'s bounded reading of which of the two signals fires in which phase.

    /// **The `.nullify` invariant, on the path the panel this host presents actually calls.**
    /// `TaskBundle.tasks` is a nullify relationship, so deleting a block must unbundle its tasks and
    /// not delete them — and the panel's Delete Block button says as much in its own dialog ("the
    /// tasks stay scheduled for …"). `TaskBundleTests` pins this for macOS's `SchedulingActions`
    /// spelling only, and that suite is inside `#if os(macOS)`; the shared
    /// `CadenceTaskMutationSupport.deleteBundle` that both iOS presenters reach had no coverage at
    /// all.
    @Test func deletingABundleUnbundlesItsTasksInsteadOfDeletingThem() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let bundle = TaskBundle(title: "Batch", dateKey: "2026-08-21", startMin: 600, durationMinutes: 30)
        let first = AppTask(title: "Pull report")
        let second = AppTask(title: "File receipts")
        context.insert(bundle)
        context.insert(first)
        context.insert(second)
        for task in [first, second] {
            task.bundle = bundle
            task.scheduledDate = bundle.dateKey
            task.scheduledStartMin = -1
        }
        bundle.tasks = [first, second]
        try context.save()

        try CadenceTaskMutationSupport.deleteBundle(bundle, modelContext: context)

        let survivors = try context.fetch(FetchDescriptor<AppTask>())
        #expect(Set(survivors.map(\.id)) == Set([first.id, second.id]))
        #expect(survivors.allSatisfy { $0.bundle == nil })
        #expect(survivors.allSatisfy { $0.scheduledDate == "2026-08-21" })
        #expect(survivors.allSatisfy { $0.scheduledStartMin == -1 })
        #expect(try context.fetch(FetchDescriptor<TaskBundle>()).isEmpty)
    }

    /// **T-295: the two ways a bundle ends must leave its members in the same state.**
    ///
    /// `deleteBundleIfFullySettled` and `deleteBundle` sit twelve lines apart in
    /// `CadenceTaskMutationSupport`, unbundling members in near-identical loops, and only the first
    /// cleared `calendarEventID`. Deliberately **not** a live-bug test: nothing in the app writes
    /// that field a non-empty value, so the value below is seeded by hand to stand in for one an
    /// older build or a CloudKit record left on disk. What is being pinned is that the two loops
    /// agree — a stale identifier does not survive one ending and not the other.
    @Test func deletingABundleClearsTheSameStaleCalendarLinkTheSettledPathClears() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let bundle = TaskBundle(title: "Batch", dateKey: "2026-08-21", startMin: 600, durationMinutes: 30)
        let task = AppTask(title: "Pull report")
        context.insert(bundle)
        context.insert(task)
        task.bundle = bundle
        task.scheduledDate = bundle.dateKey
        task.scheduledStartMin = -1
        // The state only a pre-fix build or a synced record can produce.
        task.calendarEventID = "legacy-event-identifier"
        bundle.tasks = [task]
        try context.save()

        try CadenceTaskMutationSupport.deleteBundle(bundle, modelContext: context)

        let survivor = try #require(try context.fetch(FetchDescriptor<AppTask>()).first)
        #expect(survivor.calendarEventID == "")
        // The rest of the loop must be untouched by the fix.
        #expect(survivor.bundle == nil)
        #expect(survivor.scheduledDate == "2026-08-21")
    }

    // MARK: - Absence: nothing on iOS shows or edits a Block

    /// **No card owns a Block panel, because no card draws a Block.** This counted the timeline's
    /// two asks of the host — the block's own tap and its "Edit Block" context-menu item — while
    /// [[T-3170]]'s eighth pass had already taken the Board's card. Every count here is now zero,
    /// and the surviving `@State private var showDetail` / `.sheet(isPresented:)` zeros are kept
    /// rather than folded away: T-201's defect is a *shape*, and a card re-growing it is the thing
    /// this test was filed over.
    @Test func noIOSCardOwnsOrAsksForABlockPanel() throws {
        for path in [
            "Cadence/iOS/iOSCalendarTimelineViews.swift",
            "Cadence/iOS/iOSBoardCards.swift",
            "Cadence/iOS/iOSCalendarInspectorView.swift"
        ] {
            try expectOccurrences(of: "@State private var showDetail", at: [path: 0])
            try expectOccurrences(of: ".sheet(isPresented: $showDetail)", at: [path: 0])
            try expectOccurrences(of: "bundleInspector(", at: [path: 0])
            try expectOccurrences(of: "iOSBundleInspector", at: [path: 0])
        }
        // The block itself, not only its presentation: the view that drew it is deleted.
        try expectOccurrences(
            of: "struct iOSTimelineBundleBlock",
            at: ["Cadence/iOS/iOSCalendarTimelineViews.swift": 0]
        )
    }

    /// **The Block panel is drawn nowhere at all.** This read `["Cadence/iOS/iOSBundleInspectorHost.swift": 1]`
    /// — the wrapper's `.stay` branch and nothing else. `iOSCalendarBundleDetailSheet.swift` is
    /// deleted, so the dictionary is empty; a new `iOSCalendarBundleDetailSheet(` anywhere under
    /// `Cadence/` fails here, which is the one way a 375-line sheet could come back unnoticed.
    @Test func noSurfaceDrawsTheBlockPanel() throws {
        #expect(try presenterCounts(of: "iOSCalendarBundleDetailSheet(").isEmpty)
        #expect(try presenterCounts(of: "iOSBundleInspectorSheet(").isEmpty)
        // And the files themselves are gone, which no occurrence count can say.
        let files = try swiftFiles(under: "Cadence")
        #expect(!files.contains("Cadence/iOS/iOSCalendarBundleDetailSheet.swift"))
    }

    /// **The last line of the Block panel is gone from the tree.**
    ///
    /// This was `theBundleHostIsANoOpStubHeldOpenByOneLeasedCallSite`, which pinned a documented
    /// no-op: `iOSBundleInspectorHost.swift` had been reduced to a `View` extension returning
    /// `self` because `Cadence/iOS/iOSRootView.swift` still applied it and that file was
    /// **Codex-leased**, so the panel's last line could not go in the pass that deleted the panel.
    /// The grant arrived (`docs/CODEX_WORKTREE.md`, "GRANTED to a local agent:
    /// `Cadence/iOS/iOSRootView.swift`, for T-3170 only"), the call site and the file went
    /// together, and the pin is rewritten as the absence it now describes.
    ///
    /// Stated as an absence over the whole tree rather than as a missing file, because a stub that
    /// came back under any other name would still be a Block host: the *spelling* must appear
    /// nowhere, and the file must not be in the walk.
    @Test func theBlockPanelsLastLineIsGoneFromTheTreeEntirely() throws {
        #expect(try presenterCounts(of: "iOSBundleInspectorHost").isEmpty)
        #expect(try presenterCounts(of: "iOSBundleInspectorPresentAction").isEmpty)
        #expect(try presenterCounts(of: "iOSBundleInspectorSheet").isEmpty)

        let files = try swiftFiles(under: "Cadence")
        #expect(!files.contains("Cadence/iOS/iOSBundleInspectorHost.swift"))

        // Non-vacuity, and the claim this absence is **about**: the surviving host is still
        // declared, still applied exactly once at the root, and the root still reads as a root.
        try expectOccurrences(
            of: ".iOSTaskInspectorHost()",
            at: ["Cadence/iOS/iOSRootView.swift": 1]
        )
        let root = try strippingComments(sourceFile("Cadence/iOS/iOSRootView.swift"))
        #expect(root.contains("iOSCompactRootShell("))
        #expect(!root.contains("iOSBundleInspectorHost"))
    }

    /// **No iOS surface queries, buckets or draws a Block any more.**
    ///
    /// The day timeline, Today's schedule pane, the Calendar page, the month grid and the day
    /// inspector each carried a `[String: [TaskBundle]]` the whole way down from a `@Query`. One
    /// needle per rung, because a parameter left behind fed an empty dictionary reads exactly like
    /// a parameter that is gone — which is the state [[T-3170]]'s ninth pass had to come back for
    /// on the Mac.
    @Test func noIOSCalendarSurfaceStillCarriesABlockQuery() throws {
        #expect(try presenterCounts(of: "TaskBundle", under: "Cadence/iOS").isEmpty)
        #expect(try presenterCounts(of: "bundlesByDate", under: "Cadence/iOS").isEmpty)
        #expect(try presenterCounts(of: "CadenceScheduleSupport.bundles", under: "Cadence/iOS").isEmpty)
    }

    // MARK: - Where in the file, not just how many (T-161)

    // `theBundleHostDrawsThePanelOnlyInTheStayBranchOfTheSharedRule` and
    // `theRootAppliesTheBundleHostAboveBothShellsRatherThanInsideOne` were declared here, with
    // `thePatternHelperMatchesWhatItLooksLike` as their self-check.
    //
    // The first pinned that `iOSCalendarBundleDetailSheet(bundle: bundle)` sat in the `.stay`
    // branch of `resolveHeldSubject` and not the `.close` one — a swap `cfa3b3b` showed a
    // per-file count cannot see. The second pinned that `.iOSBundleInspectorHost()` was applied to
    // the `Group` rather than inside one of its two shell branches. [[T-3170]] deleted the panel
    // and emptied the host, so there is no branch to be in and no selection to place; the
    // `iOSRootView` residue is held instead by `theBundleHostIsANoOpStubHeldOpenByOneLeasedCallSite`
    // above. The equivalent placement pin for the surviving subject is
    // `CadenceTaskInspectorHostTests`'.

    /// The host reads the shared decision rather than re-deciding, about the two facts it can observe
    /// for itself — and it is the *shared* one, not a bundle-shaped copy of a measured rule. A host
    /// that started consulting a `@Query` here would be the page's filter creeping back into the
    /// panel's lifetime by another route.
    @Test func theOneSurvivingHostAsksTheOneSharedRuleAboutTheTwoFactsItCanSee() throws {
        // **One host left, and one call.** This read two — the task host and the block host — and
        // the pair was the point: two panels, one rule, no bundle-shaped copy of it. [[T-3170]]
        // took the second panel, so the dictionary is the census of what remains rather than a
        // narrowed assertion.
        #expect(
            try presenterCounts(of: "CadenceDetailPanelPresentation.resolveHeldSubject(") == [
                "Cadence/iOS/iOSTaskInspectorHost.swift": 1,
                // [[T-7540]]: the note half of the same guard, `iOSHeldNoteSheet`. A second
                // *caller* of the one rule, not a second copy of it; its wiring is pinned by
                // `CadenceHeldNoteSheetGuardTests`.
                "Cadence/iOS/iOSMarkdownReferenceSupport.swift": 1
            ]
        )
        // Both signals, at that one call site. `isDeleted` on its own is the draft that did not work.
        try expectOccurrences(
            of: "isDeleted: task.isDeleted",
            at: ["Cadence/iOS/iOSTaskInspectorHost.swift": 1]
        )
        try expectOccurrences(
            of: "hasNoModelContext: task.modelContext == nil",
            at: ["Cadence/iOS/iOSTaskInspectorHost.swift": 1]
        )
        // The rule kept its old name in no file at all — a second copy under the old noun is the one
        // outcome this consolidation exists to prevent.
        //
        // **The needle is retired, so the corpus can never witness it** (T-553): `CadenceTaskInspectorPresentation`
        // survives under `Cadence/` only inside one doc comment, and a comment is exactly what this
        // reader blanks. Nothing here could tell the spelling still matches anything, so a typo in
        // it would leave the loop green over a repository where the rule was enforced nowhere. The
        // instrument carries the witness instead, against the nearest possible negative: the name
        // that replaced it, in the same call.
        let namesTheRetiredRule = try CadenceScanInstrument(
            "the pre-T-217 spelling of the shared panel rule",
            fires: "let phase = CadenceTaskInspectorPresentation.resolveHeldSubject(isDeleted: bundle.isDeleted)",
            andNotOn: "let phase = CadenceDetailPanelPresentation.resolveHeldSubject(isDeleted: bundle.isDeleted)",
            by: { source in
                CadenceSourceScan.matchCount(
                    "(?<![A-Za-z0-9_])CadenceTaskInspectorPresentation(?![A-Za-z0-9_])",
                    in: CadenceSourceScan.codeOnly(source)
                ) > 0
            }
        )

        let offenders = try namesTheRetiredRule.sweep(
            try swiftFiles(under: "Cadence"),
            // 558 files when this was written.
            atLeast: 300,
            including: "Cadence/iOS/iOSTaskInspectorHost.swift",
            read: sourceFile
        )
        #expect(
            offenders.isEmpty,
            "still naming the pre-T-217 spelling: \(offenders.joined(separator: ", "))"
        )

        // And the reader really is blanking comments rather than the name having left the tree:
        // the shared rule's own file explains the rename in prose, so the raw text holds the old
        // spelling and the scanned text must not. Without this the zero above is equally happy
        // with a `codeOnly` that returned "".
        let sharedRule = try sourceFile("Cadence/Shared/CadenceDetailPanelPresentation.swift")
        #expect(
            sharedRule.contains("CadenceTaskInspectorPresentation"),
            "the old spelling is gone from prose too; re-anchor this witness or drop the sweep"
        )
        #expect(!namesTheRetiredRule.fires(on: sharedRule))
    }

    /// Without this, every zero above could be a scan reading an empty string — the failure mode a
    /// `/tmp` against `/private/tmp` path mismatch produces on an isolated build tree.
    @Test func theSourceScanIsNotVacuousInBundleInspectorHost() throws {
        let files = try swiftFiles(under: "Cadence")

        #expect(files.count > 300, "the source scan found \(files.count) files and cannot be doing its job")
        for path in [
            "Cadence/iOS/iOSTaskInspectorHost.swift",
            "Cadence/iOS/iOSRootView.swift",
            "Cadence/iOS/iOSBoardCards.swift",
            "Cadence/iOS/iOSCalendarTimelineViews.swift",
            "Cadence/iOS/iOSCalendarInspectorView.swift",
            "Cadence/iOS/iOSCalendarMonthAgendaViews.swift",
            "Cadence/iOS/iOSCalendarMonthViews.swift",
            "Cadence/iOS/iOSCalendarView.swift",
            "Cadence/iOS/iOSTodaySchedulePanel.swift",
            "Cadence/Shared/CadenceDetailPanelPresentation.swift"
        ] {
            #expect(files.contains(path))
        }

        // **Every zero above is a zero over text this reader really can see.** Each file named in
        // the absence tests is asserted to hold something live, so a scan returning "" — the
        // failure a `/tmp` against `/private/tmp` prefix mismatch produces — cannot read green.
        for (path, witness) in [
            ("Cadence/iOS/iOSTaskInspectorHost.swift", "CadenceDetailPanelPresentation.resolveHeldSubject("),
            ("Cadence/iOS/iOSRootView.swift", ".iOSTaskInspectorHost()"),
            ("Cadence/iOS/iOSCalendarTimelineViews.swift", "struct iOSTimelineTaskBlock"),
            ("Cadence/iOS/iOSCalendarInspectorView.swift", "@State private var selectedEvent"),
            ("Cadence/iOS/iOSCalendarMonthViews.swift", "private var visibleEvents"),
            ("Cadence/iOS/iOSCalendarView.swift", "iOSCalendarTimelineGrid("),
            ("Cadence/iOS/iOSTodaySchedulePanel.swift", "iOSCalendarTimelineGrid(")
        ] {
            #expect(
                try strippingComments(sourceFile(path)).contains(witness),
                "\(path) no longer holds \(witness); re-anchor this witness"
            )
        }
    }
}

// MARK: - Source-reading helpers

// `matches(_:in:)`, the regular-expression counter, was declared here, with
// `thePatternHelperMatchesWhatItLooksLike` as its self-check. Its only callers were the two
// branch-placement tests [[T-3170]] retired above; `expectOccurrences` and `presenterCounts` are
// literal counts and need no pattern.

/// Every file under `relativeDirectory` holding `text` as live code, and how many times.
///
/// An empty dictionary is the shape every absence test here asserts. It is a *repo-wide* reading
/// on purpose: a per-file zero cannot see the same surface reappearing in a new file, which is how
/// a deleted view comes back.
private func presenterCounts(of text: String, under relativeDirectory: String = "Cadence") throws -> [String: Int] {
    var counts: [String: Int] = [:]
    for path in try swiftFiles(under: relativeDirectory) {
        let count = try strippingComments(sourceFile(path)).components(separatedBy: text).count - 1
        if count > 0 { counts[path] = count }
    }
    return counts
}

/// Fails unless `text` occurs exactly `count` times as live code in each listed file.
private func expectOccurrences(
    of text: String,
    at files: [String: Int],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    for (path, expected) in files {
        let code = try strippingComments(sourceFile(path))
        let actual = code.components(separatedBy: text).count - 1
        #expect(
            actual == expected,
            "\(path) contains \(text) \(actual) times, expected \(expected)",
            sourceLocation: sourceLocation
        )
    }
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// Enumerated by `enumerator(atPath:)` rather than `enumerator(at:)` on purpose: the URL variant
/// yields *absolute* paths, and `#filePath` can name the repo through a symlinked prefix
/// (`/tmp` against `/private/tmp` on an isolated build tree) that `FileManager` resolves and the
/// literal does not.
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
    // T-1269/T-1270: one pass per pattern, in CadenceSourceScan, on the guarded
    // `(?<!:)//` that the slashes in a URL cannot trigger.
    return CadenceSourceScan.strippingComments(source)
}
