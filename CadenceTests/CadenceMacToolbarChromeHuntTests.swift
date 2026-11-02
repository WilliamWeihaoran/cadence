#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// Visible macOS toolbar-chrome defects from one source hunt (agent `hunt0040mac`, [[T-9960]]'s
/// reservation, ids T-9980..T-9989). Each test names the files it reads; none sweeps a directory.
@Suite struct CadenceMacToolbarChromeHuntTests {
    private static func code(_ path: String) throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }

    /// [[T-9981]]: the task-notes editor's Open and Close buttons are the toolbar's quiet pill,
    /// as the outline button beside them is, not 30pt plates under `.cadencePlain`'s blue wash.
    @Test func theTaskNotesToolbarButtonsAreQuietPills() throws {
        let pane = try #require(CadenceSourceScan.declarationBody(
            "struct TaskNoteEditorPane: View",
            in: try Self.code("Cadence/macOS/Views/ListNotesSupportViews.swift")
        ))
        let open = try #require(pane.range(of: ".cadenceControlLabel(\"Open task notes\")"),
                                "the pane no longer draws its Open task notes button")
        let openButton = try #require(pane.range(of: "CadenceQuietPillButton(", options: .backwards,
                                                 range: pane.startIndex..<open.lowerBound),
                                      "Open task notes is not a quiet pill")
        let openSpan = String(pane[openButton.lowerBound..<open.lowerBound])
        #expect(openSpan.contains("CadenceQuietPillButton(state: .resting"))
        #expect(!openSpan.contains(".buttonStyle(.cadencePlain"), "Open task notes lights the blue wash again")
        #expect(!openSpan.contains("RoundedRectangle("), "Open task notes paints its own plate again")
        // Its sibling in the same toolbar is the reference shape.
        #expect(pane.contains("NoteOutlineJumpButton("))
        let outline = try #require(CadenceSourceScan.declarationBody(
            "struct NoteOutlineJumpButton: View",
            in: try Self.code("Cadence/macOS/Views/NoteEditorAccessoryViews.swift")
        ))
        #expect(outline.contains("CadenceQuietPillButton("), "non-vacuity: the outline button is no longer a quiet pill")

        let sheet = try #require(CadenceSourceScan.declarationBody(
            "struct TaskNotesExpandedEditorSheet: View",
            in: try Self.code("Cadence/macOS/Views/TaskInspectorContentSupportViews.swift")
        ))
        #expect(sheet.contains(".cadenceControlLabel(\"Close\")"), "non-vacuity: the sheet's Close button is gone")
        #expect(sheet.contains("CadenceQuietPillButton(state: .resting"), "Close is not a quiet pill")
        #expect(!sheet.contains(".buttonStyle(.cadencePlain"), "Close lights the blue wash again")
        #expect(!sheet.contains("RoundedRectangle("), "Close paints its own plate again")
    }

    /// [[T-9982]]: the Today timeline header's Export, Zoom out and Zoom in are one button at one
    /// size and one radius.
    @Test func theTimelineHeaderButtonsShareOneSizeAndRadius() throws {
        let service = try Self.code("Cadence/macOS/Services/SchedulingService.swift")
        let zoom = try #require(CadenceSourceScan.declarationBody("struct TimelineZoomControl: View", in: service))
        #expect(zoom.components(separatedBy: "TimelineHeaderIconButton(").count - 1 == 2,
                "the zoom pair is not drawn by the shared header button")
        #expect(!zoom.contains("RoundedRectangle("), "the zoom pair paints its own plates again")
        #expect(!zoom.contains(".frame(width: 24, height: 24)"), "the zoom pair is back at 24pt")

        let shell = try Self.code("Cadence/macOS/Views/SchedulePanelShellViews.swift")
        let export = try #require(shell.range(of: "private var exportButton: some View"),
                                  "non-vacuity: the header has no export button")
        let exportBody = String(shell[export.upperBound...].prefix(400))
        #expect(exportBody.contains("TimelineHeaderIconButton("), "Export is not the shared header button")
        #expect(!exportBody.contains("RoundedRectangle("), "Export paints its own plate again")

        let button = try #require(CadenceSourceScan.declarationBody("struct TimelineHeaderIconButton: View", in: service))
        #expect(button.contains(".frame(width: Self.side, height: Self.side)"))
        #expect(button.contains(".clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))"))
        #expect(button.contains(".buttonStyle(.cadencePlain(cornerRadius: Self.cornerRadius))"),
                "the hover wash is not at the plate's radius")
        #expect(TimelineHeaderIconButton.cornerRadius == CadenceDesktopMetrics.controlCornerRadius)
    }

    /// [[T-9983]]: a zoom button at its limit is disabled, so it neither lights a hover wash nor
    /// takes a press, and its faded glyph is read from that state rather than restated beside it.
    @Test func aZoomButtonAtItsLimitIsDisabledAndFaded() throws {
        let service = try Self.code("Cadence/macOS/Services/SchedulingService.swift")
        let zoom = try #require(CadenceSourceScan.declarationBody("struct TimelineZoomControl: View", in: service))
        #expect(zoom.contains(".disabled(zoomLevel <= range.lowerBound)"), "Zoom out is live at the lowest level")
        #expect(zoom.contains(".disabled(zoomLevel >= range.upperBound)"), "Zoom in is live at the highest level")

        let button = try #require(CadenceSourceScan.declarationBody("struct TimelineHeaderIconButton: View", in: service))
        #expect(button.contains("@Environment(\\.isEnabled)"), "the button does not read whether it is enabled")
        #expect(button.contains("Self.glyphOpacity(isEnabled: isEnabled)"))
        #expect(TimelineHeaderIconButton.glyphOpacity(isEnabled: false) < TimelineHeaderIconButton.glyphOpacity(isEnabled: true))
        #expect(TimelineHeaderIconButton.glyphOpacity(isEnabled: true) == 1)
    }

    /// [[T-9984]]: Settings' Contexts row draws its rename / archive / delete hover buttons at the
    /// Tags row's geometry -- one size, one radius token, one glyph weight.
    @Test func theContextRowActionsMatchTheTagRowActions() throws {
        guard let contexts = CadenceSourceScan.functionBody(
            named: "actionButton",
            in: try Self.code("Cadence/macOS/Views/SettingsSupportViews.swift")
        ) else {
            Issue.record("SettingsSupportViews no longer declares actionButton(…)")
            return
        }
        guard let tags = CadenceSourceScan.functionBody(
            named: "rowButton",
            in: try Self.code("Cadence/macOS/Views/SettingsTagsSection.swift")
        ) else {
            Issue.record("SettingsTagsSection no longer declares rowButton(…)")
            return
        }
        let shared = [
            ".font(.system(size: 11, weight: .semibold))",
            ".frame(width: 28, height: 28)",
            ".clipShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact))",
            ".buttonStyle(.cadencePlain(cornerRadius: Theme.radiusControlCompact))",
        ]
        for needle in shared {
            #expect(tags.contains(needle), "non-vacuity: the Tags row no longer spells \(needle)")
            #expect(contexts.contains(needle), "the Contexts row's actions do not match the Tags row's: \(needle)")
        }
        #expect(!contexts.contains("cornerRadius: 6"), "the Contexts row's actions are back on a literal 6")
    }
}
#endif
