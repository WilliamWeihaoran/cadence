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

    /// One host, applied once, above both shells — the same "both shells, one call" placement
    /// `cadenceStartupIssueBanner` has, and for the same reason. The two live mentions are the
    /// declaration and that single application; a second application anywhere would mean two hosts
    /// racing to present, which on iOS means the inner one silently does nothing.
    @Test func exactlyOneHostIsInstalledAndItIsAboveBothShells() throws {
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
