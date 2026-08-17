#if os(iOS)
import SwiftUI

// The iOS half of Cadence's design language.
//
// macOS carries its vocabulary in `Shared/Components/CadenceButtons.swift` and
// `CommitmentSharedViews.swift`, both of which are `#if os(macOS)` because they are built out of
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
/// radius scale rather than each call site picking 7, 8, 9 or 12.
struct iOSIconTile: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 34
    var iconSize: CGFloat = 15
    var cornerRadius: CGFloat = Theme.radiusControl
    var fillOpacity: Double = 0.14
    var bordered = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return Image(systemName: systemImage)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(shape.fill(color.opacity(fillOpacity)))
            .overlay {
                if bordered {
                    shape.strokeBorder(color.opacity(0.20), lineWidth: 1)
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
    /// Overrides the resting glyph colour. Without it a never-selected button always renders
    /// `Theme.muted`, which made `tint:` unreachable on buttons that are actions rather than
    /// toggles — the calendar's "jump to today" passed `Theme.blue` and could never show it.
    var foreground: Color? = nil
    var isSelected = false
    var isEnabled = true
    /// Visual size of the plate. The hit area is always at least 44pt regardless.
    var plateSize: CGFloat = 38
    var iconSize: CGFloat = 14
    var showsPlate = true
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)

        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(isEnabled ? (isSelected ? tint : (foreground ?? Theme.muted)) : Theme.dim.opacity(0.38))
                .frame(width: plateSize, height: plateSize)
                .background(shape.fill(plateFill))
                .overlay(shape.strokeBorder(plateBorder, lineWidth: 1))
                // Hit area only. Growing the *frame* to 44 made a group of these 50pt tall next
                // to a 44pt `iOSSegmentedPill` group in the same toolbar row.
                .contentShape(Rectangle())
                .iOSExpandedHitArea(max(0, (44 - plateSize) / 2))
        }
        .buttonStyle(.iosPressable)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }

    private var plateFill: Color {
        guard showsPlate else { return .clear }
        if isSelected { return tint.opacity(0.14) }
        return isEnabled ? Theme.surfaceElevated.opacity(0.55) : .clear
    }

    private var plateBorder: Color {
        guard showsPlate else { return .clear }
        if isSelected { return tint.opacity(0.28) }
        return Theme.borderSubtle.opacity(0.45)
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
    /// For a segment that genuinely cannot be chosen at the current size — Today's three-pane "Mac"
    /// layout below the width its three columns fit in. It reads as unavailable instead of
    /// accepting a tap and leaving the screen exactly as it was.
    var isEnabled = true
    var accessibilityHint: String? = nil
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.radiusControl - 3, style: .continuous)

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
            // read and tap. `dim` (#71717a) on `Theme.bg` lands at roughly 4.1:1 at 12pt, under
            // the 4.5:1 floor for normal text — `dim` is for genuinely de-emphasised content.
            .foregroundStyle(isEnabled ? (isSelected ? tint : Theme.muted) : Theme.dim.opacity(0.45))
            .padding(.horizontal, 10)
            .frame(
                minWidth: fillsWidth ? nil : minWidth,
                maxWidth: fillsWidth ? .infinity : nil,
                minHeight: fillsWidth ? 44 : 38
            )
            .background(shape.fill(isSelected && isEnabled ? tint.opacity(0.14) : Color.clear))
            .overlay(shape.strokeBorder(isSelected && isEnabled ? tint.opacity(0.26) : Color.clear, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.iosPressable)
        .disabled(!isEnabled)
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

/// How an editor section separates itself from the one above.
enum iOSEditorSectionStyle {
    /// Fields sit on a raised card. The default, and what every full-screen editor uses.
    case card
    /// Fields sit directly on the sheet, separated by a hairline. For compact sheets where a stack
    /// of cards would read as a stack of unrelated boxes.
    case ruled
}

/// The **one** titled group of fields used by every iOS editor.
///
/// There were five of these — `iOSTrackingPickerSection`, `iOSCalendarBundleEditorSection`,
/// `iOSCalendarEventEditorSection`, `iOSCalendarQuickCreateSection` and their eyebrows — four of
/// them byte-identical apart from the name, and the fifth differing only in whether the fields sat
/// on a card. That difference is now the `style` parameter.
struct iOSEditorSection<Content: View>: View {
    /// `nil` draws the group with its rule and spacing but no eyebrow — for groups whose rows
    /// already name themselves, where a heading would only repeat them. The task inspector's
    /// properties group and its action row are both this: the heading they used to carry said
    /// "Overview", which named nothing the rows did not.
    let title: String?
    var style: iOSEditorSectionStyle = .card
    var contentSpacing: CGFloat = 0
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: title == nil ? 0 : 10) {
            if let title {
                SectionEyebrowLabel(text: title)
            }

            VStack(alignment: .leading, spacing: contentSpacing) {
                content()
            }
            .modifier(iOSEditorSectionBody(style: style))
        }
        .modifier(iOSEditorSectionChrome(style: style))
    }
}

private struct iOSEditorSectionBody: ViewModifier {
    let style: iOSEditorSectionStyle

    func body(content: Content) -> some View {
        switch style {
        case .card:
            content
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusCard, shadowRadius: 12, shadowY: 5)
        case .ruled:
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct iOSEditorSectionChrome: ViewModifier {
    let style: iOSEditorSectionStyle

    func body(content: Content) -> some View {
        switch style {
        case .card:
            content
        case .ruled:
            content
                .padding(.top, 12)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Theme.borderSubtle.opacity(0.35))
                        .frame(height: 1)
                }
        }
    }
}

/// Divider between two rows inside an `iOSEditorSection`.
///
/// It owns the whole gap between two rows — call sites must not add `contentSpacing` on top, or
/// the same space is counted twice. At 9pt each side a 44pt row had a 63pt pitch, which read as a
/// list of mostly-empty rows; 6pt puts it at 57 without letting the rows touch.
struct iOSEditorDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.borderSubtle.opacity(0.55))
            .frame(height: 1)
            .padding(.vertical, 6)
    }
}

/// A field's name, in the vocabulary macOS's `TaskInspectorFieldRow` established: a **bare glyph
/// in a fixed leading slot**, then a quiet label.
///
/// It used to be a 28pt filled `iOSIconTile` beside a 14pt semibold `Theme.text` label. Stacked
/// seven deep in the task inspector that read as a column of grey squares shouting the names of
/// fields while the values — the only part that differs from task to task — sat dim on the far
/// right. The fixed slot is what makes every label in a group start on the same x, so the column
/// scans; the glyph carries which field this is, and the caller's `content` carries the answer.
struct iOSEditorInlineLabel: View {
    let label: String
    let systemImage: String
    /// Defaults to `Theme.dim`, matching the row-metadata rule: colour is for the exceptional
    /// (an overdue due date, a past do date), not for every field that happens to have an icon.
    var color: Color = Theme.dim

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 22, alignment: .leading)

            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.dim)
        }
    }
}

/// A labelled field row inside an `iOSEditorSection`: glyph, quiet label, trailing control.
/// 44pt tall, because the control on its trailing edge is the thing being tapped.
struct iOSEditorFieldRow<Content: View>: View {
    let label: String
    let systemImage: String
    var color: Color = Theme.dim
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 10) {
            iOSEditorInlineLabel(label: label, systemImage: systemImage, color: color)

            Spacer(minLength: 12)

            content()
        }
        .frame(minHeight: 44)
    }
}

// MARK: - Board column header

/// iOS counterpart of macOS's `BoardColumnHeader` — the one header treatment every board column
/// gets: a dot of colour, an uppercased label, the count, and a closing hairline.
///
/// `accentRule` swaps the neutral hairline for a coloured gradient one. The Calendar Board's
/// *today* column is the only sanctioned user, exactly as on macOS.
struct iOSBoardColumnHeader: View {
    let dotColor: Color
    let title: String
    let count: Int
    var accentRule: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)

                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(0.4)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 6)

                Text("\(count)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)

            rule
        }
    }

    @ViewBuilder
    private var rule: some View {
        if let accentRule {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [accentRule.opacity(0.85), accentRule.opacity(0.45), accentRule.opacity(0.16)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
        } else {
            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(height: 1)
        }
    }
}

// MARK: - Inline empty

/// iOS counterpart of `CommitmentInlineEmpty`: the one-line "nothing here" that sits *inside* a
/// section, as opposed to `iOSEmptyPanel`, which owns a whole pane.
struct iOSInlineEmpty: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Theme.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.surfaceElevated.opacity(0.38))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
    }
}
#endif
