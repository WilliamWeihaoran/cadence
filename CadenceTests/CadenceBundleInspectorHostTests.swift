import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-217: **the iOS bundle panel used to dismiss itself the moment an edit succeeded.**
///
/// `iOSCalendarBundleDetailSheet` was presented by the card that opened it — `@State showDetail` plus
/// `.sheet(isPresented:)` on `iOSCalendarBoardBundleCard` and on `iOSTimelineBundleBlock`. Both sit
/// inside a `ForEach(bundles)` that the surface has already filtered by day, and Today's schedule
/// pane filters the same block by *hour* on top of that. So the panel's own Save — the write that
/// changes `dateKey` or `startMin` — moved the block out of the collection drawing it, SwiftUI removed
/// the card, and the sheet went with it. T-201's defect exactly, one subject over, and nothing in the
/// panel called `dismiss()`.
///
/// Two kinds of test, as in `CadenceTaskInspectorHostTests`. The decision is a value type in
/// `Shared/` — the *same* one the task inspector reads, because nothing in it was ever about an
/// `AppTask` — and is tested against a real store. The ownership, which is the actual fix, cannot be
/// compiled here: all of `Cadence/iOS/` is inside `#if os(iOS)` and this target builds for macOS. So
/// it is pinned as source text with exact per-file counts, and `theSourceScanIsNotVacuous` stops a
/// broken reader making every zero pass silently.
@MainActor
struct CadenceBundleInspectorHostTests {

    // MARK: - The premise: the edit that used to close the panel

    /// **The bug, reproduced as data.** A bundle re-dated and re-timed from inside its own panel
    /// leaves the day query the Calendar surfaces draw it from *and* the hour query Today's pane
    /// draws it from — and the panel must survive both, because the user just typed that date.
    ///
    /// This is the bundle's version of `cancellingATaskLeavesTheModelForTheHostToKeepShowing`: the
    /// model is untouched by the write that removed the card, so a host holding the model has
    /// something to keep rendering.
    @Test func reschedulingABundleOutOfTheDayAndHourQueriesKeepsThePanelOpen() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let bundle = TaskBundle(title: "Admin sweep", dateKey: "2026-08-21", startMin: 600, durationMinutes: 30)
        context.insert(bundle)
        try context.save()

        #expect(
            CadenceScheduleSupport.bundlesByDate([bundle], includeCompleted: false)["2026-08-21"]?
                .map(\.id) == [bundle.id]
        )
        #expect(CadenceScheduleSupport.bundles(inHourRow: 10, from: [bundle]).map(\.id) == [bundle.id])

        // The panel's Save, spelled the way the panel spells it.
        CadenceTaskMutationSupport.updateBundle(
            bundle,
            title: "Admin sweep",
            dateKey: "2026-08-24",
            startMin: 900,
            durationMinutes: 30,
            modelContext: context
        )

        // Both collections the two converted surfaces draw from have dropped it…
        #expect(CadenceScheduleSupport.bundlesByDate([bundle], includeCompleted: false)["2026-08-21"] == nil)
        #expect(CadenceScheduleSupport.bundles(inHourRow: 10, from: [bundle]).isEmpty)
        // …and it is exactly where the edit put it.
        #expect(bundle.dateKey == "2026-08-24")
        #expect(bundle.startMin == 900)
        // …while the panel stays, which is the whole point.
        #expect(
            CadenceDetailPanelPresentation.resolveHeldSubject(
                isDeleted: bundle.isDeleted,
                hasNoModelContext: bundle.modelContext == nil
            ) == .stay
        )
    }

    /// The measured guard, re-measured on a `TaskBundle` rather than assumed to carry over. Both
    /// halves of a real delete report through *different* properties, which is why the rule reads two
    /// signals and why a draft guarding on `isDeleted` alone would pass the first half of this test
    /// and fail the second.
    @Test func deletingTheBundleUnderneathThePanelClosesItInBothPhasesOfTheDelete() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let bundle = TaskBundle(title: "Batch", dateKey: "2026-08-21", startMin: 600, durationMinutes: 30)
        context.insert(bundle)
        try context.save()

        #expect(
            CadenceDetailPanelPresentation.resolveHeldSubject(
                isDeleted: bundle.isDeleted,
                hasNoModelContext: bundle.modelContext == nil
            ) == .stay
        )

        context.delete(bundle)
        #expect(bundle.isDeleted, "a pending delete stopped reporting through isDeleted")
        #expect(
            CadenceDetailPanelPresentation.resolveHeldSubject(
                isDeleted: bundle.isDeleted,
                hasNoModelContext: bundle.modelContext == nil
            ) == .close
        )

        try context.save()
        #expect(bundle.modelContext == nil, "a committed delete stopped detaching the model context")
        #expect(try context.fetch(FetchDescriptor<TaskBundle>()).isEmpty)
        #expect(
            CadenceDetailPanelPresentation.resolveHeldSubject(
                isDeleted: bundle.isDeleted,
                hasNoModelContext: bundle.modelContext == nil
            ) == .close
        )
    }

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

        CadenceTaskMutationSupport.deleteBundle(bundle, modelContext: context)

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

        CadenceTaskMutationSupport.deleteBundle(bundle, modelContext: context)

        let survivor = try #require(try context.fetch(FetchDescriptor<AppTask>()).first)
        #expect(survivor.calendarEventID == "")
        // The rest of the loop must be untouched by the fix.
        #expect(survivor.bundle == nil)
        #expect(survivor.scheduledDate == "2026-08-21")
    }

    // MARK: - Ownership: no card presents the bundle panel

    /// The two surfaces that owned presentation from a card. Each carried exactly one
    /// `@State private var showDetail` and one `.sheet(isPresented: $showDetail)` before the fix and
    /// carries neither now — and `CadenceTaskInspectorHostTests` pinned those two survivors at `1`
    /// while T-201 was fixing the task half, which is how this defect stayed visible rather than
    /// being rediscovered.
    @Test func noCardStillOwnsBundlePanelPresentationState() throws {
        try expectOccurrences(
            of: "@State private var showDetail",
            at: [
                "Cadence/iOS/iOSBoardCards.swift": 0,
                "Cadence/iOS/iOSCalendarTimelineViews.swift": 0
            ]
        )
        try expectOccurrences(
            of: ".sheet(isPresented: $showDetail)",
            at: [
                "Cadence/iOS/iOSBoardCards.swift": 0,
                "Cadence/iOS/iOSCalendarTimelineViews.swift": 0
            ]
        )
        // …and each asks the host instead, twice: the card's own tap and its "Edit Block" context
        // menu item are two controls onto one panel.
        try expectOccurrences(
            of: "bundleInspector(bundle)",
            at: [
                "Cadence/iOS/iOSBoardCards.swift": 2,
                "Cadence/iOS/iOSCalendarTimelineViews.swift": 2
            ]
        )
        try expectOccurrences(
            of: "@Environment(\\.iOSBundleInspector)",
            at: [
                "Cadence/iOS/iOSBoardCards.swift": 1,
                "Cadence/iOS/iOSCalendarTimelineViews.swift": 1
            ]
        )
    }

    /// **Every presenter of the bundle panel, counted — and since T-347 there is exactly one.**
    ///
    /// This read *three* until T-347: the host, plus `iOSCalendarDayInspector` and
    /// `iOSCalendarMonthAgendaList`, which each hold the selection on the pane and attach
    /// `.sheet(item:)` above the conditional deciding whether the pane lists anything, so a bundle
    /// edited out of that day or month empties a section rather than removing the presenter. That
    /// ownership argument is unchanged and still correct — but both panes reached
    /// `iOSCalendarBundleDetailSheet` directly, so neither consulted
    /// `CadenceDetailPanelPresentation`, and a delete arriving while one was open left it bound to a
    /// dead bundle.
    ///
    /// Both keep their presentation and borrow the guard. What is left is the stronger invariant:
    /// **the bundle panel is drawn only behind the wrapper that has just asked whether the bundle
    /// still exists.** A new direct `.sheet { iOSCalendarBundleDetailSheet(...) }` anywhere fails
    /// here, and would otherwise be invisible to a test suite that cannot build this folder.
    @Test func theBundlePanelIsDrawnOnlyBehindTheGuardedWrapper() throws {
        var presenters: [String: Int] = [:]
        for path in try swiftFiles(under: "Cadence") {
            let count = try strippingComments(sourceFile(path))
                .components(separatedBy: "iOSCalendarBundleDetailSheet(").count - 1
            if count > 0 {
                presenters[path] = count
            }
        }

        #expect(
            presenters == [
                // The wrapper's `.stay` branch, and nowhere else at all.
                "Cadence/iOS/iOSBundleInspectorHost.swift": 1
            ],
            "presenters of iOSCalendarBundleDetailSheet changed: \(presenters)"
        )
    }

    /// The other side of that count: the three places that present, all now through the guard.
    /// Without this, deleting a `.sheet` outright would leave the panel count at one and read green.
    @Test func everyPaneThatPresentsTheBundlePanelGoesThroughTheGuardedWrapper() throws {
        var presenters: [String: Int] = [:]
        for path in try swiftFiles(under: "Cadence") {
            let count = try strippingComments(sourceFile(path))
                .components(separatedBy: "iOSBundleInspectorSheet(").count - 1
            if count > 0 {
                presenters[path] = count
            }
        }

        #expect(
            presenters == [
                // The host. The only one reached from a card.
                "Cadence/iOS/iOSBundleInspectorHost.swift": 1,
                // Pane-owned `.sheet(item:)`, immune to re-filtering, guarded since T-347.
                "Cadence/iOS/iOSCalendarInspectorView.swift": 1,
                "Cadence/iOS/iOSCalendarMonthAgendaViews.swift": 1
            ],
            "presenters of iOSBundleInspectorSheet changed: \(presenters)"
        )
    }

    /// One host, applied once, above both shells — the placement `iOSTaskInspectorHost()` and
    /// `cadenceStartupIssueBanner` have, for the same reason. The two live mentions are the
    /// declaration and that single application; a second application anywhere would mean two hosts
    /// racing to present, which on iOS means the inner one silently does nothing.
    @Test func exactlyOneBundleHostIsInstalledAndItIsAboveBothShells() throws {
        var applications: [String: Int] = [:]
        for path in try swiftFiles(under: "Cadence") {
            let count = try strippingComments(sourceFile(path))
                .components(separatedBy: "iOSBundleInspectorHost()").count - 1
            if count > 0 {
                applications[path] = count
            }
        }

        #expect(
            applications == [
                "Cadence/iOS/iOSBundleInspectorHost.swift": 1,
                "Cadence/iOS/iOSRootView.swift": 1
            ],
            "iOSBundleInspectorHost applications changed: \(applications)"
        )
        // Beside the task host rather than instead of it: the two panels are independent, and a
        // shell that lost one of them would still open the other.
        try expectOccurrences(
            of: ".iOSTaskInspectorHost()",
            at: ["Cadence/iOS/iOSRootView.swift": 1]
        )
    }

    // MARK: - Where in the file, not just how many (T-161)

    /// **The per-file half of the two counts above.** The repo-wide dictionaries are the right
    /// shape for "exactly N places in the whole app"; neither can say *where* in a file its one
    /// occurrence sits, and `cfa3b3b` is the standing proof that a call moving between two
    /// functions in one file is invisible to a count.
    ///
    /// The move that matters here is the panel leaving the `.stay` branch. `iOSBundleInspectorSheet`
    /// exists to ask `CadenceDetailPanelPresentation.resolveHeldSubject` whether the held bundle is
    /// still a thing to draw; swapping its two branches leaves `iOSCalendarBundleDetailSheet(` at
    /// exactly one occurrence in exactly this file, with every card in the app opening nothing.
    @Test func theBundleHostDrawsThePanelOnlyInTheStayBranchOfTheSharedRule() throws {
        let host = try strippingComments(sourceFile("Cadence/iOS/iOSBundleInspectorHost.swift"))

        #expect(
            matches(#"case \.stay:\s*iOSCalendarBundleDetailSheet\(bundle: bundle\)"#, in: host) == 1,
            "the bundle panel is not drawn directly in the .stay branch of resolveHeldSubject"
        )
        #expect(
            matches(#"case \.close:\s*Color\.clear\.onAppear\(perform: close\)"#, in: host) == 1,
            "the .close branch no longer clears the selection instead of drawing the panel"
        )

        // The modifier hands the sheet's content to the rule-checking view, never to the panel:
        // presenting `iOSCalendarBundleDetailSheet` straight from `.sheet(item:)` would also read
        // as one occurrence in one file, and would bind a deleted model.
        let modifier = try cadenceFunctionBody("func body(content: Content) -> some View", in: host)
        #expect(modifier.contains(".sheet(item: $selection)"))
        #expect(modifier.contains("iOSBundleInspectorSheet(bundle: bundle)"))
        #expect(!modifier.contains("iOSCalendarBundleDetailSheet("))
    }

    /// **"Above both shells" was a count of one in `iOSRootView.swift`.** Moving
    /// `.iOSBundleInspectorHost()` inside the `horizontalSizeClass == .regular` branch — iPad gets
    /// the bundle panel, the iPhone's board and timeline get dead taps — keeps that count at one.
    /// So the claim is stated as placement: the two shells are the `Group`'s two branches, and the
    /// host is applied to the `Group` rather than inside it.
    @Test func theRootAppliesTheBundleHostAboveBothShellsRatherThanInsideOne() throws {
        let root = try strippingComments(sourceFile("Cadence/iOS/iOSRootView.swift"))
        let body = try cadenceFunctionBody("var body: some View", in: root)
        let shells = try cadenceFunctionBody("Group", in: body)

        #expect(shells.contains("iPadMacStyleRootShell("))
        #expect(shells.contains("iOSCompactRootShell("))
        #expect(body.contains(".iOSBundleInspectorHost()"))
        #expect(
            !shells.contains(".iOSBundleInspectorHost()"),
            "the bundle host is applied inside one shell branch rather than above both"
        )
    }

    /// **Self-check on the pattern helper.** A typo matches nothing, and every `== 1` above becomes
    /// a silent zero-that-should-have-been-one.
    @Test func thePatternHelperMatchesWhatItLooksLike() {
        #expect(matches(#"case \.stay:\s*iOSCalendarBundleDetailSheet\(bundle: bundle\)"#, in: "case .stay:\n    iOSCalendarBundleDetailSheet(bundle: bundle)") == 1)
        #expect(matches(#"case \.stay:\s*iOSCalendarBundleDetailSheet\(bundle: bundle\)"#, in: "case .close:\n    iOSCalendarBundleDetailSheet(bundle: bundle)") == 0)
        #expect(matches("case (", in: "case (") == -1)
    }

    /// The host reads the shared decision rather than re-deciding, about the two facts it can observe
    /// for itself — and it is the *shared* one, not a bundle-shaped copy of a measured rule. A host
    /// that started consulting a `@Query` here would be the page's filter creeping back into the
    /// panel's lifetime by another route.
    @Test func theBundleHostAsksTheOneSharedRuleAboutTheTwoFactsItCanSee() throws {
        try expectOccurrences(
            of: "CadenceDetailPanelPresentation.resolveHeldSubject(",
            at: [
                "Cadence/iOS/iOSBundleInspectorHost.swift": 1,
                // The task host reads the identical call. Two hosts, one rule.
                "Cadence/iOS/iOSTaskInspectorHost.swift": 1
            ]
        )
        // Both signals, at the one call site. `isDeleted` on its own is the draft that did not work.
        try expectOccurrences(
            of: "isDeleted: bundle.isDeleted",
            at: ["Cadence/iOS/iOSBundleInspectorHost.swift": 1]
        )
        try expectOccurrences(
            of: "hasNoModelContext: bundle.modelContext == nil",
            at: ["Cadence/iOS/iOSBundleInspectorHost.swift": 1]
        )
        try expectOccurrences(
            of: "@Query",
            at: ["Cadence/iOS/iOSBundleInspectorHost.swift": 0]
        )
        // The rule kept its old name in no file at all — a second copy under the old noun is the one
        // outcome this consolidation exists to prevent.
        for path in try swiftFiles(under: "Cadence") {
            let code = try strippingComments(sourceFile(path))
            #expect(
                !code.contains("CadenceTaskInspectorPresentation"),
                "\(path) still names the pre-T-217 spelling of the shared rule"
            )
        }
    }

    /// Without this, every zero above could be a scan reading an empty string — the failure mode a
    /// `/tmp` against `/private/tmp` path mismatch produces on an isolated build tree.
    @Test func theSourceScanIsNotVacuousInBundleInspectorHost() throws {
        let files = try swiftFiles(under: "Cadence")

        #expect(files.count > 300, "the source scan found \(files.count) files and cannot be doing its job")
        for path in [
            "Cadence/iOS/iOSBundleInspectorHost.swift",
            "Cadence/iOS/iOSTaskInspectorHost.swift",
            "Cadence/iOS/iOSRootView.swift",
            "Cadence/iOS/iOSBoardCards.swift",
            "Cadence/iOS/iOSCalendarTimelineViews.swift",
            "Cadence/iOS/iOSCalendarInspectorView.swift",
            "Cadence/iOS/iOSCalendarMonthAgendaViews.swift",
            "Cadence/iOS/iOSCalendarBundleDetailSheet.swift",
            "Cadence/iOS/iOSTodaySchedulePanel.swift",
            "Cadence/Shared/CadenceDetailPanelPresentation.swift"
        ] {
            #expect(files.contains(path))
        }

        // The needles above are only meaningful if the text they are looking for is really there.
        let host = try strippingComments(sourceFile("Cadence/iOS/iOSBundleInspectorHost.swift"))
        #expect(host.contains("func iOSBundleInspectorHost()"))
        #expect(host.contains(".sheet(item: $selection)"))
        let card = try strippingComments(sourceFile("Cadence/iOS/iOSBoardCards.swift"))
        #expect(card.contains("struct iOSCalendarBoardBundleCard: View"))
        let block = try strippingComments(sourceFile("Cadence/iOS/iOSCalendarTimelineViews.swift"))
        #expect(block.contains("struct iOSTimelineBundleBlock: View"))
        // The two panes that keep ownership really do keep it the way this file says they do.
        for path in ["Cadence/iOS/iOSCalendarInspectorView.swift", "Cadence/iOS/iOSCalendarMonthAgendaViews.swift"] {
            let pane = try strippingComments(sourceFile(path))
            #expect(pane.contains("@State private var selectedBundle: TaskBundle?"))
            #expect(pane.contains(".sheet(item: $selectedBundle)"))
        }
    }
}

// MARK: - Source-reading helpers

/// Occurrence count for a regular expression. Returns `-1` on a malformed pattern so a typo reads
/// as a failure rather than as zero matches; `thePatternHelperMatchesWhatItLooksLike` is the
/// self-check.
private func matches(_ pattern: String, in text: String) -> Int {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return -1 }
    return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
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
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound)))
        }
    }
    return result
}
