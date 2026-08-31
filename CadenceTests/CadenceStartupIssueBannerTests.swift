import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// The startup-issue banner's collapse decision (T-154).
///
/// The defect these pin: the banner is `.frame(maxWidth: 620)` centred at the top of every shell.
/// On a 390pt iPhone that is the entire top strip, for the whole launch — page headers, and on a
/// pushed Settings category the navigation back chevron. It was `allowsHitTesting(false)`, so the
/// controls underneath still responded and were simply invisible, which is the worst version of the
/// bug: nothing looks broken, the taps just land on something the user cannot see.
///
/// Collapsing brings hit testing back on, and that is what makes the width behaviour testable
/// rather than cosmetic. A collapsed pill that kept the 620pt cap would leave an invisible tap
/// target the size of the old banner sitting over the content — a hit area that does not match what
/// was drawn, which this repo has shipped before.
@MainActor
struct CadenceStartupIssueBannerTests {
    private let recovery = CadenceStartupIssue(
        kind: .recoveryStore,
        message: "Cadence opened a recovery store because the CloudKit store could not be created."
    )
    private let inMemory = CadenceStartupIssue(
        kind: .inMemoryStore,
        message: "Recovery store creation also failed, so Cadence opened a temporary in-memory store."
    )
    private let maintenance = CadenceStartupIssue(
        kind: .maintenanceSaveFailed,
        message: "Cadence could not save startup maintenance changes: disk full."
    )

    private var allIssues: [CadenceStartupIssue] { [recovery, inMemory, maintenance] }

    private func expanded(_ issue: CadenceStartupIssue) -> CadenceStartupIssueBannerModel {
        CadenceStartupIssueBannerModel(issue: issue, isCollapsed: false)
    }

    private func collapsed(_ issue: CadenceStartupIssue) -> CadenceStartupIssueBannerModel {
        CadenceStartupIssueBannerModel(issue: issue, isCollapsed: true)
    }

    // MARK: - The width cap, which is the occlusion

    @Test func expandedBannerKeepsTheWidthCap() {
        for issue in allIssues {
            #expect(expanded(issue).maxWidth == CadenceStartupIssueBannerModel.expandedMaxWidth)
            #expect(expanded(issue).fillsAvailableWidth)
        }
    }

    /// The one that matters for the tap target: `nil`, not "some smaller number". A pill with any
    /// width cap at all still reserves that width, and its `contentShape` is derived from this.
    @Test func collapsedPillDropsTheWidthCapEntirely() {
        for issue in allIssues {
            #expect(collapsed(issue).maxWidth == nil)
            #expect(!collapsed(issue).fillsAvailableWidth)
        }
    }

    @Test func expandedCapIsWiderThanAnIPhone() {
        // 430pt is the widest current iPhone in points. The cap exceeding it is *why* the expanded
        // banner spans the whole top strip there — if this ever drops below it, the ticket's
        // premise changed and the collapse default should be revisited rather than silently kept.
        #expect(CadenceStartupIssueBannerModel.expandedMaxWidth > 430)
    }

    // MARK: - The collapsed pill still names the failure

    @Test func collapsedPillKeepsATitleThatNamesTheFailure() {
        for issue in allIssues {
            let title = collapsed(issue).collapsedTitle
            #expect(!title.isEmpty)
            #expect(collapsed(issue).title == title)
            // Short, but not a glyph. A bare icon would satisfy "it collapses" and reintroduce the
            // silence the banner exists to break.
            #expect(title.split(separator: " ").count >= 2)
            #expect(title.count <= issue.bannerTitle.count)
            #expect(title.count < issue.bannerDetail.count)
        }
    }

    @Test func collapsedTitleIsSpecificToTheIssue() {
        let titles = allIssues.map { collapsed($0).collapsedTitle }
        #expect(Set(titles).count == allIssues.count)
        #expect(collapsed(recovery).collapsedTitle == "iCloud Sync Is Off")
    }

    @Test func expandedBannerShowsTheFullTitleAndDetail() {
        for issue in allIssues {
            #expect(expanded(issue).title == issue.bannerTitle)
            #expect(expanded(issue).detail == issue.bannerDetail)
        }
    }

    /// The detail paragraph is what makes the banner tall enough to bury a page header.
    @Test func collapsedPillDropsTheDetailParagraph() {
        for issue in allIssues {
            #expect(collapsed(issue).detail == nil)
        }
    }

    // MARK: - Severity survives collapsing

    /// Collapsing is a size change, not a downgrade. An in-memory store still gets the critical
    /// tint and its own icon while it is a pill, or the user has traded the occlusion for a signal
    /// that no longer distinguishes "not syncing" from "quitting loses your work".
    @Test func toneAndIconComeFromTheIssueInBothStates() {
        for issue in allIssues {
            #expect(expanded(issue).tone == issue.bannerTone)
            #expect(collapsed(issue).tone == issue.bannerTone)
            #expect(expanded(issue).iconName == issue.bannerIcon)
            #expect(collapsed(issue).iconName == issue.bannerIcon)
        }
        #expect(collapsed(inMemory).tone == .critical)
        #expect(collapsed(recovery).tone == .caution)
    }

    // MARK: - Toggling

    @Test func togglingRoundTrips() {
        let start = expanded(recovery)
        #expect(!start.isCollapsed)
        #expect(start.toggled().isCollapsed)
        #expect(start.toggled().toggled() == start)
        #expect(start.toggled().toggled().maxWidth == CadenceStartupIssueBannerModel.expandedMaxWidth)
    }

    @Test func togglingPreservesTheIssue() {
        for issue in allIssues {
            #expect(expanded(issue).toggled().issue == issue)
        }
    }

    // MARK: - Chrome shrinks with the content

    @Test func collapsedPillIsTighterThanTheExpandedBanner() {
        for issue in allIssues {
            #expect(collapsed(issue).horizontalPadding < expanded(issue).horizontalPadding)
            #expect(collapsed(issue).verticalPadding < expanded(issue).verticalPadding)
        }
    }

    /// One line centres against its icon; a wrapping paragraph does not.
    @Test func alignmentFollowsWhetherThereIsADetailParagraph() {
        #expect(collapsed(recovery).stackAlignment == .center)
        #expect(expanded(recovery).stackAlignment == .top)
    }

    // MARK: - Accessibility, and the thing this control must never be

    @Test func accessibilityLabelMatchesWhatIsDrawn() {
        for issue in allIssues {
            #expect(collapsed(issue).accessibilityLabel == collapsed(issue).collapsedTitle)
            #expect(expanded(issue).accessibilityLabel.contains(issue.bannerTitle))
            #expect(expanded(issue).accessibilityLabel.contains(issue.bannerDetail))
        }
    }

    /// Collapse, never dismiss — and the old reason for it has expired. This comment used to say
    /// macOS Settings has no sync row; `SettingsSyncSection` is one, filed under "Connections", and
    /// it renders `CadenceSyncHealth` built from `PersistenceController.startupIssue`.
    ///
    /// The behaviour is unchanged because two better reasons hold. The pane only reacts to kinds
    /// whose `disablesCloudSync` is true, so `.maintenanceSaveFailed` and `.restoreFailed` — half of
    /// `CadenceStartupIssueKind` — still reach no Settings pane on either platform. And
    /// `.inMemoryStore` loses data on quit, so a dismissible warning is one a user could hide and
    /// then quit behind.
    ///
    /// `CadenceSyncHealthTests` pins both facts. If either changes, this test's reason should be
    /// re-argued rather than this comment quietly re-edited.
    @Test func theControlNeverOffersToDismiss() {
        for issue in allIssues {
            for hint in [collapsed(issue).accessibilityHint, expanded(issue).accessibilityHint] {
                let lowered = hint.lowercased()
                #expect(!lowered.contains("dismiss"))
                #expect(!lowered.contains("close"))
                #expect(!lowered.contains("hide"))
                #expect(!hint.isEmpty)
            }
        }
        #expect(collapsed(recovery).accessibilityHint != expanded(recovery).accessibilityHint)
    }
}
