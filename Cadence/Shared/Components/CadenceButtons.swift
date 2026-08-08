#if os(macOS)
import SwiftUI

enum CadenceDesktopMetrics {
    static let pageHorizontalPadding: CGFloat = 18
    static let pageHeaderTopPadding: CGFloat = 18
    static let pageHeaderBottomPadding: CGFloat = 12
    static let pageTitleSize: CGFloat = 22
    static let bodyTextSize: CGFloat = 13
    static let secondaryTextSize: CGFloat = 12
    static let compactControlHeight: CGFloat = 30
    static let regularControlHeight: CGFloat = 34
    static let controlCornerRadius: CGFloat = 8
    static let panelCornerRadius: CGFloat = 12
}

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
        case .compact: CadenceDesktopMetrics.compactControlHeight
        case .regular: CadenceDesktopMetrics.regularControlHeight
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .compact: CadenceDesktopMetrics.controlCornerRadius
        case .regular: 10
        }
    }
}

struct CadenceIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var tint: Color = Theme.dim
    var isSelected = false
    var isEnabled = true
    var size: CGFloat = CadenceDesktopMetrics.compactControlHeight
    var iconSize: CGFloat = 11
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CadenceDesktopMetrics.controlCornerRadius, style: .continuous)

        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(isEnabled ? (isSelected ? tint : Theme.muted) : Theme.dim.opacity(0.36))
                .frame(width: size, height: size)
                .background(shape.fill(backgroundFill))
                .overlay(shape.strokeBorder(borderColor, lineWidth: 1))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var backgroundFill: Color {
        if isSelected {
            return tint.opacity(0.14)
        }
        if isHovered && isEnabled {
            return Theme.surfaceElevated.opacity(0.9)
        }
        return Color.clear
    }

    private var borderColor: Color {
        if isSelected {
            return tint.opacity(0.28)
        }
        if isHovered && isEnabled {
            return Theme.borderSubtle.opacity(0.72)
        }
        return Theme.borderSubtle.opacity(0.28)
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
            Theme.onColor
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
