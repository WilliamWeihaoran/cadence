import Foundation
import Testing
@testable import Cadence

/// **[[T-18062]] -- a task row dragged over a group heading draws a drop-target state, on all four
/// headings that take a row, and on no heading that refuses one.**
///
/// The four were each a bare `.dropDestination(for: String.self)` with no `isTargeted:`, so the
/// one drop target that re-files a task never said "here". They all go through
/// `CadenceTaskHeadingRowDrop` now, which owns the `isTargeted:` write-back and the line it draws,
/// and registers nothing when its handler is `nil` (T-591). The look itself is a sighting; this
/// pins the wiring that makes the look possible and keeps the four from drifting apart.
struct CadenceTaskHeadingRowDropTests {
    private static let modifierPath = "Cadence/Shared/Components/CadenceTaskHeadingRowDrop.swift"

    /// (file, declaration, the handler the site must hand over, the tint it must hand over)
    private static let sites: [(file: String, declaration: String, handler: String, tint: String)] = [
        ("Cadence/macOS/Views/TasksListView.swift", "struct TasksListSectionView: View",
         "onDrop: onDropOnSectionPayload", "tint: section.tint"),
        ("Cadence/macOS/Views/TasksPanelSectionViews.swift", "struct TasksPanelIntentSectionView: View",
         "onDrop: onDropOnSectionPayload", "tint: tint"),
        ("Cadence/macOS/Views/ListDetailSupportViews.swift", "struct ListTasksGroupSectionView: View",
         "onDrop: headingRowDrop", "tint: group.tint"),
        ("Cadence/iOS/iOSTaskGroupSection.swift", "struct iOSTaskGroupHeader: View",
         "onDrop: onDropTaskPayload", "tint: color"),
    ]

    /// The shared modifier passes `isTargeted:` and draws only while targeted, and only inside the
    /// branch that registered a destination: a `nil` handler is the bare content.
    @Test func theSharedHeadingDropWritesBackItsTargetStateOnlyWhenItRegisters() throws {
        let source = try CadenceCommitSurfaceScan.scanned(Self.modifierPath)
        let body = try #require(
            CadenceSourceScan.declarationBody("func body(content: Content) -> some View", in: source),
            "the modifier has no body"
        )
        let gate = try #require(body.range(of: "if let onDrop {"), "the destination is registered unconditionally")
        let drop = try #require(body.range(of: ".dropDestination(for: String.self)"), "the modifier registers no drop")
        let targeted = try #require(body.range(of: "isTargeted: { isTargeted = $0 }"), "the drop writes back no target state")
        let otherwise = try #require(body.range(of: "} else {"), "a nil handler has no branch of its own")
        #expect(gate.upperBound < drop.lowerBound && drop.lowerBound < targeted.lowerBound)
        #expect(targeted.upperBound < otherwise.lowerBound, "the target state is written outside the registering branch")

        let refusing = String(body[otherwise.upperBound...])
        #expect(refusing.filter { !$0.isWhitespace }.hasPrefix("content}"),
                "a heading that refuses a row draws something: \(refusing)")
        #expect(!refusing.contains(".overlay") && !refusing.contains(".dropDestination"),
                "a heading that refuses a row registers or draws: \(refusing)")

        let registering = body[gate.upperBound..<otherwise.lowerBound]
        #expect(registering.contains("if isTargeted {"), "the line is drawn whether or not a row hovers")
        #expect(registering.contains(".fill(tint)"), "the line is not in the group's tint")
    }

    /// Each of the four headings that take a row reaches the shared drop -- and so passes
    /// `isTargeted:` -- with its own optional handler and tint, and keeps no bare destination.
    @Test func eachOfTheFourHeadingDestinationsPassesIsTargetedThroughTheSharedDrop() throws {
        for site in Self.sites {
            let source = try CadenceCommitSurfaceScan.scanned(site.file)
            let declaration = try #require(
                CadenceSourceScan.declarationBody(site.declaration, in: source),
                "\(site.declaration) is gone from \(site.file)"
            )
            #expect(declaration.contains("var body: some View"), "non-vacuity: \(site.declaration)")
            #expect(declaration.components(separatedBy: ".cadenceTaskHeadingRowDrop(").count - 1 == 1,
                    "\(site.declaration) does not draw the shared heading drop exactly once")
            #expect(!declaration.contains(".dropDestination("),
                    "\(site.declaration) keeps a heading drop that draws no target state")
            #expect(declaration.contains(site.handler), "\(site.declaration) hands over another handler")
            #expect(declaration.contains(site.tint), "\(site.declaration) draws in another colour")
        }
    }

    /// The list Tasks tab's handler is `nil` on a heading that files no row, the question iOS's
    /// tab already asks -- so Overdue, Due Today and the ungrouped "Tasks" draw nothing.
    @Test func theMacListTabsHeadingRegistersOnlyWhereItTakesARow() throws {
        let source = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Views/ListDetailSupportViews.swift")
        let body = try CadenceCommitSurfaceScan.declarationBody(named: "headingRowDrop", in: source)
        #expect(body.contains("guard ListTasksGroupDrop.takesDroppedRow(group) else { return nil }"))
        #expect(body.contains("return onReorderTask(droppedID, targetID)"))
        #expect(body.contains("return onRefileTask(droppedID, refiling)"))
    }
}
