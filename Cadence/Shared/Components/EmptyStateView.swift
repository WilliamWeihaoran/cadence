import SwiftUI

nonisolated enum CadenceEmptyStateMetrics {
    static func iconSide(at size: DynamicTypeSize, scaling: CadenceTypographyScaling) -> CGFloat {
        CadenceTypeScale.height(72, holding: .bodyText, textBase: 26, at: size, scaling: scaling)
    }
}

struct EmptyStateView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling
    let message: String
    var subtitle: String = ""
    let icon: String
    /// **T-3041: an empty screen during a cold iCloud import says so.**
    ///
    /// On by default, and on *here* rather than at each call site, because this view is what every
    /// main surface draws when it has nothing — which is precisely the screen a tester restoring
    /// an existing account meets, and precisely the screen that cannot otherwise be told apart
    /// from a broken install. `CadenceColdImportNotice` owns every condition; this flag only
    /// exists so a host that is not a view of the store (a picker with no matches, a preview) can
    /// opt out of a sentence about syncing.
    var statesColdImport: Bool = true

    var body: some View {
        let side = CadenceEmptyStateMetrics.iconSide(at: dynamicTypeSize, scaling: scaling)
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.dim.opacity(0.07))
                    .frame(width: side, height: side)
                Circle()
                    .strokeBorder(Theme.dim.opacity(0.12), lineWidth: 1)
                    .frame(width: side, height: side)
                Image(systemName: icon)
                    .cadenceFont(.bodyText, base: 26, weight: .regular)
                    .foregroundStyle(Theme.dim.opacity(0.6))
            }

            VStack(spacing: 5) {
                Text(message)
                    .cadenceFont(.bodyText, weight: .semibold)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: scaling == .enabled)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .cadenceFont(.fieldLabel, weight: .regular)
                        .foregroundStyle(Theme.dim)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: scaling == .enabled)
                }
            }

            if statesColdImport {
                coldImportNotice
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    /// **Read through a `TimelineView` so the line can retire on its own.**
    ///
    /// The owner's ruling is "disappear when they stop", and stopping is a fact about the clock
    /// rather than about the summary: an import that stalls posts no further event, so an
    /// `@Observable` read alone would leave the sentence standing for the rest of the launch —
    /// the exact "never clears" failure the ticket was filed against. The view therefore takes a
    /// ticking `now`, at twice the rate of `CadenceColdImportNotice.progressWindow`.
    ///
    /// `.informational` and not an accent: a sentence under an empty state is secondary to it.
    @ViewBuilder
    private var coldImportNotice: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let text = CadenceColdImportNotice.text(
                for: CadenceSyncActivityLog.shared.summary,
                now: context.date
            ) {
                CadenceInlineNotice(text: text, tone: .informational)
                    .padding(.top, 2)
            }
        }
    }
}
