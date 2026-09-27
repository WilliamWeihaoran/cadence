import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// **T-1398: what a `.popover` does to T-1364's migration boundary.**
///
/// T-1364 made "has this surface been laid out for larger text?" an environment value, which is the
/// right shape for a shared component drawn by sixty files. It left one thing unasserted, and its
/// own entry says so: whether that value reaches a `.sheet` or a `.popover` was never verified in
/// either direction. It does, and the half that makes it dangerous is that its partner does not.
///
/// **Measured, not reasoned about.** A standalone SwiftUI binary — a custom `EnvironmentKey` of
/// exactly `CadenceTypographyScaling`'s shape, installed by a modifier at a root, read back from
/// presented content — built and run twice on 2026-09-26:
///
/// | host | custom value inside a presentation | `\.dynamicTypeSize` inside it |
/// | --- | --- | --- |
/// | iPhone 17 Pro, iOS 26.5 sim, Xcode 27.0 (27A266a) | `enabled` in `.sheet`, `.popover`, `.fullScreenCover` | `accessibility5` — the system setting, via `simctl ui … content_size` |
/// | macOS 27.0, same source | `enabled` in `.sheet`, `.popover` | `large` |
///
/// and in a second iOS run the root said `.dynamicTypeSize(.accessibility3)`: inline read
/// `accessibility3`, all three presentations read `accessibility5`. So the **flag is inherited from
/// the presenter** and the **size is re-read from the host window**. A rigid picker opened from a
/// converted sheet therefore arrived carrying `.enabled` and met the reader's real text size — the
/// one combination T-1364's brief calls worse than doing nothing.
///
/// **Which is why nothing below asserts that propagation happens.** CI runs Xcode 26 and this was
/// only observed on 27; T-1279 pinned 26 and went red locally, T-1296 pinned 27 and turned CI red.
/// The measurement is recorded as a dated observation and the *fix* is written so the answer does
/// not matter: a view that pins its own width or height states its own scaling, and then it renders
/// the same whichever way the framework propagates. That property is toolchain-independent, so it
/// is the one that is pinned.
struct CadencePresentedTypographyBoundaryTests {

    /// The four view types every `.popover` in T-1364's two converted workflows presents, and
    /// **which answer each one gives**.
    ///
    /// T-1398 put all four on `.fixed`, which was the regression being stopped rather than the
    /// question being answered. T-1410 answered it per panel, and the answers differ — which is the
    /// finding, not an inconsistency. Two panels converted, because the shape they needed was the
    /// shape they already had; two stayed pinned, each for a reason that is arithmetic rather than
    /// appetite and each priced in its own test below.
    ///
    /// Not a guess: `everyPopoverInAConvertedWorkflowOpensADeclaredPicker` re-derives the list out
    /// of the five workflow files and fails if a sixth appears.
    private static let presentedPickers: [String: (path: String, scope: String)] = [
        // Converted. `iOSFittedPopover` / `iOSChoicePopoverList` / `iOSContainerChoicePopover` are
        // typealiases onto this, so the declaration belongs on the panel that owns the frame.
        "CadenceFittedPopover": (
            "Cadence/Shared/Components/CadenceChoicePicker.swift", ".cadenceScaledTypography()"
        ),
        // Converted.
        "EstimatePickerPopoverContent": (
            "Cadence/Shared/Components/EstimatePickerControl.swift", ".cadenceScaledTypography()"
        ),
        // Pinned: seven columns of a month grid do not fit a phone once a day cell can grow.
        "CadenceQuickDatePopover": (
            "Cadence/Shared/Components/CadenceDatePicker.swift", ".cadenceFixedTypography()"
        ),
        // Pinned: every row of it is a `CadenceTagChip`, which twelve surfaces draw.
        "iOSTaskTagPickerPopover": (
            "Cadence/iOS/iOSTaskDetailComponents.swift", ".cadenceFixedTypography()"
        ),
    ]

    private static let scopeModifiers = [".cadenceScaledTypography()", ".cadenceFixedTypography()"]

    private static let convertedWorkflowFiles = [
        "Cadence/iOS/iOSCreateTaskSheet.swift",
        "Cadence/iOS/iOSCreateTaskSheetSupportViews.swift",
        "Cadence/iOS/iOSTaskDetailSheet.swift",
        "Cadence/iOS/iOSTaskDetailSheetSections.swift",
        "Cadence/iOS/iOSTaskDetailComponents.swift",
    ]

    // MARK: - The two scopes are opposites, at every size

    /// The property the fix rests on: saying `.fixed` puts a converted call site back on the exact
    /// literal it replaced, at **every** text size — so pinning a picker costs nothing visible and
    /// is not a second set of numbers.
    @Test("A picker that declares itself fixed draws its old literal at all twelve text sizes")
    func declaringFixedRestoresTheLiteralAtEveryDynamicTypeSize() {
        let everySize = DynamicTypeSize.allCases
        #expect(everySize.count == 12, "a shorter walk would prove less than it claims")

        for role in CadenceTypographyRole.allCases {
            for size in everySize {
                #expect(CadenceTypeScale.size(role, at: size, scaling: .fixed) == role.baseSize,
                        "\(role) moved at \(size) under .fixed")
                #expect(CadenceTypeScale.growth(role, at: size, scaling: .fixed) == 0)
            }
        }
    }

    /// And the other half, or the test above is satisfied by a curve that never moves at all.
    @Test("The same roles do grow once a surface says it is scaled")
    func theScaledScopeStillGrowsOrTheFixedAssertionIsVacuous() {
        for role in CadenceTypographyRole.allCases {
            let largest = CadenceTypeScale.size(role, at: .accessibility5, scaling: .enabled)
            #expect(largest > role.baseSize, "\(role) does not grow, so nothing above was measured")
        }
    }

    /// Both scopes exist, and they install opposite values rather than one of them being decorative.
    @Test("The adapter declares both scopes and they disagree")
    func theAdapterDeclaresAFixedScopeAsWellAsAScaledOne() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let adapter = try read("Cadence/Shared/CadenceTypography.swift")

        #expect(adapter.contains("func cadenceFixedTypography() -> some View"))
        #expect(adapter.contains("func cadenceScaledTypography() -> some View"))
        #expect(adapter.contains("content.environment(\\.cadenceTypographyScaling, .fixed)"),
                "the fixed scope no longer installs .fixed")
        #expect(adapter.contains("content.environment(\\.cadenceTypographyScaling, .enabled)"),
                "the scaled scope no longer installs .enabled")
    }

    // MARK: - The leak this closed, priced

    /// **The "font grew, box did not" case, as arithmetic.**
    ///
    /// Two boxes in `iOSTaskTagPickerPopover`, each a literal read out of the file it is asserted
    /// against so this cannot drift into a restatement:
    ///
    /// - its create button, a `40 × 40` square holding a `.fieldLabel` glyph;
    /// - its tag rows, `minHeight: 44` holding a `.rowTitle`.
    ///
    /// **This is now the price of the pin rather than the price of the leak** (T-1410). The other
    /// panel this test used to measure — `CadenceFittedPopover`'s `width: 230` over rows at a fixed
    /// 14 — is converted, so it is asserted in
    /// `theCompactEyebrowNoLongerOutgrowsTheChoiceRowsUnderIt` and in
    /// `CadenceChoicePopoverLargeTextLayoutTests` instead. What is left here is the panel that
    /// stayed pinned, and the numbers below are what it would do if it were opted in before
    /// `CadenceTagChip` grows with it: under `.enabled` both boxes overflow at the accessibility
    /// sizes, under `.fixed` neither moves at all.
    @Test("The pinned pickers would overflow their literal boxes if they scaled")
    func theRigidPickerBoxesCannotHoldTheirTypeOnceItScales() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let tagPicker = try read("Cadence/iOS/iOSTaskDetailComponents.swift")
        // Non-vacuity: the numbers below are these literals. If the geometry is ever made
        // size-aware, this fails first and asks for the assertion to be rewritten rather than
        // quietly measuring numbers the file no longer draws.
        #expect(tagPicker.contains(".frame(width: 260, height: 340)"))
        #expect(tagPicker.contains(".frame(width: 40, height: 40)"))
        #expect(tagPicker.contains("minHeight: 44"))

        let plusButtonSide: CGFloat = 40
        let tagRowHeight: CGFloat = 44

        var overflowingSizes: [DynamicTypeSize] = []
        for size in DynamicTypeSize.allCases {
            let glyph = CadenceTypeScale.size(.fieldLabel, at: size, scaling: .enabled)
            let rowLine = CadenceTypeScale.lineHeight(.rowTitle, at: size, scaling: .enabled)
            if glyph > plusButtonSide || rowLine > tagRowHeight { overflowingSizes.append(size) }

            // The pinned answer, at the same size, for the same two boxes.
            #expect(CadenceTypeScale.size(.fieldLabel, at: size, scaling: .fixed) < plusButtonSide)
            #expect(CadenceTypeScale.lineHeight(.rowTitle, at: size, scaling: .fixed) < tagRowHeight)
        }

        #expect(overflowingSizes.contains(.accessibility5))
        #expect(overflowingSizes.count >= 2,
                "if only one size overflowed, the panel was close to fitting and the pin is cosmetic")
        #expect(!overflowingSizes.contains(.large),
                "the default size must be unaffected or T-1364's conversion was never a refactor")
    }

    /// **The leak T-1398 found, now closed by conversion rather than by pinning.**
    ///
    /// The group heading in `iOSContainerChoicePopover` is a `SectionEyebrowLabel`, which reads the
    /// scaling environment; the rows under it were a fixed `.system(size: 14)`. At `accessibility5`
    /// a 9pt eyebrow resolves to 28.06pt over rows that had not moved — a heading nearly twice the
    /// size of what it heads.
    ///
    /// The row's title is `.rowTitle` now, so the two move together. That is the assertion: the
    /// eyebrow is still **smaller** than the rows it heads at every size, which is the relationship
    /// a heading of this tier is supposed to have and the one that broke when only one of them
    /// could grow.
    @Test("The group heading stays smaller than the rows it heads, at every text size")
    func theCompactEyebrowNoLongerOutgrowsTheChoiceRowsUnderIt() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let picker = try read("Cadence/Shared/Components/CadenceChoicePicker.swift")
        // Non-vacuity: the base below is the one the panel actually draws.
        #expect(picker.contains("static let titleSize: CGFloat = 14"),
                "the choice row's title base moved, so this comparison is stale")
        #expect(picker.contains(".cadenceFont(.rowTitle)"),
                "the choice row's title stopped going through the adapter")

        let eyebrowBase = SectionEyebrowLabel.compactFontSize
        #expect(eyebrowBase == 9)

        var widerThanItsRows: [DynamicTypeSize] = []
        for size in DynamicTypeSize.allCases {
            let eyebrow = CadenceTypeScale.size(.sectionLabel, base: eyebrowBase, at: size, scaling: .enabled)
            let rowTitle = CadenceTypeScale.size(
                .rowTitle,
                base: CadenceChoicePopoverMetrics.titleSize,
                at: size,
                scaling: .enabled
            )
            if eyebrow >= rowTitle { widerThanItsRows.append(size) }
        }
        #expect(widerThanItsRows.isEmpty,
                "the heading outgrows its own rows at \(widerThanItsRows)")

        // And the pre-conversion comparison, kept so the number this closed is still on record: a
        // row frozen at its base is what the eyebrow used to be measured against, and it lost.
        let frozenRow = CadenceChoicePopoverMetrics.titleSize
        let eyebrowAtMax = CadenceTypeScale.size(.sectionLabel, base: eyebrowBase, at: .accessibility5, scaling: .enabled)
        #expect(eyebrowAtMax > frozenRow)
        #expect(eyebrowAtMax > 2 * eyebrowBase)
    }

    // MARK: - The sweep

    /// Every rigid picker the two converted workflows open declares its own scaling.
    ///
    /// The declaration lives on the type that owns the rigid frame, not at the thirteen
    /// `.popover(isPresented:)` call sites, because the frame and the font have to agree and only
    /// the panel knows both. `CadenceFittedPopover` covers `iOSChoicePopoverList` and
    /// `iOSContainerChoicePopover`, which are typealiases onto it.
    @Test("Every picker presented from a converted workflow states its typography scaling")
    func everyPresentedPickerDeclaresItsOwnTypographyScaling() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        for (type, panel) in Self.presentedPickers.sorted(by: { $0.key < $1.key }) {
            let source = try read(panel.path)
            #expect(source.contains("struct \(type)"), "\(panel.path) no longer declares \(type)")
            #expect(source.contains(panel.scope),
                    "\(type) does not declare \(panel.scope), so it inherits its scaling from whoever presents it (T-1398)")
            // Exactly one answer per panel: a file carrying both says nothing.
            let other = Self.scopeModifiers.first { $0 != panel.scope }
            #expect(!source.contains(other ?? ""),
                    "\(type) declares both scopes, so the panel states no answer")
        }
        #expect(Self.presentedPickers.count == 4)
        // Both answers are represented, so a blanket flip in either direction fails here rather
        // than reading as four panels agreeing.
        let scopes = Set(Self.presentedPickers.values.map(\.scope))
        #expect(scopes == Set(Self.scopeModifiers))
    }

    /// And the list above is the tree's, re-derived: no `.popover` in a converted workflow opens
    /// something that has not declared.
    ///
    /// A sixth picker added to the create or detail sheet fails here rather than shipping a panel
    /// that grows its labels inside a literal frame.
    @Test("No popover in a converted workflow opens an undeclared picker")
    func everyPopoverInAConvertedWorkflowOpensADeclaredPicker() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        // The typealiased spellings the iOS call sites actually use.
        let declared: Set<String> = [
            "CadenceFittedPopover", "iOSFittedPopover",
            "CadenceChoicePopoverList", "iOSChoicePopoverList",
            "iOSContainerChoicePopover",
            "EstimatePickerPopoverContent",
            "CadenceQuickDatePopover",
            "iOSTaskTagPickerPopover",
        ]

        var found: [String] = []
        var popoverCount = 0
        for path in Self.convertedWorkflowFiles {
            let lines = try read(path).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() where line.contains(".popover(isPresented:") {
                popoverCount += 1
                // The content type is the first capitalised identifier on one of the next lines.
                let window = lines[(index + 1)..<min(index + 4, lines.count)]
                let opened = window.compactMap { candidate -> String? in
                    declared.first { candidate.contains("\($0)(") }
                }.first
                let named = try #require(opened,
                                         "\(path):\(index + 1) opens a picker this sweep does not know")
                found.append(named)
            }
        }

        #expect(popoverCount == 15, "the workflows' popover count moved; re-derive the list")
        #expect(Set(found).count >= 4, "the sweep matched one type thirteen times, which proves nothing")
    }

    /// **A panel may only opt in in the same change that makes its geometry size-aware**, which is
    /// the whole reason the scope is an environment value rather than a flag. So the two panels
    /// that are still rigid must still say so.
    ///
    /// `CadenceQuickDatePopover` is 34pt day cells and a 256pt panel; `iOSTaskTagPickerPopover` is
    /// a `260 × 340` frame around rows made of an unconverted `CadenceTagChip`. Neither may carry
    /// `.cadenceScaledTypography()` while that is true, and `CadenceQuickDateGridScaleTests` /
    /// `theRigidPickerBoxesCannotHoldTheirTypeOnceItScales` are what price each one.
    @Test("The two panels that are still rigid did not opt themselves in")
    func theStillRigidPanelsDidNotOptIn() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let pinned = Self.presentedPickers.filter { $0.value.scope == ".cadenceFixedTypography()" }
        #expect(pinned.count == 2, "the set of pinned panels moved without this test being told")
        for (type, panel) in pinned {
            let source = try read(panel.path)
            #expect(!source.contains(".cadenceScaledTypography()"),
                    "\(type) opted a rigid panel in instead of out")
        }
    }
}
