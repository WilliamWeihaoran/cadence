import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-446.** Four surfaces ask "which context?" and each used to answer "which contexts, in what
/// order, called what" for itself. T-288 correctly refused to merge the *views* — macOS's picker is
/// keyboard-first and the three iOS sites are touch popovers — and left the list underneath
/// duplicated. This suite is the pin on the list.
///
/// The behaviour half comes first because the four spellings had **diverged**, and every divergence
/// below is a case one platform got wrong rather than a distinction either meant:
///
/// - an archived context stayed offerable on three of the four,
/// - the one that filtered read its button label out of the filtered array and its saved value out
///   of the unfiltered one, so it displayed "None" over a context it then saved,
/// - equal `order` values resolved by name on macOS and by nothing in particular on iOS,
/// - an unnamed context read "Untitled Context" on one surface and blank on the other three.
///
/// The source half is the other standing requirement: a consolidation test that still passes when a
/// call site is reverted has pinned nothing. `noContextPickerDerivesItsOwnList` goes red on a call
/// site that goes back to sorting or filtering for itself, and
/// `everyContextPickerReadsTheSharedList` goes red on one that stops reading the shared list at all
/// — which is the failure a pure absence check cannot see.
@MainActor
struct CadenceContextPickerConsolidationTests {

    private struct Fixture {
        let modelContext: ModelContext
        let contexts: [Context]
        let archived: Context
        let unnamed: Context
    }

    /// Three named contexts that all carry `order == 0` — the shape that tells a tie-break apart
    /// from a stable sort, and the shape the store actually holds, because `Context.order` defaults
    /// to `0` and only the reorder UI ever writes it.
    private func makeFixture() throws -> Fixture {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())

        let zebra = Context(name: "Zebra")
        let apple = Context(name: "apple")
        let archived = Context(name: "Retired")
        archived.isArchived = true
        let unnamed = Context(name: "   ")

        for context in [zebra, apple, archived, unnamed] {
            modelContext.insert(context)
        }

        return Fixture(
            modelContext: modelContext,
            contexts: [zebra, apple, archived, unnamed],
            archived: archived,
            unnamed: unnamed
        )
    }

    // MARK: - The list

    /// The tie-break, which is the whole of the sort that iOS did not have.
    ///
    /// `@Query(sort: \Context.order)` is a sort on `order` alone; among equal keys SwiftData
    /// promises nothing. With every context at `order == 0` that is the entire list.
    @Test func contextsWithTheSameOrderAreBrokenApartByNameCaseInsensitively() throws {
        let fixture = try makeFixture()

        // The unnamed one is dropped here rather than asserted on: where whitespace falls against
        // letters is a collation detail, and `anUnnamedContextIsCalledUntitledInEveryPicker` is
        // where the unnamed case is actually pinned.
        let sorted = CadenceContextPickerSupport.sorted(fixture.contexts)
            .filter { $0.id != fixture.unnamed.id }
            .map(\.name)

        #expect(sorted == ["apple", "Retired", "Zebra"])

        // And `order` still outranks the name it falls back to.
        fixture.contexts[0].order = -1
        #expect(CadenceContextPickerSupport.sorted(fixture.contexts).first?.name == "Zebra")
    }

    /// Archiving retires a context from future choices. Three of the four pickers never learned it.
    @Test func anArchivedContextIsNotOfferedAsAFreshChoice() throws {
        let fixture = try makeFixture()

        let offered = CadenceContextPickerSupport.items(
            from: fixture.contexts,
            selectedID: nil,
            noneTitle: "No context"
        )

        #expect(!offered.contains { $0.id == fixture.archived.id })
        // The none row plus the three unarchived contexts.
        #expect(offered.count == 4)
    }

    /// The other half of the archive rule, and the bug it was hiding: the context already assigned
    /// stays in the list and stays named, however archived it is.
    ///
    /// Without this, `iOSListEditorSheet` shows "None" on a project whose context was archived
    /// while `save()` — which resolves against the unfiltered query — writes the archived context
    /// back. A picker that cannot display its own current value reports the wrong state.
    @Test func theArchivedContextThatIsAlreadyAssignedStaysVisibleAndNamed() throws {
        let fixture = try makeFixture()

        let offered = CadenceContextPickerSupport.items(
            from: fixture.contexts,
            selectedID: fixture.archived.id,
            noneTitle: "No context"
        )

        #expect(offered.contains { $0.id == fixture.archived.id })
        #expect(
            CadenceContextPickerSupport.selectionTitle(
                from: fixture.contexts,
                selectedID: fixture.archived.id,
                noneTitle: "No context"
            ) == "Retired"
        )
    }

    /// One word for an unnamed context, where there were two — "Untitled Context" on the iOS list
    /// editor and a blank row everywhere else. Whitespace counts as unnamed; the fixture's is
    /// three spaces, which the old `name.isEmpty` test called a name.
    @Test func anUnnamedContextIsCalledUntitledInEveryPicker() throws {
        let fixture = try makeFixture()

        let items = CadenceContextPickerSupport.items(
            from: fixture.contexts,
            selectedID: nil,
            noneTitle: nil
        )

        #expect(items.first { $0.id == fixture.unnamed.id }?.title == CadenceContextPickerSupport.untitledName)
        #expect(
            CadenceContextPickerSupport.selectionTitle(
                from: fixture.contexts,
                selectedID: fixture.unnamed.id,
                noneTitle: "No context"
            ) == "Untitled Context"
        )
    }

    /// The "none" row leads, and its **word** is the call site's: "No context", "None", "Use Parent
    /// Context" and "Use Goal Context" report four different things and are the part that stayed
    /// per-site. A picker that does not offer it passes `nil` and gets no row.
    @Test func theNoneRowLeadsAndKeepsTheCallSitesOwnWord() throws {
        let fixture = try makeFixture()

        let withNone = CadenceContextPickerSupport.items(
            from: fixture.contexts,
            selectedID: nil,
            noneTitle: "Use Goal Context"
        )
        #expect(withNone.first?.isNone == true)
        #expect(withNone.first?.title == "Use Goal Context")
        #expect(withNone.filter(\.isNone).count == 1)

        let withoutNone = CadenceContextPickerSupport.items(
            from: fixture.contexts,
            selectedID: nil,
            noneTitle: nil
        )
        #expect(!withoutNone.contains { $0.isNone })

        // Nothing selected reads as the none row, by its caller's word.
        #expect(
            CadenceContextPickerSupport.selectionTitle(
                from: fixture.contexts,
                selectedID: nil,
                noneTitle: "Use Goal Context"
            ) == "Use Goal Context"
        )
    }

    /// macOS's search field, which is the only presentation that passes a query. An empty or
    /// whitespace-only one is not a filter.
    @Test func theSearchQueryMatchesCaseInsensitivelyAndIgnoresSurroundingSpace() throws {
        let fixture = try makeFixture()

        func titles(_ query: String) -> [String] {
            CadenceContextPickerSupport.items(
                from: fixture.contexts,
                selectedID: nil,
                query: query,
                noneTitle: nil
            ).map(\.title)
        }

        #expect(titles("  APP  ") == ["apple"])
        #expect(titles("apple") == ["apple"])
        #expect(titles("   ").count == 3)
        #expect(titles("").count == 3)
        #expect(titles("nothing here").isEmpty)
    }

    // MARK: - The call sites

    /// Every file that presents a context picker, plus the two that hold the list it reads.
    ///
    /// **T-488 moved the rules out of `CadenceContextPickerSupport.swift`.** They are generic now
    /// — `CadencePickerSupport`, shared with the area picker — and that file keeps only `Context`'s
    /// own two facts behind a typealias. So the sweep below, whose needle is a *context* array
    /// being sorted or filtered, now expects no hits at all rather than one: the single remaining
    /// derivation is written over `elements`, not `contexts`, and no longer answers to it.
    private static let pickerSources = [
        "Cadence/Shared/CadencePickerSupport.swift",
        "Cadence/Shared/CadenceContextPickerSupport.swift",
        "Cadence/macOS/Views/CadenceContextPicker.swift",
        "Cadence/iOS/iOSListEditorViews.swift",
        "Cadence/iOS/iOSTrackingEditorSheets.swift"
    ]

    private static let callSites = [
        "Cadence/macOS/Views/CadenceContextPicker.swift",
        "Cadence/iOS/iOSListEditorViews.swift",
        "Cadence/iOS/iOSTrackingEditorSheets.swift"
    ]

    private func readCodeOnly(_ path: String) throws -> String {
        CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
    }

    /// **One file derives the list.** A picker that goes back to sorting, filtering or mapping a
    /// context array for itself is a hit here, and only the support type is allowed to be one.
    ///
    /// This is the assertion that survives a revert: the behaviour tests above stay green on a tree
    /// where `CadenceContextPickerSupport` is correct and nothing reads it.
    @Test func noContextPickerDerivesItsOwnList() throws {
        let derives = try CadenceScanInstrument(
            "context list derived at the call site",
            fires: "private var rows: [Row] { contexts.map { Row($0.name) } }",
            andNotOn: "private var rows: [Row] { CadenceContextPickerSupport.items(from: contexts, selectedID: nil, noneTitle: nil).map(Row.init) }",
            by: { source in
                CadenceSourceScan.matchCount(
                    "[A-Za-z]*[Cc]ontexts\\s*\\.\\s*(sorted|filter|map)\\s*[({]",
                    in: source
                ) > 0
            }
        )

        let hits = try derives.sweep(
            Self.pickerSources,
            atLeast: 5,
            including: "Cadence/iOS/iOSTrackingEditorSheets.swift",
            read: readCodeOnly
        )

        // Was `["Cadence/Shared/CadenceContextPickerSupport.swift"]`; see `pickerSources`. The
        // claim is strictly stronger than it was, and the instrument plus `atLeast:` are what keep
        // an empty result from being the shape a broken detector or an unread walk also produces.
        #expect(hits.isEmpty)
    }

    /// **And all three presentations read it.** Absence of a private sort is not presence of the
    /// shared one: a call site that dropped the picker entirely would pass the test above.
    ///
    /// The needle is the three list-reading entry points, not the bare type name, so referring to
    /// `CadenceContextPickerSupport.Item` in a signature does not count as reading the list.
    @Test func everyContextPickerReadsTheSharedList() throws {
        let reads = try CadenceScanInstrument(
            "call site reads the shared context list",
            fires: "rows: CadenceContextPickerSupport.items(from: contexts, selectedID: nil, noneTitle: nil)",
            andNotOn: "func row(_ item: CadenceContextPickerSupport.Item) -> some View { EmptyView() }",
            by: { source in
                CadenceSourceScan.matchCount(
                    "CadenceContextPickerSupport\\.(items|selectedItem|selectionTitle)\\(",
                    in: source
                ) > 0
            }
        )

        let hits = try reads.sweep(
            Self.callSites,
            atLeast: 3,
            including: "Cadence/iOS/iOSListEditorViews.swift",
            read: readCodeOnly
        )

        #expect(hits == Self.callSites.sorted())
    }

    /// The scan is reading code, not prose. `codeOnly` blanks comments and string literals to
    /// spaces of equal length, so the stripped source differs from the raw one without shrinking.
    @Test func theContextPickerScanReadsStrippedSourceOfTheSameLength() throws {
        for path in Self.pickerSources {
            let raw = try CadenceSourceScan.sourceFile(path)
            let code = CadenceSourceScan.codeOnly(raw)
            #expect(code != raw, "\(path) stripped to itself")
            #expect(code.count == raw.count, "\(path) changed length when stripped")
        }
    }
}
