import SwiftUI

/// Everything a task-group heading is drawn with, in one value.
///
/// It lives outside any platform guard for the usual reason — `Cadence/iOS/` is invisible to the
/// macOS-built test target — but also because the two figures below were the *whole* difference
/// between the two platforms' Today section headings, and neither was chosen. iOS drew its group
/// count at 11pt bold; macOS drew its section title at 11pt semibold in sentence case with a
/// neutral `Theme.dim` count beside it and no accent anywhere.
nonisolated struct CadenceTaskGroupHeadingMetrics: Equatable, Sendable {
    /// The count capsule's digits.
    ///
    /// **The same size as the label above it, not larger.** That is the finding `7e5459c` recorded
    /// for the board column header — a count is already demoted from its label by weight and by the
    /// capsule around it, so it must not also be bigger — and iOS's group count at 11pt against a
    /// 10pt eyebrow was the same exception in a second place.
    static let countSize: CGFloat = SectionEyebrowLabel.fontSize

    /// Between the label and the count when the heading is not spread across a row.
    static let spacing: CGFloat = 8

    static let countPaddingH: CGFloat = 8
    static let countPaddingV: CGFloat = 4

    /// **Whether a group draws a count capsule at all (T-264).** `nil` means the group does not
    /// know its own size — Apple Reminders while Cadence has not been allowed to look at them —
    /// and a capsule reading `0` there states a fact the app does not have: it reads as "nothing
    /// pending" when the truth is "cannot say". A real `0` is a real answer and keeps its capsule.
    ///
    /// This is a *decision*, not a measurement, and it is here rather than inline in either header
    /// because inline it was untestable. The rule lived twice, as an `if let` in two view bodies,
    /// and a macOS-built test target cannot call a SwiftUI `body` — so the only assertion anyone
    /// could write read the file as text, and it pinned `count`'s **type** rather than what the
    /// header does with it. A verifier changed one body to `countBadge(count ?? 0)`, putting
    /// "APPLE REMINDERS 0" back over the access card, and the whole suite stayed green. As a
    /// function the rule is an ordinary value to assert on, and both headers asking it is a single
    /// positive call-site check away from being pinned as well.
    static func showsCapsule(for count: Int?) -> Bool { count != nil }
}

/// A task group's heading: what the group is, in the group's own colour, and how many rows are
/// under it.
///
/// **The heading iOS's task surfaces share — Today, Inbox and All Tasks all draw this one row.**
/// It began as the settlement between `iOSTaskGroupHeader` and macOS's Today section header, which
/// were two spellings of one row disagreeing about more than measurements: iOS said what a group
/// *is* by tinting the label with the group's accent, macOS said it in neutral `Theme.dim`. The
/// accent is the point of an intent group — Overdue is red because it is overdue — so it wins.
///
/// The count is deliberately a single number. A split like "3 / 7" answers "how many of these are
/// late", which is a real question inside a *list* group and a tautology inside "Overdue".
///
/// **macOS's Today is no longer one of its callers, and that is a decision (T-605).** Desktop Today
/// draws `TaskListGroupHeader` now — 3×22pt bar, 14pt bold sentence case, split counts — because
/// All Tasks, Inbox and list detail beside it already did, and one desktop app with two group
/// headings was the sharper inconsistency. So the two platforms' headings differ on purpose;
/// **do not re-file that as drift.** The reasoning is on `TasksPanelIntentSectionView`. What both
/// headings still share is `CadenceTaskGroupHeadingMetrics.showsCapsule`, the rule about when a
/// count may be drawn at all — that one is not allowed to fork.
struct CadenceTaskGroupHeading: View {
    let title: String
    let tint: Color
    /// `nil` suppresses the capsule entirely rather than drawing `0`. **T-264:** a group that
    /// stands for reminders Cadence has not been allowed to look at does not know its own count,
    /// and `0` states a fact the app does not have — it reads as "nothing pending" when the truth
    /// is "cannot say". Every group that always has a real number keeps passing a plain `Int`,
    /// which converts implicitly.
    let count: Int?
    /// `true` where the heading owns the full width of its container and pushes the count to the
    /// trailing edge; `false` where it is a fragment of a wider row its host is assembling — macOS
    /// puts a disclosure chevron in front of this and lets the host's own `Spacer` place it.
    var spreads: Bool = true

    var body: some View {
        HStack(spacing: CadenceTaskGroupHeadingMetrics.spacing) {
            SectionEyebrowLabel(text: title, tint: tint)
                .lineLimit(1)

            if spreads {
                Spacer(minLength: CadenceTaskGroupHeadingMetrics.spacing)
            }

            // The rule is `showsCapsule`, asked of the optional; the `let` after it is only the
            // unwrap `countBadge` needs. Do not collapse the two into `if let count` — that is the
            // spelling macOS's header and this one drifted apart under, and it puts the T-264
            // decision somewhere no test can reach except by reading this file as text.
            if CadenceTaskGroupHeadingMetrics.showsCapsule(for: count), let count {
                countBadge(count)
            }
        }
    }

    private func countBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(.system(size: CadenceTaskGroupHeadingMetrics.countSize, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, CadenceTaskGroupHeadingMetrics.countPaddingH)
            .padding(.vertical, CadenceTaskGroupHeadingMetrics.countPaddingV)
            // The app's one count-capsule fill, already settled for the page header's badge when
            // iOS's 0.11 and macOS's 0.12 turned out to be two copies rather than two decisions.
            .background(tint.opacity(CadencePageHeaderMetrics.countFillOpacity))
            .clipShape(Capsule())
    }
}
