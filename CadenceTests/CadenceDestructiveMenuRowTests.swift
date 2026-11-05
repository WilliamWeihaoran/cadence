#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **[[T-11752]] — a destructive menu row agrees with itself.**
///
/// A saved link's long-press menu drew its Delete row with a red title (the role's) and a blue
/// `trash` (the iOS root's `.tint(Theme.blue)`). The rule is one shared modifier,
/// `cadenceDestructiveMenuRow()`, and every row menu's destructive button wears it on both
/// platforms (T-8201). This pins the modifier's colour and the census of its call sites; it cannot
/// see what UIKit or AppKit actually draws, which is an on-screen check.
@MainActor
struct CadenceDestructiveMenuRowTests {
    private static func code(_ path: String) throws -> String {
        CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
    }

    @Test func theSharedRowTintsItsGlyphWithTheDestructiveRed() throws {
        let source = try Self.code("Cadence/Shared/Components/CadenceDestructiveMenuRow.swift")
        let body = try #require(
            CadenceSourceScan.declarationBody("private struct CadenceDestructiveMenuRow: ViewModifier", in: source)
        )
        #expect(body.contains("content.tint(Theme.red)"))
    }

    /// Each file's destructive row-menu buttons, counted. A COUNT, so a new menu row added without
    /// the modifier, or one that loses it, moves the number.
    @Test(arguments: [
        // The ticket's own row, and the Mac menu it mirrors item for item ([[T-10057]]).
        ("Cadence/iOS/iOSListSupportViews.swift", 1),
        ("Cadence/macOS/Views/LinksView.swift", 1),
        // The shared iOS menu rows every list and note menu reaches.
        ("Cadence/iOS/iOSListDeletionSupport.swift", 1),
        ("Cadence/iOS/iOSNoteDeletionSupport.swift", 1),
        // Task row menus.
        ("Cadence/iOS/iOSTaskRowActionViews.swift", 1),
        ("Cadence/macOS/Views/MacTaskRowContextMenu.swift", 1),
        // Archive rows: role `.destructive`, so the same red title and the same blue glyph.
        ("Cadence/iOS/iOSListsRegularPane.swift", 2),
        ("Cadence/iOS/iOSListViews.swift", 2),
        ("Cadence/iOS/iOSSettingsView.swift", 1),
        // Mac note row menus.
        ("Cadence/macOS/Views/ListNotesViewSupportViews.swift", 1),
        ("Cadence/macOS/Views/NotesView.swift", 1),
    ])
    func everyDestructiveRowMenuButtonWearsTheSharedRow(path: String, expected: Int) throws {
        let source = try Self.code(path)
        let applied = source.components(separatedBy: ".cadenceDestructiveMenuRow()").count - 1
        #expect(applied == expected, "\(path): \(applied) destructive menu rows wear the shared tint, expected \(expected)")
    }

    /// The saved-link menu's Delete specifically -- the row the owner saw -- and not the swipe's,
    /// which draws its own red background.
    @Test func theSavedLinkMenuDeleteRowIsTheOneTinted() throws {
        let source = try Self.code("Cadence/iOS/iOSListSupportViews.swift")
        let menu = try #require(source.range(of: ".contextMenu {"), "the link row lost its menu")
        let tail = source[menu.upperBound...]
        let delete = try #require(tail.range(of: "CadenceSavedLinkRowMenu.deleteSystemImage)"))
        let modifier = try #require(tail.range(of: ".cadenceDestructiveMenuRow()"))
        #expect(delete.upperBound < modifier.lowerBound, "the tint sits before the menu's Delete row")
        let between = tail[delete.upperBound..<modifier.lowerBound]
        #expect(!between.contains("Button"), "another control sits between the Delete row and its tint")
    }
}
#endif
