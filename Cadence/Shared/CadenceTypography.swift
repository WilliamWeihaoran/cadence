import SwiftUI

/// The semantic typography roles Cadence actually draws, and the one place a point size becomes a
/// `Font`.
///
/// **Why a role rather than a number.** Before T-1364 every piece of text in the app was
/// `.font(.system(size: <literal>))`: 1,160 numeric literals, zero `ScaledMetric`, zero
/// `dynamicTypeSize`. The literals are not the defect on their own — a custom type ramp is allowed,
/// and Apple documents semantic styles as a starting point rather than a requirement. The defect is
/// that **a static number cannot observe the environment it is drawn in**. A body-font constant
/// declared on `Theme` as a `static let` would be the same defect with a token's name on it: it is
/// resolved once, at the type that declares it, with no view and therefore no
/// `\.dynamicTypeSize` in scope. Only a
/// `View`/`ViewModifier` — something SwiftUI re-evaluates when the environment changes — can read
/// the reader's text size, which is why the adapter is a modifier and `Theme` keeps colour alone.
///
/// **The roles were derived from the tree, not adopted from a list.** Every `.system(size:` site
/// under `Cadence/` was classified by what it fonts: 737 `Text`, 309 `Image` glyphs, 59 text
/// fields, 12 `Label`s. Nine size/weight pairs account for most of the text-bearing ones, and each
/// of the nine already had a name somewhere in the repo or an obvious one:
///
/// | role | base | where the base already lived |
/// | --- | --- | --- |
/// | `editorTitle` | 22 | `iOSEditorSheetMetrics.titleSize` — three sheets read it |
/// | `composerTitle` | 20 | the create sheet's one field |
/// | `bodyText` | 15 | prose and note fields |
/// | `fieldValue` | 15 | `CadenceValueTileMetrics.valueFontSize` |
/// | `rowTitle` | 14 | editable row and subtask titles |
/// | `controlLabel` | 13 | button, chip and notice labels — the largest text cluster (64 sites) |
/// | `fieldLabel` | 13 | secondary editable fields |
/// | `metadata` | 12 | hints and captions (48 sites) |
/// | `sectionLabel` | 10 | `SectionEyebrowLabel.fontSize` |
///
/// A role owns **the curve and a default base**, not the only base. Sites that already have a named
/// constant keep it and pass it in — `SectionEyebrowLabel.Size.compact` is 9pt and stays 9pt,
/// `iOSTaskAttributeChipSize.fontSize` is 13 or 11 and stays so. That is the difference between an
/// adapter and a second set of literals wearing a token's name: nothing here renames an existing
/// decision, it only makes it observable.
///
/// Glyphs use the same modifier with the companion text's role, because a glyph beside a label has
/// to grow with the label or the two stop lining up. There is no separate glyph curve.
nonisolated enum CadenceTypographyRole: String, CaseIterable, Sendable {
    /// The name of the thing a sheet exists to edit. `iOSEditorSheetMetrics.titleSize`.
    case editorTitle
    /// The one field the create sheet exists to fill in.
    ///
    /// **A documented outlier, not a second opinion this ticket settled.** The composer draws its
    /// title at 20/semibold while the three editor sheets draw theirs at 22/bold from one constant.
    /// By this repo's own standard that is a fourth spelling, but changing it is a design decision
    /// about how loud a draft title is, and T-1364 is about scaling. It is filed rather than
    /// quietly converged; see `docs/TODO.md`.
    case composerTitle
    /// Prose: a notes field, a paragraph, anything read rather than scanned.
    case bodyText
    /// The answer a field currently holds. `CadenceValueTileMetrics.valueFontSize`.
    case fieldValue
    /// The editable title of a row or subtask.
    case rowTitle
    /// What a button, chip or inline notice says. The largest single cluster in the tree.
    case controlLabel
    /// A secondary editable field — the "New tag" entry, a nested value field.
    case fieldLabel
    /// A hint, a count, a caption: text that explains other text.
    case metadata
    /// The uppercase kerned eyebrow above a group. `SectionEyebrowLabel.fontSize`.
    case sectionLabel

    /// The size this role draws at when nothing overrides it, at the default text size.
    ///
    /// Each one is the number the tree already drew, so converting a call site is a no-op at
    /// `DynamicTypeSize.large` and the conversion can be reviewed as a refactor.
    var baseSize: CGFloat {
        switch self {
        case .editorTitle: 22
        case .composerTitle: 20
        case .bodyText: 15
        case .fieldValue: 15
        case .rowTitle: 14
        case .controlLabel: 13
        case .fieldLabel: 13
        case .metadata: 12
        case .sectionLabel: 10
        }
    }

    var weight: Font.Weight {
        switch self {
        case .editorTitle: .bold
        case .composerTitle: .semibold
        case .bodyText: .regular
        case .fieldValue: .semibold
        case .rowTitle: .medium
        case .controlLabel: .semibold
        case .fieldLabel: .medium
        case .metadata: .medium
        case .sectionLabel: .semibold
        }
    }

    /// The Apple text style whose published ramp this role follows.
    ///
    /// It is chosen by *size*, not by name: a 22pt title is Title 2's size and grows the way Title 2
    /// grows. This is the only thing the style is used for — nothing here renders a semantic style,
    /// because that would throw away the custom ramp rather than scale it.
    var textStyle: Font.TextStyle {
        switch self {
        case .editorTitle: .title2
        case .composerTitle: .title3
        case .bodyText: .subheadline
        case .fieldValue: .subheadline
        case .rowTitle: .subheadline
        case .controlLabel: .footnote
        case .fieldLabel: .footnote
        case .metadata: .caption
        case .sectionLabel: .caption2
        }
    }
}

/// Whether the view tree under here has been converted to scale.
///
/// **This is the migration boundary, and it is an environment value on purpose.** T-1364's own
/// brief is explicit that a scattering of enlarged labels inside rigid controls is worse than
/// nothing: a `SectionEyebrowLabel` that grows to 33pt inside a task row whose height is still a
/// literal 44 does not help anybody read. But the eyebrow is one shared component drawn by 60-odd
/// files, so it cannot be converted "for the composer only" without forking it — and forking a
/// shared component is the thing this repo spends most of its guides unpicking.
///
/// So the component is converted once and asks the *environment* whether the surface around it has
/// been. A converted workflow says `.cadenceScaledTypography()` at its root and everything inside it
/// scales, including shared components; every other surface is untouched, at the same numbers, with
/// no second copy of anything. The migration finishes by flipping this default to `.enabled` and
/// deleting the modifier, not by another sweep through the call sites.
///
/// **It crosses a `.sheet` / `.popover` / `.fullScreenCover`, and `\.dynamicTypeSize` does not —
/// which is the asymmetry that makes an *inherited* boundary unsafe (T-1398).** T-1364 left this
/// unverified in both directions. It was measured rather than reasoned about, with a standalone
/// SwiftUI binary that installs a custom `EnvironmentKey` of this exact shape at a root and reads it
/// back from presented content:
///
/// - **iOS 26.5 simulator, Xcode 27.0 (27A266a), system text size `accessibility-extra-extra-extra-large`:**
///   the custom value reads `enabled` inside `.sheet`, `.popover` **and** `.fullScreenCover`, and
///   `\.dynamicTypeSize` reads `accessibility5` in all three.
/// - **macOS 27.0, same binary:** the custom value reads `enabled` inside `.sheet` and `.popover`.
/// - **The half that surprises:** a root that says `.dynamicTypeSize(.accessibility3)` does **not**
///   pass that override through. Presented content is reseeded from the host window's traits — it
///   read `accessibility5` (the system setting) on iOS and `large` on macOS, never the root's `3`.
///
/// So the two halves of the pair arrive from different places across a presentation boundary: the
/// migration flag is **inherited from the presenter** while the size that makes it bite is
/// **re-read from the system**. That is the worst combination available, and it was live at HEAD:
/// the pickers the converted create and detail sheets open are rigid — `CadenceFittedPopover` is a
/// literal `width: 250`, `iOSTaskTagPickerPopover` a literal `260 × 340` — and each of them draws at
/// least one converted component, so at an accessibility size their labels grew inside geometry that
/// could not.
///
/// **Which is why a presented surface states its scaling instead of inheriting it.** Whether the
/// framework propagates is a *toolchain* property — CI runs Xcode 26 and this was only observed on
/// 27, and T-1279/T-1296 are what pinning either answer costs — so the fix may not depend on the
/// answer. A view that pins its own width or height says `.cadenceFixedTypography()` or
/// `.cadenceScaledTypography()` in its own body, and then it renders the same on both toolchains
/// whichever way propagation goes. `CadencePresentedTypographyBoundaryTests` is what holds that.
///
/// **T-1410 answered the question the pin postponed, and the four panels do not answer it alike.**
/// `CadenceFittedPopover` and `EstimatePickerPopoverContent` are converted: they say
/// `.cadenceScaledTypography()`, and their geometry therefore names `.enabled` **literally** rather
/// than reading a flag back — the panel *is* the declaration, and a panel that consulted the
/// environment for its own frame would be inheriting the answer again one level down, while the
/// fonts inside it read the scope it installs. `CadenceQuickDatePopover` and
/// `iOSTaskTagPickerPopover` stay `.fixed`, for reasons that are arithmetic rather than appetite: a
/// month is seven columns wide, and every row of the tag picker is a `CadenceTagChip` that twelve
/// surfaces draw. `CadencePickerLargeTextLayoutTests` prices both decisions.
nonisolated enum CadenceTypographyScaling: String, CaseIterable, Sendable {
    /// Draw at the base size whatever the reader's text size is — the app's behaviour before
    /// T-1364, and still the behaviour of every surface that has not been converted and tested.
    case fixed
    /// Follow `\.dynamicTypeSize`.
    case enabled
}

private struct CadenceTypographyScalingKey: EnvironmentKey {
    static let defaultValue: CadenceTypographyScaling = .fixed
}

extension EnvironmentValues {
    var cadenceTypographyScaling: CadenceTypographyScaling {
        get { self[CadenceTypographyScalingKey.self] }
        set { self[CadenceTypographyScalingKey.self] = newValue }
    }
}

/// Point sizes and growths, as arithmetic rather than as rendering.
///
/// Every number a converted view draws — the font, the plate it sits on, the height of the row
/// around it — comes from here, so a test can ask what the largest supported text size produces
/// without a screen. That is the whole reason this is a pure `enum` of functions and not
/// `@ScaledMetric`.
///
/// **Why not `@ScaledMetric(relativeTo:)`, which is the obvious answer.** It was the first shape
/// tried and it fails two requirements of this ticket at once. It hands back a scaled *number* only
/// inside a rendering `DynamicProperty`, so the layout arithmetic that has to agree with the font —
/// `CadenceTaskComposerLayout`, `CadenceValueTileMetrics.minHeight` — cannot read the same value the
/// font was built from, and the two drift exactly the way the radius and the font drifted before.
/// And the test target builds on macOS, where `UIFontMetrics` does not exist and
/// `\.dynamicTypeSize` never leaves `.large`, so an assertion about accessibility sizes could not be
/// written at all. One curve, stated once, read by both the font and the layout, is what makes
/// "does the composer clip at the largest size" a question a unit test can answer.
///
/// The curve itself is Apple's, not invented: `bodyPointSizes` is the published Dynamic Type ramp
/// for the Body text style, and each role's ceiling is its own style's published ramp.
nonisolated enum CadenceTypeScale {

    // MARK: - Apple's published ramps

    /// The Body text style's point size at each `DynamicTypeSize`, as Apple publishes it.
    ///
    /// Stated as points rather than as multipliers so it stays recognisable as the table it is
    /// copied from. `.large` is 17, which is what makes an unconverted size a no-op.
    static let bodyPointSizes: [DynamicTypeSize: CGFloat] = [
        .xSmall: 14,
        .small: 15,
        .medium: 16,
        .large: 17,
        .xLarge: 19,
        .xxLarge: 21,
        .xxxLarge: 23,
        .accessibility1: 28,
        .accessibility2: 33,
        .accessibility3: 40,
        .accessibility4: 47,
        .accessibility5: 53,
    ]

    /// Body at the default size. The denominator of every multiplier below.
    static let bodyBasePointSize: CGFloat = 17

    /// How far a style is allowed to follow the Body ramp, from its own published one: the style's
    /// `accessibility5` size over its `large` size.
    ///
    /// Apple's ramps are **not** parallel — Body triples (17 → 53) while Large Title grows by 29%
    /// (34 → 44), because a headline that tripled would leave no room for anything under it. Taking
    /// `min(bodyRamp, ceiling)` reproduces that flattening closely enough to lay out against, and
    /// it errs on the large side at the middle sizes (Title 2 at `accessibility1` comes out 6%
    /// bigger here than Apple's own table). Erring large is the safe direction: layout that fits
    /// this model fits what is drawn.
    static func maximumGrowth(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 44 / 34
        case .title: 53 / 28
        case .title2: 49 / 22
        case .title3: 47 / 20
        case .headline: 53 / 17
        case .body: 53 / 17
        case .callout: 44 / 16
        case .subheadline: 42 / 15
        case .footnote: 38 / 13
        case .caption: 37 / 12
        case .caption2: 37 / 11
        @unknown default: 53 / 17
        }
    }

    // MARK: - The curve

    /// The Body ramp as a multiplier of its default size. `1` at `.large`.
    static func bodyMultiplier(at dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        (bodyPointSizes[dynamicTypeSize] ?? bodyBasePointSize) / bodyBasePointSize
    }

    /// What a role's size is multiplied by at a given reader text size.
    ///
    /// `1` whenever scaling is off, and `1` at `.large` whether it is on or not — which is why a
    /// converted call site renders identically to the literal it replaced, and why macOS (where
    /// `\.dynamicTypeSize` is always `.large` unless something sets it) is unchanged by this ticket.
    static func multiplier(
        _ role: CadenceTypographyRole,
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CGFloat {
        guard scaling == .enabled else { return 1 }
        return min(bodyMultiplier(at: dynamicTypeSize), maximumGrowth(for: role.textStyle))
    }

    /// The point size a role draws at, from a base the call site may override.
    static func size(
        _ role: CadenceTypographyRole,
        base: CGFloat? = nil,
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CGFloat {
        (base ?? role.baseSize) * multiplier(role, at: dynamicTypeSize, scaling: scaling)
    }

    /// How many points a role's text has *gained* over its base.
    ///
    /// The layout primitive. A plate around a label grows by the text's gain rather than by the
    /// text's multiplier: a 30pt chip holding 13pt text is 17pt of padding and corner, and padding
    /// does not need to triple for the glyphs inside it to stop overlapping. Proportional growth is
    /// what turns an accessibility size into three screens of chrome.
    static func growth(
        _ role: CadenceTypographyRole,
        base: CGFloat? = nil,
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CGFloat {
        let base = base ?? role.baseSize
        return size(role, base: base, at: dynamicTypeSize, scaling: scaling) - base
    }

    /// A fixed height that has to keep holding its text: the height plus what the text gained.
    static func height(
        _ base: CGFloat,
        holding role: CadenceTypographyRole,
        textBase: CGFloat? = nil,
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CGFloat {
        base + growth(role, base: textBase, at: dynamicTypeSize, scaling: scaling)
    }

    /// The line box SwiftUI lays a single line of this size out in.
    ///
    /// `1.2` is the ratio `iOSTaskInspectorMetrics.titleLineHeight` has always used to place the
    /// completion circle against the first line of a title; it is stated here so the inspector and
    /// every height computed from a font size read one number.
    static let lineHeightRatio: CGFloat = 1.2

    static func lineHeight(
        _ role: CadenceTypographyRole,
        base: CGFloat? = nil,
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CGFloat {
        size(role, base: base, at: dynamicTypeSize, scaling: scaling) * lineHeightRatio
    }

    /// Where the reader's text size stops being a preference and starts being an accessibility
    /// setting.
    ///
    /// Used for the decisions that are about *shape* rather than about size: a value that is one
    /// line at every ordinary size and is allowed two here, a shrink-to-fit that has to be dropped
    /// because shrinking text back down is precisely what the reader asked not to happen.
    static func isAccessibilitySize(_ dynamicTypeSize: DynamicTypeSize) -> Bool {
        dynamicTypeSize >= .accessibility1
    }
}

// MARK: - The modifier

private struct CadenceScaledFont: ViewModifier {
    let role: CadenceTypographyRole
    let base: CGFloat?
    let weight: Font.Weight?
    let design: Font.Design

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling

    func body(content: Content) -> some View {
        content.font(
            .system(
                size: CadenceTypeScale.size(role, base: base, at: dynamicTypeSize, scaling: scaling),
                weight: weight ?? role.weight,
                design: design
            )
        )
    }
}

private struct CadenceScaledTypographyScope: ViewModifier {
    func body(content: Content) -> some View {
        content.environment(\.cadenceTypographyScaling, .enabled)
    }
}

private struct CadenceFixedTypographyScope: ViewModifier {
    func body(content: Content) -> some View {
        content.environment(\.cadenceTypographyScaling, .fixed)
    }
}

extension View {

    /// Fonts this view by role, at whatever size the reader's text setting calls for.
    ///
    /// The replacement for `.font(.system(size:weight:))` on a converted surface. Pass `base` where
    /// the size is already named somewhere — a metrics type, a size enum — so this changes how the
    /// number is *resolved* without moving where it is decided.
    func cadenceFont(
        _ role: CadenceTypographyRole,
        base: CGFloat? = nil,
        weight: Font.Weight? = nil,
        design: Font.Design = .default
    ) -> some View {
        modifier(CadenceScaledFont(role: role, base: base, weight: weight, design: design))
    }

    /// Marks everything below as a surface that has been converted **and laid out** for larger text.
    ///
    /// Say it once at the root of a workflow, not per control. Adding it to a screen whose heights
    /// are still literals is the failure mode `CadenceTypographyScaling` exists to prevent, so it
    /// belongs in the same change that makes that screen's geometry size-aware.
    func cadenceScaledTypography() -> some View {
        modifier(CadenceScaledTypographyScope())
    }

    /// Marks everything below as **not** laid out for larger text, whatever the surface above said.
    ///
    /// **This is not the default wearing a name; it is the default made unconditional.** The
    /// environment default is `.fixed`, so an ordinary unconverted screen needs nothing. What needs
    /// this is a view that is *presented* from a converted one — and, since T-1410, one that has
    /// been *looked at and left pinned on purpose*, which is the more useful of the two readings:
    /// it is the only way a panel can say "this was considered and the answer is no" rather than
    /// merely not having been reached yet. Both remaining declarers argue that in their own bodies.
    /// The original case: T-1398 measured that a custom
    /// environment value **does** cross `.sheet`, `.popover` and `.fullScreenCover`, while
    /// `\.dynamicTypeSize` is reseeded from the host window rather than inherited. So a rigid picker
    /// opened from the composer arrived carrying `.enabled` and met the reader's real text size on
    /// the other side — the one combination that grows type inside geometry that cannot follow.
    ///
    /// The rule it exists to make statable: **a view that pins its own width or height declares its
    /// typography scaling.** Declared rather than inherited, the answer no longer depends on how
    /// this toolchain propagates environment across a presentation — which is the part that may not
    /// be pinned, because CI and this Mac are on different Xcodes.
    func cadenceFixedTypography() -> some View {
        modifier(CadenceFixedTypographyScope())
    }
}
