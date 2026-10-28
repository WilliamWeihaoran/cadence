import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-201: **the iOS task inspector used to dismiss itself on any status change.**
///
/// `iOSTaskDetailSheet` was presented by `iOSTaskRow` — `@State showDetail` plus
/// `.sheet(isPresented:)` on the row — so a status write made from inside the panel moved the task
/// out of the section's `ForEach`, SwiftUI tore the row down, and the sheet went with it. No status
/// path called `dismiss()`; the proof was the control experiment, since **Start** goes through the
/// same `onSetStatus` and keeps the row in ACTIVE, and left the panel open.
///
/// Two kinds of test here, for the reason `CadenceCancelledTaskReachabilityTests` sets out. The
/// decision — what a host does with a selection the page can no longer see — is a value type in
/// `Shared/` and is tested directly. The *ownership*, which is the actual fix, cannot be: all of
/// `Cadence/iOS/` is inside `#if os(iOS)` and this target builds for macOS. So it is pinned as
/// source text with exact per-file counts, and `theSourceScanIsNotVacuousInTaskInspectorHost` stops a broken reader
/// making every zero pass silently.
@MainActor
struct CadenceTaskInspectorHostTests {

    // MARK: - What a host does with a selection the page can no longer see

    /// The whole rule. A gone task closes the panel; leaving the page's own query does not, in
    /// either combination — which is the half a "tidy up the selection" change would get wrong.
    @Test func onlyAGoneTaskClosesTheInspector() {
        #expect(
            CadenceDetailPanelPresentation.resolve(subjectIsGone: false, subjectLeftThePageQuery: false)
                == .stay
        )
        #expect(
            CadenceDetailPanelPresentation.resolve(subjectIsGone: false, subjectLeftThePageQuery: true)
                == .stay
        )
        #expect(
            CadenceDetailPanelPresentation.resolve(subjectIsGone: true, subjectLeftThePageQuery: false)
                == .close
        )
        #expect(
            CadenceDetailPanelPresentation.resolve(subjectIsGone: true, subjectLeftThePageQuery: true)
                == .close
        )
    }

    /// Three signals, any one of them sufficient. `isDeleted` catches the pending delete, a nil
    /// `modelContext` the committed one, and a missing row a delete saved in another context
    /// ([[T-7561]]); the real-store tests below and in `CadenceHeldNoteSheetGuardTests` are why.
    ///
    /// The rule is `CadenceDetailPanelPresentation` rather than `CadenceTaskInspectorPresentation`
    /// since T-217: nothing in it is about an `AppTask`, and the bundle panel's host needed exactly
    /// it. `CadenceBundleInspectorHostTests` measures the same two phases against a `TaskBundle`.
    @Test func aHeldTaskIsGoneIfAnySignalSaysSo() {
        // Every combination of the three, so a mutation that drops any one of them is a named red.
        for isDeleted in [false, true] {
            for hasNoModelContext in [false, true] {
                for rowIsMissing in [false, true] {
                    let gone = isDeleted || hasNoModelContext || rowIsMissing
                    #expect(
                        CadenceDetailPanelPresentation.heldSubjectIsGone(
                            isDeleted: isDeleted,
                            hasNoModelContext: hasNoModelContext,
                            rowIsMissingFromItsContext: rowIsMissing
                        ) == gone,
                        "isDeleted \(isDeleted), no context \(hasNoModelContext), row missing \(rowIsMissing)"
                    )
                    #expect(
                        CadenceDetailPanelPresentation.resolveHeldSubject(
                            isDeleted: isDeleted,
                            hasNoModelContext: hasNoModelContext,
                            rowIsMissingFromItsContext: rowIsMissing
                        ) == (gone ? .close : .stay)
                    )
                }
            }
        }
    }

    /// The premise the ownership fix rests on, run against a real store rather than argued:
    /// **cancelling is not deleting.** The model survives `markCancelled`, so a host holding it has
    /// something to keep rendering — while Today's active sections stop listing it, which is exactly
    /// the filtering that used to take the panel down with the row.
    @Test func cancellingATaskLeavesTheModelForTheHostToKeepShowing() throws {
        let todayKey = "2026-08-21"
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let subject = AppTask(title: "cancel me")
        subject.scheduledDate = todayKey
        context.insert(subject)
        try context.save()
        CadenceTaskRecurrenceWorkflowSupport.markCancelled(subject, in: context, now: Date())

        #expect(subject.isCancelled)
        #expect(
            CadenceDetailPanelPresentation.resolveHeldSubject(heldModel: subject) == .stay
        )
        #expect(
            CadenceTaskQuerySupport.activeTodayTasks(from: [subject], todayKey: todayKey, sortMode: .listOrder)
                .isEmpty
        )
    }

    /// The extreme case, and **the measurement that decided the guard's shape.** A first draft read
    /// `isDeleted` alone and this test is what killed it: across a real delete, the two halves of the
    /// lifecycle report through *different* properties. Measured on Xcode 27.0 (macOS 27.0,
    /// arm64, `en_US_POSIX`/UTC as the test action pins them), 2026-09-25 —
    /// - after `delete(_:)` and before the save, `isDeleted` is the one that is true;
    /// - after the save, `modelContext` is the one that is nil.
    ///
    /// **That split is bounded here, not pinned (T-1318).** Which signal fires in which half is
    /// SwiftData's answer and not this app's, and this repository builds on two Xcode majors that
    /// have already disagreed once about a neighbouring one — [[T-1279]] pinned 26's `rollback()`
    /// and went red locally, [[T-1296]] pinned 27's and turned CI red. Each looked like a fix and
    /// was a swap of which environment was broken. So each phase asserts the property the host
    /// actually needs and that no toolchain may take away: **at least one** of the two signals
    /// fires, and the combined predicate closes the inspector.
    ///
    /// Neither is asserted as "the other one is false", because that would pin SwiftData's
    /// internals rather than our rule; and the `.stay` above the delete is the non-vacuity that
    /// says neither signal fires while the task is alive, so "at least one" is not a disjunction
    /// that was already true.
    @Test func deletingTheTaskUnderneathTheInspectorClosesItInBothPhasesOfTheDelete() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let subject = AppTask(title: "delete me")
        context.insert(subject)
        try context.save()

        #expect(
            CadenceDetailPanelPresentation.resolveHeldSubject(heldModel: subject) == .stay
        )

        context.delete(subject)
        #expect(
            subject.isDeleted || subject.modelContext == nil,
            "a pending delete reported through neither of the two signals the guard reads"
        )
        #expect(
            CadenceDetailPanelPresentation.resolveHeldSubject(heldModel: subject) == .close
        )

        try context.save()
        #expect(
            subject.isDeleted || subject.modelContext == nil,
            "a committed delete reported through neither of the two signals the guard reads"
        )
        // The store's own half, which is not an observation of anything: the row is gone.
        #expect(try context.fetch(FetchDescriptor<AppTask>()).isEmpty)
        #expect(
            CadenceDetailPanelPresentation.resolveHeldSubject(heldModel: subject) == .close
        )
    }

    // MARK: - Ownership: no row presents the inspector

    /// The four surfaces that owned presentation from a row or a card. Each had exactly one
    /// `iOSTaskDetailSheet(task:)` before the fix and has none now — the crisp retired spelling,
    /// rather than `.sheet(isPresented:`, which was ambiguous in these two calendar files for as
    /// long as they also presented a *bundle* sheet that way. T-217 took that second sheet off both
    /// of them, so the ambiguity is gone; the needle is still the specific one, because a needle
    /// that only works while a neighbouring defect exists is not the needle to keep.
    @Test func noRowOrCardStillPresentsTheInspector() throws {
        try expectOccurrences(
            of: "iOSTaskDetailSheet(",
            at: [
                "Cadence/iOS/iOSTaskViews.swift": 0,
                "Cadence/iOS/iOSBoardCards.swift": 0,
                "Cadence/iOS/iOSCalendarTimelineViews.swift": 0,
                "Cadence/iOS/iOSTodaySchedulePanel.swift": 0
            ]
        )
        // …and each asks the host instead. `iOSTodaySchedulePanel` reads **zero** since T-1273:
        // it used to ask twice, from `iOSScheduleReadyTaskRow`'s title button and its trailing info
        // button, and the whole "Ready to Schedule" stack those two lived in is gone. The blocks
        // still drawn on that pane are `iOSTimelineTaskBlock`, which asks from the file above it.
        // The entry stays at `0` rather than leaving the list, for the same reason the four `0`s in
        // the check above stay: this pane presenting an inspector again is the regression.
        try expectOccurrences(
            of: "taskInspector(task)",
            at: [
                "Cadence/iOS/iOSTaskViews.swift": 1,
                "Cadence/iOS/iOSBoardCards.swift": 1,
                "Cadence/iOS/iOSCalendarTimelineViews.swift": 1,
                "Cadence/iOS/iOSTodaySchedulePanel.swift": 0
            ]
        )
        try expectOccurrences(
            of: "@Environment(\\.iOSTaskInspector)",
            at: [
                "Cadence/iOS/iOSTaskViews.swift": 1,
                "Cadence/iOS/iOSBoardCards.swift": 1,
                "Cadence/iOS/iOSCalendarTimelineViews.swift": 1,
                "Cadence/iOS/iOSTodaySchedulePanel.swift": 0
            ]
        )
    }

    /// The row's own presentation state is gone, and so is the `Binding<Bool>` it handed its context
    /// menu. Both spellings existed exactly once before the fix and nowhere after it — the context
    /// menu takes an `openDetail` action now, so no call site can hold the flag again by accident.
    @Test func theRowNoLongerOwnsAnyInspectorPresentationState() throws {
        try expectOccurrences(
            of: "@State private var showDetail",
            at: [
                "Cadence/iOS/iOSTaskViews.swift": 0,
                "Cadence/iOS/iOSTodaySchedulePanel.swift": 0,
                // These two read `1` until T-217, and the survivor in each was the Block card /
                // Block block presenting its own detail sheet from inside a filtered `ForEach` —
                // the same defect on a different sheet, pinned here rather than fixed because it
                // needed a Block host and not this one. T-217 gave it one and [[T-3170]] deleted
                // the Block feature outright, so no card in this app owns detail-panel
                // presentation state at all; `CadenceBundleInspectorHostTests` is where that half
                // is asserted.
                "Cadence/iOS/iOSBoardCards.swift": 0,
                "Cadence/iOS/iOSCalendarTimelineViews.swift": 0
            ]
        )
        try expectOccurrences(
            of: "showDetail: $showDetail",
            at: ["Cadence/iOS/iOSTaskViews.swift": 0]
        )
        try expectOccurrences(
            of: "@Binding var showDetail",
            at: ["Cadence/iOS/iOSTaskRowActionViews.swift": 0]
        )
        try expectOccurrences(
            of: "let openDetail: () -> Void",
            at: ["Cadence/iOS/iOSTaskRowActionViews.swift": 1]
        )
    }

    /// **Every presenter of the inspector, counted — and since T-347 there is exactly one.**
    ///
    /// This read *five* until T-347: the host, plus four surfaces left alone because each already
    /// owns its presentation on a view that does not re-filter under it. That reasoning was about
    /// **ownership**, and it is still right — three of the four present from inside a sheet, where a
    /// host above the sheet is already presenting and a request to it would do nothing. But those
    /// four reached `iOSTaskDetailSheet` *directly*, which meant they also skipped
    /// `CadenceDetailPanelPresentation`, and an external delete arriving while one of them was open
    /// left it bound to a dead model.
    ///
    /// So the four keep their presentation and gain the guard, by presenting the same
    /// `iOSTaskInspectorSheet` wrapper the host does. The invariant that leaves is strictly stronger
    /// than the one it replaces and is the fourth step T-347 asked for: **nothing in this app draws
    /// `iOSTaskDetailSheet` except the wrapper that has just asked whether the task still exists.**
    /// A new direct `.sheet { iOSTaskDetailSheet(...) }` anywhere — row-owned (the T-201 regression)
    /// or page-owned (the T-347 one) — fails here, and it is otherwise invisible to a test suite
    /// that cannot build this folder.
    @Test func theInspectorPanelIsDrawnOnlyBehindTheGuardedWrapper() throws {
        var presenters: [String: Int] = [:]
        for path in try swiftFiles(under: "Cadence") {
            let count = try strippingComments(sourceFile(path))
                .components(separatedBy: "iOSTaskDetailSheet(").count - 1
            if count > 0 {
                presenters[path] = count
            }
        }

        #expect(
            presenters == [
                // The wrapper's `.stay` branch, and nowhere else at all.
                "Cadence/iOS/iOSTaskInspectorHost.swift": 1
            ],
            "presenters of iOSTaskDetailSheet changed: \(presenters)"
        )
    }

    /// The other side of the same count: the five places that *present*, all now through the guard.
    /// Counting the wrapper as well as the panel is what stops the fix being undone by deletion —
    /// dropping a `.sheet` entirely would leave the panel count at one and read as green.
    @Test func everySurfaceThatPresentsTheInspectorGoesThroughTheGuardedWrapper() throws {
        var presenters: [String: Int] = [:]
        for path in try swiftFiles(under: "Cadence") {
            let count = try strippingComments(sourceFile(path))
                .components(separatedBy: "iOSTaskInspectorSheet(").count - 1
            if count > 0 {
                presenters[path] = count
            }
        }

        #expect(
            presenters == [
                // The host. The only one reached from a row.
                "Cadence/iOS/iOSTaskInspectorHost.swift": 1,
                // Page-owned `.sheet(item:)`, immune to re-filtering, guarded since T-347.
                "Cadence/iOS/iOSSearchView.swift": 1,
                // Sheet-owned `.sheet(item:)` — a nearer host would have to live inside the sheet.
                "Cadence/iOS/iOSMarkdownEditingSurface.swift": 1,
                "Cadence/iOS/iOSMarkdownReferenceSupport.swift": 1
                // `iOSCalendarBundleDetailSheet.swift` was the fifth, and was one of T-201's
                // deliberate exceptions — a sheet presenting the task inspector from inside a
                // sheet. [[T-3170]] deleted it with the Block feature.
            ],
            "presenters of iOSTaskInspectorSheet changed: \(presenters)"
        )
    }

    /// One host above both shells. T-3078 removed the callerless past-due list sheet and its
    /// nested host. Keep this manifest-listed test name so its whole-product inventory remains
    /// registered; the exact surviving set rejects a revived sheet host or another stray owner.
    @Test func theHostIsInstalledAboveBothShellsAndInsideTheOneSheetThatCarriesAPage() throws {
        var applications: [String: Int] = [:]
        for path in try swiftFiles(under: "Cadence") {
            let count = try strippingComments(sourceFile(path))
                .components(separatedBy: "iOSTaskInspectorHost()").count - 1
            if count > 0 {
                applications[path] = count
            }
        }

        #expect(
            applications == [
                "Cadence/iOS/iOSTaskInspectorHost.swift": 1,
                "Cadence/iOS/iOSRootView.swift": 1
            ],
            "iOSTaskInspectorHost applications changed: \(applications)"
        )
        try expectOccurrences(
            of: ".cadenceStartupIssueBanner(PersistenceController.startupIssue)",
            at: ["Cadence/iOS/iOSRootView.swift": 1]
        )
    }

    // MARK: - Where in the file, not just how many (T-161)

    /// **The per-file half of the two counts above.** A repo-wide dictionary is the right shape for
    /// "exactly N places in the whole app"; what it cannot say is *where* in each file the one
    /// occurrence sits, and `cfa3b3b` is the standing proof that a call moving between two
    /// functions in one file is invisible to a count.
    ///
    /// Here the move that matters is the panel leaving the `.stay` branch. `iOSTaskInspectorSheet`
    /// exists to ask `CadenceDetailPanelPresentation.resolveHeldSubject` whether the held task is
    /// still a thing to draw; swapping its two branches — panel on `.close`, `Color.clear` on
    /// `.stay` — leaves `iOSTaskDetailSheet(` at exactly one occurrence in exactly this file, and
    /// every assertion in this suite green while tapping a row opens nothing.
    @Test func theHostDrawsThePanelOnlyInTheStayBranchOfTheSharedRule() throws {
        let host = try strippingComments(sourceFile("Cadence/iOS/iOSTaskInspectorHost.swift"))

        #expect(
            matches(#"case \.stay:\s*iOSTaskDetailSheet\(task: task\)"#, in: host) == 1,
            "the inspector is not drawn directly in the .stay branch of resolveHeldSubject"
        )
        #expect(
            matches(#"case \.close:\s*Color\.clear\.onAppear\(perform: close\)"#, in: host) == 1,
            "the .close branch no longer clears the selection instead of drawing the panel"
        )

        // The modifier hands the sheet's content to the rule-checking view, never to the panel:
        // presenting `iOSTaskDetailSheet` straight from `.sheet(item:)` would also read as one
        // occurrence in one file, and would bind a deleted model.
        let modifier = try cadenceFunctionBody("func body(content: Content) -> some View", in: host)
        #expect(modifier.contains(".sheet(item: $selection)"))
        #expect(modifier.contains("iOSTaskInspectorSheet(task: task)"))
        #expect(!modifier.contains("iOSTaskDetailSheet("))
    }

    /// **"Above both shells" was a count of one in `iOSRootView.swift`.** Moving
    /// `.iOSTaskInspectorHost()` inside the `horizontalSizeClass == .regular` branch — iPad gets the
    /// inspector, iPhone's four tabs get dead taps — keeps that count at one. So the claim is
    /// stated as placement: the two shells are the `Group`'s two branches, and the host and the
    /// startup banner are applied to the `Group` rather than inside it. (The bundle host was the
    /// third subject of this placement claim until [[T-3170]] deleted it.)
    @Test func theRootAppliesTheHostAboveBothShellsRatherThanInsideOne() throws {
        let root = try strippingComments(sourceFile("Cadence/iOS/iOSRootView.swift"))
        let body = try cadenceFunctionBody("var body: some View", in: root)
        let shells = try cadenceFunctionBody("Group", in: body)

        #expect(shells.contains("iPadMacStyleRootShell("))
        #expect(shells.contains("iOSCompactRootShell("))

        for modifier in [
            ".iOSTaskInspectorHost()",
            // `.iOSBundleInspectorHost()` was the third entry here. [[T-3170]] emptied the
            // modifier, then the `iOSRootView.swift` grant let the call site and the file go
            // together; its absence is pinned by
            // `CadenceBundleInspectorHostTests.theBlockPanelsLastLineIsGoneFromTheTreeEntirely`.
            ".cadenceStartupIssueBanner(PersistenceController.startupIssue)"
        ] {
            #expect(
                body.contains(modifier),
                "iOSRootView's body no longer applies \(modifier)"
            )
            #expect(
                !shells.contains(modifier),
                "\(modifier) is applied inside one shell branch rather than above both"
            )
        }
    }

    /// The retired sheet cannot reintroduce a nested inspector owner on Today's task groups.
    @Test func theRetiredTodayListSheetHasNoNestedTaskInspectorHost() throws {
        let sections = CadenceSourceScan.codeOnly(try sourceFile("Cadence/iOS/iOSTodayTaskSections.swift"))
        #expect(sections.contains("struct iOSTodayTaskSections: View"))
        #expect(!sections.contains("iOSTodayOverdueListSheet"))
        #expect(!sections.contains(".iOSTaskInspectorHost()"))
    }

    /// The host reads the shared decision rather than re-deciding, and it reads it about the two
    /// facts it can observe for itself. A host that started consulting a `@Query` here would be the page's
    /// filter creeping back into the panel's lifetime by another route.
    @Test func theHostAsksTheSharedRuleAboutTheTwoFactsItCanSee() throws {
        try expectOccurrences(
            of: "CadenceDetailPanelPresentation.resolveHeldSubject(",
            at: ["Cadence/iOS/iOSTaskInspectorHost.swift": 1]
        )
        // The model spelling, which reads all three signals in `Shared/` ([[T-7561]]): a host
        // handing over facts it picked itself is how `isDeleted` alone once shipped as a draft.
        try expectOccurrences(
            of: "CadenceDetailPanelPresentation.resolveHeldSubject(heldModel: task)",
            at: ["Cadence/iOS/iOSTaskInspectorHost.swift": 1]
        )
        try expectOccurrences(
            of: "@Query",
            at: ["Cadence/iOS/iOSTaskInspectorHost.swift": 0]
        )
    }

    /// Without this, every zero above could be a scan reading an empty string — the failure mode a
    /// `/tmp` against `/private/tmp` path mismatch produces on an isolated build tree.
    @Test func theSourceScanIsNotVacuousInTaskInspectorHost() throws {
        let files = try swiftFiles(under: "Cadence")

        #expect(files.count > 300, "the source scan found \(files.count) files and cannot be doing its job")
        for path in [
            "Cadence/iOS/iOSTaskInspectorHost.swift",
            "Cadence/iOS/iOSRootView.swift",
            "Cadence/iOS/iOSTaskViews.swift",
            "Cadence/iOS/iOSTaskRowActionViews.swift",
            "Cadence/iOS/iOSBoardCards.swift",
            "Cadence/iOS/iOSCalendarTimelineViews.swift",
            "Cadence/iOS/iOSTodaySchedulePanel.swift",
            "Cadence/Shared/CadenceDetailPanelPresentation.swift"
        ] {
            #expect(files.contains(path))
        }

        // The needles above are only meaningful if the text they are looking for is really there.
        let host = try strippingComments(sourceFile("Cadence/iOS/iOSTaskInspectorHost.swift"))
        #expect(host.contains("func iOSTaskInspectorHost()"))
        #expect(host.contains(".sheet(item: $selection)"))
        let row = try strippingComments(sourceFile("Cadence/iOS/iOSTaskViews.swift"))
        #expect(row.contains("private func openDetail()"))
        #expect(row.contains("iOSTaskRowContextMenu("))
    }

    /// **Self-check on the two new tools.** A typo in a pattern matches nothing and every
    /// `== 1` above becomes a silent zero-that-should-have-been-one; a slicer that quietly returned
    /// the whole file would make every scoped assertion as unscoped as the counts they replace. So
    /// run both against literals that must and must not be accepted.
    @Test func thePatternHelperAndTheSlicerBothDoWhatTheyLookLike() throws {
        #expect(matches(#"case \.stay:\s*iOSTaskDetailSheet\(task: task\)"#, in: "case .stay:\n    iOSTaskDetailSheet(task: task)") == 1)
        #expect(matches(#"case \.stay:\s*iOSTaskDetailSheet\(task: task\)"#, in: "case .close:\n    iOSTaskDetailSheet(task: task)") == 0)
        // A malformed pattern must read as a failure, never as "no matches".
        #expect(matches("case (", in: "case (") == -1)

        // Both bodies are padded past `cadenceFunctionBody`'s minimum length, which exists so a
        // slice that collapsed to nothing throws rather than passing every `!contains`.
        let sample = """
        var body: some View {
            Group {
                iPadMacStyleRootShell(selection: $selection)
                iOSCompactRootShell(selectedTab: $tab)
            }
            .modifierAboveBothShellsAndNotInsideEitherOfThem()
        }
        """
        let body = try cadenceFunctionBody("var body: some View", in: sample)
        let group = try cadenceFunctionBody("Group", in: body)
        #expect(body.contains(".modifierAboveBothShellsAndNotInsideEitherOfThem()"))
        #expect(group.contains("iOSCompactRootShell("))
        #expect(!group.contains(".modifierAboveBothShellsAndNotInsideEitherOfThem()"))
    }
}

// MARK: - Source-reading helpers

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

/// Occurrence count for a regular expression. Returns `-1` on a malformed pattern so a typo reads
/// as a failure rather than as zero matches — `thePatternHelperAndTheSlicerBothDoWhatTheyLookLike` is the
/// self-check the guide asks for.
private func matches(_ pattern: String, in text: String) -> Int {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return -1 }
    return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
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
