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

    init(
        size: CadenceTagChipSize = .regular,
        selection: CadenceTagChipSelection = .none,
        isArchived: Bool,
        input: CadenceTagChipInput = .current
    ) {
        self.size = size
        self.selection = selection
        self.isArchived = isArchived
        self.input = input
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

    var fontSize: CGFloat {
        switch size {
        case .regular: return 12
        case .compact: return 10
        }
    }

    var fontWeight: Font.Weight {
        switch size {
        case .regular: return .medium
        case .compact: return .semibold
        }
    }

    var dotDiameter: CGFloat {
        switch size {
        case .regular: return 6
        case .compact: return 5
        }
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
    var maximumLabelWidth: CGFloat {
        switch size {
        case .regular: return 130
        case .compact: return 92
        }
    }

    // MARK: The remove control

    /// The drawn size of the `x`. Larger under touch because a finger is not a pointer — that
    /// *visual* difference is deliberate, and it is what keeps the expanded touch target from
    /// having to reach past the chip and into its neighbour.
    var removeControlSize: CGFloat {
        switch (input, size) {
        case (.touch, .regular):   return 22
        case (.touch, .compact):   return 18
        case (.pointer, .regular): return 14
        case (.pointer, .compact): return 12
        }
    }

    /// What the remove control must measure *to the touch*. 44pt under touch, per the platform's
    /// own guidance; under a pointer the drawn control already is the target.
    var removeHitTargetSize: CGFloat {
        switch input {
        case .touch:   return 44
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
        let labelHeight = ceil(fontSize * 1.25)
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
    static func editableStripSpacing(
        for size: CadenceTagChipSize,
        input: CadenceTagChipInput = .current
    ) -> CGFloat {
        let overhang = CadenceTagChipStyle(size: size, isArchived: false, input: input).removeHitOverhang()
        return max(6, overhang.horizontal * 2)
    }

    static func editableStripLineSpacing(
        for size: CadenceTagChipSize,
        input: CadenceTagChipInput = .current
    ) -> CGFloat {
        let overhang = CadenceTagChipStyle(size: size, isArchived: false, input: input).removeHitOverhang()
        return max(6, overhang.vertical * 2)
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

    private var style: CadenceTagChipStyle {
        CadenceTagChipStyle(size: size, selection: selection, isArchived: tag.isArchived)
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
                .font(.system(size: style.fontSize, weight: style.fontWeight))
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

    private var style: CadenceTagChipStyle {
        CadenceTagChipStyle(size: size, isArchived: false)
    }

    var body: some View {
        Text("+\(count)")
            .font(.system(size: style.fontSize, weight: .semibold))
            .foregroundStyle(Theme.dim)
            .padding(.horizontal, style.horizontalPadding)
            .padding(.vertical, style.verticalPadding)
            .background(Theme.surfaceElevated.opacity(0.75))
            .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
    }
}
