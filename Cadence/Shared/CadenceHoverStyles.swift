import SwiftUI

struct CadencePlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CadencePlainButtonBody(configuration: configuration)
    }
}

private struct CadencePlainButtonBody: View {
    let configuration: ButtonStyle.Configuration
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
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.blue.opacity(backgroundOpacity))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
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
            .contentShape(RoundedRectangle(cornerRadius: 10))
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
