import SwiftUI
import Testing
@testable import Cadence

/// **[[T-13261]].** A calendar switched off in Settings > Calendar said so differently on each
/// platform: both rows muted the calendar's title, and the phone's row also faded itself whole to
/// 0.68 -- the colour dot, the link menu and the Active switch with it -- where the Mac kept them at
/// full strength. No hardware or input constraint separates the two ([[T-8201]]), and the fade greyed
/// the one control that turns the calendar back on. Both rows now take the title ink from
/// `CadenceCalendarSettingsRowStyle` and dim nothing else.
///
/// A view cannot be rendered here, so the decision is pinned directly and each platform's row is
/// read from source for its use of it.
@MainActor
struct CadenceCalendarSettingsInactiveRowTests {

    private static func body(_ declaration: String, in file: String) throws -> String {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(file))
        return try #require(CadenceSourceScan.declarationBody(declaration, in: source),
                            "\(file) no longer declares \(declaration)")
    }

    private static func squeezed(_ text: String) -> String { String(text.filter { !$0.isWhitespace }) }

    private static let rows: [(file: String, declaration: String)] = [
        ("Cadence/iOS/iOSCalendarSettingsSection.swift", "struct iOSCalendarSettingsRow: View"),
        ("Cadence/macOS/Views/SettingsListManagementSections.swift", "struct SettingsCalendarRow: View"),
    ]

    @Test func aSwitchedOffCalendarsTitleIsMutedAndAnActiveOneIsNot() {
        #expect(CadenceCalendarSettingsRowStyle.titleInk(isActive: false) == Theme.muted)
        #expect(CadenceCalendarSettingsRowStyle.titleInk(isActive: true) == Theme.text)
    }

    /// Both rows read the shared ink for the title, so the one signal cannot part again.
    @Test func bothCalendarRowsTakeTheSharedTitleInk() throws {
        for row in Self.rows {
            let body = Self.squeezed(try Self.body(row.declaration, in: row.file))
            #expect(body.contains("CadenceCalendarSettingsRowStyle.titleInk(isActive:isActive)"),
                    "\(row.declaration) no longer takes the shared switched-off title ink")
        }
    }

    /// The half that drifted: neither row fades itself, or anything on it, by whether the calendar
    /// is on -- the Active switch has to read as a live control in both states.
    @Test func neitherCalendarRowFadesItselfWhenSwitchedOff() throws {
        var scanned = 0
        for row in Self.rows {
            let body = Self.squeezed(try Self.body(row.declaration, in: row.file))
            scanned += body.contains("Toggle(\"Active\"") ? 1 : 0
            #expect(!body.contains(".opacity(isActive"),
                    "\(row.declaration) fades by isActive again, greying its Active switch")
        }
        #expect(scanned == Self.rows.count, "non-vacuity: \(scanned) of \(Self.rows.count) rows still draw the Active switch")
    }
}
