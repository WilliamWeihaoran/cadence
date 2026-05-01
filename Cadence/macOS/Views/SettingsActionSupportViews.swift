#if os(macOS)
import SwiftUI

enum SettingsActionTone {
    case filled(Color)
    case tinted(Color)
}

struct SettingsActionButton<Label: View>: View {
    let tone: SettingsActionTone
    let action: () -> Void
    @ViewBuilder let label: () -> Label

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
        .buttonStyle(.cadencePlain)
    }

    private var foregroundColor: Color {
        switch tone {
        case .filled:
            return .white
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
