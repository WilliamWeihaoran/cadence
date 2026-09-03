import SwiftUI

/// What the startup-issue banner draws, for one issue in one of its two states.
///
/// This is a value type rather than a handful of `if isCollapsed` branches inside `body` because
/// the two things most likely to go wrong here are both invisible in a screenshot:
///
/// - The collapsed pill has to keep **naming the failure**. A chevron, a dot, or a bare icon would
///   satisfy "it collapses" and defeat the ticket — the failure is otherwise completely silent, and
///   an unlabelled glyph in the corner is silence with extra steps.
/// - Collapsing has to **drop the width cap**. The banner is only tappable now, so a collapsed pill
///   that kept `maxWidth: 620` would leave a 620pt-wide invisible tap target sitting over the
///   content, which is this repo's oldest UI defect wearing a new hat: a hit area that does not
///   match what was drawn.
///
/// `CadenceTests` builds for macOS and cannot see anything under `#if os(iOS)`, so keeping the
/// decision out here is also what makes it pinnable at all.
struct CadenceStartupIssueBannerModel: Equatable {
    let issue: CadenceStartupIssue
    let isCollapsed: Bool

    /// The expanded banner's width cap — wide enough to read a two-line detail on a Mac, and
    /// wider than any phone, which is exactly why the expanded form covers an iPhone's top strip.
    static let expandedMaxWidth: CGFloat = 620

    init(issue: CadenceStartupIssue, isCollapsed: Bool) {
        self.issue = issue
        self.isCollapsed = isCollapsed
    }

    /// `nil` when collapsed, so the pill hugs its content instead of reserving the expanded
    /// banner's footprint. The tap region is derived from this, so `nil` is load-bearing.
    var maxWidth: CGFloat? { isCollapsed ? nil : Self.expandedMaxWidth }

    var iconName: String { issue.bannerIcon }

    var tone: CadenceSyncHealthTone { issue.bannerTone }

    /// The headline, in whichever length this state can afford.
    var title: String { isCollapsed ? collapsedTitle : issue.bannerTitle }

    /// The short form used by the collapsed pill.
    ///
    /// `recoveryStore` reuses its full title because that title is already four words; the rest
    /// are shortened. Every one of them still says what is broken.
    var collapsedTitle: String {
        switch issue.kind {
        case .recoveryStore: return "iCloud Sync Is Off"
        case .inMemoryStore: return "Changes Are Not Saved"
        case .maintenanceSaveFailed: return "Maintenance Failed"
        case .restoreFailed: return "Restore Did Not Run"
        }
    }

    /// `nil` when collapsed. The detail line is what makes the expanded banner tall, and the
    /// height is what buries an iPhone page header and the pushed-Settings back chevron.
    var detail: String? { isCollapsed ? nil : issue.bannerDetail }

    /// Snug around the pill, roomier around the full banner.
    var horizontalPadding: CGFloat { isCollapsed ? 12 : 16 }
    var verticalPadding: CGFloat { isCollapsed ? 8 : 12 }

    /// The collapsed pill is a single line, so its icon centres against the text; the expanded
    /// banner's icon has to sit against the first line of a wrapping detail paragraph.
    var stackAlignment: VerticalAlignment { isCollapsed ? .center : .top }

    /// Only the expanded banner pushes its content to the leading edge of the 620pt cap.
    var fillsAvailableWidth: Bool { !isCollapsed }

    var accessibilityLabel: String {
        isCollapsed ? collapsedTitle : "\(issue.bannerTitle). \(issue.bannerDetail)"
    }

    /// Never "dismiss" — but no longer because macOS has nowhere else to show a failure. It does:
    /// `SettingsSyncSection` folds `PersistenceController.startupIssue` into
    /// `CadenceSyncHealth.resolve`, and `.sync` is filed under "Connections" in the rail. The claim
    /// that used to sit here — that only iOS renders `CadenceSyncHealth` — was true when written and
    /// is now false.
    ///
    /// Two reasons survive it, both narrower and both enforced elsewhere rather than asserted here.
    ///
    /// **One: the pane only sees half the kinds.** `resolve` reacts to a kind whose
    /// `disablesCloudSync` is true, and that gate is deliberate — reporting a maintenance-save
    /// failure as a sync failure "would be its own lie", per `CadenceStartupIssueKind`. So
    /// `.maintenanceSaveFailed` and `.restoreFailed` reach no Settings pane on *either* platform, and
    /// for those two this banner is still the only durable indicator in the app.
    ///
    /// **Two: one kind cannot safely be hidden at all.** `.inMemoryStore` has `losesDataOnQuit`, so a
    /// dismiss would let someone hide the warning and then quit, losing everything written this
    /// launch. Collapse keeps the affordance on screen; dismiss does not.
    ///
    /// Both facts are pinned by `CadenceSyncHealthTests`, not by this comment.
    var accessibilityHint: String {
        isCollapsed ? "Expands to show what went wrong." : "Collapses to a compact badge."
    }

    func toggled() -> CadenceStartupIssueBannerModel {
        CadenceStartupIssueBannerModel(issue: issue, isCollapsed: !isCollapsed)
    }
}

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
///
/// **Tapping it collapses it to a pill, and tapping the pill expands it again** (T-154). At
/// `maxWidth: 620` this thing is wider than any iPhone, so on a 390pt phone the expanded form
/// covered the whole top strip for the entire launch — page headers, and on a pushed Settings
/// category the navigation back chevron. It was `allowsHitTesting(false)`, so those controls still
/// worked; they were simply invisible. Collapsing is the same behaviour on all three shells, not a
/// compact-width fork: a Mac window is wide enough that the banner occludes nothing, but a user who
/// has read it once should still be able to put it away there too.
///
/// It does **not** dismiss, on any platform — see the note on `accessibilityHint` for the reason,
/// which is no longer the one that used to be written here. macOS *does* have a sync pane now
/// (`SettingsSyncSection`, under "Connections"), so "a Mac has no indicator anywhere" is false; what
/// holds is that the pane only reacts to kinds whose `disablesCloudSync` is true, and that
/// `.inMemoryStore` loses data on quit.
struct CadenceStartupIssueBanner: View {
    let issue: CadenceStartupIssue

    /// Deliberately `@State` and deliberately not `@AppStorage`. See the note on
    /// `View.cadenceStartupIssueBanner(_:)`.
    @State private var isCollapsed = false

    private var model: CadenceStartupIssueBannerModel {
        CadenceStartupIssueBannerModel(issue: issue, isCollapsed: isCollapsed)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.radiusPanel)
    }

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) { isCollapsed.toggle() }
        } label: {
            banner
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityHint(model.accessibilityHint)
    }

    private var banner: some View {
        HStack(alignment: model.stackAlignment, spacing: 10) {
            Image(systemName: model.iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(model.tone.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                if let detail = model.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if model.fillsAvailableWidth {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, model.horizontalPadding)
        .padding(.vertical, model.verticalPadding)
        .frame(maxWidth: model.maxWidth)
        .background(Theme.surfaceElevated)
        .overlay {
            shape.strokeBorder(model.tone.tint.opacity(0.22), lineWidth: 1)
        }
        .clipShape(shape)
        .shadow(color: Theme.overlayCardShadow, radius: 22, x: 0, y: 10)
        // The whole tap region, and the last word on it: the same rounded rect that is filled, at
        // the frame the fill actually occupies. Not the shadow, not the corners it rounds off, and
        // — because `model.maxWidth` is nil when collapsed — not the expanded banner's width once
        // the pill has shrunk away from it.
        .contentShape(shape)
    }
}

extension View {
    /// Floats the startup-issue banner over the top of a root shell, or nothing when there is no
    /// issue.
    ///
    /// One modifier so the three shells (macOS split view, iPad sidebar, iPhone tab bar) cannot
    /// end up with three different insets for the same banner.
    ///
    /// **The collapsed state is per-launch, not persisted.** Both readings are defensible and this
    /// one was chosen: a banner that re-announces itself at full height on every launch is noisy,
    /// but `PersistenceController.startupIssue` is *already* per-launch — it is recomputed at
    /// `init` and is nil unless **this** launch failed to open the store it asked for, so the
    /// banner appearing at all is new information about the session in front of you. An
    /// `@AppStorage` flag would also be keyed on the collapse gesture rather than on the issue, so
    /// collapsing a `recoveryStore` banner once would silently pre-collapse a later
    /// `inMemoryStore` one — the strictly worse failure, where quitting discards the session —
    /// down to a pill the user never chose to shrink. The cost of the choice is one tap per launch,
    /// and only on a launch that is genuinely degraded.
    ///
    /// The overlay's padding is outside the banner's `contentShape`, so taps that land in the
    /// 14/18pt inset — or anywhere else beside the drawn shape — pass through to the shell.
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
