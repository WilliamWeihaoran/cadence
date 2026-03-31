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
        configuration.label
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
