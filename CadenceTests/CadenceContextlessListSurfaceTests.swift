import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Cadence

/// **The shape five tickets have now been filed for, held in one place.**
///
/// `Area.context` and `Project.context` are optional, and iOS's list editor writes `nil` there from
/// a "None" row in new and edit mode alike — so a list that belongs to no context is a state a
/// shipping surface makes, and it arrives on the Mac by sync. Every control that shows lists
/// grouped by context has been written the same way, and every one of them has been wrong the same
/// way:
///
/// | ticket | surface | what it lost |
/// |---|---|---|
/// | T-534 | `ContainerPickerFilterSupport.groups` | the row a task is already filed in |
/// | T-538 | the macOS sidebar (`SidebarView.listSections`) | the list, entirely — no row at all |
/// | T-558 | `TildeContainerPickerSupport.flatContainers` | both macOS composers' `~` panel |
/// | T-559 | `CreateListSheet` / `EditListSheet` | the ability to make or correct one |
///
/// The cause is one sentence, and it is the reason a compiler diagnostic could never have existed
/// for any of them: **rendering derived by traversing contexts silently defines its own domain, and
/// its blind spot is exactly the rows whose relationship is `nil`.** `ForEach(contexts) { $0.areas }`
/// never constructs the nil case, so the optional is *discharged by the iteration* rather than
/// narrowed by a check somebody forgot.
///
/// So this suite is two halves, and the first is the load-bearing one:
///
/// 1. **A behavioural registry.** One fixture holding a context-less list of each kind and a list
///    under a context that is not offered, run through every list-offering entry point the test
///    target can call. It does not care how a surface spells the question.
/// 2. **A source ledger.** Every file that derives lists from a context, by count. A scan cannot
///    tell a right fold from a wrong one — but it can make the sixth one impossible to add without
///    somebody writing down which it is, which is the whole failure mode above.
@MainActor
struct CadenceContextlessListSurfaceTests {

    // MARK: - Fixture

    private struct Fixture {
        /// The contexts a control is handed. `retired` is deliberately absent.
        let offered: [Context]
        let areas: [Area]
        let projects: [Project]
        /// Filed under `offered[0]`. The control must keep drawing this one too.
        let filed: Area
        /// No context at all.
        let loose: Area
        /// No context at all.
        let stray: Project
        /// Filed under a context that exists and was not offered — an archived one, here.
        let stranded: Project
        let modelContext: ModelContext
    }

    private func makeFixture() throws -> Fixture {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let work = Context(name: "Work")
        work.order = 0
        let retired = Context(name: "Retired")
        retired.order = 1
        retired.isArchived = true

        let filed = Area(name: "Filed", context: work)
        filed.order = 0
        let loose = Area(name: "Loose", context: nil)
        loose.order = 1
        let stray = Project(name: "Stray", context: nil)
        stray.order = 2
        let stranded = Project(name: "Stranded", context: retired)
        stranded.order = 3

        for model in [work, retired] { modelContext.insert(model) }
        for model in [filed, loose] { modelContext.insert(model) }
        for model in [stray, stranded] { modelContext.insert(model) }
        try modelContext.save()

        return Fixture(
            offered: [work],
            areas: [filed, loose],
            projects: [stray, stranded],
            filed: filed,
            loose: loose,
            stray: stray,
            stranded: stranded,
            modelContext: modelContext
        )
    }

    // MARK: - 1. The behavioural registry

    /// One list-offering entry point, reduced to the names it offers.
    private struct Surface {
        let name: String
        let names: (Fixture) -> [String]
    }

    /// **Every pure entry point in the app that answers "which lists may I show, grouped by
    /// context".** Four, and they are named rather than counted, because a registry whose
    /// membership is a number is a registry nobody has to add to.
    ///
    /// The macOS sidebar and the iPad sidebar are one entry — since T-538 they are literally one
    /// call, and `CadenceSidebarListsSupportTests` pins that they still are. `CreateGoalSheet`'s
    /// picker is *not* here and cannot be: its grouping is written inline in a SwiftUI `body`, so
    /// nothing outside that view can call it. That is what the ledger below is for.
    private static let surfaces: [Surface] = [
        Surface(name: "TildeContainerPickerSupport.flatContainers") { fixture in
            TildeContainerPickerSupport.flatContainers(
                query: "",
                contexts: fixture.offered,
                areas: fixture.areas,
                projects: fixture.projects,
                // Nothing assigned, matching the `groups` entry below: this registry asks what a
                // control offers as a *fresh* choice. The list a draft is already in is T-684's
                // question and is pinned in `CadenceTildeContainerPickerTests`.
                selection: .inbox
            )
            .map(\.name)
            // Inbox is a row of this panel rather than a list, and none of the other three
            // surfaces offers it — so it is dropped here rather than added to every expectation.
            .filter { $0 != "Inbox" }
        },
        Surface(name: "ContainerPickerFilterSupport.groups") { fixture in
            ContainerPickerFilterSupport.groups(
                contexts: fixture.offered,
                areas: fixture.areas,
                projects: fixture.projects,
                selection: .inbox,
                query: ""
            ).flatMap { $0.areas.map(\.name) + $0.projects.map(\.name) }
        },
        Surface(name: "GoalLinkPresentation.candidateGroups") { fixture in
            GoalLinkPresentation.candidateGroups(
                contexts: fixture.offered,
                areas: fixture.areas,
                projects: fixture.projects,
                query: ""
            ).flatMap { $0.targets.map(\.name) }
        },
        Surface(name: "CadenceSidebarLists.sections") { fixture in
            CadenceSidebarLists.sections(
                contexts: fixture.offered.map {
                    CadenceSidebarLists.ContextRef(id: $0.id, name: $0.name)
                },
                elements: fixture.areas.map { CadenceSidebarLists.Item($0) }
                    + fixture.projects.map { CadenceSidebarLists.Item($0) },
                keepingEmptyContexts: true,
                item: { $0 }
            ).flatMap { $0.elements.map(\.name) }
        }
    ]

    /// **The pin.** Every surface offers the context-less lists and the un-offered context's list,
    /// and still offers the filed one.
    ///
    /// Asserted as set equality over the whole offer, not as `contains` — `contains` is green on a
    /// surface that gained the leftovers and lost the filed row, which is the mirror-image defect
    /// and the one a fix of this shape is most likely to introduce.
    @Test func everyListOfferingSurfaceReachesAListNoOfferedContextOwns() throws {
        let fixture = try makeFixture()

        #expect(Self.surfaces.count == 4)
        #expect(
            Self.surfaces.map(\.name).sorted() == [
                "CadenceSidebarLists.sections",
                "ContainerPickerFilterSupport.groups",
                "GoalLinkPresentation.candidateGroups",
                "TildeContainerPickerSupport.flatContainers"
            ]
        )

        for surface in Self.surfaces {
            let offered = surface.names(fixture)
            #expect(
                Set(offered) == ["Filed", "Loose", "Stray", "Stranded"],
                "\(surface.name) offers \(offered.sorted()) — a list with no offered context is missing"
            )
        }
    }

    /// The leftovers go **last**, everywhere that has an order at all. A control that surfaced them
    /// by prepending them would pass the test above and reorder every user's list on every screen.
    @Test func theLeftoversAreOfferedAfterTheListsAnOfferedContextOwns() throws {
        let fixture = try makeFixture()

        for surface in Self.surfaces {
            let offered = surface.names(fixture)
            let filedIndex = try #require(offered.firstIndex(of: "Filed"), "\(surface.name)")
            for leftover in ["Loose", "Stray", "Stranded"] {
                let index = try #require(offered.firstIndex(of: leftover), "\(surface.name) / \(leftover)")
                #expect(index > filedIndex, "\(surface.name) draws \(leftover) before Filed")
            }
        }
    }

    /// The catch-all's own name, once. All four surfaces — including `GoalLinkCandidateGroup.title`,
    /// which used to say "No Context" — read `CadenceSidebarLists.ungroupedTitle` rather than
    /// respelling it (T-771). `flatContainers` renders no heading at all, so it is not asserted
    /// here.
    @Test func theCatchAllHeadingIsReadFromOnePlaceByEverythingThatDrawsOne() throws {
        let fixture = try makeFixture()

        let pickerGroups = ContainerPickerFilterSupport.groups(
            contexts: fixture.offered,
            areas: fixture.areas,
            projects: fixture.projects,
            selection: .inbox,
            query: ""
        )
        #expect(pickerGroups.last?.contextID == nil)
        #expect(pickerGroups.last?.title == CadenceSidebarLists.ungroupedTitle)

        let sidebarSections = CadenceSidebarLists.sections(
            contexts: fixture.offered.map { CadenceSidebarLists.ContextRef(id: $0.id, name: $0.name) },
            items: fixture.areas.map { CadenceSidebarLists.Item($0) }
                + fixture.projects.map { CadenceSidebarLists.Item($0) }
        )
        #expect(sidebarSections.last?.contextID == nil)
        #expect(sidebarSections.last?.title == CadenceSidebarLists.ungroupedTitle)

        // The former divergence: this used to be its own literal "No Context" (T-771).
        let goalGroups = GoalLinkPresentation.candidateGroups(
            contexts: fixture.offered,
            areas: fixture.areas,
            projects: fixture.projects,
            query: ""
        )
        #expect(goalGroups.last?.context == nil)
        #expect(goalGroups.last?.title == CadenceSidebarLists.ungroupedTitle)
        #expect(CadenceSidebarLists.ungroupedTitle == "Other")
    }

    /// The membership rule itself, which is the half that kept being respelled. `nil` and "a
    /// context the caller did not offer" are the same answer; a real offered context is not.
    @Test func theOfferedContextTestTreatsNilAndAnUnofferedContextAlike() {
        let offered = UUID()
        let elsewhere = UUID()

        #expect(CadenceSidebarLists.isOffered(offered, among: [offered]))
        #expect(CadenceSidebarLists.isOffered(elsewhere, among: [offered]) == false)
        #expect(CadenceSidebarLists.isOffered(nil, among: [offered]) == false)
        #expect(CadenceSidebarLists.isOffered(nil, among: []) == false)
        #expect(CadenceSidebarLists.isOffered(offered, among: []) == false)
    }

    // MARK: - 2. The source ledger

    private static func contextDerivedListCount(in source: String) -> Int {
        let code = CadenceSourceScan.codeOnly(source)
        // Two spellings, and they are the only two the repo uses: a flat array narrowed by a
        // context identity, and the relationship walked off a context.
        return CadenceSourceScan.matchCount("\\.context\\?\\.id\\s*==", in: code)
            + CadenceSourceScan.matchCount("\\b\\w*[Cc]ontext\\.(?:areas|projects)\\b", in: code)
    }

    private func contextDerivedListInstrument() throws -> CadenceScanInstrument {
        try CadenceScanInstrument(
            "derives lists from a context",
            fires: """
            for context in contexts {
                let owned = areas.filter { $0.context?.id == context.id }
                let more = context.projects ?? []
            }
            """,
            // The nearest miss: reading a *task*'s own context, and reading a list's context for
            // anything but membership. Both mention the same properties in the same shapes.
            andNotOn: """
            task.context = area.context
            let tint = project.context.map { Color(hex: $0.colorHex) }
            let ids = contexts.map(\\.id)
            """,
            by: { Self.contextDerivedListCount(in: $0) > 0 }
        )
    }

    /// **The ledger.** Every file that derives lists from a context, with the count, and a note on
    /// how each one answers "and the lists no context owns".
    ///
    /// A scan cannot judge these — a fold scoped to one context on purpose (a deletion cascade, an
    /// MCP response *about* that context) is right, and a fold meant to show the user every list is
    /// wrong. What the ledger buys is that the tenth entry cannot be added silently, which is
    /// exactly how the first five got written.
    private static let knownContextDerivedListSites: [String: Int] = [
        // Correct by scope: both walk the one context being deleted, and its lists are precisely
        // what the cascade is about.
        "Cadence/Services/CadenceListDeleteHelpers.swift": 2,
        "Cadence/Shared/CadenceListDeletionSummary.swift": 2,
        // Correct by scope: an MCP response *about* a named context, plus one habit filter keyed
        // on a context id the caller asked for.
        "Cadence/Services/MCPReadOnly/CadenceReadService.swift": 7,
        // A write path: the DEBUG sample-data seeder attaches lists to the contexts it just made.
        "Cadence/iOS/iOSSampleDataSupport.swift": 6,
        // **Guarded downstream, not here.** `listGroupOrder` is a bare context walk and does lose
        // the unfiled lists — its only consumer, `todayListGroups`, rebuilds them as `leftovers`
        // from the tasks themselves and sorts them onto the tail. Correct today, and correct for a
        // reason that lives in a different function.
        "Cadence/Shared/CadenceTaskQuerySupport.swift": 2,
        // Correct: catch-all keyed on the offered set (T-683). It was the sixth instance of the
        // fold — a bucket keyed on `context == nil`, right for a list with no context and wrong
        // for one whose context exists and was not offered. Latent rather than live even then,
        // because every caller passes an unfiltered context query; fixed anyway, because the next
        // caller is what latent means. Its heading now reads `ungroupedTitle` ("Other") rather
        // than its own "No Context" literal (T-771), pinned by
        // `theGoalSheetsCatchAllHeadingReadsTheSharedUngroupedTitle`.
        "Cadence/macOS/Sheets/CreateGoalSheet.swift": 2,
        // Correct: the optional-to-optional comparison. `nil == nil` is the unfiled bucket, so the
        // new list is numbered against the siblings it will actually sit beside (T-559).
        "Cadence/macOS/Sheets/CreateListSheet.swift": 2,
        // Correct: catch-all keyed on the offered set (T-534).
        "Cadence/macOS/Views/ContainerPickerSupportViews.swift": 2,
        // Correct: catch-all keyed on the offered set (T-558).
        "Cadence/macOS/Views/TildeContainerPicker.swift": 2
    ]

    @Test func everyPlaceThatDerivesListsFromAContextIsOnTheLedger() throws {
        let offenders = try contextDerivedListInstrument().sweep(
            try cadenceAppSwiftFiles(),
            // 565 files at the time of writing; the floor rules out a walk that found one folder
            // and called it the app.
            atLeast: 400,
            // An explicitly *shared* witness, so a walk narrowed to either platform tree throws
            // `walkMissedItsWitness` before it counts anything.
            including: "Cadence/Shared/CadenceTaskQuerySupport.swift",
            read: cadenceTestSource
        )

        let unexpected = Set(offenders).subtracting(Self.knownContextDerivedListSites.keys)
        #expect(
            unexpected.isEmpty,
            """
            \(unexpected.sorted()) derives lists from a context. Say in \
            knownContextDerivedListSites how it reaches the lists no context owns — see T-534, \
            T-538, T-558.
            """
        )
        let gone = Set(Self.knownContextDerivedListSites.keys).subtracting(offenders)
        #expect(gone.isEmpty, "\(gone.sorted()) no longer derives lists from a context — delete its ledger line")
    }

    /// The ledger's *numbers*, not only its paths: a file with seven that keeps one is still on the
    /// list, and path equality alone would never notice the six that went.
    @Test func theContextDerivedListLedgerStatesHowManySitesEachFileHas() throws {
        var actual: [String: Int] = [:]
        for path in try cadenceAppSwiftFiles() {
            let count = Self.contextDerivedListCount(in: try cadenceTestSource(path))
            if count > 0 { actual[path] = count }
        }

        #expect(actual == Self.knownContextDerivedListSites, "measured: \(actual.sorted { $0.key < $1.key })")
        // The headline, so a report and the ledger cannot disagree.
        #expect(actual.values.reduce(0, +) == 27)
        #expect(actual.count == 9)
        // And the two columns that used to be the worst of them are off the list entirely: neither
        // derives its rows by walking contexts any more (T-538).
        #expect(actual["Cadence/macOS/Views/SidebarView.swift"] == nil)
        #expect(actual["Cadence/macOS/Views/SidebarComponents.swift"] == nil)
        #expect(actual["Cadence/iOS/iOSRootSidebar.swift"] == nil)
    }

    // MARK: - 3. T-683: the goal sheet's initial-linked-list picker

    /// **The sixth instance, and the one the behavioural registry cannot reach.**
    ///
    /// `CreateGoalSheet` buckets lists inline in a SwiftUI `body`, so no test can call its
    /// grouping — the ledger above exists precisely because of that. What is checkable is which
    /// question the catch-all asks: `context == nil` is right for a list that belongs to no
    /// context and wrong for one whose context exists and was not offered, which is the ordinary
    /// state of a list under an archived context.
    ///
    /// Latent on this tree — `allContexts` is an unfiltered `@Query`, so nothing is dropped today —
    /// and fixed anyway, because "latent" here names the caller that has not been written yet.
    @Test func theGoalSheetsInitialListPickerBucketsOnTheOfferedContextsRatherThanOnNil() throws {
        let raw = try cadenceTestSource("Cadence/macOS/Sheets/CreateGoalSheet.swift")
        let code = CadenceSourceScan.codeOnly(raw)
        #expect(code != raw, "the comment stripper read the wrong file")
        #expect(code.contains("struct CreateGoalSheet: View"), "non-vacuity: still the sheet")
        // The fold it is a catch-all for is still there; this is not a test that passed by the
        // picker being deleted.
        #expect(CadenceSourceScan.matchCount("\\.context\\?\\.id\\s*==\\s*ctx\\.id", in: code) == 2)

        #expect(code.contains("let offered = Set(allContexts.map(\\.id))"))
        #expect(
            CadenceSourceScan.matchCount(
                "!CadenceSidebarLists\\.isOffered\\(\\$0\\.context\\?\\.id, among: offered\\)",
                in: code
            ) == 2,
            "the goal sheet's catch-all does not ask the offered-context question for both kinds"
        )
        // The pre-T-683 spelling, for both kinds.
        #expect(CadenceSourceScan.matchCount("\\$0\\.context == nil", in: code) == 0)
    }

    /// **The heading is converged (T-771).** Two spellings of the same bucket used to be live in
    /// the app: "Other" (`CadenceSidebarLists.ungroupedTitle`, both sidebars and the container
    /// picker) and "No Context" (here and `GoalLinkCandidateGroup.title`). They are the same row
    /// under the same rule, so both now read the shared constant rather than restating it.
    /// "No context" — the macOS context picker's own none-row — is a different idea, an unset
    /// *field*, and is deliberately untouched.
    @Test func theGoalSheetsCatchAllHeadingReadsTheSharedUngroupedTitle() throws {
        // `strippingComments`, not `codeOnly`: the pre-T-771 literal this guards against would
        // have lived *inside* a string, and `codeOnly` blanks literal contents.
        let raw = try cadenceTestSource("Cadence/macOS/Sheets/CreateGoalSheet.swift")
        let code = CadenceSourceScan.strippingComments(raw)
        #expect(code != raw, "the comment stripper read the wrong file")
        // The pre-T-771 spelling.
        #expect(CadenceSourceScan.matchCount("Section\\(\"No Context\"\\)", in: code) == 0)
        #expect(CadenceSourceScan.matchCount("Section\\(CadenceSidebarLists\\.ungroupedTitle\\)", in: code) == 1)
        #expect(CadenceSidebarLists.ungroupedTitle == "Other")
    }

    /// **The sweep that stops the second spelling coming back (T-771).** `ungroupedTitle`'s own
    /// value is "Other" — nine characters, under `CadenceSharedConstantReuseSweepTests`'
    /// twelve-character floor — so the general shared-constant sweep cannot guard this rename on
    /// its own; this is the narrow one written for it.
    ///
    /// The needle is the exact case, "No Context", not "no context" or "No context": the last of
    /// those is a live and different concept (the macOS context picker's own none-row, an unset
    /// *field* rather than a catch-all bucket) and must keep typing its own literal undisturbed.
    private func noContextRespellingInstrument() throws -> CadenceScanInstrument {
        try CadenceScanInstrument(
            "catch-all respelled as \"No Context\" (T-771)",
            fires: """
            Section("No Context") {
                Text(target.name)
            }
            """,
            // The still-live, different concept: the context picker's own none-row, lower-case.
            andNotOn: """
            let noneTitle = "No context"
            """,
            by: { CadenceSourceScan.matchCount("\"No Context\"", in: CadenceSourceScan.strippingComments($0)) > 0 }
        )
    }

    @Test func theCatchAllNeverRespellsItselfAsNoContextAgain() throws {
        let offenders = try noContextRespellingInstrument().sweep(
            try cadenceAppSwiftFiles(),
            atLeast: 400,
            including: "Cadence/macOS/Sheets/CreateGoalSheet.swift",
            read: cadenceTestSource
        )
        #expect(
            offenders.isEmpty,
            """
            \(offenders) respells the catch-all as "No Context" instead of reading \
            CadenceSidebarLists.ungroupedTitle ("Other") — T-771 converged this to one spelling
            """
        )
    }

    // MARK: - 4. T-559: the Mac can make and correct one

    /// `CreateListSheet` takes an optional context and states it in a row that can change it.
    ///
    /// A scan, because the sheet's state and its `create()` are private to a SwiftUI `View`. What
    /// it pins is the two halves that were the defect: the non-optional parameter, and the absence
    /// of any control at all.
    @Test func theMacCreateListSheetTakesAnOptionalContextAndDrawsARowForIt() throws {
        let raw = try cadenceTestSource("Cadence/macOS/Sheets/CreateListSheet.swift")
        let code = CadenceSourceScan.strippingComments(raw)
        #expect(code != raw, "the comment stripper read the wrong file")
        #expect(code.contains("struct CreateListSheet: View {"))

        #expect(code.contains("init(context: Context?)"))
        #expect(code.contains("ListEditorContextRow(contexts: contexts, selectedID: $selectedContextID)"))
        // The pre-T-559 spellings.
        #expect(code.contains("let context: Context\n") == false)
        #expect(code.contains("titleTrailing") == false)
        // And the sheet writes what the row holds, not what it was opened on.
        #expect(CadenceSourceScan.matchCount("context:\\s*selectedContext\\b", in: code) == 2)
    }

    /// Both edit sheets draw the same row, seed it from the stored value, and write it back.
    ///
    /// Seeding matters on its own: a row that always opened on "No context" would silently clear
    /// every list's context the first time somebody renamed one.
    @Test func bothMacListEditorsDrawTheContextRowAndRoundTripTheStoredValue() throws {
        let raw = try cadenceTestSource("Cadence/macOS/Sheets/EditListSheet.swift")
        let code = CadenceSourceScan.strippingComments(raw)
        #expect(code != raw, "the comment stripper read the wrong file")
        #expect(code.contains("struct EditAreaSheet: View {"))
        #expect(code.contains("struct EditProjectSheet: View {"))

        // One row per sheet, not one for the file.
        #expect(
            CadenceSourceScan.matchCount(
                "ListEditorContextRow\\(contexts: contexts, selectedID: \\$selectedContextID\\)",
                in: code
            ) == 2
        )
        for model in ["area", "project"] {
            #expect(code.contains("State(initialValue: \(model).context?.id)"), "\(model) editor does not seed the row")
            #expect(code.contains("\(model).context = selectedContext"), "\(model) editor does not write the row back")
        }

        // **The half a behavioural test cannot reach.** `applyEdits()` is private to a SwiftUI
        // `View`, and the write it performs is the one that turns a context control into T-293:
        // moving a list without re-pointing its tasks leaves them in the list and out of the
        // context. Once per sheet, over the targets the undo also carries — three mentions of
        // `contextChangeTargets` each (the property, the save, the lifecycle path).
        #expect(
            CadenceSourceScan.matchCount(
                "CadenceTaskMutationSupport\\.reassignInheritedContext\\(",
                in: code
            ) == 2
        )
        #expect(CadenceSourceScan.matchCount("contextChangeTargets", in: code) == 6)
        #expect(CadenceSourceScan.matchCount("inheritedContextTargets\\(", in: code) == 2)
    }

    /// The row is one component, in `Sheets/`, and nothing else declares its own.
    @Test func theListEditorContextRowIsDeclaredInExactlyOnePlace() throws {
        let instrument = try CadenceScanInstrument(
            "list editor context row declaration",
            fires: "struct ListEditorContextRow: View {\n    let contexts: [Context]\n}",
            andNotOn: "ListEditorContextRow(contexts: contexts, selectedID: $selectedContextID)",
            by: { source in
                CadenceSourceScan.matchCount(
                    "struct\\s+\\w*ListEditorContextRow\\b",
                    in: CadenceSourceScan.codeOnly(source)
                ) > 0
            }
        )

        let declarations = try instrument.sweep(
            try cadenceAppSwiftFiles(),
            atLeast: 400,
            including: "Cadence/macOS/Sheets/ListEditorSupportViews.swift",
            read: cadenceTestSource
        )

        #expect(declarations == ["Cadence/macOS/Sheets/ListEditorSupportViews.swift"])
    }

    /// The sidebar's catch-all header opens the sheet too, on no context.
    @Test func theSidebarsCatchAllHeaderOpensTheCreateSheetOnNoContext() throws {
        let raw = try cadenceTestSource("Cadence/macOS/Views/SidebarView.swift")
        let code = CadenceSourceScan.strippingComments(raw)
        #expect(code != raw, "the comment stripper read the wrong file")
        #expect(code.contains("struct SidebarView: View {"))

        // `owner` is `nil` on the catch-all and the "+" is handed over unconditionally — the
        // pre-T-559 spelling wrapped it in `owner.map`, which withheld the button there.
        #expect(code.contains("onAddList: { newListTarget = SidebarNewListTarget(context: owner) }"))
        #expect(code.contains("owner.map") == false)
        #expect(code.contains("CreateListSheet(context: target.context)"))

        // And the header component no longer has a "no button" case to fall into.
        let components = CadenceSourceScan.strippingComments(
            try cadenceTestSource("Cadence/macOS/Views/SidebarComponents.swift")
        )
        #expect(components.contains("let onAddList: () -> Void"))
        #expect(components.contains("let onAddList: (() -> Void)?") == false)
    }

    /// The catch-all's presentation id is the section's own, not a fourth spelling of "unfiled".
    @Test func theSidebarsNewListTargetIdentifiesTheCatchAllTheSameWayTheSectionDoes() {
        let context = Context(name: "Work")

        #expect(SidebarNewListTarget(context: context).id == context.id.uuidString)
        #expect(SidebarNewListTarget(context: nil).id == CadenceSidebarLists.Section.ungroupedID)
    }

    // MARK: - 5. T-559: moving a list takes its tasks with it

    /// **T-293, one level up.** `AppTask.context` is a denormalized copy of the list's, so a list
    /// that changes context and leaves its tasks behind drops them out of the context while they
    /// stay in the list. Adding a context control to the Mac's editors without re-pointing would
    /// have shipped that bug a second time.
    @Test func reassigningAnInheritedContextWritesExactlyTheTargetsItAnnounces() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let work = Context(name: "Work")
        let home = Context(name: "Home")
        let area = Area(name: "Filed", context: work)
        // A child project with no context of its own inherits through the area, so its tasks are
        // invalidated by the area's move as well — the half every call site used to miss.
        let inheriting = Project(name: "Inheriting", context: nil, area: area)
        // A child that names its own context does not, and must be left alone.
        let independent = Project(name: "Independent", context: home, area: area)

        let direct = AppTask(title: "Direct")
        direct.area = area
        direct.context = work
        let inherited = AppTask(title: "Inherited")
        inherited.project = inheriting
        inherited.context = work
        let untouched = AppTask(title: "Untouched")
        untouched.project = independent
        untouched.context = home

        for model in [work, home] { modelContext.insert(model) }
        modelContext.insert(area)
        for model in [inheriting, independent] { modelContext.insert(model) }
        for model in [direct, inherited, untouched] { modelContext.insert(model) }
        area.projects = [inheriting, independent]
        area.tasks = [direct]
        inheriting.tasks = [inherited]
        independent.tasks = [untouched]
        try modelContext.save()

        let announced = CadenceTaskMutationSupport.inheritedContextTargets(area: area)
        #expect(Set(announced.map(\.title)) == ["Direct", "Inherited"])

        area.context = home
        CadenceTaskMutationSupport.reassignInheritedContext(area: area)

        #expect(direct.context?.id == home.id)
        #expect(inherited.context?.id == home.id)
        // The one the announcement left out is the one the write left alone.
        #expect(untouched.context?.id == home.id)
        #expect(announced.contains { $0.title == "Untouched" } == false)
    }

    /// A project announces its own tasks and nothing else — nothing inherits from a project.
    @Test func aProjectsInheritedContextTargetsAreItsOwnTasks() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let project = Project(name: "Solo", context: nil)
        let task = AppTask(title: "Only")
        task.project = project
        modelContext.insert(project)
        modelContext.insert(task)
        project.tasks = [task]
        try modelContext.save()

        #expect(CadenceTaskMutationSupport.inheritedContextTargets(project: project).map(\.title) == ["Only"])
        #expect(CadenceTaskMutationSupport.inheritedContextTargets().isEmpty)
    }

    /// The undo a macOS editor builds when the context moves puts the tasks back too, not only the
    /// list's own fields — including the cascaded ones, which is what `inheritedContextTargets`
    /// exists to hand it. A snapshot taken from `area.tasks` alone restores the list and leaves the
    /// child project's tasks pointing at the context the save was refused from.
    @Test func aRefusedContextMoveRestoresTheCascadedTasksAndNotOnlyTheList() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let work = Context(name: "Work")
        let home = Context(name: "Home")
        let area = Area(name: "Filed", context: work)
        let inheriting = Project(name: "Inheriting", context: nil, area: area)
        let cascaded = AppTask(title: "Cascaded")
        cascaded.project = inheriting
        cascaded.context = work

        for model in [work, home] { modelContext.insert(model) }
        modelContext.insert(area)
        modelContext.insert(inheriting)
        modelContext.insert(cascaded)
        area.projects = [inheriting]
        inheriting.tasks = [cascaded]
        try modelContext.save()

        let undo = CadenceListEditSnapshot(
            area,
            tasks: CadenceTaskMutationSupport.inheritedContextTargets(area: area)
        )
        area.context = home
        area.name = "Renamed"
        CadenceTaskMutationSupport.reassignInheritedContext(area: area)
        #expect(cascaded.context?.id == home.id)

        undo.restore()

        #expect(area.name == "Filed")
        #expect(area.context?.id == work.id)
        #expect(cascaded.context?.id == work.id)
    }

    /// **T-685, the same defect on iOS.** The Mac's editors ask `inheritedContextTargets` what the
    /// move reaches; `iOSListEditorSheet.save()` re-derived it as `area.tasks ?? []`, which is the
    /// direct tasks only. `reassignTasks` then calls the shared reassignment, which by design also
    /// re-points every child project that inherits — tasks the snapshot never held, so a refused
    /// save put the area back and left them in the context the save did not land.
    ///
    /// `save()` is private to a SwiftUI `View`, so the branch is reached the only way it can be:
    /// the set the editor *names* is read out of its source, and then that set is actually
    /// snapshotted, moved and restored here. A scan alone would only pin a spelling; this asserts
    /// what the spelling costs the user.
    @Test func theIOSListEditorsAreaUndoSetRestoresACascadedChildProjectsTasks() throws {
        let editor = CadenceSourceScan.strippingComments(
            try cadenceTestSource("Cadence/iOS/iOSListEditorViews.swift")
        )
        #expect(editor.contains("struct iOSListEditorSheet: View"), "the scan read the wrong file")
        let save = try #require(CadenceSourceScan.functionBody(named: "save", in: editor))
        #expect(save.contains("case .editArea(let area):"), "the editor no longer has an area branch")

        let namesTheCascade = CadenceSourceScan.matchCount(
            #"CadenceListEditSnapshot\(\s*area,\s*tasks: CadenceTaskMutationSupport\.inheritedContextTargets\(area: area\)\s*\)"#,
            in: save
        ) == 1
        let namesTheDirectTasksOnly = CadenceSourceScan.matchCount(
            #"CadenceListEditSnapshot\(area, tasks: area\.tasks \?\? \[\]\)"#,
            in: save
        ) == 1
        #expect(
            namesTheCascade != namesTheDirectTasksOnly,
            "the area branch names neither undo set this test knows how to run"
        )

        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let work = Context(name: "Work")
        let home = Context(name: "Home")
        let area = Area(name: "Filed", context: work)
        let inheriting = Project(name: "Inheriting", context: nil, area: area)
        let direct = AppTask(title: "Direct")
        direct.area = area
        direct.context = work
        let cascaded = AppTask(title: "Cascaded")
        cascaded.project = inheriting
        cascaded.context = work

        for model in [work, home] { modelContext.insert(model) }
        modelContext.insert(area)
        modelContext.insert(inheriting)
        for model in [direct, cascaded] { modelContext.insert(model) }
        area.projects = [inheriting]
        area.tasks = [direct]
        inheriting.tasks = [cascaded]
        try modelContext.save()

        let targets = namesTheCascade
            ? CadenceTaskMutationSupport.inheritedContextTargets(area: area)
            : (area.tasks ?? [])
        let undo = CadenceListEditSnapshot(area, tasks: targets)

        area.name = "Renamed"
        area.context = home
        CadenceTaskMutationSupport.reassignInheritedContext(in: area.tasks ?? [], area: area)
        #expect(direct.context?.id == home.id)
        #expect(cascaded.context?.id == home.id, "the cascade did not reach the child project")

        undo.restore()

        #expect(area.name == "Filed")
        #expect(area.context?.id == work.id)
        #expect(direct.context?.id == work.id)
        #expect(
            cascaded.context?.id == work.id,
            "the iOS editor's undo set left a child project's tasks in the context the refused save did not land"
        )
    }
}
