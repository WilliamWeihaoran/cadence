import Foundation
import Testing
@testable import Cadence

/// **[[T-12191]] — every iOS task group folds from its heading, as every Mac group does.**
///
/// T-11214 decided the fold for both platforms: every group folds. The Mac already did; iOS folded
/// only Completed. The reading of the fold state is the shared `CadenceTaskGroupFold`, exercised
/// here directly; the iOS views are `#if os(iOS)` and this target runs on macOS, so their wiring
/// is pinned from source — the same way `CadenceTodayUnificationTests` pins the Completed fold.
struct CadenceTaskGroupFoldTests {
    // MARK: - The set's reading

    @Test func aPageStartsWithEveryGroupOpen() {
        let collapsed: Set<String> = []
        #expect(CadenceTaskGroupFold.isExpanded("today-list-inbox", in: collapsed))
        #expect(CadenceTaskGroupFold.isExpanded("Tasks", in: collapsed))
    }

    @Test func foldingOneGroupLeavesItsNeighboursOpen() {
        var collapsed: Set<String> = []
        CadenceTaskGroupFold.setExpanded(false, "a", in: &collapsed)
        #expect(collapsed == ["a"])
        #expect(!CadenceTaskGroupFold.isExpanded("a", in: collapsed))
        #expect(CadenceTaskGroupFold.isExpanded("b", in: collapsed))

        // Idempotent both ways: a second fold is still one entry, an unfold of an open group
        // changes nothing.
        CadenceTaskGroupFold.setExpanded(false, "a", in: &collapsed)
        CadenceTaskGroupFold.setExpanded(true, "b", in: &collapsed)
        #expect(collapsed == ["a"])

        CadenceTaskGroupFold.setExpanded(true, "a", in: &collapsed)
        #expect(collapsed.isEmpty)
        #expect(CadenceTaskGroupFold.isExpanded("a", in: collapsed))
    }

    // MARK: - The iOS component

    private func code(_ path: String) throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }

    @Test func theTouchTaskGroupFoldsFromItsHeadingAndHidesItsRowsWhenFolded() throws {
        let file = try code("Cadence/iOS/iOSTaskGroupSection.swift")
        let section = try #require(CadenceSourceScan.declarationBody("struct iOSTaskGroupSection: View", in: file))
        // Required, not defaulted: a surface that drew a group which cannot fold would not compile.
        #expect(section.contains("@Binding var collapsedGroupIDs: Set<String>\n"), "the group no longer takes its page's fold set")
        #expect(!section.contains("collapsedGroupIDs: Set<String> ="), "the fold set has a default again")
        #expect(section.contains("CadenceTaskGroupFold.isExpanded(key, in: collapsed.wrappedValue)"))
        #expect(section.contains("CadenceTaskGroupFold.setExpanded($0, key, in: &collapsed.wrappedValue)"))
        #expect(section.contains("isExpanded: isExpanded"), "the heading is no longer handed the group's fold")
        #expect(
            section.contains("if !tasks.isEmpty && isExpanded.wrappedValue {"),
            "a folded group still draws its rows"
        )

        // The heading draws the shared disclosure when it has a fold, and keeps the drop target
        // on the whole header either way.
        let header = try #require(CadenceSourceScan.declarationBody("struct iOSTaskGroupHeader: View", in: file))
        let branch = try #require(header.range(of: "if let isExpanded {"))
        let disclosure = try #require(header.range(of: "iOSTaskGroupDisclosure("), "the heading no longer folds")
        let plain = try #require(header.range(of: "} else {"))
        #expect(branch.lowerBound < disclosure.lowerBound && disclosure.lowerBound < plain.lowerBound)
        #expect(header.contains(".iOSNewTaskDropTarget(group: dropIdentity)"), "the header lost its drop target")

        // One fold control for every group and for Completed.
        let completed = try #require(CadenceSourceScan.declarationBody("struct iOSCompletedTasksSection: View", in: file))
        #expect(completed.contains("iOSTaskGroupDisclosure("))
        #expect(!completed.contains("Image(systemName:"), "the Completed section draws its own chevron again")
    }

    /// The set is each page's own `@State`, unpersisted, as the Mac keeps it — not an
    /// `@AppStorage` key, which would sync a fold across devices that the Mac never did.
    @Test func eachTouchHostOwnsAnUnpersistedFoldSet() throws {
        let declaration = "@State private var collapsedGroupIDs: Set<String> = []"
        for path in [
            "Cadence/iOS/iOSTaskCollectionPage.swift",
            "Cadence/iOS/iOSListDetailView.swift",
            "Cadence/iOS/iOSTodayView.swift",
        ] {
            let source = try code(path)
            #expect(source.components(separatedBy: declaration).count - 1 == 1, "\(path) does not own one fold set")
            #expect(!source.contains("@AppStorage(CadencePreferenceKeys.iosCollapsed"), "\(path) persists the fold")
        }

        // Every group is handed its page's set, and every grouped call site keys its group by the
        // group's own id, which is unique per page; the single ungrouped section folds under its
        // title. The collection page also hands the set down to `iOSTaskCollectionSections`.
        let sites: [(path: String, sections: Int, bindings: Int, keyed: Int)] = [
            ("Cadence/iOS/iOSTaskCollectionPage.swift", 2, 3, 1),
            ("Cadence/iOS/iOSListDetailView.swift", 1, 1, 1),
            ("Cadence/iOS/iOSTodayTaskSections.swift", 1, 1, 1),
        ]
        for site in sites {
            let source = try code(site.path)
            func count(_ needle: String) -> Int { source.components(separatedBy: needle).count - 1 }
            #expect(count("iOSTaskGroupSection(") == site.sections, "non-vacuity: \(site.path)")
            #expect(count("collapsedGroupIDs: $collapsedGroupIDs") == site.bindings,
                    "\(site.path): a group is drawn without its page's fold set")
            #expect(count("groupID: group.id") == site.keyed, "\(site.path)")
        }
    }

    /// `iOSCompactTodayHost` is an `Equatable` view that skips its body when `==` holds. A fold
    /// it did not compare would be a tap that changed the set and redrew nothing.
    @Test func thePhoneTodayHostRedrawsWhenAGroupFolds() throws {
        let today = try code("Cadence/iOS/iOSTodayView.swift")
        let host = try #require(CadenceSourceScan.declarationBody("struct iOSCompactTodayHost: View, Equatable", in: today))
        #expect(host.contains("let collapsedGroupIDsValue: Set<String>"))
        #expect(
            host.contains("&& lhs.collapsedGroupIDsValue == rhs.collapsedGroupIDsValue"),
            "the phone's Today skips its redraw when a group folds"
        )
    }
}
