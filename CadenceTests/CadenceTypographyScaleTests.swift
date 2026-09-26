import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// What the reader's text size does to a point size.
///
/// **These are the assertions T-1364's brief says the existing sweeps cannot make.**
/// `iOSCalendarMetricsTests`, `CalendarBoardCompactLayoutTests`, `TimelineMetricsTests` and
/// `CadenceTaskComposerLayoutTests` all pin corner radii, hour heights and a keyboard budget at the
/// *default* text size, and every one of them stays green while a converted screen clips — typography
/// and geometry are different invariants and those suites hold the geometry one. Nothing here adds a
/// constant; every test asks what happens at a text size the app was never previously evaluated at.
struct CadenceTypographyScaleTests {

    /// All twelve, in order, so a test that walks them cannot silently walk three.
    private let everySize = DynamicTypeSize.allCases

    @Test("The scale table covers every size SwiftUI can hand it")
    func theRampIsApplesPublishedBodyRampAndItIsComplete() {
        // Non-vacuity first: a table missing an entry falls back to the base size, which would make
        // every "it grows" assertion below pass at the sizes it forgot.
        #expect(everySize.count == 12)
        for size in everySize {
            #expect(CadenceTypeScale.bodyPointSizes[size] != nil,
                    "the Body ramp has no entry for \(size), so that size would silently not scale")
        }
        // The two ends of Apple's published Body ramp, which is what makes `.large` a no-op.
        #expect(CadenceTypeScale.bodyPointSizes[.large] == CadenceTypeScale.bodyBasePointSize)
        #expect(CadenceTypeScale.bodyPointSizes[.large] == 17)
        #expect(CadenceTypeScale.bodyPointSizes[.accessibility5] == 53)
        #expect(CadenceTypeScale.bodyMultiplier(at: .large) == 1)
    }

    /// The property that makes the conversion reviewable as a refactor: nothing moved at the size
    /// everyone was looking at.
    @Test("A converted call site draws its old literal at the default text size")
    func everyRoleIsItsBaseSizeAtTheDefaultTextSize() {
        for role in CadenceTypographyRole.allCases {
            #expect(CadenceTypeScale.size(role, at: .large, scaling: .enabled) == role.baseSize)
            #expect(CadenceTypeScale.growth(role, at: .large, scaling: .enabled) == 0)
        }
    }

    /// The other half of that: an unconverted surface is untouched at **every** size, which is the
    /// whole point of the migration boundary being an environment value and not a global flip.
    @Test("An unconverted surface is the app's previous behaviour at every size")
    func scalingOffIsFixedAtEverySizeIncludingTheLargest() {
        for role in CadenceTypographyRole.allCases {
            for size in everySize {
                #expect(CadenceTypeScale.size(role, at: size, scaling: .fixed) == role.baseSize)
                #expect(CadenceTypeScale.growth(role, at: size, scaling: .fixed) == 0)
                #expect(CadenceTypeScale.height(44, holding: role, at: size, scaling: .fixed) == 44)
            }
        }
    }

    @Test("Every role grows with the reader's text size and never shrinks on the way up")
    func everyRoleIsMonotonicAcrossTheRamp() {
        for role in CadenceTypographyRole.allCases {
            var previous: CGFloat = 0
            for size in everySize {
                let rendered = CadenceTypeScale.size(role, at: size, scaling: .enabled)
                #expect(rendered >= previous, "\(role) went backwards at \(size)")
                previous = rendered
            }
            // Strictly larger the moment the reader asks for one step up — a role whose cap had
            // been set below 1 would satisfy monotonicity while scaling nothing.
            #expect(CadenceTypeScale.size(role, at: .xLarge, scaling: .enabled)
                > CadenceTypeScale.size(role, at: .large, scaling: .enabled))
        }
    }

    /// The assertion that would have caught "we added the API and wired it to a ceiling of 1".
    @Test("At the largest supported size every role is at least twice its base")
    func theLargestSizeIsActuallyLarge() {
        for role in CadenceTypographyRole.allCases {
            let rendered = CadenceTypeScale.size(role, at: .accessibility5, scaling: .enabled)
            #expect(rendered >= role.baseSize * 2,
                    "\(role) only reaches \(rendered) from \(role.baseSize) at accessibility5")
            // And not unbounded: Apple's own Body ramp tops out at 3.12x and no role may exceed it.
            #expect(rendered <= role.baseSize * CadenceTypeScale.bodyMultiplier(at: .accessibility5))
        }
    }

    /// Apple's ramps are not parallel, and copying Body's onto a title is how a converted screen
    /// ends up with a 69pt title over a 42pt field.
    @Test("A title follows a flatter ramp than body text, as Apple's own tables do")
    func titleRolesAreCappedBelowTheBodyRamp() {
        let titleAtMax = CadenceTypeScale.multiplier(.editorTitle, at: .accessibility5, scaling: .enabled)
        let bodyAtMax = CadenceTypeScale.multiplier(.bodyText, at: .accessibility5, scaling: .enabled)
        #expect(titleAtMax < bodyAtMax)
        // The cap is Title 2's published ramp, 22 -> 49, and it is what binds rather than Body's.
        #expect(titleAtMax == CadenceTypeScale.maximumGrowth(for: .title2))
        #expect(titleAtMax < CadenceTypeScale.bodyMultiplier(at: .accessibility5))
        // Below the cap the two are the same curve, so the flattening is a ceiling and not a
        // second ramp with its own shape.
        #expect(CadenceTypeScale.multiplier(.editorTitle, at: .xLarge, scaling: .enabled)
            == CadenceTypeScale.bodyMultiplier(at: .xLarge))
    }

    /// Containers grow by what their text gained, not by what it was multiplied by. A 44pt row that
    /// tripled would be 137pt of chrome around one line.
    @Test("A container grows by the text's gain, not by the text's multiplier")
    func containerGrowthIsAdditive() {
        let size = DynamicTypeSize.accessibility3
        let gain = CadenceTypeScale.growth(.fieldLabel, at: size, scaling: .enabled)
        #expect(gain > 0)
        #expect(CadenceTypeScale.height(44, holding: .fieldLabel, at: size, scaling: .enabled) == 44 + gain)
        // Proportional growth would be strictly larger here, which is the thing being rejected.
        #expect(44 + gain < 44 * CadenceTypeScale.multiplier(.fieldLabel, at: size, scaling: .enabled))
    }

    @Test("Accessibility sizes are the ones Apple calls accessibility sizes")
    func theAccessibilityThresholdIsWhereApplePutsIt() {
        #expect(CadenceTypeScale.isAccessibilitySize(.xxxLarge) == false)
        #expect(CadenceTypeScale.isAccessibilitySize(.accessibility1))
        #expect(CadenceTypeScale.isAccessibilitySize(.accessibility5))
    }

    @Test("One line-height ratio, and the inspector reads it rather than restating it")
    func theLineHeightRatioIsStatedOnce() {
        #expect(CadenceTypeScale.lineHeightRatio == 1.2)
        let line: CGFloat = iOSTaskInspectorMetrics.titleSize * CadenceTypeScale.lineHeightRatio
        #expect(iOSTaskInspectorMetrics.titleLineHeight == line)
        #expect(iOSTaskInspectorMetrics.titleLineHeight(at: .large, scaling: .fixed)
            == iOSTaskInspectorMetrics.titleLineHeight)
    }
}

/// The geometry of the two shared controls the converted workflow is built out of, at every size.
///
/// This is the suite that goes red for the failure T-1364's brief names: a font that grew while the
/// box around it did not. `CadenceValueTileMetrics.minHeight` was a literal 56 whose own comment
/// said it left "room to grow one point under a larger dynamic type setting" — one point, against a
/// setting that asks for thirty.
struct CadenceScaledControlGeometryTests {

    private let everySize = DynamicTypeSize.allCases

    @Test("The value tile always reserves room for the two lines it draws")
    func theTileNeverAsksForLessRoomThanItsTextNeeds() {
        for size in everySize {
            for scaling in CadenceTypographyScaling.allCases {
                let needed = CadenceValueTileMetrics.intrinsicHeight(at: size, scaling: scaling)
                let reserved = CadenceValueTileMetrics.minHeight(at: size, scaling: scaling)
                #expect(reserved >= needed,
                        "the tile reserves \(reserved) for \(needed) of text at \(size)/\(scaling)")
            }
        }
    }

    @Test("The tile is still fifty-six points on every screen that has not been converted")
    func theTileIsUnchangedAtTheDefault() {
        #expect(CadenceValueTileMetrics.minHeight(at: .large, scaling: .fixed)
            == CadenceValueTileMetrics.minHeight)
        #expect(CadenceValueTileMetrics.minHeight(at: .large, scaling: .enabled)
            == CadenceValueTileMetrics.minHeight)
        #expect(CadenceValueTileMetrics.minHeight(at: .accessibility5, scaling: .fixed)
            == CadenceValueTileMetrics.minHeight)
        // The headroom the 56 was chosen with survives as the headroom term rather than as a 56.
        #expect(CadenceValueTileMetrics.headroom > 0)
    }

    @Test("The tile grows with the reader and roughly triples by the largest size")
    func theTileGrowsWithItsText() {
        let base = CadenceValueTileMetrics.minHeight(at: .large, scaling: .enabled)
        let largest = CadenceValueTileMetrics.minHeight(at: .accessibility5, scaling: .enabled)
        #expect(largest > base * 2)
        var previous: CGFloat = 0
        for size in everySize {
            let height = CadenceValueTileMetrics.minHeight(at: size, scaling: .enabled)
            #expect(height >= previous)
            previous = height
        }
    }

    /// Shrinking the text back down is exactly what the reader asked not to happen, and it is the
    /// specific thing the audit calls out about `minimumScaleFactor`.
    @Test("The tile stops shrinking its value once the text size is an accessibility setting")
    func theTileDropsShrinkToFitAtAccessibilitySizes() {
        #expect(CadenceValueTileMetrics.valueMinimumScaleFactor(at: .xxxLarge, scaling: .enabled) == 0.8)
        #expect(CadenceValueTileMetrics.valueMinimumScaleFactor(at: .accessibility1, scaling: .enabled) == 1)
        #expect(CadenceValueTileMetrics.valueLineLimit(at: .xxxLarge, scaling: .enabled) == 1)
        #expect(CadenceValueTileMetrics.valueLineLimit(at: .accessibility1, scaling: .enabled) == 2)
        // And an unconverted surface keeps both, at every size.
        #expect(CadenceValueTileMetrics.valueMinimumScaleFactor(at: .accessibility5, scaling: .fixed) == 0.8)
        #expect(CadenceValueTileMetrics.valueLineLimit(at: .accessibility5, scaling: .fixed) == 1)
        // The reserved height knows about the second line, or the tile overlaps exactly where the
        // line limit allowed it to wrap.
        #expect(CadenceValueTileMetrics.minHeight(at: .accessibility1, scaling: .enabled)
            > CadenceValueTileMetrics.minHeight(at: .xxxLarge, scaling: .enabled)
                + CadenceTypeScale.lineHeight(.fieldValue, base: CadenceValueTileMetrics.valueFontSize, at: .xxxLarge, scaling: .enabled))
    }

    @Test("A labelled field row and its glyph slot both move with the label")
    func theFieldRowGrowsByWhatItsLabelGained() {
        let size = DynamicTypeSize.accessibility5
        let gain = CadenceTypeScale.growth(.fieldLabel, at: size, scaling: .enabled)
        #expect(CadenceSettingsRowMetrics.rowHeight(at: size, scaling: .enabled)
            == CadenceSettingsRowMetrics.rowHeight + gain)
        #expect(CadenceSettingsRowMetrics.glyphSlot(at: size, scaling: .enabled)
            == CadenceSettingsRowMetrics.glyphSlot + gain)
        // The slot still holds the glyph drawn in it, which is the only reason it exists.
        #expect(CadenceSettingsRowMetrics.glyphSlot(at: size, scaling: .enabled)
            >= CadenceTypeScale.size(.fieldLabel, at: size, scaling: .enabled))
        #expect(CadenceSettingsRowMetrics.rowHeight(at: .large, scaling: .enabled)
            == CadenceSettingsRowMetrics.rowHeight)
    }

    /// The inspector's completion circle is placed by arithmetic over the title beside it, so it is
    /// the clearest case of a derived figure that has to survive the title changing size.
    @Test("The completion circle stays centred on the title's first line at every size")
    func theCompletionCircleFollowsTheTitle() {
        for size in everySize {
            let line = iOSTaskInspectorMetrics.titleLineHeight(at: size, scaling: .enabled)
            let glyph = iOSTaskInspectorMetrics.completionGlyphSize(at: size, scaling: .enabled)
            let padding = iOSTaskInspectorMetrics.completionTopPadding(at: size, scaling: .enabled)
            #expect(padding >= 0)
            // Centred: the circle plus twice the nudge is the line it sits on.
            #expect(abs((padding * 2 + glyph) - line) < 0.001, "circle is off the line at \(size)")
            // And the indent under the title is still the circle plus the gap, not a third number.
            #expect(iOSTaskInspectorMetrics.titleColumnInset(at: size, scaling: .enabled)
                == glyph + iOSTaskInspectorMetrics.titleRowSpacing)
        }
        #expect(iOSTaskInspectorMetrics.completionGlyphSize(at: .large, scaling: .enabled)
            == iOSTaskInspectorMetrics.completionGlyphSize)
        #expect(iOSTaskInspectorMetrics.completionGlyphSize(at: .accessibility5, scaling: .enabled)
            > iOSTaskInspectorMetrics.completionGlyphSize)
    }
}

/// That the converted workflow is converted **all the way**, which is the part of T-1364 a numeric
/// assertion cannot see.
///
/// The brief is explicit that a scattering of enlarged labels inside rigid controls is worse than
/// nothing, so "one complete workflow" has to be a checkable claim rather than a description. These
/// are the two halves of it: no raw font literal survives inside the workflow, and the workflow says
/// where its scaling scope begins.
struct CadenceTypographyConversionSweepTests {

    /// Create a task, then open it and read it back. The sheet, its tiles and suggestion strip, the
    /// detail sheet, its sections and its components.
    ///
    /// `CadenceFieldRows.swift` and `SectionEyebrowLabel.swift` are deliberately **not** here even
    /// though both were edited: each holds types outside this workflow — settings rows, the
    /// `Size.font` two unconverted macOS readers still call — and those keep their literals until
    /// their own surface is converted. Listing them would make this sweep a lie in the other
    /// direction.
    private static let workflow = [
        "Cadence/iOS/iOSCreateTaskSheet.swift",
        "Cadence/iOS/iOSCreateTaskSheetSupportViews.swift",
        "Cadence/iOS/iOSTaskDetailSheet.swift",
        "Cadence/iOS/iOSTaskDetailSheetSections.swift",
        "Cadence/iOS/iOSTaskDetailComponents.swift",
        "Cadence/Shared/Components/CadenceValueTile.swift",
    ]

    private static func fontLiteralInstrument() throws -> CadenceScanInstrument {
        try CadenceScanInstrument(
            "raw font literal",
            fires: "Text(title).font(.system(size: 13, weight: .semibold))",
            andNotOn: "Text(title).cadenceFont(.controlLabel, base: 13)",
            by: { $0.contains(".font(.system(size:") }
        )
    }

    @Test func noRawFontLiteralSurvivesInsideTheConvertedWorkflow() throws {
        let instrument = try Self.fontLiteralInstrument()
        let read = CadenceSourceScan.strippedSourceReader()

        // The reader, before an empty result is believed. `strippingComments` blanks comments and
        // keeps code; a reader swapped for `codeOnly` would blank nothing relevant here, but one
        // pointed at the wrong root returns empty strings and this sweep passes forever.
        #expect(try read("Cadence/iOS/iOSDesignSystem.swift").contains(".font(.system(size:"),
                "the sweep's reader no longer reaches unconverted source, so its needle cannot match")

        let hits = try instrument.sweep(
            Self.workflow,
            atLeast: Self.workflow.count,
            including: "Cadence/iOS/iOSCreateTaskSheet.swift",
            read: read
        )
        #expect(hits.isEmpty, "these files still draw a fixed font: \(hits.joined(separator: ", "))")
    }

    /// The positive half: the workflow does not merely lack literals, it routes through the adapter.
    /// A file with every `.font` deleted satisfies the sweep above.
    @Test func everyWorkflowFileThatDrawsTextGoesThroughTheAdapter() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        // The detail sheet itself draws no text of its own — it hosts the sections that do — so it
        // is the one file here that legitimately has no call.
        let drawsText = Self.workflow.filter { $0 != "Cadence/iOS/iOSTaskDetailSheet.swift" }
        #expect(drawsText.count == 5)
        for path in drawsText {
            #expect(try read(path).contains(".cadenceFont("), "\(path) draws no scaled font")
        }

        // The two shared types the workflow's field rows are made of, converted in place rather
        // than forked — the rest of `CadenceFieldRows.swift` is settings and is a later ticket.
        let fieldRows = try read("Cadence/Shared/Components/CadenceFieldRows.swift")
        #expect(fieldRows.contains(".cadenceFont(.fieldLabel)"))
        #expect(fieldRows.contains("CadenceSettingsRowMetrics.rowHeight(at: dynamicTypeSize, scaling: scaling)"))
        // The eyebrow routes through `cadenceUppercaseLabel(size:kerning:)` rather than
        // `cadenceFont`, because its tracking has to move with its size — see
        // `CadenceUppercaseLabelTrackingTests`, which is what holds the four draw sites together.
        // Both the call and the modifier, so a caller that kept the name over a body that stopped
        // consulting the environment is caught here rather than only there.
        let eyebrow = try read("Cadence/Shared/Components/SectionEyebrowLabel.swift")
        #expect(eyebrow.contains(".cadenceUppercaseLabel(size: size.fontSize, kerning: size.kerning)"))
        #expect(eyebrow.contains("CadenceTypeScale.multiplier(.sectionLabel, at: dynamicTypeSize, scaling: scaling)"))
    }

    /// Where the scope begins, and that it begins in exactly two places.
    ///
    /// The count is the assertion. A third `.cadenceScaledTypography()` means a surface was opted in
    /// without its geometry being made size-aware, which is the failure mode the environment flag
    /// exists to make visible rather than the improvement it looks like.
    @Test func exactlyTwoSurfacesDeclareThemselvesConverted() throws {
        let instrument = try CadenceScanInstrument(
            "scaled typography scope",
            fires: "NavigationStack { body }.cadenceScaledTypography().tint(Theme.blue)",
            andNotOn: "func cadenceScaledTypography() -> some View { modifier(scope) }",
            by: { $0.contains(".cadenceScaledTypography()") }
        )

        let read = CadenceSourceScan.strippedSourceReader()
        #expect(try read("Cadence/Shared/CadenceTypography.swift").contains("cadenceScaledTypography"),
                "the sweep's reader no longer reaches the adapter, so its needle cannot match")

        var paths: [String] = []
        for root in ["Cadence", "CadenceWidgets", "CadenceMCPServer"] {
            paths += try CadenceSourceScan.swiftFiles(under: root)
        }
        #expect(paths.contains("Cadence/Shared/CadenceTypography.swift"))

        let hits = try instrument.sweep(
            paths,
            atLeast: 300,
            including: "Cadence/iOS/iOSCreateTaskSheet.swift",
            read: read
        )
        #expect(hits == [
            "Cadence/iOS/iOSCreateTaskSheet.swift",
            "Cadence/iOS/iOSTaskDetailSheet.swift",
        ])
    }
}
