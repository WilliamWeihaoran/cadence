import SwiftUI

/// The startup-issue banner, drawn identically on macOS, iPhone and iPad.
///
/// This was a `private struct RootStartupIssueBanner` inside `macOSRootView.swift` and had no iOS
/// equivalent at all, so a store that had silently dropped to a local recovery container was a
/// visible banner on a Mac and nothing whatsoever on an iPad. It is shared rather than copied
/// because it is plain SwiftUI over `Theme` — there was never anything platform-specific in it,
/// and the copy would have started drifting on the first restyle.
///
/// Placement is the part that legitimately differs, and it is the part each root still supplies —
/// see `View.cadenceStartupIssueBanner(_:)`.
struct CadenceStartupIssueBanner: View {
    let issue: CadenceStartupIssue

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: issue.bannerIcon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(issue.bannerTone.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(issue.bannerTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(issue.bannerDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 620)
        .background(Theme.surfaceElevated)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusPanel)
                .stroke(issue.bannerTone.tint.opacity(0.22), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusPanel))
        .shadow(color: Theme.overlayCardShadow, radius: 22, x: 0, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(issue.bannerTitle). \(issue.bannerDetail)")
        // Purely informational, and it sits over the top of the shell on every platform — on
        // iPhone directly over the first rows of the Tasks tab. It must not eat the taps meant
        // for what is behind it.
        .allowsHitTesting(false)
    }
}

extension View {
    /// Floats the startup-issue banner over the top of a root shell, or nothing when there is no
    /// issue.
    ///
    /// One modifier so the three shells (macOS split view, iPad sidebar, iPhone tab bar) cannot
    /// end up with three different insets for the same banner.
    func cadenceStartupIssueBanner(_ issue: CadenceStartupIssue?) -> some View {
        overlay(alignment: .top) {
            if let issue {
                CadenceStartupIssueBanner(issue: issue)
                    .padding(.top, 14)
                    .padding(.horizontal, 18)
            }
        }
    }
}
