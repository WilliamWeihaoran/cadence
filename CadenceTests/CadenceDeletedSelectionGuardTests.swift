// T-3244: compiled for macOS only. `CadenceTests` now also builds for an iOS destination, and
// this suite reaches macOS-only app types that do not exist there. The gate preserves exactly the
// coverage this file had before; narrowing it so any cross-platform half runs on iOS too is
// follow-up, not part of making the target iOS-capable.
#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-345, T-346, T-347: **one defect, three surfaces — a selection that outlives its model.**
///
/// The app already had the *model-side* answer. `CadenceDetailPanelPresentation.resolveHeldSubject`
/// asks a held `PersistentModel` whether it is still real, and both iOS inspector hosts read it. What
/// it cannot answer is the case where the surface holds an **id** rather than the model: the macOS
/// sidebar holds a `SidebarItem`, macOS Goals holds a `UUID`, and neither has an `isDeleted` to read.
/// `CadenceSelectionNormalization` is that half, and these three tickets are the three places it was
/// missing or, in Goals' case, present but conflated with a filter.
///
/// **The sharp one is T-346**, and the shape of its bug decides the shape of these tests. The Goals
/// guard read `visibleGoals.contains(selected) || trimmedQuery.isEmpty`, so it retargeted a stale
/// selection *while you were searching* and left one in place the moment you cleared the box. Any
/// test that types a search passes against the bug. The empty-search path is the one that has to be
/// asserted, and `aDeletedGoalIsRetargetedWithTheSearchBoxEmpty` is that test.
@MainActor
struct CadenceDeletedSelectionGuardTests {

    // MARK: - The shared rule (T-346's two questions, kept apart)

    /// Existence and visibility, and no combination of them lets a missing id survive. The last two
    /// cases are the bug: a selection absent from the store is retargeted whether or not a filter is
    /// running, because "the search box is empty" was never evidence that a goal still exists.
    @Test func aMissingIDIsRetargetedWhateverTheFilterSays() {
        let live = UUID()
        let gone = UUID()
        let fallback = UUID()

        #expect(!CadenceSelectionNormalization.isStale(live, existingIDs: [live, fallback]))
        #expect(CadenceSelectionNormalization.isStale(gone, existingIDs: [live, fallback]))
        // Nothing selected is not a stale selection; seeding an empty page is a separate decision.
        #expect(!CadenceSelectionNormalization.isStale(UUID?.none, existingIDs: [live]))

        for filterIsActive in [false, true] {
            #expect(
                CadenceSelectionNormalization.normalized(
                    gone,
                    existingIDs: [live, fallback],
                    visibleIDs: [live, fallback],
                    filterIsActive: filterIsActive,
                    fallback: fallback
                ) == fallback,
                "a missing id survived with filterIsActive: \(filterIsActive)"
            )
        }
    }

    /// The half that is *not* an existence check, kept because it is the current product behaviour
    /// and changing it was never part of the ticket. A goal that still exists but is hidden by a
    /// live search retargets; the same goal with the box cleared is kept, because a page can have
    /// good reasons to hold a selection it is not currently listing.
    @Test func anExistingButUnlistedSelectionTurnsOnWhetherAFilterIsRunning() {
        let hidden = UUID()
        let shown = UUID()

        #expect(
            CadenceSelectionNormalization.normalized(
                hidden,
                existingIDs: [hidden, shown],
                visibleIDs: [shown],
                filterIsActive: true,
                fallback: shown
            ) == shown
        )
        #expect(
            CadenceSelectionNormalization.normalized(
                hidden,
                existingIDs: [hidden, shown],
                visibleIDs: [shown],
                filterIsActive: false,
                fallback: shown
            ) == hidden
        )
    }

    /// The unfiltered spelling asks existence and nothing else — the sidebar's whole question.
    @Test func theUnfilteredSpellingAsksExistenceAlone() {
        let live = UUID()
        let gone = UUID()

        #expect(CadenceSelectionNormalization.normalized(live, existingIDs: [live], fallback: nil) == live)
        #expect(CadenceSelectionNormalization.normalized(gone, existingIDs: [live], fallback: live) == live)
        #expect(CadenceSelectionNormalization.normalized(gone, existingIDs: [live], fallback: nil) == nil)
    }

    // **T-346's five tests left with [[T-5002]].** They drove GoalsView.normalizedSelection,
    // the Goals page's wrapper over the shared rule, and the page is gone. The RULE they were
    // really about is `CadenceSelectionNormalization.normalized(...)`, which is still exercised
    // below by the sidebar, the list detail and the iOS surfaces that spend it; the wrapper's
    // absence is pinned by
    // `CadenceCodexTrackingUIRetirementTests.codexRetiredTrackingViewsAreGoneFromTheTree`.

    // MARK: - T-345: the macOS sidebar

    /// A real area, deleted underneath the selection. Before this ticket the root `selection` stayed
    /// on `.area(id)` and `RootDetailContent` handed the id to `AreaDetailLoader`, whose `@Query`
    /// found nothing and whose body drew nothing at all.
    @Test func deletingTheSelectedAreaSendsTheSidebarBackToToday() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let doomed = Area(name: "Home")
        let survivor = Area(name: "Work")
        context.insert(doomed)
        context.insert(survivor)
        try context.save()
        let selection = SidebarItem.area(doomed.id)
        let beforeDelete = Set(try context.fetch(FetchDescriptor<Area>()).map(\.id))

        #expect(
            macOSRootSelectionNormalization.normalized(
                selection,
                areaIDs: beforeDelete,
                projectIDs: []
            ) == selection,
            "a live area was retargeted, so the assertion below would be vacuous"
        )

        context.delete(doomed)
        try context.save()
        let remaining = try context.fetch(FetchDescriptor<Area>())
        #expect(remaining.map(\.id) == [survivor.id])

        #expect(
            macOSRootSelectionNormalization.normalized(
                selection,
                areaIDs: Set(remaining.map(\.id)),
                projectIDs: []
            ) == .today
        )
    }

    /// The same for a project, and — the half a per-case fix gets wrong — a project id must be
    /// checked against *project* ids. Handing the surviving area's ids as the project set would
    /// retarget a perfectly live project.
    @Test func deletingTheSelectedProjectSendsTheSidebarBackToToday() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let area = Area(name: "Work")
        let doomed = Project(name: "Launch")
        context.insert(area)
        context.insert(doomed)
        try context.save()
        let selection = SidebarItem.project(doomed.id)
        let areaIDs = Set(try context.fetch(FetchDescriptor<Area>()).map(\.id))
        let projectIDs = Set(try context.fetch(FetchDescriptor<Project>()).map(\.id))

        #expect(
            macOSRootSelectionNormalization.normalized(
                selection,
                areaIDs: areaIDs,
                projectIDs: projectIDs
            ) == selection
        )

        context.delete(doomed)
        try context.save()
        let survivingProjects = try context.fetch(FetchDescriptor<Project>())
        #expect(survivingProjects.isEmpty)
        let survivingAreas = Set(try context.fetch(FetchDescriptor<Area>()).map(\.id))
        #expect(survivingAreas == areaIDs, "the project delete took the area with it")

        #expect(
            macOSRootSelectionNormalization.normalized(
                selection,
                areaIDs: survivingAreas,
                projectIDs: []
            ) == .today
        )
    }

    /// **Archiving is not deleting.** The sidebar stops listing an archived list, but the model is
    /// still there and the page is still readable, so the id sets handed to the normalizer are every
    /// area and every project rather than the active ones. A normalizer built on `isActive` would
    /// throw the user off a page they are reading the moment they archive it — a different
    /// behaviour change wearing this fix's clothes.
    @Test func archivingTheSelectedListDoesNotMoveTheSelection() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let area = Area(name: "Home")
        context.insert(area)
        try context.save()
        area.status = .archived
        try context.save()

        let stored = try context.fetch(FetchDescriptor<Area>())
        #expect(stored.count == 1 && stored[0].isArchived)

        let selection = SidebarItem.area(area.id)
        #expect(
            macOSRootSelectionNormalization.normalized(
                selection,
                areaIDs: Set(stored.map(\.id)),
                projectIDs: []
            ) == selection
        )
    }

    /// The static destinations name a page, not a row, so nothing about them can go stale and the
    /// normalizer must not touch them — including on a store with no lists at all, which is the
    /// state a fresh install and a full data reset both land in.
    @Test func staticDestinationsAreNeverRetargeted() {
        for item in [
            SidebarItem.today, .allTasks, .inbox,
            .notes, .calendar, .focus, .settings
        ] {
            #expect(
                macOSRootSelectionNormalization.normalized(item, areaIDs: [], projectIDs: []) == item,
                "\(item) was retargeted"
            )
        }
        #expect(macOSRootSelectionNormalization.normalized(nil, areaIDs: [], projectIDs: []) == nil)
    }

    // MARK: - Where the guard is wired (source scan)

    // **`goalsNoLongerLetsAnEmptySearchBoxExcuseAMissingGoal` left with [[T-5002]]**, with the
    // file it read. It pinned `|| trimmedQuery.isEmpty` by its absence from `GoalsView.swift`;
    // there is no `GoalsView.swift`, which is the strongest form of that absence there is.

    /// T-345's two halves, which are only a fix together: the normalizer that retargets, and the
    /// state the loaders draw for the frames before it does.
    @Test func theMacOSRootNormalizesItsSelectionAndItsLoadersHaveAMissingState() throws {
        let root = try strippingComments(sourceFile("Cadence/macOS/macOSRootView.swift"))
        let body = try cadenceFunctionBody("var body: some View", in: root)
        #expect(
            body.contains("SidebarSelectionNormalizer(selection: $selection)"),
            "the root no longer normalizes its own selection"
        )

        let support = try strippingComments(sourceFile("Cadence/macOS/Views/macOSRootStateSupport.swift"))
        let rule = try cadenceFunctionBody("static func normalized(", in: support)
        #expect(rule.contains("existingIDs: areaIDs"))
        #expect(rule.contains("existingIDs: projectIDs"))

        // Both loaders, and both `else` branches. Counting `MissingListDetailView()` file-wide would
        // pass with two of them in one loader and none in the other.
        let detail = try strippingComments(sourceFile("Cadence/macOS/Views/ListDetailView.swift"))
        for loader in ["struct AreaDetailLoader: View", "struct ProjectDetailLoader: View"] {
            let scoped = try cadenceFunctionBody(loader, in: detail)
            #expect(
                scoped.components(separatedBy: "MissingListDetailView()").count - 1 == 1,
                "\(loader) draws no missing-list state"
            )
        }
    }

    /// **macOS says what iOS says — and since T-522 both read it from one declaration.**
    /// `iOSMissingListView` has shipped this state for as long as iOS has had the `else` macOS was
    /// missing, so the copy is borrowed rather than written again; two platforms explaining one
    /// situation in two different sentences is exactly the drift the root guide's one-style rule
    /// names.
    ///
    /// This used to assert the two files carried the **same literals**, chosen deliberately over a
    /// shared constant so that editing one and not the other failed. It worked, and it was the
    /// weaker of the two available mechanisms: it pinned the pair rather than removing the second
    /// copy, and it cost `CadenceEmptyStateAuditTests` a standing `emptyStateDuplicateAllowance`
    /// entry pointing here. What it was really enforcing was convergence, so it asserts convergence
    /// — each surface reads `CadenceEmptyStateCopy.missingList*`, neither keeps a private spelling
    /// beside it, and the constant still says the sentence iOS shipped.
    ///
    /// The glyph stays a literal in both. An SF Symbol name is a picture rather than a sentence,
    /// which is the same distinction `CadenceSharedConstantReuseSweepTests` draws when it refuses to
    /// harvest symbol names.
    @Test func theMacMissingListStateReusesTheSentenceIOSAlreadyShips() throws {
        let mac = try strippingComments(sourceFile("Cadence/macOS/Views/ListDetailView.swift"))
        let phone = try strippingComments(sourceFile("Cadence/iOS/iOSRootSidebar.swift"))
        let macState = try cadenceFunctionBody("struct MissingListDetailView: View", in: mac)
        let phoneState = try cadenceFunctionBody("struct iOSMissingListView: View", in: phone)

        for copy in [
            "CadenceEmptyStateCopy.missingListTitle",
            "CadenceEmptyStateCopy.missingListSubtitle",
            "questionmark.folder"
        ] {
            #expect(phoneState.contains(copy), "iOS no longer says \(copy); macOS is now the only one that does")
            #expect(macState.contains(copy), "macOS no longer says \(copy)")
        }

        // Neither surface keeps the words themselves next to the constant it reads. That is the
        // state this test used to describe, and the state T-522 removed.
        for retyped in [
            CadenceEmptyStateCopy.missingListTitle,
            CadenceEmptyStateCopy.missingListSubtitle
        ] {
            #expect(macState.contains("\"\(retyped)\"") == false, "macOS spells \"\(retyped)\" out again")
            #expect(phoneState.contains("\"\(retyped)\"") == false, "iOS spells \"\(retyped)\" out again")
        }

        // Reading one constant twice is not a convergence if the constant has quietly become
        // something else, so the sentence is pinned by value too — and it is iOS's, unchanged.
        #expect(CadenceEmptyStateCopy.missingListTitle == "List not found")
        #expect(
            CadenceEmptyStateCopy.missingListSubtitle
                == "This list may have been archived, deleted, or changed on another device."
        )

        // The panel component is allowed to differ — `iOSEmptyPanel` is behind `#if os(iOS)` — and
        // this is the line that records *why*, so a later reader does not "unify" it into a build
        // failure.
        #expect(macState.contains("EmptyStateView("))
        #expect(phoneState.contains("iOSEmptyPanel("))
    }

    /// T-347: the local sheets, pinned as *pairings* rather than as counts.
    ///
    /// The repo-wide dictionaries in `CadenceTaskInspectorHostTests` and
    /// `CadenceBundleInspectorHostTests` say the panel is drawn in exactly one place and the wrapper
    /// presented in a named few. What they cannot say is that each `.sheet(item:)` hands its
    /// subject to the wrapper and that the wrapper's close closure clears **that same** binding — a
    /// close that cleared a neighbouring selection would leave the sheet re-presenting forever, and
    /// every count in this suite green.
    ///
    /// **It was six, and the Block half is gone entirely** ([[T-3170]]). The iOS Block panel, its
    /// host and the day inspector's `selectedBundle` are deleted, so every row left here hands an
    /// `AppTask` to `iOSTaskInspectorSheet` — the `subject == "task"` branch is the only branch
    /// with a subject, and the `wrapper` ternary is kept rather than folded away so a `bundle` row
    /// coming back cannot slip in unpaired.
    @Test func eachLocalSheetPresentsTheGuardedWrapperAndClearsItsOwnBinding() throws {
        let sheets: [(String, String, String)] = [
            ("Cadence/iOS/iOSMarkdownEditingSurface.swift", "selectedEmbeddedTask", "task"),
            ("Cadence/iOS/iOSMarkdownReferenceSupport.swift", "selectedReferenceTask", "task"),
            ("Cadence/iOS/iOSSearchView.swift", "selectedTask", "task")
        ]

        for (path, binding, subject) in sheets {
            let code = try strippingComments(sourceFile(path))
            let wrapper = subject == "task" ? "iOSTaskInspectorSheet" : "iOSBundleInspectorSheet"
            let pattern = #"\.sheet\(item: \$\#(binding)[^)]*\)\s*\{\s*\#(subject) in\s*\#(wrapper)\(\#(subject): \#(subject)\)\s*\{\s*\#(binding) = nil\s*\}"#
            #expect(
                matches(pattern, in: code) == 1,
                "\(path) does not hand $\(binding) to \(wrapper) and clear it on close"
            )
        }
    }

    /// The regex above, self-checked. A needle that cannot fail is worth nothing, and this one is
    /// built by interpolation, which is exactly how a pattern silently stops matching.
    @Test func theSheetPairingPatternMatchesWhatItLooksLike() {
        let binding = "selectedTask"
        let subject = "task"
        let wrapper = "iOSTaskInspectorSheet"
        let pattern = #"\.sheet\(item: \$\#(binding)[^)]*\)\s*\{\s*\#(subject) in\s*\#(wrapper)\(\#(subject): \#(subject)\)\s*\{\s*\#(binding) = nil\s*\}"#

        #expect(matches(pattern, in: """
        .sheet(item: $selectedTask) { task in
            iOSTaskInspectorSheet(task: task) { selectedTask = nil }
        }
        """) == 1)
        // The unguarded spelling this ticket removed.
        #expect(matches(pattern, in: """
        .sheet(item: $selectedTask) { task in
            iOSTaskDetailSheet(task: task)
        }
        """) == 0)
        // The wrapper present, but closing the wrong selection.
        #expect(matches(pattern, in: """
        .sheet(item: $selectedTask) { task in
            iOSTaskInspectorSheet(task: task) { selectedNote = nil }
        }
        """) == 0)
        #expect(matches("([", in: "([") == -1, "a malformed pattern must read as a failure, not as zero")
    }

    /// Without this, every scan above could be a reader that found nothing — the failure mode a
    /// `/tmp` against `/private/tmp` path mismatch produces on an isolated build tree.
    @Test func theSelectionGuardSourceScanIsNotVacuous() throws {
        let files = try swiftFiles(under: "Cadence")
        #expect(files.count > 300, "the source scan found \(files.count) files and cannot be doing its job")

        for path in [
            "Cadence/Shared/CadenceSelectionNormalization.swift",
            "Cadence/Shared/CadenceDetailPanelPresentation.swift",
            "Cadence/macOS/macOSRootView.swift",
            "Cadence/macOS/Views/macOSRootStateSupport.swift",
            "Cadence/macOS/Views/ListDetailView.swift",
            "Cadence/iOS/iOSRootSidebar.swift",
            "Cadence/iOS/iOSMarkdownEditingSurface.swift",
            "Cadence/iOS/iOSMarkdownReferenceSupport.swift",
            "Cadence/iOS/iOSSearchView.swift",
            "Cadence/iOS/iOSCalendarInspectorView.swift",
            "Cadence/iOS/iOSCalendarMonthAgendaViews.swift"
        ] {
            #expect(files.contains(path), "\(path) is not where the scan thinks it is")
        }

        // The needles are only meaningful if the surrounding text is really being read.
        // Read against the shared rule's own file since [[T-5002]] deleted `GoalsView.swift`:
        // it is the one every surface below spends, so a stripper that did nothing here would
        // blind every scan in this suite rather than one of them.
        let rule = try sourceFile("Cadence/Shared/CadenceSelectionNormalization.swift")
        #expect(rule.contains("enum CadenceSelectionNormalization"))
        let stripped = try strippingComments(rule)
        #expect(stripped != rule, "the comment stripper did nothing")
        #expect(stripped.count == rule.count, "the stripper shortened the source instead of blanking it")

        let detail = try strippingComments(sourceFile("Cadence/macOS/Views/ListDetailView.swift"))
        #expect(detail.contains("struct MissingListDetailView: View"))
    }
}

// MARK: - Scan helpers

/// Occurrence count for a regular expression. Returns `-1` on a malformed pattern so a typo reads as
/// a failure rather than as zero matches; `theSheetPairingPatternMatchesWhatItLooksLike` self-checks.
private func matches(_ pattern: String, in text: String) -> Int {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return -1 }
    return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// Enumerated by `enumerator(atPath:)` rather than `enumerator(at:)`: the URL variant yields
/// absolute paths, and `#filePath` can name the repo through a symlinked prefix (`/tmp` against
/// `/private/tmp` on an isolated build tree) that `FileManager` resolves and the literal does not.
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

/// Blanks out `//` line comments and `/* */` block comments so the assertions read code rather than
/// prose. Blanking rather than removing keeps every offset, so `stripped.count == raw.count`.
private func strippingComments(_ source: String) throws -> String {
    // T-1269/T-1270: one pass per pattern, in CadenceSourceScan, on the guarded
    // `(?<!:)//` that the slashes in a URL cannot trigger.
    return CadenceSourceScan.strippingComments(source)
}

#endif
