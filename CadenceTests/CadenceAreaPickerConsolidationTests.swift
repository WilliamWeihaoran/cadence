import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-488.** `iOSListEditorSheet` draws a Context row and, one line down the same `Form`, an Area
/// row. T-446 fixed the Context row: the trigger label had resolved the selected id against the
/// *filtered* list while `save()` resolved it against the unfiltered `@Query`, so a project whose
/// context had been archived displayed "None" and wrote the archived context back. The Area row was
/// left spelling the identical mistake against `areas.filter(\.isActive)`.
///
/// The live consequence: complete or archive an area, then open any project filed under it. The
/// Area row reads **"None"**, and Save writes the inactive area back unchanged — so the sheet can
/// neither tell you where the project is nor let you move it out.
///
/// The behavioural half of this suite is the display/save **agreement**, not the filter: a
/// deactivated-but-assigned area has to show its own name *and* still be the value the popover
/// resolves. A test that only asserted "inactive areas are hidden" would pass on the broken tree.
///
/// The source half is the other standing requirement. `Cadence/iOS/` is behind `#if os(iOS)` and is
/// not compiled by the macOS test target, so a call site that reverts to filtering for itself is
/// invisible to every assertion above — `noAreaPickerDerivesItsOwnList` and
/// `theAreaPickerReadsTheSharedList` are the two that can see it.
@MainActor
struct CadenceAreaPickerConsolidationTests {

    private struct Fixture {
        let modelContext: ModelContext
        let areas: [Area]
        let completed: Area
        let archived: Area
        let unnamed: Area
    }

    /// Areas that all carry `order == 0` — the shape the store actually holds, because
    /// `Area.order` defaults to `0` and only the reorder UI ever writes it — and one area in each
    /// of the two retired states, because `Area` has three and `Context` has two. Copying
    /// `Context`'s `!isArchived` rule across would leave the completed one offerable.
    private func makeFixture() throws -> Fixture {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())

        let zebra = Area(name: "Zebra")
        let apple = Area(name: "apple")
        let completed = Area(name: "Shipped")
        completed.status = .done
        let archived = Area(name: "Retired")
        archived.status = .archived
        let unnamed = Area(name: "   ")

        for area in [zebra, apple, completed, archived, unnamed] {
            modelContext.insert(area)
        }

        return Fixture(
            modelContext: modelContext,
            areas: [zebra, apple, completed, archived, unnamed],
            completed: completed,
            archived: archived,
            unnamed: unnamed
        )
    }

    // MARK: - The list

    /// **The bug, stated as the agreement it broke.** The area the project is already in is named
    /// by the trigger and is present in the list the trigger opens, whichever retired state it is
    /// in — so the label and the value `save()` writes are the same area.
    ///
    /// Both halves are asserted because either alone passes on a broken tree: the old `areaTitle`
    /// showed "None" while `selectedArea` happily resolved the inactive area for `save()`.
    @Test func theInactiveAreaThatIsAlreadyAssignedIsNamedAndStaysInTheList() throws {
        let fixture = try makeFixture()

        for retired in [fixture.completed, fixture.archived] {
            let selected = CadenceAreaPickerSupport.selectedItem(
                from: fixture.areas,
                selectedID: retired.id,
                noneTitle: "None"
            )
            #expect(selected.id == retired.id, "\(retired.name) did not resolve to itself")
            #expect(selected.title == retired.name)

            let offered = CadenceAreaPickerSupport.items(
                from: fixture.areas,
                selectedID: retired.id,
                noneTitle: "None"
            )
            #expect(offered.contains { $0.id == retired.id }, "\(retired.name) was dropped from its own picker")
        }
    }

    /// Completing or archiving an area retires it from *fresh* choices. Both states, because
    /// `Area.isActive` is not `!isArchived` and this is the fact a copy of the context rule gets
    /// wrong.
    @Test func aCompletedOrArchivedAreaIsNotOfferedAsAFreshChoice() throws {
        let fixture = try makeFixture()

        let offered = CadenceAreaPickerSupport.items(
            from: fixture.areas,
            selectedID: nil,
            noneTitle: "None"
        )

        #expect(!offered.contains { $0.id == fixture.completed.id })
        #expect(!offered.contains { $0.id == fixture.archived.id })
        // The none row plus the three areas that are still active.
        #expect(offered.count == 4)
    }

    /// The quieter half of the same disagreement: an unnamed area read "None" in the trigger and
    /// "Untitled Area" in the list it opened, so the row and the popover named it two ways.
    /// Whitespace counts as unnamed; the fixture's name is three spaces, which the old
    /// `name.isEmpty` test called a name.
    @Test func anUnnamedAreaIsCalledUntitledByTheTriggerAndTheListAlike() throws {
        let fixture = try makeFixture()

        let listed = CadenceAreaPickerSupport.items(
            from: fixture.areas,
            selectedID: nil,
            noneTitle: nil
        ).first { $0.id == fixture.unnamed.id }?.title

        #expect(listed == "Untitled Area")
        #expect(
            CadenceAreaPickerSupport.selectionTitle(
                from: fixture.areas,
                selectedID: fixture.unnamed.id,
                noneTitle: "None"
            ) == "Untitled Area"
        )
        #expect(CadenceAreaPickerSupport.untitledName == "Untitled Area")
    }

    /// The tie-break, which is the whole of the sort iOS did not have: `@Query(sort: \Area.order)`
    /// orders on `order` alone, and among equal keys SwiftData promises nothing.
    @Test func areasWithTheSameOrderAreBrokenApartByNameCaseInsensitively() throws {
        let fixture = try makeFixture()

        // The unnamed one is dropped here rather than asserted on: where whitespace falls against
        // letters is a collation detail, and the untitled test above is where it is pinned.
        let sorted = CadenceAreaPickerSupport.sorted(fixture.areas)
            .filter { $0.id != fixture.unnamed.id }
            .map(\.name)

        #expect(sorted == ["apple", "Retired", "Shipped", "Zebra"])

        // And `order` still outranks the name it falls back to.
        fixture.areas[0].order = -1
        #expect(CadenceAreaPickerSupport.sorted(fixture.areas).first?.name == "Zebra")
    }

    // MARK: - The call site

    private static let areaPickerSources = [
        "Cadence/Shared/CadencePickerSupport.swift",
        "Cadence/Shared/CadenceAreaPickerSupport.swift",
        "Cadence/iOS/iOSListEditorViews.swift"
    ]

    private static let ruleSources = [
        "Cadence/Shared/CadencePickerSupport.swift",
        "Cadence/Shared/CadenceAreaPickerSupport.swift",
        "Cadence/Shared/CadenceContextPickerSupport.swift"
    ]

    private func readCodeOnly(_ path: String) throws -> String {
        CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
    }

    /// **No area picker sorts or filters an area array for itself.** This is the assertion that
    /// survives a revert: every behavioural test above stays green on a tree where
    /// `CadenceAreaPickerSupport` is correct and `iOSListEditorSheet` has gone back to
    /// `areas.filter(\.isActive)`.
    ///
    /// `.map` is deliberately not a needle: `nextAreaOrder()` legitimately reads
    /// `areas.map(\.order).max()`, which is allocation, not picking.
    @Test func noAreaPickerDerivesItsOwnList() throws {
        let derives = try CadenceScanInstrument(
            "area list derived at the call site",
            fires: "private var activeAreas: [Area] { areas.filter(\\.isActive) }",
            andNotOn: "private var rows: [Row] { CadenceAreaPickerSupport.items(from: areas, selectedID: nil, noneTitle: nil).map(Row.init) }",
            by: { source in
                CadenceSourceScan.matchCount(
                    "[A-Za-z]*[Aa]reas\\s*\\.\\s*(sorted|filter)\\s*[({]",
                    in: source
                ) > 0
            }
        )

        let hits = try derives.sweep(
            Self.areaPickerSources,
            atLeast: 3,
            including: "Cadence/iOS/iOSListEditorViews.swift",
            read: readCodeOnly
        )

        #expect(hits.isEmpty)
    }

    /// **And the call site reads the shared list.** Absence of a private filter is not presence of
    /// the shared rule: a sheet that dropped the Area row entirely would pass the test above.
    @Test func theAreaPickerReadsTheSharedList() throws {
        let reads = try CadenceScanInstrument(
            "call site reads the shared area list",
            fires: "rows: CadenceAreaPickerSupport.items(from: areas, selectedID: nil, noneTitle: nil)",
            andNotOn: "func row(_ item: CadenceAreaPickerSupport.Item) -> some View { EmptyView() }",
            by: { source in
                CadenceSourceScan.matchCount(
                    "CadenceAreaPickerSupport\\.(items|selectedItem|selectionTitle)\\(",
                    in: source
                ) > 0
            }
        )

        let hits = try reads.sweep(
            ["Cadence/iOS/iOSListEditorViews.swift"],
            atLeast: 1,
            including: "Cadence/iOS/iOSListEditorViews.swift",
            read: readCodeOnly
        )

        #expect(hits == ["Cadence/iOS/iOSListEditorViews.swift"])
    }

    /// **One file states the rules.** The cheap fix for T-488 was a copy of
    /// `CadenceContextPickerSupport` with two words changed — which is the [[T-374]] defect,
    /// committed by the ticket that exists to remove one. Both per-type files are facts and a
    /// typealias; neither declares a sort, a filter or an item list of its own.
    @Test func theAreaPickerSupportIsNotASecondCopyOfTheContextPicker() throws {
        let restates = try CadenceScanInstrument(
            "picker rules restated per type",
            fires: "enum AreaPicker { static func sorted(_ areas: [Area]) -> [Area] { areas } }",
            andNotOn: "typealias AreaPicker = CadencePickerSupport<Area>",
            by: { source in
                CadenceSourceScan.matchCount(
                    "static func (sorted|selectable|matching|items|selectedItem|selectionTitle)\\s*[(<]",
                    in: source
                ) > 0
            }
        )

        let hits = try restates.sweep(
            Self.ruleSources,
            atLeast: 3,
            including: "Cadence/Shared/CadenceAreaPickerSupport.swift",
            read: readCodeOnly
        )

        #expect(hits == ["Cadence/Shared/CadencePickerSupport.swift"])
    }

    /// The scan is reading code, not prose — both of these files describe `areas.filter(\.isActive)`
    /// in their own doc comments, which is exactly what `codeOnly` has to blank. It replaces
    /// comments and string literals with spaces of equal length, so the stripped source differs
    /// from the raw one without shrinking.
    @Test func theAreaPickerScanReadsStrippedSourceOfTheSameLength() throws {
        for path in Set(Self.areaPickerSources + Self.ruleSources).sorted() {
            let raw = try CadenceSourceScan.sourceFile(path)
            let code = CadenceSourceScan.codeOnly(raw)
            #expect(code != raw, "\(path) stripped to itself")
            #expect(code.count == raw.count, "\(path) changed length when stripped")
        }
    }
}
