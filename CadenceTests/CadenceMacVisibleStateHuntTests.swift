import Foundation
import Testing
@testable import Cadence

/// Three visible macOS defects from one source hunt (agent `hunt1837mac`, [[T-9820]]'s range).
@Suite struct CadenceMacVisibleStateHuntTests {
    private static func code(_ path: String) throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }

    /// [[T-9821]]: an Apple Reminder row in the Mac Inbox hovers exactly as the task rows around
    /// it do -- `TaskHoverVisuals`' neutral wash and rim at `Theme.radiusCard` -- instead of a
    /// purple 8pt wash and rim of its own.
    @Test func theInboxReminderRowHoversLikeATaskRow() throws {
        let source = try Self.code("Cadence/macOS/Views/InboxSupportViews.swift")
        let row = try #require(CadenceSourceScan.declarationBody(
            "private struct AppleReminderTaskRow: View", in: source
        ))
        #expect(row.contains(".fill(TaskHoverVisuals.hoverFill(isHovered: isHovered))"),
                "the reminder row's hover wash is not the task row's")
        #expect(row.contains(".strokeBorder(TaskHoverVisuals.borderColor(isHovered: isHovered), lineWidth: 1)"),
                "the reminder row's hover rim is not the task row's")
        #expect(row.components(separatedBy: "RoundedRectangle(cornerRadius: Theme.radiusCard)").count - 1 == 2,
                "the reminder row's hover is not drawn at the task row's radius")
        // The defect by name: a hue chosen by hover, at a radius no neighbouring row uses.
        #expect(!row.contains("isHovered ? Theme."), "the reminder row paints a hover hue of its own again")
        #expect(!row.contains("RoundedRectangle(cornerRadius: 8)"), "the reminder row's hover is back at 8pt")
    }

    /// [[T-9822]]: a Settings action button fades itself when it cannot be pressed.
    @Test func aDisabledSettingsActionButtonFades() {
        #expect(SettingsActionButtonMetrics.opacity(isEnabled: true) == 1)
        #expect(SettingsActionButtonMetrics.opacity(isEnabled: false) == SettingsActionButtonMetrics.disabledOpacity)
        #expect(SettingsActionButtonMetrics.opacity(isEnabled: false) < SettingsActionButtonMetrics.opacity(isEnabled: true))
    }

    /// [[T-9822]]'s wiring: the fade is read from the environment `.disabled` sets, so "Refresh"
    /// and "Check iCloud Status" fade while their fetch runs, and no caller re-spells the fade (which
    /// would now fade it twice).
    @Test func theSettingsActionButtonOwnsItsDisabledFade() throws {
        let support = try Self.code("Cadence/macOS/Views/SettingsActionSupportViews.swift")
        let button = try #require(CadenceSourceScan.declarationBody(
            "struct SettingsActionButton<Label: View>: View", in: support
        ))
        #expect(button.contains("@Environment(\\.isEnabled) private var isEnabled"))
        #expect(button.contains(".opacity(SettingsActionButtonMetrics.opacity(isEnabled: isEnabled))"))

        var disabledSites = 0
        var doubleFades: [String] = []
        // The four files whose Settings action buttons take `.disabled`, named rather than swept.
        for path in [
            "Cadence/macOS/Views/SettingsRemindersSection.swift",
            "Cadence/macOS/Views/SettingsSyncSection.swift",
            "Cadence/macOS/Views/SettingsTagsSection.swift",
            "Cadence/macOS/Views/SettingsTemplatesSection.swift",
        ] {
            let lines = try Self.code(path).components(separatedBy: "\n")
            for (index, line) in lines.enumerated()
            where line.trimmingCharacters(in: .whitespaces).hasPrefix(".disabled(") {
                disabledSites += 1
                guard index + 1 < lines.count else { continue }
                if lines[index + 1].trimmingCharacters(in: .whitespaces).hasPrefix(".opacity(") {
                    doubleFades.append("\(path):\(index + 2)")
                }
            }
        }
        // Refresh, Check iCloud Status, Create Tag, Save, Reset Template, and the template editor.
        #expect(disabledSites == 6, "non-vacuity: found \(disabledSites) `.disabled(` sites, expected 6")
        #expect(doubleFades.isEmpty, "a Settings caller fades a disabled button by hand: \(doubleFades)")
    }

    /// [[T-9823]]: the `~` list picker says "No matching lists" when a query matches nothing, in the
    /// shared sentence, as the context and calendar pickers say "No matching ...".
    @Test func theTildePickerNamesWhatMatchedNothing() throws {
        let source = try Self.code("Cadence/macOS/Views/TildeContainerPicker.swift")
        #expect(source.contains("Text(CadenceEmptyStateCopy.listsTitle(isNarrowed: true))"))
        #expect(!source.contains("Text(\"No results\")"), "the `~` picker says \"No results\" again")
        #expect(CadenceEmptyStateCopy.listsTitle(isNarrowed: true) == "No matching lists")
    }
}
