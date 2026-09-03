import Foundation
import Testing
@testable import Cadence

/// **T-674 addendum (2026-09-04), found by an outside audit while the ticket's ten `Button` sites
/// were in progress.** `CadenceIOSControlAccessibilityTests.unnamedIconButtonCount` keys on the
/// literal `Button` keyword, so a control drawn as a bare `.onTapGesture` is invisible to it — the
/// detector is honest about what it can see, and this shape sits outside it.
///
/// `IconGrid`'s per-glyph cell in `CreateContextSheet.swift` was exactly that: a `ZStack` with an
/// `Image(systemName:)` that mutated `selected` from `.onTapGesture`. No `Button`, no accessible
/// name, no accessibility trait, no accessibility action — reachable in Release from ordinary
/// context creation or editing.
///
/// **Banned outright rather than ledgered.** `knownUnnamedIconButtonSites` tracks fixes in
/// progress across many sites; this shape measured to exactly **one** occurrence in the whole
/// tree (see the window comment on `iconOnlyTapGestureCount` below), and the fix removed it
/// outright, so there is nothing to carry in a list. The next one fails this test instead of
/// joining one.
struct CadenceIconOnlyTapGestureAccessibilityTests {

    private func detector() throws -> CadenceScanInstrument {
        try CadenceScanInstrument(
            "icon-only .onTapGesture with no enclosing control",
            fires: """
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected == icon ? Theme.blue.opacity(0.2) : Theme.surfaceElevated)
                Image(systemName: icon)
                    .font(.system(size: cellSize * 0.44))
            }
            .frame(width: cellSize, height: cellSize)
            .onTapGesture { selected = icon }
            """,
            andNotOn: """
            HStack {
                Image(systemName: icon)
                    .font(.system(size: cellSize * 0.44))
                Text(icon)
            }
            .onTapGesture { selected = icon }
            """,
            by: { Self.iconOnlyTapGestureCount(in: $0) > 0 }
        )
    }

    /// How many glyphs in the file reach a `.onTapGesture` with nothing that could carry a name
    /// in between.
    ///
    /// A hit needs an `Image(systemName:)` that reaches `.onTapGesture` within a **300-character**
    /// window with nothing else drawn in between. The window is not arbitrary: measured against
    /// the real tree (not assumed), the true site's gap was **246 characters** (`IconGrid`'s
    /// `Image` to its `.onTapGesture`) and the nearest look-alike's was **511**
    /// (`iOSCalendarBundleDetailSheet`'s `Menu` trigger — its `Image` sits inside the `Menu`'s own
    /// `label:` closure, and the row around it is tapped as a whole). 300 sits in the
    /// 265-character gap between them, and `theWindowSeparatesTheRealSiteFromItsNearestLookAlikes`
    /// below pins that measurement on real files rather than leaving it a comment.
    ///
    /// The `Text(` guard catches the other real shape (a `Text` sibling means the glyph is
    /// riding along a labelled row, not standing in for one) regardless of gap. `Button`/`Menu`
    /// catch a control introduced *between* the glyph and the gesture; they do not reach back
    /// over one that already wraps the glyph — proximity is what excludes that shape here.
    static func iconOnlyTapGestureCount(in source: String) -> Int {
        guard source.contains(".onTapGesture") else { return 0 }
        let code = CadenceSourceScan.codeOnly(source)
        var count = 0
        var cursor = code.startIndex
        while let hit = code.range(of: "Image(systemName", range: cursor..<code.endIndex) {
            cursor = hit.upperBound
            let windowEnd = code.index(cursor, offsetBy: 300, limitedBy: code.endIndex) ?? code.endIndex
            let window = code[cursor..<windowEnd]
            guard let tapRange = window.range(of: ".onTapGesture") else { continue }
            let between = window[window.startIndex..<tapRange.lowerBound]
            if between.contains("Button") || between.contains("Menu") || between.contains("Text(") {
                continue
            }
            count += 1
        }
        return count
    }

    @Test func noIconOnlyOnTapGestureControlIsLeftInTheApp() throws {
        let offenders = try detector().sweep(
            try CadenceSourceScan.swiftFiles(under: "Cadence"),
            // Same floor as the sibling sweeps: 565 files at the time of writing, so a walk that
            // found one folder and called it the app is not evidence of anything.
            atLeast: 400,
            including: "Cadence/macOS/Sheets/CreateContextSheet.swift",
            read: CadenceSourceScan.sourceFile
        )
        #expect(
            offenders.isEmpty,
            """
            \(offenders.sorted()) draws an icon-only control from a bare .onTapGesture with no \
            enclosing Button or Menu and no accessible name. Convert it to a Button and pair it \
            with .cadenceControlLabel(…).
            """
        )
    }

    /// **The measurement the window comment states, pinned rather than left in prose.** All three
    /// are real files this audit's own proximity search turned up as the closest things to a false
    /// positive; none of them is one, and this is what proves it rather than assumes it.
    @Test func theWindowSeparatesTheRealSiteFromItsNearestLookAlikes() throws {
        // A whole row (icon + task title) tapped to open an inspector — the glyph is not the
        // control, the row is, and `Text(task.title)` sits between them regardless.
        let calendarMonthCell = try CadenceSourceScan.sourceFile(
            "Cadence/macOS/Views/CalendarPageMonthSupportViews.swift"
        )
        // Two icon-only `Button`s (open link, delete) inside a card whose own background is
        // separately tapped to open the URL.
        let linksRow = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/LinksView.swift")
        // A `Menu` whose label is a bare glyph, in a row that is itself tapped as a whole.
        let bundleDetailRow = try CadenceSourceScan.sourceFile(
            "Cadence/iOS/iOSCalendarBundleDetailSheet.swift"
        )
        #expect(Self.iconOnlyTapGestureCount(in: calendarMonthCell) == 0)
        #expect(Self.iconOnlyTapGestureCount(in: linksRow) == 0)
        #expect(Self.iconOnlyTapGestureCount(in: bundleDetailRow) == 0)
    }

    /// Non-vacuity: the fixed file must not still contain the shape this suite bans, read from
    /// disk rather than assumed fixed because the source edit above says so.
    @Test func createContextSheetsIconGridNoLongerDrawsTheBannedShape() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/macOS/Sheets/CreateContextSheet.swift")
        #expect(Self.iconOnlyTapGestureCount(in: source) == 0)
        #expect(source.contains(#".cadenceControlLabel("Select \(icon) icon")"#))
    }
}
