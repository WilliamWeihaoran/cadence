import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-215: macOS's archive cancelled a list's remaining active tasks and iOS's archive only wrote
/// `status = .archived`, so the same area wound down to two different sets of open work depending
/// on which device the swipe happened on. The divergence existed because
/// `TaskContainerLifecycleService` sat inside `TaskWorkflowService.swift`'s `#if os(macOS)` while
/// importing nothing platform-specific — the sixth instance of that shape after `RemindersManager`,
/// `PrivacyDataResetService`, `ListDeleteHelpers`, `SchedulingActions.createBundle(from:adding:)`
/// and the list delete cascades.
///
/// **Two kinds of test here, and the second kind is the point.** Pinning the arithmetic proves the
/// confirmation counts truthfully; it proves nothing about iOS *reaching* the wind-down.
/// `Cadence/iOS/` is entirely inside `#if os(iOS)` and this target builds for macOS, so there is no
/// iOS symbol to reference and the only available tool is a source-text assertion. The helpers
/// follow `CadenceListDeletionSurfaceTests`: exact per-file counts rather than "contains",
/// comment-stripping rather than allowlisting, and a non-vacuity test so a broken scan cannot make
/// the absence assertions pass silently.
@MainActor
struct CadenceListArchiveSurfaceTests {

    private func container() throws -> ModelContainer {
        try CadenceModelContainerFactory.makeInMemoryContainer()
    }

    private func task(_ title: String, status: TaskStatus = .todo) -> AppTask {
        let task = AppTask(title: title)
        task.status = status
        if status == .done || status == .cancelled {
            task.completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        }
        return task
    }

    // MARK: - What the confirmation promises

    /// The count is the settle's own array. An area rolls up its child projects — because that is
    /// what `cancelRemainingActiveTasks(in:includingChildProjects:)` walks, and a child project
    /// keeps its own `status`, so its tasks stay reachable from All Tasks after the parent is filed
    /// away — and already-settled work is excluded, because the wind-down leaves it alone.
    @Test func theArchiveSummaryCountsExactlyWhatTheWindDownWillSettle() throws {
        let modelContext = ModelContext(try container())
        let area = Area(name: "Home")
        let child = Project(name: "Kitchen", area: area)

        let open = task("open")
        open.area = area
        let inProgress = task("in progress", status: .inProgress)
        inProgress.area = area
        let alreadyDone = task("done", status: .done)
        alreadyDone.area = area
        let alreadyCancelled = task("cancelled", status: .cancelled)
        alreadyCancelled.area = area
        let openInChild = task("open in child")
        openInChild.project = child

        for model in [open, inProgress, alreadyDone, alreadyCancelled, openInChild] {
            modelContext.insert(model)
        }
        modelContext.insert(area)
        modelContext.insert(child)
        area.tasks = [open, inProgress, alreadyDone, alreadyCancelled]
        area.projects = [child]
        child.tasks = [openInChild]
        try modelContext.save()

        let summary = CadenceContainerWindDownSummary.forArea(area)
        #expect(summary.openTasks == 3)
        #expect(summary.requiresConfirmation)
        #expect(!summary.isEmpty)

        // And the number was a promise: exactly those three change, and nothing else does.
        TaskContainerLifecycleService.cancelRemainingActiveTasks(
            in: area,
            includingChildProjects: true,
            in: modelContext
        )
        let cancelled = [open, inProgress, openInChild].map(\.isCancelled)
        #expect(cancelled == [true, true, true])
        #expect(alreadyDone.status == .done)
        #expect(alreadyCancelled.status == .cancelled)
        #expect(CadenceContainerWindDownSummary.forArea(area).openTasks == 0)
    }

    /// A task carrying both an `area` and a `project` under that area appears in two of the
    /// relationship arrays the walk visits. Counting it twice would inflate the number the user is
    /// deciding on — the same trap `CadenceListDeletionSummary` documents for the delete cascade.
    @Test func aTaskFiledUnderBothAnAreaAndItsProjectIsCountedOnce() throws {
        let modelContext = ModelContext(try container())
        let area = Area(name: "Home")
        let child = Project(name: "Kitchen", area: area)
        let subject = task("filed twice")
        subject.area = area
        subject.project = child

        modelContext.insert(area)
        modelContext.insert(child)
        modelContext.insert(subject)
        area.tasks = [subject]
        area.projects = [child]
        child.tasks = [subject]
        try modelContext.save()

        #expect(CadenceContainerWindDownSummary.forArea(area).openTasks == 1)
    }

    /// A project's summary is its own tasks and nothing else — there is no container below it.
    @Test func aProjectSummaryCountsItsOwnOpenTasks() throws {
        let modelContext = ModelContext(try container())
        let project = Project(name: "Ship")
        let open = task("open")
        open.project = project
        let done = task("done", status: .done)
        done.project = project

        modelContext.insert(project)
        modelContext.insert(open)
        modelContext.insert(done)
        project.tasks = [open, done]
        try modelContext.save()

        #expect(CadenceContainerWindDownSummary.forProject(project).openTasks == 1)
    }

    /// The conditional-confirmation rule. Archiving a list with nothing open in it flips one flag
    /// and is one tap from Restore, so iOS performs it on the spot; a sheet that appears even when
    /// the answer is "nothing happens" is a sheet people learn to dismiss without reading.
    @Test func aListWithNothingStillOpenNeedsNoConfirmation() throws {
        let modelContext = ModelContext(try container())
        let area = Area(name: "Finished")
        let done = task("done", status: .done)
        done.area = area
        modelContext.insert(area)
        modelContext.insert(done)
        area.tasks = [done]
        try modelContext.save()

        let summary = CadenceContainerWindDownSummary.forArea(area)
        #expect(summary.isEmpty)
        #expect(!summary.requiresConfirmation)
        #expect(summary.settledLine == nil)
    }

    @Test func theSettledLineCountsAndPluralizesAndSaysNothingAtZero() {
        #expect(CadenceContainerWindDownSummary(openTasks: 1).settledLine == "1 open task will be cancelled")
        #expect(CadenceContainerWindDownSummary(openTasks: 7).settledLine == "7 open tasks will be cancelled")
        #expect(CadenceContainerWindDownSummary(openTasks: 0).settledLine == nil)
        #expect(CadenceContainerWindDownSummary().isEmpty)
    }

    // MARK: - The wind-down is no longer macOS-only

    /// `remainingActiveTasks` is the array the settle walks, not a second walk that happens to
    /// agree — which is what lets the confirmation count without over-promising. Pinned by identity
    /// rather than by count.
    @Test func theExposedArrayIsTheOneTheSettleActuallyWalks() throws {
        let modelContext = ModelContext(try container())
        let area = Area(name: "Home")
        let open = task("open")
        open.area = area
        let done = task("done", status: .done)
        done.area = area
        modelContext.insert(area)
        modelContext.insert(open)
        modelContext.insert(done)
        area.tasks = [open, done]
        try modelContext.save()

        let promised = TaskContainerLifecycleService.remainingActiveTasks(in: area, includingChildProjects: true)
        #expect(promised.map(\.id) == [open.id])

        TaskContainerLifecycleService.cancelRemainingActiveTasks(
            in: area,
            includingChildProjects: true,
            in: modelContext
        )
        let changed = [open, done].filter(\.isCancelled)
        #expect(changed.map(\.id) == promised.map(\.id))
    }

    /// A kanban column is the third container the service winds down, and its accessor moved with
    /// the other two. Pinned so the section overload is not quietly dropped as unused: macOS's
    /// column archive is its only caller today, and it is the surface T-247 is about.
    @Test func theSectionOverloadStillScopesToItsColumn() throws {
        let modelContext = ModelContext(try container())
        let area = Area(name: "Board")
        let inColumn = task("in column")
        inColumn.sectionName = "Doing"
        inColumn.area = area
        let elsewhere = task("elsewhere")
        elsewhere.sectionName = "Later"
        elsewhere.area = area
        modelContext.insert(area)
        modelContext.insert(inColumn)
        modelContext.insert(elsewhere)
        area.tasks = [inColumn, elsewhere]
        try modelContext.save()

        let remaining = TaskContainerLifecycleService.remainingActiveTasks(
            in: TaskSectionConfig(name: "Doing"),
            area: area,
            project: nil
        )
        #expect(remaining.map(\.title) == ["in column"])
    }

    /// The type left the macOS guard whole. The new file carries no platform conditional at all —
    /// not "one documented seam" as `CadenceListDeleteHelpers` does, because there is nothing here
    /// that needs one — and the old file no longer declares it.
    @Test func theLifecycleServiceLivesInServicesWithNoPlatformConditional() throws {
        let moved = try strippingComments(sourceFile("Cadence/Services/CadenceTaskContainerLifecycleService.swift"))
        #expect(moved.contains("enum TaskContainerLifecycleService {"))
        #expect(moved.contains("struct CadenceContainerWindDownSummary"))
        #expect(moved.contains("enum CadenceWindDownOutcome"))
        #expect(moved.components(separatedBy: "#if os(").count - 1 == 0)

        let old = try strippingComments(sourceFile("Cadence/macOS/Services/TaskWorkflowService.swift"))
        #expect(old.contains("enum TaskWorkflowService {"))
        #expect(!old.contains("enum TaskContainerLifecycleService"))

        // The move is recorded where somebody would go looking for it. Read from the raw source,
        // because the tombstone is a comment and `strippingComments` blanks it.
        let raw = try sourceFile("Cadence/macOS/Services/TaskWorkflowService.swift")
        #expect(raw.contains("CadenceTaskContainerLifecycleService.swift"))
    }

    // MARK: - iOS reaches it, from one place

    /// The wind-down is reached from exactly one iOS file, once per container kind. A second call
    /// site would mean some surface had grown its own archive beside the one that confirms.
    @Test func iOSArchivesThroughTheSharedWindDownFromOnePlaceOnly() throws {
        try expectCallSites(of: "TaskContainerLifecycleService.cancelRemainingActiveTasks", at: [
            "Cadence/iOS/iOSListArchiveSupport.swift": 2,
            "Cadence/iOS/iOSListViews.swift": 0,
            "Cadence/iOS/iOSListsRegularPane.swift": 0
        ])

        // `archiveList` is declared once and called once: the immediate path in the host, and the
        // confirmed path in the modifier. The declaration is the third `archiveList(`.
        try expectOccurrences(of: "archiveList(", at: [
            "Cadence/iOS/iOSListArchiveSupport.swift": 2,
            "Cadence/iOS/iOSListViews.swift": 1
        ])

        // Nothing else on iOS files a list away by hand. This is the assertion the ticket is about:
        // a bare `status = .archived` *is* the bug.
        for path in try swiftFiles(under: "Cadence/iOS")
        where path != "Cadence/iOS/iOSListArchiveSupport.swift" {
            let code = try strippingComments(sourceFile(path))
            #expect(
                !code.contains("status = .archived"),
                "\(path) archives a list by hand instead of going through ModelContext.archiveList"
            )
        }
    }

    /// One confirmation, built in one place, armed by one decision. Every archive affordance — the
    /// iPhone row swipe, its context menu, and the iPad pane's copies of both — routes up to
    /// `iOSListsView`, so the phone and the tablet cannot come to ask different questions.
    @Test func everyIOSArchiveSurfaceGoesThroughTheOneDecision() throws {
        // The sheet is `iOSWindDownConfirmationSheet` since T-247 shared it with the kanban
        // column; the list surface still builds it in exactly one place.
        try expectCallSites(of: "iOSWindDownConfirmationSheet", at: [
            "Cadence/iOS/iOSListArchiveSupport.swift": 1,
            "Cadence/iOS/iOSListViews.swift": 0,
            "Cadence/iOS/iOSListsRegularPane.swift": 0
        ])

        try expectCallSites(of: ".iOSListArchive", at: [
            "Cadence/iOS/iOSListViews.swift": 1,
            "Cadence/iOS/iOSListsRegularPane.swift": 0
        ])

        // The conditional-confirmation test is asked once, by the host. The iPad pane calls up into
        // `archive(_:)` instead of deciding for itself.
        try expectOccurrences(of: "requiresConfirmation", at: [
            "Cadence/iOS/iOSListViews.swift": 1,
            "Cadence/iOS/iOSListArchiveSupport.swift": 0,
            "Cadence/iOS/iOSListsRegularPane.swift": 0
        ])
    }

    /// The other direction of the same divergence. macOS's two archive branches are what iOS was
    /// measured against, so they are pinned too: closing T-215 by *removing* the Mac's wind-down
    /// would satisfy every assertion above and be the wrong fix.
    @Test func macOSStillWindsDownOnArchiveAndOnCompletion() throws {
        let sheet = try strippingComments(sourceFile("Cadence/macOS/Sheets/EditListSheet.swift"))
        #expect(sheet.components(separatedBy: "TaskContainerLifecycleService.cancelRemainingActiveTasks(").count - 1 == 2)
        #expect(sheet.components(separatedBy: "TaskContainerLifecycleService.completeRemainingActiveTasks(").count - 1 == 2)
    }

    /// Without this, every zero and every absence assertion above could be passing because the
    /// reader returned an empty string.
    @Test func theSourceScanActuallyReadsTheseFiles() throws {
        let files = try swiftFiles(under: "Cadence")
        #expect(files.count > 300)
        #expect(files.contains("Cadence/Services/CadenceTaskContainerLifecycleService.swift"))
        #expect(files.contains("Cadence/macOS/Services/TaskWorkflowService.swift"))
        #expect(files.contains("Cadence/iOS/iOSListArchiveSupport.swift"))
        #expect(files.contains("Cadence/iOS/iOSListViews.swift"))
        #expect(files.contains("Cadence/iOS/iOSListsRegularPane.swift"))

        // And it must be reading *code*, through the same reader the absence checks use.
        let support = try strippingComments(sourceFile("Cadence/iOS/iOSListArchiveSupport.swift"))
        #expect(support.contains("enum iOSListArchiveTarget: Identifiable"))
        let confirmation = try strippingComments(sourceFile("Cadence/iOS/iOSWindDownConfirmation.swift"))
        #expect(confirmation.contains("struct iOSWindDownConfirmationSheet: View"))

        // The `status = .archived` sweep above would pass vacuously if the one file that *does*
        // spell it had stopped spelling it, or if the sweep were reading the wrong folder.
        #expect(support.contains("status = .archived"))
        let pane = try strippingComments(sourceFile("Cadence/iOS/iOSListsRegularPane.swift"))
        #expect(pane.contains("archiveArea(area)"))
    }
}

// MARK: - Source-reading helpers

/// Fails unless `name` is called exactly `count` times in each listed file.
///
/// **Exact counts, not "contains".** `CadenceSharedBoardChromeTests` documents why: a mutation run
/// caught a version of that file asserting only that each file mentioned the shared component
/// somewhere, and reverting *one* of four call sites left it green.
private func expectCallSites(
    of name: String,
    at callSites: [String: Int],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    for (path, expected) in callSites {
        let code = try strippingComments(sourceFile(path))
        let actual = code.components(separatedBy: "\(name)(").count - 1
        #expect(
            actual == expected,
            "\(path) calls \(name) \(actual) times, expected \(expected)",
            sourceLocation: sourceLocation
        )
    }
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
/// rather than prose. Crude on purpose: a `//` inside a string literal is blanked too, which can
/// only ever make these checks *stricter* about what counts as a comment, never looser about live
/// code.
private func strippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound)))
        }
    }
    return result
}
