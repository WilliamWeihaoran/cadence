#if os(macOS)
import SwiftUI

let todayPanelHeaderHeight: CGFloat = 100

struct PanelHeader: View {
    let eyebrow: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(eyebrow.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .kerning(0.8)
            Text(title)
                .font(.system(size: CadenceDesktopMetrics.pageTitleSize, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
        }
        .padding(.horizontal, CadenceDesktopMetrics.pageHorizontalPadding)
        .padding(.top, CadenceDesktopMetrics.pageHeaderTopPadding)
        .padding(.bottom, CadenceDesktopMetrics.pageHeaderBottomPadding)
    }
}
#endif
