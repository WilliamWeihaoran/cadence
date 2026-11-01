#if os(macOS)
import SwiftUI

enum SettingsActionTone {
    case filled(Color)
    case tinted(Color)
}

/// **[[T-9822]].** How strongly a Settings action button draws, by whether it can be pressed.
///
/// The button paints its own label colour and plate, so `.disabled` alone left it at full
/// strength: Reminders' "Refresh" and Sync's "Check iCloud Status" are switched off while their
/// fetch runs and still read as live buttons. Three other callers (Create Tag, the tag editor's
/// Save, Reset Template) each re-spelled a `0.45` fade beside their `.disabled`; the fade is the
/// button's now, read from the environment `.disabled` sets, so no caller can forget it and none
/// fades it twice.
enum SettingsActionButtonMetrics {
    static let disabledOpacity: Double = 0.45

    static func opacity(isEnabled: Bool) -> Double {
        isEnabled ? 1 : disabledOpacity
    }
}

struct SettingsActionButton<Label: View>: View {
    let tone: SettingsActionTone
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(foregroundColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.cadencePlain(cornerRadius: 8))
        .opacity(SettingsActionButtonMetrics.opacity(isEnabled: isEnabled))
    }

    private var foregroundColor: Color {
        switch tone {
        case .filled(let color):
            return Theme.onColor(for: color)
        case .tinted(let color):
            return color
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .filled(let color):
            return color
        case .tinted(let color):
            return color.opacity(0.12)
        }
    }
}
#endif
