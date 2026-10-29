import Foundation
import Testing
@testable import Cadence

/// T-489: `.stroke` on a filled `RoundedRectangle`/`Circle`/`Capsule` centres its line on the
/// path, so half of it draws outside the shape's own bounds and a control renders wider than it
/// measures — the defect `SettingsListManagementSections.swift`'s 28x28 glyph well named it by.
/// `.strokeBorder` insets instead, and it exists only on `InsettableShape`.
///
/// The user's decision was an app-wide sweep to `.strokeBorder` **wherever the shape is
/// filled**, with two carve-outs named in the ticket: a bare `Path` (or `NSBezierPath` /
/// `UIBezierPath`, or a `Canvas` `GraphicsContext.stroke(Path, ...)` call) cannot be converted at
/// all — `.strokeBorder` is not a member of any of those types, so the qualifier is not stylistic,
/// it is a compile error waiting to happen. And a stroke-only decoration with no companion fill
/// is "not the same case" even when it happens to be expressed as a `Circle`/`RoundedRectangle`.
///
/// **Failing-first.** Reverting any one of the 83 sites this sweep converted back to `.stroke(`
/// turns `noShapeStrokeCallRemainsOutsideTheBezierPathFiles` red — it is swept over
/// the whole tree, not a fixed file list, so a reverted site is caught regardless of which file it
/// lives in. There are no exceptions left to convert since [[T-8411]].
struct CadenceStrokeBorderSweepTests {

    // MARK: - The two carve-outs the ticket names

    /// Files whose `.stroke()` calls are AppKit/UIKit bezier-path drawing (`NSBezierPath`,
    /// `UIBezierPath`) or raw `CGPath`/`Path` canvas drawing — never a SwiftUI `Shape`.
    /// `.strokeBorder` is not a member of any of these types: converting would not compile. This
    /// is the ticket's "a bare Path ... is not the same case" qualifier.
    static let bezierPathDrawingFiles: Set<String> = [
        "Cadence/macOS/Editor/MarkdownEditorLayoutManager.swift",
        "Cadence/macOS/Editor/MarkdownEditorSupport.swift",
        "Cadence/macOS/Editor/MarkdownTableCanvasDrawing.swift",
        "Cadence/macOS/Editor/MarkdownTaskEmbedDrawingSupport.swift",
        "Cadence/macOS/Editor/MarkdownEditorTextViewDecorations.swift",
        "Cadence/macOS/Editor/MarkdownEditorInteractionSupport.swift",
        "Cadence/iOS/iOSMarkdownTaskEmbedLayoutInfo.swift",
        "Cadence/iOS/iOSMarkdownImageLayoutInfo.swift",
        "Cadence/iOS/iOSMarkdownBlockCanvasSupport.swift",
        "Cadence/iOS/iOSMarkdownTableGridRendering.swift",
    ]

    /// T-489's other carve-out — two `Circle()` progress-ring `.stroke`s in macOS's
    /// `TaskCompletionAnimationViews.swift`, a track and a `.trim`-ed arc with no companion fill —
    /// is retired ([[T-8411]]). That glyph is gone: both platforms draw
    /// `CadenceTaskCompletionCircle`, whose fill is the inset `strokeBorder` ring masked by a wedge,
    /// so it traces its own resting ring exactly and there is no stroke-only exception left.

    // MARK: - The sweep

    /// Every `.stroke(` call **with an argument list**, read from `codeOnly` text (so a string
    /// literal or comment spelling `.stroke(` cannot be counted as code), outside the bezier-path
    /// files above. Excludes the bare zero-argument `.stroke()` AppKit/UIKit form and
    /// `context.stroke(` (`GraphicsContext`'s `Path`-based `Canvas` draw call) — neither is a
    /// `Shape` modifier, so neither is a candidate regardless of which file it is in.
    static func remainingShapeStrokeSites() throws -> [(file: String, line: Int, text: String)] {
        var hits: [(String, Int, String)] = []
        let paths = try CadenceSourceScan.swiftFiles(under: "Cadence")
            + CadenceSourceScan.swiftFiles(under: "CadenceWidgets")
        for path in paths {
            if bezierPathDrawingFiles.contains(path) { continue }
            let source = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            for (index, line) in source.components(separatedBy: "\n").enumerated() {
                guard line.contains(".stroke(") else { continue }
                if line.contains("context.stroke(") { continue }
                hits.append((path, index + 1, line.trimmingCharacters(in: .whitespaces)))
            }
        }
        return hits
    }

    /// The instrument backing the sweep, self-checked at construction: it must fire on an
    /// unconverted call and must not fire on the converted spelling of the very same call, so a
    /// detector that stopped discriminating cannot be built.
    static let unconvertedStrokeInstrument = try! CadenceScanInstrument(
        "unconvertedShapeStroke",
        fires: ".stroke(Theme.borderSubtle, lineWidth: 1)",
        andNotOn: ".strokeBorder(Theme.borderSubtle, lineWidth: 1)"
    ) { text in
        text.contains(".stroke(") && !text.contains("context.stroke(")
    }

    @Test
    func unconvertedStrokeInstrumentStillDiscriminates() throws {
        // Constructing `unconvertedStrokeInstrument` above already ran both witnesses; this test
        // exists so a failure there is reported as a numbered `Testing` failure rather than only a
        // fatal thrown from a top-level `let`.
        #expect(Self.unconvertedStrokeInstrument.fires(on: ".stroke(Theme.blue, lineWidth: 2)"))
        #expect(!Self.unconvertedStrokeInstrument.fires(on: ".strokeBorder(Theme.blue, lineWidth: 2)"))
    }

    @Test
    func noShapeStrokeCallRemainsOutsideTheBezierPathFiles() throws {
        let hits = try Self.remainingShapeStrokeSites()
        #expect(hits.isEmpty, "unconverted .stroke( site(s): \(hits)")

        // Non-vacuity: the sweep read the shared completion circle, and that file's fill is the
        // converted spelling rather than a trimmed stroke.
        let circle = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/Shared/Components/CadenceTaskCompletionCircle.swift")
        )
        #expect(circle.contains(".mask(CadenceTaskCompletionWedge(fraction: fill))"), "non-vacuity: the circle's fill moved")
        #expect(!Self.unconvertedStrokeInstrument.fires(on: circle), "the completion circle strokes a shape again")
    }

    /// Named spot-pins on a handful of the 83 converted sites — including the ticket's own
    /// motivating example — so a regression that only clears the aggregate sweep (e.g. deleting
    /// the line rather than fixing it) still has a specific, individually-named assertion to
    /// fail.
    @Test
    func theTicketsMotivatingSiteReadsStrokeBorder() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/SettingsListManagementSections.swift")
        #expect(
            CadenceSourceScan.matchCount(
                "\\.overlay\\(RoundedRectangle\\(cornerRadius: Theme\\.radiusControlCompact\\)\\.strokeBorder\\(Theme\\.borderSubtle\\)\\)",
                in: source
            ) == 1
        )
        #expect(!source.contains(".overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.borderSubtle))"))
    }

    @Test
    func aSelectionRingOverlaidOnAFilledSwatchWasConverted() throws {
        // SettingsTagsSection.swift:485 — a Circle() selection ring drawn on top of a filled
        // Circle() swatch. No `.fill` on the ring itself, but it overlays a filled sibling shape
        // of the same size, which is the case the ticket's "wherever the shape is filled" covers
        // — distinct from the stroke-only progress ring T-8411 retired, which had no filled sibling at all.
        let source = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/SettingsTagsSection.swift")
        #expect(CadenceSourceScan.matchCount("Circle\\(\\)\\s*\\.strokeBorder\\(Theme\\.text\\.opacity\\(0\\.78\\), lineWidth: 2\\)", in: source) == 1)
    }

    @Test
    func anOutlineOnlyButtonWithNoSeparateFillWasConverted() throws {
        // TaskInspectorContentSupportViews.swift's iconButton has no separate background fill —
        // the RoundedRectangle IS the button's boundary, drawn via `.background`. Still a bounded
        // control outline (not a "stroke-only decoration" like a progress ring or chart line), so
        // it converts. Since T-6231 an active (status-tinted) button drops the rim, so the colour
        // is conditional; the rim is still a strokeBorder.
        let source = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TaskInspectorContentSupportViews.swift")
        #expect(CadenceSourceScan.matchCount("RoundedRectangle\\(cornerRadius: Self\\.cornerRadius\\)\\s*\\.strokeBorder\\(isActive \\? Color\\.clear : Theme\\.borderSubtle, lineWidth: 1\\)", in: source) == 1)
        #expect(!source.contains(".stroke(isActive ? Color.clear : Theme.borderSubtle"))
    }

    @Test
    func multiLineStrokeCallsWereConverted() throws {
        // Sites where `.stroke(` opened a multi-line argument list (a computed border color),
        // rather than a single-line call — a different shape for the same regex to miss.
        let sites: [(file: String, pattern: String)] = [
            (
                "Cadence/macOS/Views/KanbanColumnSupportViews.swift",
                "Circle\\(\\)\\s*\\.strokeBorder\\(\\s*CadenceColorPalette\\.matches"
            ),
            (
                "Cadence/macOS/Views/TasksPanelComponents.swift",
                "RoundedRectangle\\(cornerRadius: Theme\\.radiusCard\\)\\s*\\.strokeBorder\\(\\s*TaskHoverVisuals\\.borderColor"
            ),
            (
                // Since T-3167 the plate, its rim and its clip are one `blockShape`.
                "Cadence/macOS/Views/TimelineEventBlock.swift",
                "blockShape\\s*\\.strokeBorder\\(\\s*TimelineHoverVisuals\\.borderColor"
            ),
        ]
        for site in sites {
            let source = try CadenceSourceScan.sourceFile(site.file)
            #expect(
                CadenceSourceScan.matchCount(site.pattern, in: source) == 1,
                "expected exactly one strokeBorder match for \(site.pattern) in \(site.file)"
            )
        }
    }
}
