#if os(iOS)
import SwiftUI

// The iOS half of Cadence's design language.
//
// macOS carries its vocabulary in `macOS/Views/CadenceButtons.swift` and
// `macOS/Views/CommitmentSharedViews.swift` — they sat under `Shared/Components/` until T-283/T-288
// moved them, which is where a reader looking for a shared control would have found them and been
// wrong. Both are `#if os(macOS)` because they are built out of
// `CadenceDesktopMetrics` — 30pt control heights, hover states, `.help(_:)` tooltips. None of that
// translates: a 30pt tap target is half of what a finger needs, and a hover state never fires.
//
// So this file is the *counterpart*, not a copy. Same names, same roles, same tokens; touch
// geometry (44pt minimum) and press feedback in place of hover. Anything that needs a chip, an
// icon badge, a button or a board column header on iOS should reach for one of these rather than
// assembling another one inline — which is how the surfaces drifted in the first place.

// MARK: - Press feedback

/// The press translation of macOS's `.cadencePlain` hover wash. A finger already occludes the
/// control it is on, so the feedback is a fast dim + shrink rather than a background that would sit
/// under the fingertip anyway.
struct iOSPressableButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.97
    var pressedOpacity: Double = 0.62

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == iOSPressableButtonStyle {
    static var iosPressable: iOSPressableButtonStyle { iOSPressableButtonStyle() }
}

// MARK: - Touch targets

extension View {
    /// Grows a control's hit area by `inset` on every edge **without** changing what it occupies in
    /// layout. Small glyph controls — a 16pt completion circle, a 20pt close button — need 44pt of
    /// tappable area, but padding them out to 44pt would blow the row apart. Pad, take the content
    /// shape at the padded size, then pad back negatively.
    func iOSExpandedHitArea(_ inset: CGFloat = 7) -> some View {
        padding(inset)
            .contentShape(Rectangle())
            .padding(-inset)
    }
}

// MARK: - Pushed-page chrome

/// The back control a pushed compact screen carries **inside** its own header.
///
/// On iPhone every screen is pushed onto one `NavigationStack`, and the navigation bar above the
/// page header was holding a single chevron and nothing else: a full 44pt row of chrome per screen,
/// directly above a header that already named the page. `iOSHidesCompactNavigationBar()` drops that
/// row and its one control moves down here, onto the header row that was already being drawn.
struct iOSHeaderBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.blue)
                // Small in layout so it neither pushes the title off a 6.1" screen nor makes the
                // header row taller than the text in it, 44pt+ to a finger — the same trick
                // `iOSIconButton` uses for its plate.
                .frame(width: 30, height: 38)
                .contentShape(Rectangle())
                .iOSExpandedHitArea(7)
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel("Back")
    }
}

private struct iOSCompactNavigationBarHidden: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @ViewBuilder
    func body(content: Content) -> some View {
        if horizontalSizeClass == .compact {
            content.toolbar(.hidden, for: .navigationBar)
        } else {
            content
        }
    }
}

extension View {
    /// Hides the navigation bar on compact width, where the page's own header carries the back
    /// control (`iOSHeaderBackButton`) instead of letting the bar hold a row for it alone.
    ///
    /// `.toolbar(.hidden, for: .navigationBar)` inside a `NavigationStack` keeps the interactive
    /// swipe-back gesture — it is the old `NavigationView` + `.navigationBarHidden(true)` pairing
    /// that used to kill it. Regular width is left untouched on purpose: the iPad shell hosts these
    /// same views with no navigation stack around them, so there is no bar to hide and nothing to
    /// go back to.
    func iOSHidesCompactNavigationBar() -> some View {
        modifier(iOSCompactNavigationBarHidden())
    }
}

// MARK: - Icon tile

/// iOS counterpart of `CommitmentIconTile`: a glyph on a tinted rounded square, on the shared
/// radius scale rather than each call site picking 7, 8, 9 or 12. Since T-178 the radius and the
/// curve are the *same* two figures `CommitmentIconTile` reads, so the pair now agrees on all four
/// of its geometry numbers rather than three.
struct iOSIconTile: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 34
    var iconSize: CGFloat = 15
    var cornerRadius: CGFloat = CadencePageHeaderMetrics.tileCornerRadius
    /// Both defaults come from the shared tile vocabulary rather than being restated here. They
    /// were literals — the same 0.14 `CommitmentIconTile` already read from the metrics, plus a
    /// 0.20 border that tile did not draw at all. One of those two numbers being spelled twice is
    /// how the pair drifted in the first place.
    var fillOpacity: Double = CadencePageHeaderMetrics.tileFillOpacity
    var bordered = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: CadencePageHeaderMetrics.tileCornerStyle)

        return Image(systemName: systemImage)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(shape.fill(color.opacity(fillOpacity)))
            .overlay {
                if bordered {
                    shape.strokeBorder(color.opacity(CadencePageHeaderMetrics.tileBorderOpacity), lineWidth: 1)
                }
            }
    }
}

// MARK: - Meta chip

/// iOS counterpart of `CommitmentMetaChip`. One chip shape for goal status, goal kind, event
/// times, habit cadence — everywhere a small tinted fact hangs off a title.
struct iOSMetaChip: View {
    let label: String
    let color: Color
    var systemImage: String? = nil
    /// Filled/high-contrast treatment for the chip that should read as the primary metric.
    var prominent: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(prominent ? Theme.bg : color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(prominent ? color : color.opacity(0.13))
        .clipShape(Capsule())
    }
}

// MARK: - Buttons

/// Same four roles as macOS's `CadenceActionButtonRole`, so "primary" means the same thing on both
/// platforms.
enum iOSActionButtonRole {
    case primary
    case secondary
    case ghost
    case destructive
}

enum iOSActionButtonSize {
    case compact
    case regular

    var fontSize: CGFloat {
        switch self {
        case .compact: 13
        case .regular: 15
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .compact: 13
        case .regular: 18
        }
    }

    /// Both sizes clear the 44pt touch floor; "compact" is compact in type and width, not in the
    /// part a finger has to hit.
    var minHeight: CGFloat {
        switch self {
        case .compact: 44
        case .regular: 48
        }
    }

    var cornerRadius: CGFloat { Theme.radiusControl }
}

/// iOS counterpart of `CadenceActionButton`, replacing the `.borderedProminent` / `.bordered`
/// system buttons the tracking surfaces were using. Those inherit the OS's own material and corner
/// radius, so a "primary" action looked like a different app depending on which screen you were on.
struct iOSActionButton: View {
    let title: String
    var systemImage: String?
    var role: iOSActionButtonRole = .secondary
    var size: iOSActionButtonSize = .regular
    var tint: Color?
    var fullWidth = false
    var isDisabled = false
    let action: () -> Void

    private var resolvedTint: Color {
        tint ?? (role == .destructive ? Theme.red : Theme.blue)
    }

    private var foreground: Color {
        switch role {
        case .primary: Theme.onColor
        case .secondary: resolvedTint
        case .ghost: Theme.muted
        case .destructive: Theme.red
        }
    }

    private var background: Color {
        switch role {
        case .primary: resolvedTint
        case .secondary: resolvedTint.opacity(0.12)
        case .ghost: Color.clear
        case .destructive: Theme.red.opacity(0.12)
        }
    }

    private var border: Color {
        switch role {
        case .primary, .ghost: Color.clear
        case .secondary: resolvedTint.opacity(0.20)
        case .destructive: Theme.red.opacity(0.24)
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)

        Button(action: action) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: size.fontSize - 1, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: size.fontSize, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, size.horizontalPadding)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: size.minHeight)
            .background(shape.fill(background))
            .overlay(shape.strokeBorder(border, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.iosPressable)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.52 : 1)
    }
}

/// iOS counterpart of `CadenceIconButton`. Always 44pt of hit area, whatever the glyph's own size.
struct iOSIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var tint: Color = Theme.text
    var isSelected = false
    /// Visual size of the plate. The hit area is always at least 44pt regardless.
    var plateSize: CGFloat = 38
    var iconSize: CGFloat = 14
    let action: () -> Void

    // `foreground`, `isEnabled` and `showsPlate` are gone. `foreground` existed for one caller —
    // the calendar's `location.fill` jump-to-today, an action rather than a toggle, which passed
    // `Theme.blue` and could not show it while the resting colour was hardcoded to `Theme.muted`.
    // That button went with the `‹ ➤ ›` cluster; jump-to-today is the `Today` row in
    // `iOSDateJumpTitle`'s popover now, which draws its own blue. The other two never had a caller
    // at all. All four remaining call sites take the defaults, so removing them changes nothing
    // that renders — see `iOSSettingsTagsSection`, which reaches `tint` the supported way, through
    // `isSelected`.

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)

        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(isSelected ? tint : Theme.muted)
                .frame(width: plateSize, height: plateSize)
                .background(shape.fill(plateFill))
                .overlay(shape.strokeBorder(plateBorder, lineWidth: 1))
                // Hit area only. Growing the *frame* to 44 made a group of these 50pt tall next
                // to a 44pt `iOSSegmentedPill` group in the same toolbar row.
                .contentShape(Rectangle())
                .iOSExpandedHitArea(max(0, (44 - plateSize) / 2))
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel(accessibilityLabel)
    }

    private var plateFill: Color {
        isSelected ? tint.opacity(0.14) : Theme.surfaceElevated.opacity(0.55)
    }

    private var plateBorder: Color {
        isSelected ? tint.opacity(0.28) : Theme.borderSubtle.opacity(0.45)
    }
}

// MARK: - Segmented pill group

/// iOS counterpart of `CommitmentFilterBar`: a recessed track holding one pill per option. Used for
/// the calendar's view-mode switch, so the mode picker and macOS's read as one control family.
struct iOSSegmentedPillGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 3) {
            content()
        }
        .padding(3)
        .background(Theme.bg.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.34), lineWidth: 1)
        }
    }
}

/// One pill inside an `iOSSegmentedPillGroup`. Mirrors `CadencePillButton`'s selected treatment
/// (tint wash + tint hairline) at touch height.
struct iOSSegmentedPill: View {
    let title: String
    var systemImage: String? = nil
    let isSelected: Bool
    var tint: Color = Theme.blue
    var minWidth: CGFloat = 58
    /// Equal-width segments that between them fill the row, with a label that **wraps and shrinks
    /// before it truncates**.
    ///
    /// This is what `iOSSegmentedChoice` sets, and it exists because a chooser laid across a form
    /// row is the one place truncation is fatal: with `lineLimit(1)` and nothing else, four options
    /// across an iPhone left roughly 80pt each and silently cut "Days of Week" and "Times per Week"
    /// down to "Days of W…" and "Times per…" — two options unreadable and indistinguishable from
    /// one another. A toolbar pill instead sizes to its own label and scrolls if the row runs out,
    /// so it neither needs nor wants this.
    ///
    /// 44pt rather than 38 here for the same reason: these carry two lines of text, and a form
    /// control that is the only thing tappable in its row should be a full touch target on its own
    /// rather than borrowing the track's 3pt padding to reach the floor.
    var fillsWidth = false
    var accessibilityHint: String? = nil
    let action: () -> Void

    // No `isEnabled`. It was written for one segment — Today's three-pane "Mac" layout, unavailable
    // below the width its three columns fit in — and that layout is deleted. No caller has passed
    // `false` since. A segment that cannot be chosen should not be in the group at all, which is
    // what the calendar's `monthDetailControl` does: it drops the whole control rather than dimming
    // a pill.

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.radiusControlCompact, style: .continuous)

        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .bold : .semibold))
                    .lineLimit(fillsWidth ? 2 : 1)
                    .minimumScaleFactor(fillsWidth ? 0.75 : 1)
                    .multilineTextAlignment(.center)
            }
            // `Theme.muted`, not `Theme.dim`: an unselected segment is a label you are meant to
            // read and tap, so it sits above the quietest stop rather than at it. This used to be
            // a legibility argument — `dim` was `#71717a` and landed near 4.1:1 on `Theme.bg`,
            // under the 4.5:1 floor for normal text. T-847 raised `dim` clear of that floor on
            // every surface, so it is a hierarchy call now: `dim` is for genuinely de-emphasised
            // content, and an unselected segment is not that.
            .foregroundStyle(isSelected ? tint : Theme.muted)
            .padding(.horizontal, 10)
            .frame(
                minWidth: fillsWidth ? nil : minWidth,
                maxWidth: fillsWidth ? .infinity : nil,
                minHeight: fillsWidth ? 44 : 38
            )
            .background(shape.fill(isSelected ? tint.opacity(0.14) : Color.clear))
            .overlay(shape.strokeBorder(isSelected ? tint.opacity(0.26) : Color.clear, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint ?? "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The value-bound spelling of the same control: hand it the options and a binding, get an
/// `iOSSegmentedPillGroup` of equal-width pills.
///
/// There used to be a second segmented control here — its own track at `Theme.surfaceElevated`, its
/// own hardcoded radius 8 and 10, and a solid tint fill behind the selected label — so a form's
/// chooser and a toolbar's chooser were the same control wearing two looks, and one of them was off
/// the radius scale entirely. This is now a layout over `iOSSegmentedPill`: nothing about the
/// appearance is decided here, so the two cannot drift again.
///
/// The `ViewBuilder` spelling stays for the segments this one cannot express — a group mixing a
/// `ForEach` with a standalone pill (the calendar's Board), per-segment icons, disabled segments,
/// accessibility hints.
struct iOSSegmentedChoice<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selection: T
    var color: Color = Theme.blue

    var body: some View {
        iOSSegmentedPillGroup {
            ForEach(options, id: \.value) { option in
                iOSSegmentedPill(
                    title: option.label,
                    isSelected: selection == option.value,
                    tint: color,
                    fillsWidth: true
                ) {
                    selection = option.value
                }
            }
        }
    }
}

// MARK: - Editor sections

/// The editor field vocabulary now lives in `Shared/Components/CadenceFieldRows.swift` and is read
/// by **both** platforms (T-20).
///
/// `iOSEditorInlineLabel`'s own doc comment already described itself as adopting "the vocabulary
/// macOS's `TaskInspectorFieldRow` established", and `iOSNavigationSettingsSection` was rebuilt on
/// these rows in `775833d` — while macOS Settings kept stacking a bold title over a grey paragraph
/// over a row of filled pills. Nothing here was ever iOS-specific; the only platform difference is
/// the row height, which is one computed property on `CadenceSettingsRowMetrics`.
///
/// The iOS names stay as typealiases so no call site moved. Do not re-declare a struct here.
typealias iOSEditorSectionStyle = CadenceFieldSectionStyle
typealias iOSEditorSection<Content: View> = CadenceFieldSection<Content>
typealias iOSEditorDivider = CadenceFieldDivider
typealias iOSEditorInlineLabel = CadenceInlineFieldLabel
typealias iOSEditorFieldRow<Content: View> = CadenceFieldRow<Content>

// MARK: - Board column header

// The board column header is `CadenceBoardColumnHeader` in
// `Shared/Components/CadenceBoardColumnHeader.swift`. `iOSBoardColumnHeader` used to be declared
// here and opened its own doc comment with "iOS counterpart of macOS's `BoardColumnHeader`" — a
// fork that named the thing it was a copy of and survived review anyway, because `iOSFoo` reads
// as an iOS thing in a diff rather than as a second `Foo`.

// MARK: - Inline empty

// The one-line "nothing here" inside a section is `CadenceInlineEmpty` in
// `Shared/Components/CadenceInlineEmpty.swift`. `iOSInlineEmpty` was declared here, opening with
// "iOS counterpart of `CommitmentInlineEmpty`" — a copy of a component that was already sitting in
// `Shared/Components/`, unreachable only because the file around it was `#if os(macOS)`.
// `iOSEmptyPanel`, which owns a whole pane rather than a row, is a different thing and stays.

#endif
