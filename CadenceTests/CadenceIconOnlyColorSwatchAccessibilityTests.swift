import Foundation
import Testing
@testable import Cadence

/// **A colour swatch is `IconGrid`'s exact pre-T-674 defect, one struct up (T-797).**
///
/// `ColorGrid` -- a top-level type in `CreateContextSheet.swift`, not a member of any
/// `CreateContextSheet` -- drew a bare `Circle()` mutating `selected` from
/// `.onTapGesture` — no `Button`, no accessible name, no accessibility trait — reachable in
/// Release from ordinary context creation or editing. `CadenceIconOnlyTapGestureAccessibilityTests`
/// (T-674) correctly does **not** fire on it: that detector keys on `Image(systemName:)`, and a
/// swatch draws `Circle().fill(Color(hex:))`, no `Image` at all. Same shape, different needle, so
/// its own detector rather than a fourth case bolted onto the sibling one.
///
/// **The name was the open question T-797 was filed with, and it turned out to already be
/// answered.** Measured 2026-09-04: six other swatch grids in the tree — `TagColorSwatches`
/// (`SettingsTagsSection.swift`), `ListEditorColorStrip`, `iOSListColorSwatch`,
/// `TagPickerPopoverViews`, `KanbanColumnSupportViews` and `iOSSettingsComponents` — all name the
/// control by what tapping it *does* ("Use this colour" / "Selected colour"), with the hex
/// reserved for a sighted-only `.help()` tooltip. `SettingsTagsSection.swift` states why in as many
/// words: "a screen reader cannot verify a colour and the repo does not invent colour names for
/// one" — the same reasoning `CadenceAccentPalettePresentation` gives for the accent picker.
/// `ColorGrid` now draws the converged idiom instead of inventing an eighth one. `iOSTrackingColorGrid`
/// was the one file that predated the convergence, still naming its swatches `"Color \(hex)"` after
/// this comment was written; T-934 brought it in line, so all seven swatch grids now agree.
struct CadenceIconOnlyColorSwatchAccessibilityTests {

    private func detector() throws -> CadenceScanInstrument {
        try CadenceScanInstrument(
            "icon-only .onTapGesture color swatch with no enclosing control",
            fires: """
            Circle()
                .fill(Color(hex: hex))
                .frame(width: swatchSize, height: swatchSize)
                .overlay(
                    Circle()
                        .strokeBorder(Theme.onColor.opacity(isSelected ? 1 : 0), lineWidth: 2)
                )
                .onTapGesture { selected = hex }
            """,
            // The nearest look-alike: a colour dot beside a `Text`, tapped as a whole row rather
            // than as a swatch — `GoalTimelineGoalRailRow`'s real shape. The dot is not the
            // control here, the row is, and `Text(` sits between the fill and the gesture
            // regardless of how far apart they are.
            andNotOn: """
            HStack {
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 15, height: 15)
                Text(goal.title)
            }
            .onTapGesture { onSelect(goal) }
            """,
            by: { Self.iconOnlyColorSwatchCount(in: $0) > 0 }
        )
    }

    /// How many swatches in the file reach a `.onTapGesture` with nothing that could carry a name
    /// in between.
    ///
    /// A hit needs a `Circle()` whose very next call is `.fill(Color(` — a colour swatch, and not
    /// a `RoundedRectangle` or a plain `Circle()` used for a ring or a clip shape — that reaches
    /// `.onTapGesture` within a **650-character** window with nothing else drawn in between.
    ///
    /// **The `Circle()` requirement is load-bearing, found by this suite's own first sweep rather
    /// than assumed safe.** Keying on `.fill(Color(` alone also fired on
    /// `CalendarPageMonthSupportViews.swift`'s task chip, whose background is a `RoundedRectangle`
    /// filled with `Color(hex: task.containerColor)` and whose whole chip — not the fill — is
    /// tapped to open an inspector; the gap there is 356 characters, comfortably inside a window
    /// sized for the real shape, and the row's `Text(task.title)` is drawn *before* the fill
    /// rather than between it and the gesture, so the `Text(` guard alone does not exclude it.
    /// Requiring the swatch's own shape does, by construction, rather than by widening the guard
    /// list to chase the next look-alike.
    ///
    /// Measured against the real tree: the pre-fix `ColorGrid`'s gap from `Circle()` to
    /// `.onTapGesture` was **548** characters, so 650 clears it with margin. `Button`/`Menu` catch
    /// a control introduced between the fill and the gesture; `Text(` catches the row-is-the-
    /// control shape when it sits between the two — see
    /// `theWindowSeparatesTheRealSwatchFromItsNearestLookAlikes`, which pins both exclusions on the
    /// real files rather than leaving them a comment.
    static func iconOnlyColorSwatchCount(in source: String) -> Int {
        guard source.contains(".onTapGesture") else { return 0 }
        let code = CadenceSourceScan.codeOnly(source)
        var count = 0
        var cursor = code.startIndex
        while let hit = code.range(of: "Circle()", range: cursor..<code.endIndex) {
            cursor = hit.upperBound
            let afterCircle = skippingWhitespace(from: cursor, in: code)
            guard code[afterCircle...].hasPrefix(".fill(Color(") else { continue }

            let windowEnd = code.index(cursor, offsetBy: 650, limitedBy: code.endIndex) ?? code.endIndex
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

    private static func skippingWhitespace(from start: String.Index, in code: String) -> String.Index {
        var index = start
        while index < code.endIndex, code[index] == " " || code[index] == "\n" || code[index] == "\t" {
            index = code.index(after: index)
        }
        return index
    }

    @Test func noIconOnlyColorSwatchInTheAppIsLeftAsABareOnTapGesture() throws {
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
            \(offenders.sorted()) draws a colour swatch from a bare .onTapGesture with no \
            enclosing Button and no accessible name. Wrap it in a Button and name it \
            "Use this colour" / "Selected colour", matching TagColorSwatches.
            """
        )
    }

    /// **The measurement the window comment states, pinned rather than left in prose.** All three
    /// are real files a proximity search over the whole tree turned up as the closest things to a
    /// false positive — the third one actually was one, on this suite's first sweep, until the
    /// `Circle()` requirement excluded it by construction. None of the three is a false positive
    /// now, and this is what proves it rather than assumes it.
    @Test func theWindowSeparatesTheRealSwatchFromItsNearestLookAlikes() throws {
        // A colour dot beside a `Text`, tapped as a whole row — the dot is not the control.
        let goalRailRow = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/GoalTimelineSupportViews.swift")
        let goalTimelineBar = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/GoalTimelineBarView.swift")
        // A `RoundedRectangle` chip background filled with a task's colour, 356 characters from
        // its own `.onTapGesture` — close enough to land inside any window sized for the real
        // shape, and excluded only because it is not a `Circle()`.
        let calendarChip = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarPageMonthSupportViews.swift")
        #expect(Self.iconOnlyColorSwatchCount(in: goalRailRow) == 0)
        #expect(Self.iconOnlyColorSwatchCount(in: goalTimelineBar) == 0)
        #expect(Self.iconOnlyColorSwatchCount(in: calendarChip) == 0)
    }

    /// Non-vacuity: the fixed file must not still contain the shape this suite bans, read from
    /// disk rather than assumed fixed because the source edit above says so.
    @Test func createContextSheetsColorGridNoLongerDrawsTheBannedShape() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/macOS/Sheets/CreateContextSheet.swift")
        #expect(Self.iconOnlyColorSwatchCount(in: source) == 0)
        #expect(source.contains(#".accessibilityLabel(isSelected ? "Selected colour" : "Use this colour")"#))
        #expect(source.contains(".help(hex)"))
    }

    /// **T-934: `iOSTrackingColorGrid` was the one holdout this file's own doc comment named.**
    /// Unlike `ColorGrid`, it already wraps its swatch in a `Button` — this suite's bare-
    /// `.onTapGesture` detector correctly does not fire on it — but it still names the control by
    /// its hex value, `"Color \(color)"`, rather than by what tapping it does. A screen reader
    /// cannot verify a colour, so a hex-named control reads a string sighted users never see and
    /// non-sighted users cannot check. This pins the fix directly rather than leaving the sweep to
    /// notice it only if the bare-gesture shape reappears.
    @Test func iOSTrackingColorGridNamesItsSwatchesByActionNotByHex() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTrackingEditorComponents.swift")
        #expect(!source.contains(#"accessibilityLabel("Color \(color)")"#))
        #expect(source.contains(#".accessibilityLabel(isOn ? "Selected colour" : "Use this colour")"#))
    }
}
