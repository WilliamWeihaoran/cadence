import SwiftUI

/// **[[T-9535]].** `cornerRadius` is the radius the hover wash, its stroke and the hit shape are
/// drawn at. It defaults to `Theme.radiusControl` for a label with no plate of its own; a label
/// that paints its own plate at another radius passes that radius
/// (`.cadencePlain(cornerRadius: 8)`), so the pointer lights one outline whose corners meet the
/// plate's -- AGENTS.md's one-hover-layer-at-one-radius rule. Before this the wash was always
/// 10pt, and ~40 Mac plates (7, 8, 12, 14...) drew a second outline that disagreed at the corners.
struct CadencePlainButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = Theme.radiusControl

    func makeBody(configuration: Configuration) -> some View {
        CadencePlainButtonBody(configuration: configuration, cornerRadius: cornerRadius)
    }
}

private struct CadencePlainButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let cornerRadius: CGFloat
    @State private var isHovered = false

    private var backgroundOpacity: Double {
        if configuration.isPressed { return 0.14 }
        if isHovered { return 0.08 }
        return 0
    }

    private var strokeOpacity: Double {
        if configuration.isPressed { return 0.24 }
        if isHovered { return 0.18 }
        return 0
    }

    var body: some View {
        #if os(macOS)
        configuration.label
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Theme.blue.opacity(backgroundOpacity))
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Theme.blue.opacity(strokeOpacity))
            }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .modifier(CadenceHoverTracking(isHovered: $isHovered))
        #else
        // T-289. This is a *hover* wash, and touch has no hover — so on iOS the wash above could
        // only ever fire on press, painting a blue rounded rectangle no other iOS control draws.
        // The two `iOSDateJumpTitle` call sites were the visible half; the reach is larger, because
        // `CadenceDatePicker` and `EstimatePickerControl` are shared components that apply this
        // style unconditionally and have ~15 iOS call sites between them. Fixing the style rather
        // than fencing each caller is what stops the next shared component reintroducing it.
        //
        // `makeBody` is called directly rather than re-spelling 0.97 / 0.62 / 0.12: iOS's press
        // feedback is `iOSPressableButtonStyle`, which documents itself as "the press translation
        // of macOS's `.cadencePlain` hover wash", and this is that sentence made executable.
        // `contentShape` is kept so the hit area does not change with the paint.
        iOSPressableButtonStyle().makeBody(configuration: configuration)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        #endif
    }
}

/// **[[T-9465]].** The one hover plate a Mac choice-menu row draws: a fill at
/// `CadenceMenuRowButtonStyle.cornerRadius` behind the whole row, and nothing else.
///
/// The rows used to take `.cadencePlain` *and* add their own plate (`CreateTaskPickerHover`,
/// `TaskPickerRowHover`, `CalendarPickerRowHover`, `ContextPickerRowHover`, a hand-rolled
/// `isHovered` fill, or `.cadenceHoverHighlight(cornerRadius: 6)`), so one pointer lit two layers at
/// two radii -- the style's 10pt wash and stroke around the row's 6pt fill -- against AGENTS.md's
/// one-hover-layer-at-one-radius rule. The rows' selected / keyboard-highlighted fills stay on
/// the label at this same radius, so selection and hover share one shape.
struct CadenceMenuRowButtonStyle: ButtonStyle {
    static let cornerRadius: CGFloat = 6
    static let hoverOpacity: Double = 0.06
    static let pressedOpacity: Double = 0.12

    func makeBody(configuration: Configuration) -> some View {
        CadenceMenuRowButtonBody(configuration: configuration)
    }
}

private struct CadenceMenuRowButtonBody: View {
    let configuration: ButtonStyle.Configuration
    @State private var isHovered = false

    private var fillOpacity: Double {
        if configuration.isPressed { return CadenceMenuRowButtonStyle.pressedOpacity }
        if isHovered { return CadenceMenuRowButtonStyle.hoverOpacity }
        return 0
    }

    var body: some View {
        #if os(macOS)
        configuration.label
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: CadenceMenuRowButtonStyle.cornerRadius)
                    .fill(Theme.blue.opacity(fillOpacity))
            )
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .modifier(CadenceHoverTracking(isHovered: $isHovered))
        #else
        iOSPressableButtonStyle().makeBody(configuration: configuration)
            .contentShape(Rectangle())
        #endif
    }
}

struct CadenceHoverHighlight: ViewModifier {
    var cornerRadius: CGFloat = 8
    var fillColor: Color = Theme.blue.opacity(0.06)
    var strokeColor: Color = Theme.blue.opacity(0.14)

    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isHovered ? fillColor : Color.clear)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(isHovered ? strokeColor : Color.clear)
            }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .modifier(CadenceHoverTracking(isHovered: $isHovered))
    }
}

private struct CadenceHoverTracking: ViewModifier {
    @Binding var isHovered: Bool

    func body(content: Content) -> some View {
        #if os(macOS)
        content.onHover { isHovered = $0 }
        #else
        content
        #endif
    }
}

extension ButtonStyle where Self == CadencePlainButtonStyle {
    static var cadencePlain: CadencePlainButtonStyle { CadencePlainButtonStyle() }

    /// The plain style around a label that paints its own plate at `cornerRadius` ([[T-9535]]).
    static func cadencePlain(cornerRadius: CGFloat) -> CadencePlainButtonStyle {
        CadencePlainButtonStyle(cornerRadius: cornerRadius)
    }
}

extension ButtonStyle where Self == CadenceMenuRowButtonStyle {
    static var cadenceMenuRow: CadenceMenuRowButtonStyle { CadenceMenuRowButtonStyle() }
}

extension View {
    func cadenceHoverHighlight(
        cornerRadius: CGFloat = 8,
        fillColor: Color = Theme.blue.opacity(0.06),
        strokeColor: Color = Theme.blue.opacity(0.14)
    ) -> some View {
        modifier(
            CadenceHoverHighlight(
                cornerRadius: cornerRadius,
                fillColor: fillColor,
                strokeColor: strokeColor
            )
        )
    }
}
