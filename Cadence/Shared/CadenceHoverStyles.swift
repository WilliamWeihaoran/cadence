import SwiftUI

/// **[[T-9601]].** The shape the hover wash, its stroke and the hit shape are drawn in.
///
/// [[T-9535]] gave the style a *radius*, which can only answer a rounded-rectangle plate. Ten
/// controls clip their label to a `Circle` or a `Capsule` -- the date picker's day cells and its
/// quick pills, the Focus overlay's close and round action buttons, the inbox completion circle,
/// the Settings and board colour swatches, start-focus, the segmented pill and the root floating
/// button -- and every one of them got a 10pt rounded rectangle washed round a round plate, which
/// is the same disagreement T-9535 fixed for corners, one shape further out. A plate now declares
/// its shape rather than a number, so the one hover layer meets the control it sits under.
// `nonisolated` because this file is compiled under default main-actor isolation, and a
// main-actor-isolated `Equatable` conformance cannot be used from the nonisolated context a
// `#expect` macro expands into -- 5 `IsolatedConformances` warnings, which are errors in the
// Swift 6 language mode. The plate is a value with no state and belongs on no actor.
nonisolated enum CadencePlainButtonPlate: Equatable {
    case roundedRectangle(CGFloat)
    case circle
    case capsule

    /// The hit shape. `AnyShape` is enough here because `contentShape` asks only for a `Shape`;
    /// the wash and its stroke are drawn case by case below, because `strokeBorder` needs an
    /// `InsettableShape` and erasing the plate would quietly demote it to `stroke` -- a hairline
    /// half a line width further out than every plate this style has ever drawn.
    var hitShape: AnyShape {
        switch self {
        case .roundedRectangle(let radius): AnyShape(RoundedRectangle(cornerRadius: radius))
        case .circle: AnyShape(Circle())
        case .capsule: AnyShape(Capsule())
        }
    }
}

/// **[[T-9535]], [[T-9601]].** `plate` is the shape the hover wash, its stroke and the hit shape
/// are drawn in. It defaults to a `Theme.radiusControl` rounded rectangle for a label with no
/// plate of its own; a label that paints its own plate passes that plate
/// (`.cadencePlain(cornerRadius: 8)`, `.cadencePlain(.circle)`), so the pointer lights one outline
/// that meets the plate's -- AGENTS.md's one-hover-layer-at-one-radius rule. Before T-9535 the
/// wash was always a 10pt rounded rectangle, and ~40 Mac plates (7, 8, 12, 14...) drew a second
/// outline that disagreed at the corners.
struct CadencePlainButtonStyle: ButtonStyle {
    var plate: CadencePlainButtonPlate = .roundedRectangle(Theme.radiusControl)

    func makeBody(configuration: Configuration) -> some View {
        CadencePlainButtonBody(configuration: configuration, plate: plate)
    }
}

private struct CadencePlainButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let plate: CadencePlainButtonPlate
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

    // **The wash and its stroke stay spelled out HERE, inside `body`, three cases each**, rather
    // than in two tidy `@ViewBuilder` properties beside it. `CadencePressFeedbackSurfaceTests`
    // cuts this body at the `#else` and counts the paint in each branch, so that the touch branch
    // can be proved to draw none; paint moved to a sibling property leaves that fence reading an
    // empty room. The duplication is the price of the guard and is deliberate.
    var body: some View {
        #if os(macOS)
        configuration.label
            .contentShape(plate.hitShape)
            .background {
                switch plate {
                case .roundedRectangle(let radius): RoundedRectangle(cornerRadius: radius).fill(Theme.blue.opacity(backgroundOpacity))
                case .circle: Circle().fill(Theme.blue.opacity(backgroundOpacity))
                case .capsule: Capsule().fill(Theme.blue.opacity(backgroundOpacity))
                }
            }
            .overlay {
                switch plate {
                case .roundedRectangle(let radius): RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.blue.opacity(strokeOpacity))
                case .circle: Circle().strokeBorder(Theme.blue.opacity(strokeOpacity))
                case .capsule: Capsule().strokeBorder(Theme.blue.opacity(strokeOpacity))
                }
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
            .contentShape(plate.hitShape)
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
        CadencePlainButtonStyle(plate: .roundedRectangle(cornerRadius))
    }

    /// The plain style around a label that paints a ROUND plate -- a `Circle` or a `Capsule`
    /// ([[T-9601]]). A radius cannot express either, and 10pt round a circle is the wash this
    /// spelling exists to stop.
    static func cadencePlain(_ plate: CadencePlainButtonPlate) -> CadencePlainButtonStyle {
        CadencePlainButtonStyle(plate: plate)
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
