#if os(macOS)
import SwiftUI

enum CadenceActionButtonRole {
    case primary
    case secondary
    case ghost
    case destructive
}

enum CadenceActionButtonSize {
    case compact
    case regular

    var fontSize: CGFloat {
        switch self {
        case .compact: 12
        case .regular: 13
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .compact: 12
        case .regular: 16
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .compact: 7
        case .regular: 9
        }
    }

    var minHeight: CGFloat {
        switch self {
        case .compact: 30
        case .regular: 34
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .compact: 8
        case .regular: 10
        }
    }
}

struct CadenceActionButton: View {
    let title: String
    var systemImage: String?
    var role: CadenceActionButtonRole = .secondary
    var size: CadenceActionButtonSize = .regular
    var tint: Color?
    var minWidth: CGFloat?
    var fullWidth = false
    var isDisabled = false
    var shortcut: KeyboardShortcut?
    let action: () -> Void

    private var resolvedTint: Color {
        tint ?? defaultTint
    }

    private var defaultTint: Color {
        switch role {
        case .primary, .secondary, .ghost:
            Theme.blue
        case .destructive:
            Theme.red
        }
    }

    private var foreground: Color {
        switch role {
        case .primary:
            .white
        case .secondary:
            resolvedTint
        case .ghost:
            Theme.muted
        case .destructive:
            Theme.red
        }
    }

    private var background: Color {
        switch role {
        case .primary:
            resolvedTint
        case .secondary:
            resolvedTint.opacity(0.10)
        case .ghost:
            Color.clear
        case .destructive:
            Theme.red.opacity(0.12)
        }
    }

    private var border: Color {
        switch role {
        case .primary, .ghost:
            Color.clear
        case .secondary:
            resolvedTint.opacity(0.18)
        case .destructive:
            Theme.red.opacity(0.24)
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size.cornerRadius)

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
            .padding(.vertical, size.verticalPadding)
            .frame(minWidth: minWidth, maxWidth: fullWidth ? .infinity : nil, minHeight: size.minHeight)
            .background(shape.fill(background))
            .overlay(shape.strokeBorder(border, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.cadencePlain)
        .keyboardShortcut(shortcut)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.52 : 1)
    }
}

struct CadencePillButton: View {
    let title: String
    let isSelected: Bool
    var minWidth: CGFloat?
    var tint: Color = Theme.blue
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? tint : Theme.dim)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(minWidth: minWidth, minHeight: 30)
                .background(Capsule().fill(isSelected ? tint.opacity(0.12) : Color.clear))
                .overlay(Capsule().strokeBorder(isSelected ? tint.opacity(0.24) : Color.clear, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.cadencePlain)
    }
}
#endif
