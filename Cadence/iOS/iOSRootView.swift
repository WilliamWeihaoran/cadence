#if os(iOS)
import SwiftUI

struct iOSRootView: View {
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let _ = themeManager.selectedTheme

        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "iphone")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.blue)
                Text("iOS coming soon")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Building macOS first")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.dim)
            }
        }
        .preferredColorScheme(.dark)
    }
}
#endif
