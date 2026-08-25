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
/// source text with exact per-file counts, and `theSourceScanIsNotVacuous` stops a broken reader
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

    /// Both signals, either of them sufficient. `isDeleted` catches the pending delete and a nil
    /// `modelContext` catches the committed one; the next test is why it takes two.
    ///
    /// The rule is `CadenceDetailPanelPresentation` rather than `CadenceTaskInspectorPresentation`
    /// since T-217: nothing in it is about an `AppTask`, and the bundle panel's host needed exactly
    /// it. `CadenceBundleInspectorHostTests` measures the same two phases against a `TaskBundle`.
    @Test func aHeldTaskIsGoneIfEitherSignalSaysSo() {
        #expect(!CadenceDetailPanelPresentation.heldSubjectIsGone(isDeleted: false, hasNoModelContext: false))
        #expect(CadenceDetailPanelPresentation.heldSubjectIsGone(isDeleted: true, hasNoModelContext: false))
        #expect(CadenceDetailPanelPresentation.heldSubjectIsGone(isDeleted: false, hasNoModelContext: true))
        #expect(CadenceDetailPanelPresentation.heldSubjectIsGone(isDeleted: true, hasNoModelContext: true))

        #expect(
            CadenceDetailPanelPresentation.resolveHeldSubject(isDeleted: false, hasNoModelContext: false)
                == .stay
        )
        #expect(
            CadenceDetailPanelPresentation.resolveHeldSubject(isDeleted: true, hasNoModelContext: false)
                == .close
        )
        #expect(
            CadenceDetailPanelPresentation.resolveHeldSubject(isDeleted: false, hasNoModelContext: true)
                == .close
        )
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
            CadenceDetailPanelPresentation.resolveHeldSubject(
                isDeleted: subject.isDeleted,
                hasNoModelContext: subject.modelContext == nil
            ) == .stay
        )
        #expect(
            CadenceTaskQuerySupport.activeTodayTasks(from: [subject], todayKey: todayKey, sortMode: .listOrder)
                .isEmpty
        )
    }

    /// The extreme case, and **the measurement that decided the guard's shape.** A first draft read
    /// `isDeleted` alone and this test is what killed it: across a real delete, the two halves of the
    /// lifecycle report through *different* properties —
    /// - after `delete(_:)` and before the save, `isDeleted` is the one that is true;
    /// - after the save, `modelContext` is the one that is nil.
    ///
    /// Neither is asserted here as "the other one is false", because that would pin SwiftData's
    /// internals rather than our rule. What is asserted is that each phase is caught, which is the
    /// property the host needs, and that the combined predicate is what catches both.
    @Test func deletingTheTaskUnderneathTheInspectorClosesItInBothPhasesOfTheDelete() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let subject = AppTask(title: "delete me")
        context.insert(subject)
        try context.save()

        #expect(
            CadenceDetailPanelPresentation.resolveHeldSubject(
                isDeleted: subject.isDeleted,
                hasNoModelContext: subject.modelContext == nil
            ) == .stay
        )

        context.delete(subject)
        #expect(subject.isDeleted, "a pending delete stopped reporting through isDeleted")
        #expect(
            CadenceDetailPanelPresentation.resolveHeldSubject(
                isDeleted: subject.isDeleted,
                hasNoModelContext: subject.modelContext == nil
            ) == .close
        )

        try context.save()
        #expect(subject.modelContext == nil, "a committed delete stopped detaching the model context")
        #expect(try context.fetch(FetchDescriptor<AppTask>()).isEmpty)
        #expect(
            CadenceDetailPanelPresentation.resolveHeldSubject(
                isDeleted: subject.isDeleted,
                hasNoModelContext: subject.modelContext == nil
            ) == .close
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
                "Cadence/iOS/iPadTodayScheduleViews.swift": 0
            ]
        )
        // …and each asks the host instead. `iOSScheduleReadyTaskRow` asks twice: the title button
        // and the trailing info button are two controls onto one panel.
        try expectOccurrences(
            of: "taskInspector(task)",
            at: [
                "Cadence/iOS/iOSTaskViews.swift": 1,
                "Cadence/iOS/iOSBoardCards.swift": 1,
                "Cadence/iOS/iOSCalendarTimelineViews.swift": 1,
                "Cadence/iOS/iPadTodayScheduleViews.swift": 2
            ]
        )
        try expectOccurrences(
            of: "@Environment(\\.iOSTaskInspector)",
            at: [
                "Cadence/iOS/iOSTaskViews.swift": 1,
                "Cadence/iOS/iOSBoardCards.swift": 1,
                "Cadence/iOS/iOSCalendarTimelineViews.swift": 1,
                "Cadence/iOS/iPadTodayScheduleViews.swift": 1
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
                "Cadence/iOS/iPadTodayScheduleViews.swift": 0,
                // These two read `1` until T-217, and the survivor in each was the bundle card /
                // bundle block presenting `iOSCalendarBundleDetailSheet` from inside a filtered
                // `ForEach` — the same defect on a different sheet, pinned here rather than fixed
                // because it needed a bundle host and not this one. It has one now
                // (`iOSBundleInspectorHost`), so no card in this app owns detail-panel presentation
                // state at all; `CadenceBundleInspectorHostTests` is where that half is asserted.
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

    /// **Every presenter of the inspector, counted.** Five, and only five: the host, plus the four
    /// surfaces that were left alone on purpose because each already owns its presentation on a view
    /// that does not re-filter under it — and three of those present from *inside* a sheet, where a
    /// host above the sheet is the wrong owner because it is already presenting.
    ///
    /// This is the assertion that catches a *sixth* one appearing. A new row-owned
    /// `.sheet { iOSTaskDetailSheet(...) }` is the exact regression T-201 fixed, and it would
    /// otherwise be invisible to a test suite that cannot build this folder.
    @Test func theInspectorIsPresentedFromExactlyFivePlacesInTheWholeApp() throws {
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
                // The host. The only one reached from a row.
                "Cadence/iOS/iOSTaskInspectorHost.swift": 1,
                // Page-owned `.sheet(item:)`, already immune.
                "Cadence/iOS/iOSSearchView.swift": 1,
                // Sheet-owned `.sheet(item:)` — a nearer host would have to live inside the sheet.
                "Cadence/iOS/iOSMarkdownEditingSurface.swift": 1,
                "Cadence/iOS/iOSMarkdownReferenceSupport.swift": 1,
                "Cadence/iOS/iOSCalendarBundleDetailSheet.swift": 1
            ],
            "presenters of iOSTaskDetailSheet changed: \(presenters)"
        )
    }

    /// One host above both shells, plus one **inside** the one sheet that presents a whole page.
    ///
    /// This test read "exactly one" and said a second application "would mean two hosts racing to
    /// present, which on iOS means the inner one silently does nothing". The second half is
    /// backwards, and `iOSTaskInspectorHost`'s own documentation has always said so: the
    /// environment resolves to the **innermost** host, and it is the *outer* one that does nothing
    /// — it is already presenting the sheet, so a request from inside cannot open anything. That
    /// is the same fact the five-presenter test above records when it says three of the four
    /// exceptions "present from inside a sheet, where a host above the sheet is the wrong owner".
    ///
    /// So the exception is stated positively rather than the assertion loosened: still an exact
    /// set, so a third application anywhere is still a failure. `iOSTodayOverdueListSheet` (T-195,
    /// second half) presents `iOSListDetailView` — a whole page of task rows, every one of which
    /// asks the environment for the inspector — from Today's past-due summary cards. A nested host
    /// is what those rows reach; without it every one of them is a dead tap, which is the defect
    /// class this whole suite exists to catch. It costs the five-presenter count nothing: the host
    /// is the presenter, so `iOSTaskDetailSheet(` still appears in exactly five files.
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
                "Cadence/iOS/iOSRootView.swift": 1,
                // The nearer owner, inside a sheet the root host cannot present through.
                "Cadence/iOS/iOSTodayTaskSections.swift": 1
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
    /// stated as placement: the two shells are the `Group`'s two branches, and the host, the bundle
    /// host and the startup banner are all applied to the `Group` rather than inside it.
    @Test func theRootAppliesTheHostAboveBothShellsRatherThanInsideOne() throws {
        let root = try strippingComments(sourceFile("Cadence/iOS/iOSRootView.swift"))
        let body = try cadenceFunctionBody("var body: some View", in: root)
        let shells = try cadenceFunctionBody("Group", in: body)

        #expect(shells.contains("iPadMacStyleRootShell("))
        #expect(shells.contains("iOSCompactRootShell("))

        for modifier in [
            ".iOSTaskInspectorHost()",
            ".iOSBundleInspectorHost()",
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

    /// The nested host, likewise placed rather than counted. `iOSTodayTaskSections.swift` declares
    /// several views; the one that must carry it is the sheet presenting a whole page of task rows,
    /// and it must carry it on the view it actually renders. A `.iOSTaskInspectorHost()` that
    /// drifted onto a neighbouring view — or onto another member of this very struct — leaves the
    /// file count at one and every row inside the sheet a dead tap again.
    ///
    /// Scoping to the struct alone was measurably not enough: the first draft of this test sliced
    /// `struct iOSTodayOverdueListSheet: View` and survived a mutation that moved the modifier onto
    /// a second computed property in the same struct. `var body` is the scope that means what the
    /// sentence above says.
    @Test func theNestedHostSitsOnTheSheetThatCarriesAWholePageOfRows() throws {
        let sections = try strippingComments(sourceFile("Cadence/iOS/iOSTodayTaskSections.swift"))
        let sheet = try cadenceFunctionBody("struct iOSTodayOverdueListSheet: View", in: sections)
        let body = try cadenceFunctionBody("var body: some View", in: sheet)

        #expect(body.contains(".iOSTaskInspectorHost()"))
        #expect(sheet.contains("iOSListDetailView("))
    }

    /// The host reads the shared decision rather than re-deciding, and it reads it about the two
    /// facts it can observe for itself. A host that started consulting a `@Query` here would be the page's
    /// filter creeping back into the panel's lifetime by another route.
    @Test func theHostAsksTheSharedRuleAboutTheTwoFactsItCanSee() throws {
        try expectOccurrences(
            of: "CadenceDetailPanelPresentation.resolveHeldSubject(",
            at: ["Cadence/iOS/iOSTaskInspectorHost.swift": 1]
        )
        // Both signals, at the one call site. `isDeleted` on its own is the draft that did not work.
        try expectOccurrences(
            of: "isDeleted: task.isDeleted",
            at: ["Cadence/iOS/iOSTaskInspectorHost.swift": 1]
        )
        try expectOccurrences(
            of: "hasNoModelContext: task.modelContext == nil",
            at: ["Cadence/iOS/iOSTaskInspectorHost.swift": 1]
        )
        try expectOccurrences(
            of: "@Query",
            at: ["Cadence/iOS/iOSTaskInspectorHost.swift": 0]
        )
    }

    /// Without this, every zero above could be a scan reading an empty string — the failure mode a
    /// `/tmp` against `/private/tmp` path mismatch produces on an isolated build tree.
    @Test func theSourceScanIsNotVacuous() throws {
        let files = try swiftFiles(under: "Cadence")

        #expect(files.count > 300, "the source scan found \(files.count) files and cannot be doing its job")
        for path in [
            "Cadence/iOS/iOSTaskInspectorHost.swift",
            "Cadence/iOS/iOSRootView.swift",
            "Cadence/iOS/iOSTaskViews.swift",
            "Cadence/iOS/iOSTaskRowActionViews.swift",
            "Cadence/iOS/iOSBoardCards.swift",
            "Cadence/iOS/iOSCalendarTimelineViews.swift",
            "Cadence/iOS/iPadTodayScheduleViews.swift",
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
/// as a failure rather than as zero matches — `thePatternHelperMatchesWhatItLooksLike` is the
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
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound)))
        }
    }
    return result
}
