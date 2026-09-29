import SwiftUI

// MARK: - How a tag draws, as a decision rather than a call-site convention

/// How dense the surface drawing the chip is.
///
/// Two sizes, chosen by the *surface*, not by the platform: an editable strip or a picker row gets
/// `.regular`, a metadata line under a task row or on a kanban card gets `.compact`. macOS and iOS
/// answer that question the same way, which is the point — `iOSTagChip` and `TagChip` used to be
/// two different chips deciding it separately.
nonisolated enum CadenceTagChipSize: Hashable, CaseIterable {
    /// Editable tag strips, picker rows, the tag filter bar.
    case regular
    /// Dense metadata: task rows, kanban cards, note list rows.
    case compact
}

/// Whether the chip is acting as a toggle, and which way it is set.
///
/// `.none` is a plain display chip. The other two exist for the tag filter bar, which is the one
/// surface where a tag chip means "this filter is on/off" rather than "this thing carries this
/// tag" — keeping it in this enum is what stops that surface hand-rolling a fourth spelling of the
/// chip.
nonisolated enum CadenceTagChipSelection: Hashable, CaseIterable {
    case none
    case on
    case off
}

/// What is going to touch the remove control.
///
/// A parameter rather than a bare `#if os(iOS)` inside the metrics, so `CadenceTests` — which only
/// ever builds for macOS — can pin the touch numbers too. `.current` is the compile-time answer;
/// everything else takes it as input.
nonisolated enum CadenceTagChipInput: Hashable, CaseIterable {
    case pointer
    case touch

    static var current: CadenceTagChipInput {
        #if os(iOS)
        return .touch
        #else
        return .pointer
        #endif
    }
}

/// The whole state → appearance decision for a tag chip.
///
/// **`isArchived` is resolved here and nowhere else.** `Tag` carries `isArchived`, and before this
/// type existed only macOS drew it — iOS's chip was a coloured capsule with no archived branch at
/// all, so an archived tag on iPhone and iPad was pixel-identical to a live one. That is a fact the
/// model holds and the UI dropped, so it belongs in the chip's own resolution rather than in an
/// `opacity(tag.isArchived ? … : …)` re-derived per call site.
///
/// A tag's colour is user-owned (`Tag.colorHex`), so the chip spends it on **identity** — the dot,
/// the fill tint, the border — and keeps the *label* on `Theme` tokens, which is what leaves the
/// label free to carry **state**. The archived chip therefore drops the tag colour entirely and
/// goes neutral; that reads at a glance beside a live chip in a way a slightly lower opacity does
/// not.
///
/// **T-1412: how this type answers the reader's text size, and why it is two stored properties
/// rather than nine `at:scaling:` signatures.**
///
/// The chip is drawn by twelve surfaces across both platforms and **eleven of them are not
/// converted**, so this conversion had to be safe to land ahead of its own call sites. It is, for
/// exactly one reason: the two properties default to `.large` / `.fixed`, and
/// `CadenceTypeScale.multiplier` returns `1` whenever scaling is `.fixed` — *at every one of the
/// twelve `DynamicTypeSize` cases*, not only at the default. So an unconverted surface gets the
/// literal it drew before, and the eleven that have no `.cadenceScaledTypography()` root above them
/// render identically. `CadenceTagChipScaleTests.everyChipMetricIsItsOldLiteralUnderFixedScaling`
/// is what holds that, over both chip sizes, both inputs and all twelve sizes.
///
/// **Three judgements this type makes rather than inherits**, each measured rather than assumed:
///
/// 1. **The dot and the `x` are content, so they scale *proportionally*; the paddings do not.**
///    This is the one place the repo's additive rule is the wrong one, and the arithmetic says so:
///    6pt of dot grown additively by what a 12pt label gains is a **27pt dot** beside 37pt of text,
///    which is a bullet turned into a disc. A dot is a glyph the label's size chooses, the same way
///    a `cadenceFont` glyph passes its companion label's role — so it takes the *multiplier*.
///    `horizontalPadding`, `verticalPadding`, `contentSpacing` and `cornerRadius` stay literal,
///    which is the additive rule in its usual form: a plate keeps its chrome and grows by its text.
/// 2. **`maximumLabelWidth` is a cap, and a cap grows additively or not at all.** Proportional
///    growth puts the regular cap at **400pt** at `accessibility5` — wider than the 375pt phone the
///    chip has to fit on, so the "cap" would have stopped capping anything. Additive gives 155pt,
///    and the honest consequence is stated rather than hidden: **a grown chip shows fewer
///    characters than a small one does**, because the cap is a width and the text inside it tripled.
///    That is the right trade for a *tag* — the dot carries identity, the full name is in
///    `accessibilityLabel(for:)` and in `help`, and the alternative is a chip that eats the row it
///    is metadata on. `CadenceTagPickerMetrics` is what proves the capped chip still fits its panel.
/// 3. **The strip spacings fall out of `removeHitOverhang()` and therefore *shrink*.** They are not
///    decoration: they exist because a 44pt touch target grown around a 22pt drawn control spills
///    past the chip. Once the drawn control is itself bigger than 44 there is no spill left, so the
///    overhang goes to zero and the spacing returns to its 6pt floor. A spacing that grew here
///    would be paying twice for a target the chip already covers.
nonisolated struct CadenceTagChipStyle: Equatable {
    /// Which colour the label takes. A `Theme` token, never the tag's own hex — see the type note.
    nonisolated enum LabelInk: Hashable, CaseIterable {
        /// `Theme.muted` — a plain, live chip.
        case muted
        /// `Theme.text` — a filter chip that is switched on.
        case emphasized
        /// `Theme.dim` — archived, or a filter chip switched off.
        case dimmed
    }

    let size: CadenceTagChipSize
    let selection: CadenceTagChipSelection
    let isArchived: Bool
    let input: CadenceTagChipInput
    /// The reader's text size, as the chip's own drawing environment reported it.
    let dynamicTypeSize: DynamicTypeSize
    /// Whether the surface drawing this chip has been converted **and laid out** for larger text.
    /// `.fixed` — the default, and the answer eleven of the twelve draw sites still give — puts
    /// every metric below back on the literal it replaced.
    let scaling: CadenceTypographyScaling

    init(
        size: CadenceTagChipSize = .regular,
        selection: CadenceTagChipSelection = .none,
        isArchived: Bool,
        input: CadenceTagChipInput = .current,
        dynamicTypeSize: DynamicTypeSize = .large,
        scaling: CadenceTypographyScaling = .fixed
    ) {
        self.size = size
        self.selection = selection
        self.isArchived = isArchived
        self.input = input
        self.dynamicTypeSize = dynamicTypeSize
        self.scaling = scaling
    }

    // MARK: State → appearance

    /// `false` for an archived tag: the fill, the border and the dot all fall back to neutral
    /// `Theme` tokens. This is the single fact every "does this look archived?" question reduces to.
    var usesTagColor: Bool { !isArchived }

    var labelInk: LabelInk {
        if isArchived { return .dimmed }
        switch selection {
        case .none: return .muted
        case .on:   return .emphasized
        case .off:  return .dimmed
        }
    }

    /// Alpha of the chip's fill — of the tag colour when `usesTagColor`, of `Theme.surfaceElevated`
    /// otherwise.
    var fillOpacity: Double {
        if isArchived { return 0.5 }
        switch selection {
        case .none: return 0.14
        case .on:   return 0.20
        case .off:  return 0.07
        }
    }

    /// Alpha of the chip's 1pt border — of the tag colour when `usesTagColor`, of `Theme.border`
    /// otherwise.
    var strokeOpacity: Double {
        if isArchived { return 0.55 }
        switch selection {
        case .none: return 0.35
        case .on:   return 0.42
        case .off:  return 0.18
        }
    }

    /// Applied to the finished chip. An archived tag recedes as a whole, on top of losing its colour.
    var chipOpacity: Double { isArchived ? 0.68 : 1 }

    // MARK: Metrics

    /// **The role every figure in this type is derived from.** Both chip sizes are `metadata`'s
    /// tier — 12 is the role's own default base and 10 is a base this site already owned — so they
    /// are one role at two bases rather than two curves, and the compact chip stays smaller than
    /// the regular one at every text size by construction.
    static let labelRole: CadenceTypographyRole = .metadata

    /// The label size before the reader's text size is applied: the literal the chip drew at
    /// before T-1412, and the `base:` every derivation below passes.
    var baseFontSize: CGFloat {
        switch size {
        case .regular: return 12
        case .compact: return 10
        }
    }

    var fontSize: CGFloat {
        CadenceTypeScale.size(Self.labelRole, base: baseFontSize, at: dynamicTypeSize, scaling: scaling)
    }

    /// What the label gained over its base. The additive term for anything that is a *box* around
    /// the label rather than content beside it.
    var labelGrowth: CGFloat {
        CadenceTypeScale.growth(Self.labelRole, base: baseFontSize, at: dynamicTypeSize, scaling: scaling)
    }

    /// What the label was multiplied by. The term for content that has to stay in proportion to
    /// the text — see judgement 1 on this type.
    var labelMultiplier: CGFloat {
        CadenceTypeScale.multiplier(Self.labelRole, at: dynamicTypeSize, scaling: scaling)
    }

    var fontWeight: Font.Weight {
        switch size {
        case .regular: return .medium
        case .compact: return .semibold
        }
    }

    var baseDotDiameter: CGFloat {
        switch size {
        case .regular: return 6
        case .compact: return 5
        }
    }

    /// **Proportional, not additive** — the one figure here that is. The dot is the chip's identity
    /// channel and is read *as a bullet beside the name*, so it has to stay in the name's
    /// proportion; grown by the label's gain instead it would be a 27pt disc at `accessibility5`,
    /// larger than the 18.5pt this produces and larger than half the line it sits on.
    var dotDiameter: CGFloat {
        baseDotDiameter * labelMultiplier
    }

    var contentSpacing: CGFloat {
        switch size {
        case .regular: return 5
        case .compact: return 4
        }
    }

    var horizontalPadding: CGFloat {
        switch size {
        case .regular: return 8
        case .compact: return 6
        }
    }

    var verticalPadding: CGFloat {
        switch size {
        case .regular: return 5
        case .compact: return 3
        }
    }

    var cornerRadius: CGFloat {
        switch size {
        case .regular: return 7
        case .compact: return 5
        }
    }

    /// **The truncation rule.** A tag name is free text, so without a cap one long name pushes the
    /// rest of a row's metadata off the end — and on iOS, where these strips wrap rather than
    /// scroll, off the end means unreachable. Past this width the label truncates with a tail
    /// ellipsis and the chip stops growing.
    var baseMaximumLabelWidth: CGFloat {
        switch size {
        case .regular: return 130
        case .compact: return 92
        }
    }

    /// **A cap grows additively or it stops being a cap** (T-1412, judgement 2).
    ///
    /// Multiplying it is the obvious move and it is measured to be wrong: 130 × the `metadata`
    /// multiplier is **400pt at `accessibility5`**, against the 375pt of the narrowest iPhone this
    /// app runs on — so the cap would sit outside every container it is supposed to protect and the
    /// truncation rule would be dead code at exactly the size a reader needs the rest of the row.
    /// Additive gives 155, which is the chip growing by what its own text gained.
    ///
    /// **What that costs, said out loud:** the text tripled and the box it may occupy grew by a
    /// fifth, so a grown chip truncates *sooner in characters* than a small one. That is the
    /// intended trade rather than an oversight — the chip is metadata, the coloured dot carries the
    /// identity, and `accessibilityLabel(for:)` and `help` both carry the untruncated name — and it
    /// is what keeps the chip inside `CadenceTagPickerMetrics.width(at:scaling:)` at every size.
    var maximumLabelWidth: CGFloat {
        CadenceTypeScale.height(
            baseMaximumLabelWidth,
            holding: Self.labelRole,
            textBase: baseFontSize,
            at: dynamicTypeSize,
            scaling: scaling
        )
    }

    // MARK: The remove control

    /// A finger is 44pt, per the platform's own guidance. Stated once so the target, the inset and
    /// the strip spacing derived from it cannot answer it separately.
    static let touchTargetSize: CGFloat = 44

    /// The drawn size of the `x` before the reader's text size is applied. Larger under touch
    /// because a finger is not a pointer — that *visual* difference is deliberate, and it is what
    /// keeps the expanded touch target from having to reach past the chip and into its neighbour.
    var baseRemoveControlSize: CGFloat {
        switch (input, size) {
        case (.touch, .regular):   return 22
        case (.touch, .compact):   return 18
        case (.pointer, .regular): return 14
        case (.pointer, .compact): return 12
        }
    }

    /// **Proportional, like the dot and for the same reason** (T-1412, judgement 1): the `x` is a
    /// glyph drawn *beside* the label, and the glyph inside it is already `removeControlSize × 0.42`
    /// — so the control is content and takes the label's multiplier, not its gain.
    var removeControlSize: CGFloat {
        baseRemoveControlSize * labelMultiplier
    }

    /// What the remove control must measure *to the touch*: never less than 44pt under a finger,
    /// and never less than what is drawn.
    ///
    /// The second half is what T-1412 added. Under a finger the drawn control passes 44 somewhere
    /// around `accessibility1`, and a target frozen at 44 there would be *smaller* than the button
    /// it is supposed to cover — the inset would go negative and the chip would clip its own `x`.
    var removeHitTargetSize: CGFloat {
        switch input {
        case .touch:   return max(Self.touchTargetSize, removeControlSize)
        case .pointer: return removeControlSize
        }
    }

    /// How far the remove control's hit area is grown beyond what is drawn, in every direction.
    /// Zero under a pointer.
    var removeHitInset: CGFloat {
        max(0, (removeHitTargetSize - removeControlSize) / 2)
    }

    /// Height of the chip, given its tallest piece of content.
    func chipHeight(hasRemoveControl: Bool) -> CGFloat {
        let labelHeight = ceil(fontSize * CadenceTypeScale.lineHeightRatio)
        let content = hasRemoveControl ? max(labelHeight, removeControlSize) : labelHeight
        return content + verticalPadding * 2
    }

    /// How far the remove control's hit area spills past the chip's own bounds. The control sits
    /// `horizontalPadding` in from the trailing edge and is vertically centred, so this is the
    /// clearance a neighbouring chip needs.
    func removeHitOverhang() -> (horizontal: CGFloat, vertical: CGFloat) {
        let horizontal = max(0, removeHitInset - horizontalPadding)
        let vertical = max(0, removeHitInset - (chipHeight(hasRemoveControl: true) - removeControlSize) / 2)
        return (horizontal, vertical)
    }

    // MARK: Strip spacing

    /// The spacing an **editable** strip of these chips must use.
    ///
    /// Not decoration: under touch the remove control's hit area is grown to 44pt and therefore
    /// spills past the chip, so a strip packed tighter than this hands taps aimed at one chip to
    /// its neighbour's remove button. An expanded, filled shape quietly eating the tap next to it
    /// is a failure mode this repo has shipped before, so the numbers live beside the ones that
    /// cause them and `CadenceTagChipStyleTests` pins the relationship.
    ///
    /// **They take the environment because they are derived from `removeHitOverhang()`, and they
    /// get *smaller* as the text grows** (T-1412, judgement 3). The spill exists only while the
    /// 44pt target is bigger than the drawn control; once the reader's text size has pushed the
    /// drawn `x` past 44 there is nothing spilling and both spacings return to
    /// `stripSpacingFloor`. The two arguments default to an unconverted surface, which is what the
    /// two macOS strips are and what keeps their call sites on the numbers they already drew.
    /// The floor both spacings fall back to once there is no spill left to clear.
    static let stripSpacingFloor: CGFloat = 6

    static func editableStripSpacing(
        for size: CadenceTagChipSize,
        input: CadenceTagChipInput = .current,
        at dynamicTypeSize: DynamicTypeSize = .large,
        scaling: CadenceTypographyScaling = .fixed
    ) -> CGFloat {
        let overhang = CadenceTagChipStyle(
            size: size, isArchived: false, input: input,
            dynamicTypeSize: dynamicTypeSize, scaling: scaling
        ).removeHitOverhang()
        return max(stripSpacingFloor, overhang.horizontal * 2)
    }

    static func editableStripLineSpacing(
        for size: CadenceTagChipSize,
        input: CadenceTagChipInput = .current,
        at dynamicTypeSize: DynamicTypeSize = .large,
        scaling: CadenceTypographyScaling = .fixed
    ) -> CGFloat {
        let overhang = CadenceTagChipStyle(
            size: size, isArchived: false, input: input,
            dynamicTypeSize: dynamicTypeSize, scaling: scaling
        ).removeHitOverhang()
        return max(stripSpacingFloor, overhang.vertical * 2)
    }

    // MARK: Label

    /// `Tag.name` is free text and can be empty; the slug is the guaranteed-present fallback. iOS's
    /// chip did this and macOS's did not, so an unnamed tag drew as a bare coloured dot on one
    /// platform and a named chip on the other.
    static func displayName(for tag: Tag) -> String {
        displayName(name: tag.name, slug: tag.slug)
    }

    static func displayName(name: String, slug: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty { return trimmedName }
        let trimmedSlug = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedSlug.isEmpty ? "tag" : trimmedSlug
    }

    /// What a screen reader reads and a macOS tooltip shows. Archived is *spoken*, not only drawn —
    /// dimming is invisible to VoiceOver.
    static func accessibilityLabel(for tag: Tag) -> String {
        accessibilityLabel(name: tag.name, slug: tag.slug, isArchived: tag.isArchived)
    }

    static func accessibilityLabel(name: String, slug: String, isArchived: Bool) -> String {
        let resolved = displayName(name: name, slug: slug)
        return isArchived ? "\(resolved) (archived)" : resolved
    }
}

// MARK: - The chip

/// **The** tag chip, both platforms, every surface.
///
/// macOS drew a muted rounded rect and iOS a coloured capsule; the capsule lost, because it spent
/// the chip's only two colour channels — fill and label — on the same fact. A tag's `colorHex` is
/// user-chosen against one fixed near-black palette with no light variant, so a label rendered in
/// it is legible at the user's discretion rather than by construction; and with the label already
/// carrying identity there is nowhere left to put *state*, which is exactly why iOS never grew
/// archived dimming. The rounded rect keeps the label on a `Theme` token and lets the dot, the tint
/// and the border carry the colour — legible at any hue, with one channel left over for state.
struct CadenceTagChip: View {
    let tag: Tag
    var size: CadenceTagChipSize = .regular
    var selection: CadenceTagChipSelection = .none
    /// Supplied only by strips that can actually remove a tag. `nil` draws no control at all —
    /// which is what every chip nested inside a larger button must pass, since a button inside a
    /// button is not a thing either platform resolves the way a reader expects.
    var onRemove: (() -> Void)? = nil

    /// **The chip reads both halves of the pair itself rather than taking a parameter** (T-1412).
    /// Twelve surfaces draw it and eleven have no scaled root above them, so the environment's
    /// `.fixed` default *is* their answer and none of them needed editing. The two converted
    /// callers — the detail sheet's strip and `iOSTaskTagPickerPopover` — install `.enabled` above
    /// this and the chip picks it up with them.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var typographyScaling

    private var style: CadenceTagChipStyle {
        CadenceTagChipStyle(
            size: size,
            selection: selection,
            isArchived: tag.isArchived,
            dynamicTypeSize: dynamicTypeSize,
            scaling: typographyScaling
        )
    }

    private var tagColor: Color { Color(hex: tag.colorHex) }

    private var labelColor: Color {
        switch style.labelInk {
        case .muted:      return Theme.muted
        case .emphasized: return Theme.text
        case .dimmed:     return Theme.dim
        }
    }

    private var accentColor: Color { style.usesTagColor ? tagColor : Theme.dim }

    private var fillColor: Color {
        (style.usesTagColor ? tagColor : Theme.surfaceElevated).opacity(style.fillOpacity)
    }

    private var strokeColor: Color {
        (style.usesTagColor ? tagColor : Theme.border).opacity(style.strokeOpacity)
    }

    var body: some View {
        HStack(spacing: style.contentSpacing) {
            Circle()
                .fill(accentColor)
                .frame(width: style.dotDiameter, height: style.dotDiameter)

            Text(CadenceTagChipStyle.displayName(for: tag))
                // The same role and base `style.fontSize` resolves, so the label and every figure
                // derived from it cannot disagree about what size the text is.
                .cadenceFont(CadenceTagChipStyle.labelRole, base: style.baseFontSize, weight: style.fontWeight)
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: style.maximumLabelWidth, alignment: .leading)
                .accessibilityLabel(CadenceTagChipStyle.accessibilityLabel(for: tag))

            if let onRemove {
                removeButton(onRemove)
            }
        }
        .padding(.horizontal, style.horizontalPadding)
        .padding(.vertical, style.verticalPadding)
        .background(fillColor)
        .overlay(
            RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                .strokeBorder(strokeColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
        .opacity(style.chipOpacity)
        // `maximumLabelWidth` is a **cap**, and a bare `frame(maxWidth:)` is not one: it is
        // flexible upward, so in any container that offers more room — a picker row with a
        // trailing `Spacer`, say — a three-letter tag drew as a 130pt-wide chip with the name
        // stranded at its leading edge. Measured, not reasoned about. Fixing the width here rather
        // than at each strip is what makes the cap behave the same on every surface; the old macOS
        // chip carried the same `maxWidth` and only looked right because the two strips that used
        // it happened to be `fixedSize` themselves.
        .fixedSize(horizontal: true, vertical: false)
        .help(CadenceTagChipStyle.accessibilityLabel(for: tag))
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        let button = Button(action: action) {
            Image(systemName: "xmark")
                // Not a literal and not a second curve: `removeControlSize` has already been
                // scaled, and the glyph is a fixed fraction of the control it is centred in. A
                // `cadenceFont` here would apply the reader's multiplier a second time.
                .font(.system(size: (style.removeControlSize * 0.42).rounded(), weight: .bold))
                .foregroundStyle(Theme.dim)
                .frame(width: style.removeControlSize, height: style.removeControlSize)
                // The hit area grows past what is drawn — to 44pt under touch, not at all under a
                // pointer — through negative padding, so the chip's layout is unchanged.
                // `CadenceTagChipStyle`'s strip spacing is what keeps the spill off the next chip.
                .padding(style.removeHitInset)
                .contentShape(Rectangle())
                .padding(-style.removeHitInset)
        }
        .accessibilityLabel("Remove tag \(CadenceTagChipStyle.displayName(for: tag))")

        // The button *style* is the genuine platform split: a pointer gets `.cadencePlain`'s hover
        // treatment, a finger gets `.iosPressable`'s press feedback. Nothing else here forks.
        #if os(macOS)
        return button
            .buttonStyle(.cadencePlain)
            .help("Remove tag")
        #else
        return button.buttonStyle(.iosPressable)
        #endif
    }
}

// MARK: - The read-only strip

/// A **read-only** strip of compact tag chips, sized to fit and collapsing into a `+N` when it does
/// not: dense task rows, board cards, note list rows.
///
/// Shared, and shared late. This was declared inside `#if os(macOS)` in
/// `macOS/Views/TagPickerSupportViews.swift`, which is why `CadenceNotesListSupport` — a *shared*
/// file — carried a private `NoteRowTagStrip` that was this type line for line, with a comment
/// saying so and asking for exactly this move. iOS's board card then needed a third, and a rule
/// that a strip of chips looks the same on both platforms is only as strong as the strip they can
/// both reach.
///
/// **The `ViewThatFits` ladder is the whole point, and it is what makes the cap hold in a board
/// column.** `CadenceTagChip` caps its *label*, not the chip, so three long names still measure
/// wider than a 300pt column's content box; the ladder drops to one chip and then to a bare `+N`
/// rather than letting the strip push its neighbours out of the card. A fixed prefix cannot do
/// that, which is why `limit` is a ceiling rather than a count.
///
/// The overflow badge is inert here. macOS's *editable* strips hang a popover off it so the
/// collapsed tags stay removable; nothing in this strip can remove a tag, so there is nothing to
/// reach, and a popover on a card whose whole job is to be clicked or tapped through would be a
/// second affordance in the same pixels. The hidden names stay legible through `help`, which is a
/// tooltip under a pointer and an accessibility hint under a finger.
struct CompactTagStrip: View {
    let tags: [Tag]
    var limit: Int = 2
    var allowsArchived: Bool = true

    private var visibleTags: [Tag] {
        let base = allowsArchived ? tags : tags.filter { !$0.isArchived }
        return TagSupport.uniqueBySlug(base)
    }

    var body: some View {
        if !visibleTags.isEmpty {
            ViewThatFits(in: .horizontal) {
                compactTagRow(limit: min(limit, visibleTags.count))
                compactTagRow(limit: min(1, visibleTags.count))
                compactTagRow(limit: 0)
            }
        }
    }

    private func compactTagRow(limit: Int) -> some View {
        let hidden = visibleTags.dropFirst(limit)
        return HStack(spacing: 4) {
            ForEach(visibleTags.prefix(limit)) { tag in
                CadenceTagChip(tag: tag, size: .compact)
            }
            if !hidden.isEmpty {
                CadenceTagOverflowBadge(count: hidden.count, size: .compact)
                    .help(hidden.map { CadenceTagChipStyle.accessibilityLabel(for: $0) }.joined(separator: ", "))
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Overflow

/// The `+N` that stands in for tag chips a strip could not fit. Shared for the same reason the chip
/// is: it had been drawn three ways.
struct CadenceTagOverflowBadge: View {
    let count: Int
    var size: CadenceTagChipSize = .regular

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var typographyScaling

    private var style: CadenceTagChipStyle {
        CadenceTagChipStyle(
            size: size,
            isArchived: false,
            dynamicTypeSize: dynamicTypeSize,
            scaling: typographyScaling
        )
    }

    var body: some View {
        Text("+\(count)")
            // It sits in the same strip as the chips it stands in for, so it follows the same
            // role at the same base or the badge stops matching the row it is in.
            .cadenceFont(CadenceTagChipStyle.labelRole, base: style.baseFontSize, weight: .semibold)
            .foregroundStyle(Theme.dim)
            .padding(.horizontal, style.horizontalPadding)
            .padding(.vertical, style.verticalPadding)
            .background(Theme.surfaceElevated.opacity(0.75))
            .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
    }
}

// MARK: - The panel the chips are the rows of

/// Every box `iOSTaskTagPickerPopover` draws, as arithmetic over the chip in it.
///
/// **Why this lives here and not in `Cadence/iOS/`.** The panel is iOS-only and sits inside
/// `#if os(iOS)`, which `CadenceTests` — built for macOS — cannot see; and every figure below is
/// the chip's own growth plus this panel's chrome, so stating it anywhere else would mean stating
/// the chip's arithmetic twice. `iOSTaskInspectorMetrics` and `CadencePageHeaderMetrics` are
/// deliberately outside the platform fence for the first reason; `CadenceChoicePopoverMetrics`
/// lives beside the rows it measures for the second. This is both.
///
/// **The panel is the declaration** (T-1410's rule, kept): `iOSTaskTagPickerPopover` says
/// `.cadenceScaledTypography()` in its own body, so the frame it draws names `.enabled` *literally*
/// rather than reading the flag back out of an environment it is itself installing. The fonts
/// inside it read the scope it installs, which is what makes the frame and the type agree. Nothing
/// here asserts anything about whether the environment crosses the `.popover` — see
/// `CadenceTypographyScaling` for why that may not be pinned.
///
/// **The touch floor is 44 on both build platforms**, unlike `CadenceSettingsRowMetrics.rowHeight`,
/// because this panel only ever exists under a finger. A macOS-built test therefore reads the
/// number the phone draws rather than the desktop's 34.
nonisolated enum CadenceTagPickerMetrics {

    // MARK: - The literals the panel drew before T-1412

    /// The panel's width at the default text size.
    static let width: CGFloat = 260
    /// The panel's height at the default text size.
    static let height: CGFloat = 340
    /// Around the scrolling list of rows.
    static let listPadding: CGFloat = 6
    /// Inside a row, on each side.
    static let rowHorizontalPadding: CGFloat = 10
    /// Between a row's chip and its checkmark — a `Spacer(minLength:)`, so it is a floor.
    static let rowContentSpacing: CGFloat = 8
    /// Above and below a row's tallest content. The row was a bare `minHeight: 44` before, which
    /// is 19pt of air around a 25pt chip; this is the share of it the chip may not eat.
    static let rowVerticalPadding: CGFloat = 4
    /// The hairline between the list and the create field.
    static let dividerHeight: CGFloat = 1
    /// Around the create row.
    static let footerPadding: CGFloat = 10
    /// The create field and the `+` beside it are the same square.
    static let footerControlSide: CGFloat = 40
    /// A finger. See the type note for why this is not `CadenceSettingsRowMetrics.rowHeight`.
    static let touchTargetHeight: CGFloat = 44
    /// A catalogue showing fewer than three rows is a label with a scrollbar.
    static let minimumVisibleRows: Int = 3

    /// The `+` in `iOSTaskTagStrip` that opens this panel — a T-1364 residual, since its glyph was
    /// converted to `.controlLabel` while the box around it stayed `30 × 26`.
    static let addButtonWidth: CGFloat = 30
    static let addButtonHeight: CGFloat = 26
    static let addButtonGlyphSize: CGFloat = 11

    // MARK: - The chip, which is what a row is

    /// `.touch` is stated rather than taken from `.current` because this panel is only ever drawn
    /// on iOS; the input does not reach any figure below (a picker row's chip draws no remove
    /// control), but taking the compile-time answer would make a macOS-built test measure a
    /// pointer's chip for a panel no pointer can open.
    static func chipStyle(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CadenceTagChipStyle {
        CadenceTagChipStyle(
            size: .regular,
            isArchived: false,
            input: .touch,
            dynamicTypeSize: dynamicTypeSize,
            scaling: scaling
        )
    }

    /// The widest a row's chip can draw: its chrome, its dot, and the label cap it truncates at.
    static func maximumChipWidth(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CGFloat {
        let style = chipStyle(at: dynamicTypeSize, scaling: scaling)
        return style.horizontalPadding * 2
            + style.dotDiameter
            + style.contentSpacing
            + style.maximumLabelWidth
    }

    static func chipHeight(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CGFloat {
        chipStyle(at: dynamicTypeSize, scaling: scaling).chipHeight(hasRemoveControl: false)
    }

    /// The tick on a selected row. `.metadata`, the same role the chip's label reads.
    static func checkmarkSize(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CGFloat {
        CadenceTypeScale.size(CadenceTagChipStyle.labelRole, at: dynamicTypeSize, scaling: scaling)
    }

    // MARK: - The row

    /// The row's floor: a finger, the chip in it, or the empty state's label — whichever is
    /// tallest.
    ///
    /// Three reasons rather than one, and which of them binds changes as the type grows. At the
    /// sizes this panel was drawn at the finger wins and the row is the 44 it always was; past
    /// roughly `accessibility1` the chip wins, which is the "font grew, box did not" case the
    /// radius and metric sweeps stay green through.
    static func rowMinHeight(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CGFloat {
        let emptyStateLine = CadenceTypeScale.lineHeight(.rowTitle, at: dynamicTypeSize, scaling: scaling)
        return max(
            touchTargetHeight,
            max(
                chipHeight(at: dynamicTypeSize, scaling: scaling),
                emptyStateLine
            ) + rowVerticalPadding * 2
        )
    }

    /// What a fully occupied row measures across. The claim `width(at:scaling:)` has to beat.
    static func rowContentWidth(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CGFloat {
        rowHorizontalPadding * 2
            + maximumChipWidth(at: dynamicTypeSize, scaling: scaling)
            + rowContentSpacing
            + checkmarkSize(at: dynamicTypeSize, scaling: scaling)
    }

    // MARK: - The panel

    /// The panel widens by what a chip's label gained — **additively**, which is this app's rule
    /// (T-1410): 260 multiplied would be 801pt at `accessibility5`, on a phone 375 wide.
    static func width(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CGFloat {
        CadenceTypeScale.height(
            Self.width,
            holding: CadenceTagChipStyle.labelRole,
            at: dynamicTypeSize,
            scaling: scaling
        )
    }

    /// The create field, and the `+` square beside it.
    static func footerControlSide(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CGFloat {
        CadenceTypeScale.height(Self.footerControlSide, holding: .fieldLabel, at: dynamicTypeSize, scaling: scaling)
    }

    static func footerHeight(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CGFloat {
        footerControlSide(at: dynamicTypeSize, scaling: scaling) + footerPadding * 2
    }

    /// The list's height at the default size, once the footer and the hairline have had theirs.
    /// The block the panel keeps for rows, and the reason the panel's own height grows by the
    /// footer alone: a list scrolls, so a taller row means fewer rows rather than a taller panel.
    static var baseListInnerHeight: CGFloat {
        Self.height - dividerHeight - (Self.footerControlSide + footerPadding * 2) - listPadding * 2
    }

    static func listInnerHeight(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CGFloat {
        max(
            baseListInnerHeight,
            CGFloat(minimumVisibleRows) * rowMinHeight(at: dynamicTypeSize, scaling: scaling)
        )
    }

    /// How many whole rows the reader can see without scrolling.
    static func visibleRows(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> Int {
        Int(
            (listInnerHeight(at: dynamicTypeSize, scaling: scaling)
                / rowMinHeight(at: dynamicTypeSize, scaling: scaling)).rounded(.down)
        )
    }

    /// The panel, block by block — which is what makes "does the tag catalogue still fit on a
    /// phone" a unit test rather than a screenshot.
    static func panelHeight(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CGFloat {
        listInnerHeight(at: dynamicTypeSize, scaling: scaling)
            + listPadding * 2
            + dividerHeight
            + footerHeight(at: dynamicTypeSize, scaling: scaling)
    }

    // MARK: - The `+` that opens it

    static func addButtonWidth(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CGFloat {
        CadenceTypeScale.height(
            Self.addButtonWidth, holding: .controlLabel, textBase: Self.addButtonGlyphSize,
            at: dynamicTypeSize, scaling: scaling
        )
    }

    static func addButtonHeight(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CGFloat {
        CadenceTypeScale.height(
            Self.addButtonHeight, holding: .controlLabel, textBase: Self.addButtonGlyphSize,
            at: dynamicTypeSize, scaling: scaling
        )
    }
}
