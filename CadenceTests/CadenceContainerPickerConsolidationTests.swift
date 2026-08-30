import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-514 — the display/save split, third instance.**
///
/// T-446 found it for `Context` and T-488 for `Area`: a picker whose *label* resolved the selected
/// id against a filtered array while its *save* resolved the same id against the unfiltered one, so
/// a list that had since been archived showed "None" and was written straight back.
/// `CadencePickerSupport.selectable(_:selectedID:)` is the rule that removes it — hide what you
/// could newly pick, never the one already assigned.
///
/// The container picker is the same defect in the shape the generic was explicitly *not* built for:
/// a grouped three-way Inbox / Area / Project control, two arrays under two group headings, whose
/// "none" row is Inbox — a real destination rather than the absence of one. So it is not a
/// `items(from:selectedID:noneTitle:)` drop-in. What it takes is `selectable(_:selectedID:)`
/// applied to **both** arrays, plus a breadcrumb that resolves its title against the unfiltered
/// ones.
///
/// **What is behavioural here and what is not.** `Cadence/iOS/` is not compiled by the macOS test
/// target, so the four SwiftUI call sites can only be scanned. The rules underneath them are
/// `Shared/` and `Models/` and are exercised directly: that is the first half of this file.
@Suite
struct CadenceContainerPickerConsolidationTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
    }

    private struct Fixture {
        let modelContext: ModelContext
        let liveArea: Area
        let archivedArea: Area
        let doneArea: Area
        let liveProject: Project
        let archivedProject: Project
        let pausedProject: Project
        let areas: [Area]
        let projects: [Project]
    }

    private func makeFixture() throws -> Fixture {
        let modelContext = try makeContext()

        let liveArea = Area(name: "Operations")
        let archivedArea = Area(name: "Old Ops")
        archivedArea.status = .archived
        let doneArea = Area(name: "Finished Ops")
        doneArea.status = .done

        let liveProject = Project(name: "Rebrand")
        let archivedProject = Project(name: "Old Rebrand")
        archivedProject.status = .archived
        let pausedProject = Project(name: "Paused Rebrand")
        pausedProject.status = .paused

        for area in [liveArea, archivedArea, doneArea] { modelContext.insert(area) }
        for project in [liveProject, archivedProject, pausedProject] { modelContext.insert(project) }
        try modelContext.save()

        return Fixture(
            modelContext: modelContext,
            liveArea: liveArea,
            archivedArea: archivedArea,
            doneArea: doneArea,
            liveProject: liveProject,
            archivedProject: archivedProject,
            pausedProject: pausedProject,
            areas: [liveArea, archivedArea, doneArea],
            projects: [liveProject, archivedProject, pausedProject]
        )
    }

    // MARK: - The rule, on both arrays

    /// **The whole of T-514, behaviourally.** The archived area is not offered as a fresh choice
    /// and *is* offered once it is the one assigned — so the picker that opens on a task filed
    /// there has a row for where the task actually is, which is the row the user needs in order to
    /// pick a different one.
    @Test func theContainerPickerOffersTheRetiredListATaskIsAlreadyFiledIn() throws {
        let fixture = try makeFixture()

        #expect(CadenceTaskComposerSupport.pickableAreas(fixture.areas, selectedID: nil).map(\.name)
                == ["Operations"])
        #expect(CadenceTaskComposerSupport.pickableAreas(
            fixture.areas,
            selectedID: fixture.archivedArea.id
        ).map(\.name) == ["Old Ops", "Operations"])

        // A *completed* area is as retired as an archived one, and equally still shown when it is
        // where the task is. That is `Area.isOfferableInPicker` being `isActive` rather than
        // `!isArchived`, which is the fact T-488 established and a near-copy would have lost.
        #expect(CadenceTaskComposerSupport.pickableAreas(
            fixture.areas,
            selectedID: fixture.doneArea.id
        ).map(\.name) == ["Finished Ops", "Operations"])
    }

    /// The second array, which is the half a `Context`/`Area`-shaped fix would have left out — and
    /// did leave out, twice, because `Project` was deliberately not a `CadencePickable`.
    @Test func theSameRuleReachesTheProjectArrayAndNotOnlyTheAreaOne() throws {
        let fixture = try makeFixture()

        #expect(CadenceTaskComposerSupport.pickableProjects(fixture.projects, selectedID: nil).map(\.name)
                == ["Rebrand"])
        #expect(CadenceTaskComposerSupport.pickableProjects(
            fixture.projects,
            selectedID: fixture.archivedProject.id
        ).map(\.name) == ["Old Rebrand", "Rebrand"])
        #expect(CadenceTaskComposerSupport.pickableProjects(
            fixture.projects,
            selectedID: fixture.pausedProject.id
        ).map(\.name) == ["Paused Rebrand", "Rebrand"])
    }

    /// A selection that names a *deleted* list is not a retired list: there is nothing to show, and
    /// Inbox is where the task is. The two are different questions and `selectable` answers only
    /// the first — `normalizedContainer` owns the second.
    @Test func anIdentifierForADeletedListAddsNoRowToEitherArray() throws {
        let fixture = try makeFixture()
        let vanished = UUID()

        #expect(CadenceTaskComposerSupport.pickableAreas(fixture.areas, selectedID: vanished).map(\.name)
                == ["Operations"])
        #expect(CadenceTaskComposerSupport.pickableProjects(fixture.projects, selectedID: vanished).map(\.name)
                == ["Rebrand"])
    }

    /// `Project` is a `CadencePickable` now, and the fact it contributes is `isActive` — every
    /// state but `active` retires it from fresh choices, matching `Area` and not `Context`.
    @Test func everyProjectStateButActiveIsRetiredFromFreshChoices() throws {
        let project = Project(name: "Rebrand")

        project.status = .active
        #expect(project.isOfferableInPicker)
        for retired in [ProjectStatus.paused, .done, .archived] {
            project.status = retired
            #expect(!project.isOfferableInPicker, "\(retired) should not be offered as a fresh choice")
        }
    }

    /// An unnamed project is called one thing, by the same rule areas and contexts are called
    /// theirs — the quieter half of T-488, where a trigger said "None" and the list it opened said
    /// "Untitled Area" about the same list.
    @Test func anUnnamedProjectIsCalledTheSameThingByThePickerAsByEverythingElse() {
        #expect(CadenceProjectPickerSupport.untitledName == CadenceTitleNormalization.defaultProjectName)
        #expect(CadenceProjectPickerSupport.title(for: Project(name: "   ")) == CadenceTitleNormalization.defaultProjectName)
        #expect(CadenceProjectPickerSupport.title(for: Project(name: "  Rebrand ")) == "Rebrand")
    }

    /// `order`, then name — the tie-break that is the load-bearing half, because `Project.order`
    /// defaults to `0` and SwiftData promises nothing among equal sort keys.
    @Test func theProjectListSortsByOrderThenNameJustAsTheOtherTwoDo() {
        let zebra = Project(name: "Zebra")
        let apple = Project(name: "apple")
        let mango = Project(name: "Mango")
        #expect(CadenceProjectPickerSupport.sorted([zebra, apple, mango]).map(\.name)
                == ["apple", "Mango", "Zebra"])

        zebra.order = -1
        #expect(CadenceProjectPickerSupport.sorted([zebra, apple, mango]).first?.name == "Zebra")
    }

    /// The no-argument spelling says in its own comment that it is "the same rule with nothing
    /// assigned". It has to actually be that. Two overloads of one name whose results come back in
    /// different orders is a trap, and the order is not cosmetic here: `order` defaults to `0`, so
    /// among ties `@Query(sort:)` promises nothing and only `CadencePickerSupport.sorted`'s
    /// name tie-break makes the list stable — which is the reason that tie-break exists.
    @Test func theNoArgumentPickableSpellingIsTheSelectedIDOneWithNothingAssigned() {
        let zebraArea = Area(name: "Zebra")
        let appleArea = Area(name: "apple")
        #expect(CadenceTaskComposerSupport.pickableAreas([zebraArea, appleArea]).map(\.name)
                == CadenceTaskComposerSupport.pickableAreas([zebraArea, appleArea], selectedID: nil).map(\.name))
        #expect(CadenceTaskComposerSupport.pickableAreas([zebraArea, appleArea]).map(\.name)
                == ["apple", "Zebra"])

        let zebraProject = Project(name: "Zebra")
        let appleProject = Project(name: "apple")
        #expect(CadenceTaskComposerSupport.pickableProjects([zebraProject, appleProject]).map(\.name)
                == CadenceTaskComposerSupport.pickableProjects([zebraProject, appleProject], selectedID: nil).map(\.name))
        #expect(CadenceTaskComposerSupport.pickableProjects([zebraProject, appleProject]).map(\.name)
                == ["apple", "Zebra"])
    }

    // MARK: - The half that was already right

    /// The anchor for the split. The *save* side always resolved against existence rather than
    /// activity, and still does — which is why the breadcrumb reading `activeAreas` was a
    /// disagreement rather than a consistent policy, and why pointing the breadcrumb at this
    /// resolver is the fix rather than a second opinion.
    @Test func theSharedResolverNamesARetiredListRatherThanFallingThroughToInbox() throws {
        let fixture = try makeFixture()

        #expect(CadenceTaskComposerSupport.containerName(
            for: .area(fixture.archivedArea.id),
            areas: fixture.areas,
            projects: fixture.projects
        ) == "Old Ops")
        #expect(CadenceTaskComposerSupport.containerName(
            for: .project(fixture.archivedProject.id),
            areas: fixture.areas,
            projects: fixture.projects
        ) == "Old Rebrand")

        // …and a deleted one really is Inbox, so "Inbox" is still a truthful answer somewhere.
        #expect(CadenceTaskComposerSupport.containerName(
            for: .area(UUID()),
            areas: fixture.areas,
            projects: fixture.projects
        ) == CadenceTaskInspectorSupport.inboxSegmentTitle)
    }

    /// The token vocabulary the three-way control is written against, pinned because the picker now
    /// round-trips through it instead of re-deriving `dropFirst(5)` / `dropFirst(8)`.
    @Test func theSelectionIdentifierAccessorsUnwrapExactlyOneSideOfTheThreeWayChoice() {
        let areaID = UUID()
        let projectID = UUID()

        #expect(CadenceTaskComposerSupport.selectedAreaID(.area(areaID)) == areaID)
        #expect(CadenceTaskComposerSupport.selectedAreaID(.project(projectID)) == nil)
        #expect(CadenceTaskComposerSupport.selectedAreaID(.inbox) == nil)

        #expect(CadenceTaskComposerSupport.selectedProjectID(.project(projectID)) == projectID)
        #expect(CadenceTaskComposerSupport.selectedProjectID(.area(areaID)) == nil)
        #expect(CadenceTaskComposerSupport.selectedProjectID(.inbox) == nil)

        #expect(CadenceTaskComposerSupport.selection(fromToken: "area:\(areaID.uuidString)") == .area(areaID))
        #expect(CadenceTaskComposerSupport.selection(fromToken: "project:\(projectID.uuidString)") == .project(projectID))
    }

    // MARK: - The call sites, which the macOS test target does not compile

    private static let containerPickerCallSites = [
        "Cadence/iOS/iOSTaskDetailComponents.swift",
        "Cadence/iOS/iOSCalendarQuickCreateSheet.swift",
        "Cadence/iOS/iOSCreateTaskSheetSupportViews.swift",
        "Cadence/iOS/iOSTaskRowActionViews.swift"
    ]

    /// **Every call site hands the picker the plain queries.** Narrowing is the control's own job
    /// now; a caller that pre-filters puts back exactly the defect — four sites did, and each had
    /// spelled the filter its own way (`activeAreas`, `areas.filter(\.isActive)`,
    /// `pickableAreas(areas)`), which is why this is a shape test and not a grep for one phrase.
    @Test func noCallSitePreFiltersTheListsItHandsTheContainerPicker() throws {
        let handsAFilteredArray = try CadenceScanInstrument(
            "container picker handed a pre-narrowed array",
            fires: """
            iOSContainerChoicePopover(
                areas: areas.filter(\\.isActive),
                projects: projects,
                selection: $token,
                isPresented: $shown
            )
            """,
            andNotOn: """
            iOSContainerChoicePopover(
                areas: areas,
                projects: projects,
                selection: $token,
                isPresented: $shown
            )
            """,
            by: { source in
                let calls = CadenceSourceScan.matchCount("iOSContainerChoicePopover\\(", in: source)
                let plain = CadenceSourceScan.matchCount(
                    "iOSContainerChoicePopover\\(\\s*areas:\\s*areas,\\s*projects:\\s*projects,",
                    in: source
                )
                return calls > 0 && plain != calls
            }
        )

        let hits = try handsAFilteredArray.sweep(
            Self.containerPickerCallSites,
            atLeast: 4,
            including: "Cadence/iOS/iOSTaskDetailComponents.swift",
            read: CadenceSourceScan.strippedSourceReader()
        )

        #expect(hits.isEmpty)
    }

    /// **And the control narrows for itself.** Absence of a filter at the call sites is not
    /// presence of the rule: a popover that simply listed every archived area would pass the sweep
    /// above and offer the user four dead lists.
    @Test func theContainerPickerNarrowsThroughTheSharedSelectableRule() throws {
        let picker = try CadenceSourceScan.strippingComments(
            CadenceSourceScan.sourceFile("Cadence/iOS/iOSChoicePicker.swift")
        )

        #expect(picker.contains("struct iOSContainerChoicePopover"))
        #expect(picker.contains("let areas: [Area]"))
        #expect(picker.contains("let projects: [Project]"))
        #expect(picker.contains("CadenceTaskComposerSupport.pickableAreas("))
        #expect(picker.contains("CadenceTaskComposerSupport.pickableProjects("))
        #expect(picker.contains("selectedAreaID(containerSelection)"))
        #expect(picker.contains("selectedProjectID(containerSelection)"))

        // The pre-T-514 spelling, in either of the two forms it took.
        #expect(CadenceSourceScan.matchCount("activeAreas|activeProjects", in: picker) == 0)
        #expect(CadenceSourceScan.matchCount("[Aa]reas\\s*\\.\\s*filter", in: picker) == 0)
    }

    /// **The breadcrumb reads the unfiltered arrays.** This is the segment that said "Inbox" over a
    /// task that was in an area all along, and it says so because it resolved the id its own way
    /// instead of through the resolver the save already used.
    @Test func thePlacementBreadcrumbNamesItsContainerThroughTheSharedResolver() throws {
        let breadcrumb = try CadenceSourceScan.strippingComments(
            CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskDetailComponents.swift")
        )

        let declaration = try #require(
            breadcrumb.range(of: "struct iOSTaskPlacementBreadcrumb: View {"),
            "the breadcrumb this test is about is not declared here any more"
        )
        let body = try #require(
            breadcrumb.range(of: "struct iOSTaskAttributeChip", range: declaration.upperBound..<breadcrumb.endIndex),
            "the breadcrumb's extent could not be bounded"
        )
        let scope = String(breadcrumb[declaration.upperBound..<body.lowerBound])

        #expect(scope.contains("let areas: [Area]"))
        #expect(scope.contains("let projects: [Project]"))
        #expect(scope.contains("CadenceTaskComposerSupport.containerName("))
        #expect(scope.contains("CadenceTaskComposerSupport.resolvedContainer("))
        // The three things it used to re-derive: the filtered arrays, the prefix arithmetic, and
        // the fall-through that produced the wrong word.
        #expect(CadenceSourceScan.matchCount("activeAreas|activeProjects", in: scope) == 0)
        #expect(CadenceSourceScan.matchCount("dropFirst\\(", in: scope) == 0)
    }

    /// The other three-way container control on this platform is the row's context menu, and it had
    /// the same hole: a task in an archived area got a Move to List menu with no checkmark in it.
    @Test func theRowContextMenusMoveToListOffersTheSameRowsAsThePopover() throws {
        let actions = try CadenceSourceScan.strippingComments(
            CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskRowActionViews.swift")
        )

        #expect(actions.contains("CadenceTaskComposerSupport.pickableAreas(areas, selectedID: task.area?.id)"))
        #expect(actions.contains("CadenceTaskComposerSupport.pickableProjects(projects, selectedID: task.project?.id)"))
        #expect(CadenceSourceScan.matchCount("activeAreas|activeProjects", in: actions) == 0)
    }

    /// **One file states the rules**, exactly as the Context and Area suites require of theirs.
    /// `CadenceProjectPickerSupport` is the two facts and a typealias; the sort, the filter and the
    /// item list stay in `CadencePickerSupport`.
    @Test func theProjectPickerSupportIsNotAThirdCopyOfTheRules() throws {
        let projectSupport = try CadenceSourceScan.strippingComments(
            CadenceSourceScan.sourceFile("Cadence/Shared/CadenceProjectPickerSupport.swift")
        )

        #expect(projectSupport.contains("typealias CadenceProjectPickerSupport = CadencePickerSupport<Project>"))
        #expect(projectSupport.contains("extension Project: CadencePickable"))
        #expect(CadenceSourceScan.matchCount("func\\s+(sorted|selectable|matching|items)\\s*\\(", in: projectSupport) == 0)
        #expect(CadenceSourceScan.matchCount("\\.filter\\s*\\{|\\.sorted\\s*\\{", in: projectSupport) == 0)

        // Not vacuous: the file really was read and really does say something.
        #expect(projectSupport.count > 400)
    }

    // MARK: - T-536 / T-542: the near-copies the shared helpers exist to remove

    /// Every file under `Cadence/`, so a new near-copy is caught wherever it is written rather
    /// than only at the three paths T-542 happened to name.
    private static func allAppSources() throws -> [String] {
        try CadenceSourceScan.swiftFiles(under: "Cadence")
    }

    /// The one file allowed to spell either shape: the file that declares them.
    private static let composerSupportPath = "Cadence/Shared/CadenceTaskComposerSupport.swift"

    /// **T-542.** `TasksPanelComponents`, `SchedulePanelComponents` and `TaskEmbedFieldEditorPopover`
    /// each re-spelled `CadenceTaskComposerSupport.container(of:)` — correctly, which is why this
    /// is convergence rather than a fix, and why the guard has to be a *shape* sweep. A fourth copy
    /// would be correct too; the cost is that the next change to the rule reaches three sites and
    /// misses one.
    ///
    /// The expected hit set is `[composerSupportPath]` rather than empty **on purpose**: the
    /// declaration matches its own detector, so a set equal to exactly the declaring file proves
    /// the sweep is live at the same time as it proves the copies are gone. An empty result here
    /// would mean the detector had stopped seeing the shape at all.
    @Test func noAppSurfaceReSpellsTheTaskToSelectionGetterTheComposerSupportDeclares() throws {
        let reSpellsTheGetter = try CadenceScanInstrument(
            "task-to-selection getter re-spelled",
            fires: """
            get: {
                if let a = task.area    { return .area(a.id) }
                if let p = task.project { return .project(p.id) }
                return .inbox
            },
            """,
            andNotOn: """
            get: { CadenceTaskComposerSupport.container(of: task) },
            """,
            by: { source in
                let collapsed = source.replacingOccurrences(
                    of: "\\s+", with: " ", options: .regularExpression
                )
                return CadenceSourceScan.matchCount(
                    #"(?:if let (\w+) = task\.area \{ return \.area\(\1\.id\) \})|(?:if let (\w+) = task\.project \{ return \.project\(\2\.id\) \})"#,
                    in: collapsed
                ) > 0
            }
        )

        let hits = try reSpellsTheGetter.sweep(
            Self.allAppSources(),
            atLeast: 500,
            including: Self.composerSupportPath,
            read: { CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile($0)) }
        )

        #expect(hits == [Self.composerSupportPath])

        // T-161: absence of the copy is not presence of the call. Pin the wiring too, so reverting
        // a call site fails this test rather than only the sweep above.
        for path in [
            "Cadence/macOS/Views/TasksPanelComponents.swift",
            "Cadence/macOS/Views/SchedulePanelComponents.swift",
            "Cadence/macOS/Views/TaskEmbedFieldEditorPopover.swift"
        ] {
            let source = try CadenceSourceScan.strippingComments(CadenceSourceScan.sourceFile(path))
            #expect(
                source.contains("CadenceTaskComposerSupport.container(of: task)"),
                "\(path) no longer reads the shared task-to-selection accessor"
            )
        }
    }

    /// **T-536.** The `area:` / `project:` container token is one encoding, and `dropFirst(5)` /
    /// `dropFirst(8)` are that encoding's prefix lengths written as numbers. Four files re-derived
    /// them: the two iOS sheets T-536 named, plus `CreateGoalSheet`, whose seed tag is the same
    /// vocabulary reached from macOS.
    ///
    /// The negative witness is the *nearest* one in this repo and not a strawman: eight sites parse
    /// a `task:` or `note:` markdown payload with the very same `dropFirst(5)`, and a detector that
    /// keyed on the number alone would condemn all of them. It is the pair — this prefix with that
    /// length — that names the container encoding.
    @Test func noAppSurfaceReDerivesTheContainerTokenPrefixArithmetic() throws {
        let reDerivesTheToken = try CadenceScanInstrument(
            "container token prefix arithmetic re-derived",
            fires: """
            guard containerSelection.hasPrefix("area:"),
                  let id = UUID(uuidString: String(containerSelection.dropFirst(5)))
            else { return nil }
            """,
            andNotOn: """
            if trimmed.hasPrefix("task:") {
                return target(kind: .task, payload: String(trimmed.dropFirst(5)))
            }
            """,
            by: { source in
                let area = source.contains("hasPrefix(\"area:\")") && source.contains("dropFirst(5)")
                let project = source.contains("hasPrefix(\"project:\")") && source.contains("dropFirst(8)")
                return area || project
            }
        )

        let hits = try reDerivesTheToken.sweep(
            Self.allAppSources(),
            atLeast: 500,
            including: Self.composerSupportPath,
            read: CadenceSourceScan.strippedSourceReader()
        )

        #expect(hits == [Self.composerSupportPath])

        for path in [
            "Cadence/iOS/iOSTaskDetailSheet.swift",
            "Cadence/iOS/iOSCalendarQuickCreateSheet.swift",
            "Cadence/macOS/Sheets/CreateGoalSheet.swift"
        ] {
            let source = try CadenceSourceScan.strippingComments(CadenceSourceScan.sourceFile(path))
            #expect(
                source.contains("CadenceTaskComposerSupport.selection(fromToken:"),
                "\(path) no longer reads the shared token mapping"
            )
        }

        // And the quick-create tile names its list through the shared resolver, whose `displayName`
        // trims before it falls back — the one place the old copy genuinely differed.
        let quickCreate = try CadenceSourceScan.strippingComments(
            CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarQuickCreateSheet.swift")
        )
        #expect(quickCreate.contains("CadenceTaskComposerSupport.containerName(for: containerChoice"))
        #expect(CadenceSourceScan.matchCount("defaultAreaName|defaultProjectName", in: quickCreate) == 0)
    }

    /// **The two sweeps above read the tree through different readers, and that has to stay true.**
    /// `codeOnly` blanks string literals as well as comments, so the token sweep's `hasPrefix("area:")`
    /// needle can never match there — it would be permanently, silently green. `strippingComments`
    /// keeps literals, so the getter sweep would count this suite's own fixtures as code. Each sweep
    /// takes the reader it needs; this pins that the pairing cannot collapse into one.
    @Test func theTwoContainerSweepsReadTheTreeThroughGenuinelyDifferentReaders() throws {
        let raw = try CadenceSourceScan.sourceFile(Self.composerSupportPath)
        let literalsKept = CadenceSourceScan.strippingComments(raw)
        let literalsBlanked = CadenceSourceScan.codeOnly(raw)

        #expect(literalsKept.contains("hasPrefix(\"area:\")"))
        #expect(!literalsBlanked.contains("hasPrefix(\"area:\")"))
        #expect(literalsBlanked.contains("hasPrefix("))
    }
}
