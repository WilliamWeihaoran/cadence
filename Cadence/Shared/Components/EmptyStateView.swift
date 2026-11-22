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
                // T-10015: centred like the subtitle, so a heading that wraps at an accessibility
                // size does not sit flush left under the centred icon.
                Text(message)
                    .cadenceFont(.bodyText, weight: .semibold)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
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

    /// The shared notice, set 2pt under the subtitle. The reading itself is
    /// `CadenceColdImportNoticeLine`, which a hand-built empty state draws too ([[T-14431]]).
    private var coldImportNotice: some View {
        CadenceColdImportNoticeLine()
            .padding(.top, 2)
    }
}

/// **[[T-14431]]: the cold-import sentence, as one view any empty state of the store can draw.**
///
/// Lifted out of `EmptyStateView` (T-3041) because the Mac's Focus "Pick a task" card draws its
/// own hand-built empty state and so never said what iOS's Focus page, over the same state, says.
/// Draws nothing at all when `CadenceColdImportNotice.text` answers `nil`, so a caller places it
/// unconditionally and gets silence in every state but one.
///
/// **Re-read on a 30 s tick while it stands, so the line can retire on its own.** The owner's
/// ruling is "disappear when they stop", and stopping is a fact about the clock rather than about
/// the summary: an import that stalls posts no further event, so an `@Observable` read alone would
/// leave the sentence standing for the rest of the launch — the exact "never clears" failure the
/// ticket was filed against. So while the notice is drawn, a task bumps `tick` at twice the rate
/// of `CadenceColdImportNotice.progressWindow` and the body asks again; an import that starts is
/// an event, which the `@Observable` read already answers.
///
/// **[[T-19622]]: silence is no child at all.** This read through a `TimelineView`, which is a
/// child of its stack even when its content is empty, so every stack holding the line charged
/// its spacing for nothing — 7 pt of dead space under the Mac Focus "Pick a task" subtitle in
/// every state but a running import. An `if` with no content is dropped by a stack outright, so
/// the clock lives on the notice it refreshes rather than around it.
///
/// `.informational` and not an accent: a sentence under an empty state is secondary to it.
struct CadenceColdImportNoticeLine: View {
    /// Read by `body` only so that bumping it asks the question again; `Date.now` is the clock.
    @State private var tick = 0

    var body: some View {
        let _ = tick
        if let text = CadenceColdImportNotice.text(
            for: CadenceSyncActivityLog.shared.summary,
            now: .now
        ) {
            CadenceInlineNotice(text: text, tone: .informational)
                .task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(30))
                        tick &+= 1
                    }
                }
        }
    }
}
