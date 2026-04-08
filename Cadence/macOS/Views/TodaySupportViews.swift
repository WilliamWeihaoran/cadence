#if os(macOS)
import SwiftUI

struct PanelHeader: View {
    let eyebrow: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(eyebrow.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .kerning(0.8)
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }
}
#endif
