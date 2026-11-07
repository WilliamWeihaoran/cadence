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
        // [[T-12322]]: a list's Archive row is NOT destructive (the Mac's `ListEditorArchiveButton`
        // ruling, under T-8201), so the Lists page, its regular-width pane and the sidebar row
        // ([[T-11753]]) wear the shared red on none of their rows. Zero, not dropped: a list
        // Archive that regains the red moves these numbers.
        ("Cadence/iOS/iOSListsRegularPane.swift", 0),
        ("Cadence/iOS/iOSListViews.swift", 0),
        ("Cadence/iOS/iOSRootSidebar.swift", 0),
        // [[T-12451]]: Settings' context Archive is not destructive either (the [[T-12322]]
        // ruling), so that file's only row menu wears the shared red on none of its rows -- its
        // Delete is the shared `iOSListDeleteMenuButton`, counted under iOSListDeletionSupport.
        ("Cadence/iOS/iOSSettingsView.swift", 0),
        // Mac note row menus.
        ("Cadence/macOS/Views/ListNotesViewSupportViews.swift", 1),
        ("Cadence/macOS/Views/NotesView.swift", 1),
    ])
    func everyDestructiveRowMenuButtonWearsTheSharedRow(path: String, expected: Int) throws {
        let source = try Self.code(path)
        let applied = source.components(separatedBy: ".cadenceDestructiveMenuRow()").count - 1
        #expect(applied == expected, "\(path): \(applied) destructive menu rows wear the shared tint, expected \(expected)")
    }

    /// **[[T-12451]] -- Settings' context Archive is plain.** Recoverable from the Archived section,
    /// so it takes neither the destructive role (the red title) nor the shared red glyph; Delete,
    /// beside it, still does. Whitespace is dropped so the shape, not the indentation, is read.
    @Test func theSettingsContextArchiveRowIsPlainBesideARedDelete() throws {
        let settings = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSettingsView.swift"))
        let source = String(settings.filter { !$0.isWhitespace })
        #expect(source.contains("Button{archive(context)}label:{Label(\"ArchiveContext\",systemImage:\"archivebox\")}"),
                "non-vacuity: the context row's Archive was not found as a plain Button")
        #expect(!source.contains("Button(role:.destructive){archive(context)}"))
        #expect(source.contains("iOSListDeleteMenuButton(target:.context(context))"),
                "the context row's Delete moved; this test reads the two side by side")
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
