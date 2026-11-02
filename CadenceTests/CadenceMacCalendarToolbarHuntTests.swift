#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// Two visible macOS Calendar toolbar defects from one source hunt (agent `hunt0808mac`,
/// [[T-9960]]'s range). Each test names the one file it reads; none sweeps a directory.
/// Not seen on screen: the sighting is [[T-9965]].
@Suite struct CadenceMacCalendarToolbarHuntTests {
    private static func code(_ path: String) throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }

    private static let calendarToolbarPath = "Cadence/macOS/Views/CalendarPageSupportViews.swift"

    /// [[T-9961]]: the Calendar toolbar's zoom readout is the Today timeline header's "2×", from
    /// one helper, not its own "2x".
    @Test func theCalendarZoomReadoutSpellsTheTimelineHeadersMultiplicationSign() throws {
        #expect(TimelineZoomControl.levelLabel(2) == "2×")
        #expect(!TimelineZoomControl.levelLabel(3).contains("x"), "the readout is spelled with a letter x")

        let source = try Self.code(Self.calendarToolbarPath)
        let zoom = try #require(CadenceSourceScan.declarationBody(
            "private struct CalendarToolbarZoomControl: View", in: source
        ))
        #expect(zoom.contains("Text(TimelineZoomControl.levelLabel(zoomLevel))"),
                "the Calendar zoom readout does not read the shared label")
        #expect(!zoom.contains("x\")"), "the Calendar zoom readout spells its own \"x\" again")

        let today = try #require(CadenceSourceScan.declarationBody(
            "struct TimelineZoomControl: View",
            in: try Self.code("Cadence/macOS/Services/SchedulingService.swift")
        ))
        #expect(today.contains("Text(Self.levelLabel(zoomLevel))"),
                "the Today header's zoom readout does not read the shared label")
    }

    /// [[T-9962]]: every group in the Calendar toolbar is the compact control height, so the
    /// Week / Month / Board segments no longer stand 6pt taller than the zoom and Board-arrow
    /// groups and the Today button beside them.
    @Test func everyCalendarToolbarGroupIsTheCompactControlHeight() throws {
        // The relation the fix rests on: a segment inside the group inset is one compact control.
        #expect(CalendarToolbarMetrics.segmentHeight + 2 * CalendarToolbarMetrics.groupInset
                == CadenceDesktopMetrics.compactControlHeight)
        #expect(CalendarToolbarMetrics.segmentHeight < CadenceDesktopMetrics.compactControlHeight,
                "non-vacuity: the segment is the full control height again")

        let source = try Self.code(Self.calendarToolbarPath)
        let modes = try #require(CadenceSourceScan.declarationBody(
            "private struct CalendarViewModeControl: View", in: source
        ))
        #expect(modes.components(separatedBy: "minHeight: CalendarToolbarMetrics.segmentHeight").count - 1 == 2,
                "the mode and Board segments are not both at the shared segment height")
        #expect(!modes.contains("minHeight: CadenceDesktopMetrics.compactControlHeight"),
                "a segment is back at the full control height inside the group's inset")
        #expect(modes.contains(".padding(CalendarToolbarMetrics.groupInset)"))

        for name in ["private struct CalendarToolbarZoomControl: View",
                     "private struct CalendarBoardWindowNavigationControl: View"] {
            let group = try #require(CadenceSourceScan.declarationBody(name, in: source))
            #expect(group.contains(".padding(.vertical, CalendarToolbarMetrics.groupInset)"),
                    "\(name) does not sit in the shared group inset")
        }
        let ghost = try #require(CadenceSourceScan.declarationBody(
            "private struct CalendarIconGhostButton: View", in: source
        ))
        #expect(ghost.contains("size: CalendarToolbarMetrics.segmentHeight"),
                "the toolbar's icon buttons are not the shared segment height")
    }
}
#endif
