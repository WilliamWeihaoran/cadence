#if os(iOS)
import SwiftUI

/// Everything the one wind-down confirmation draws, and nothing about which container it came from.
///
/// **One sheet, two containers, and that is the point.** T-215 gave lists a confirmation before an
/// archive that irreversibly cancels their open tasks; T-247 needed the identical question asked of
/// a kanban column, in both directions (archiving cancels, completing marks done). The two agree on
/// nothing except the shape of the question, so the shape is what is shared: a headline, what the
/// reversible half does, the subject's own identity, and the settle's own count. A second sheet
/// would have been a near-copy of a hundred lines of chrome that then drifted — the estimate picker
/// and the three kanban boards are this repo's standing examples.
struct iOSWindDownSubject {
    /// Names the action, and is the navigation title and the button title both: "Archive Area",
    /// "Archive Column", "Complete Column". A confirmation whose button says something other than
    /// its title is a confirmation you have to read twice.
    let title: String
    let actionIcon: String
    let headline: String
    /// What the *reversible* half does, said plainly, so the irreversible half below can be read
    /// against it. This is the sentence the whole sheet exists for.
    let explanation: String
    let name: String
    let icon: String
    let colorHex: String
    /// Shown instead of `summary.settledLine` when there is nothing open. Reachable only when a
    /// caller presents the sheet anyway — the decision points do not, because
    /// `requiresConfirmation` is false — so it is a truthful fallback rather than a state to design
    /// around.
    let emptyNote: String
    let summary: CadenceContainerWindDownSummary
}

/// The confirmation. One view for iPhone and iPad — they differ in the width it is handed, not in
/// what it says or how it is armed.
///
/// **Why a confirmation at all, when macOS has none.** macOS's archive lives in the footer of an
/// edit sheet you had to open, or in a column popover you had to open; iOS's live on a row swipe, a
/// long-press menu item and a list-editor row. The settle underneath them is identical, so the
/// ceremony has to come from somewhere, and here it is the only place it can. It is deliberately
/// *conditional*: `requiresConfirmation` is false when the container has no open work, and then the
/// gesture just acts. A sheet that appears every time — including where the answer is "nothing
/// happens" — is a sheet people learn to dismiss without reading, which is the same argument the
/// delete confirmation makes against a typed phrase.
///
/// **Why no typed phrase here either.** The action is scoped, the scope is knowable, and it is
/// stated: N open tasks. The container itself is recoverable; what is not is the settle, and saying
/// so plainly is a better signal than making someone type a word.
struct iOSWindDownConfirmationSheet: View {
    let subject: iOSWindDownSubject
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// Cancelling is destructive and reads red; finishing work is not, and a red "Complete Column"
    /// would be the button lying about what it does. Derived from the outcome rather than carried
    /// on the subject, so the two callers cannot disagree about which is which.
    private var isCancelling: Bool {
        subject.summary.outcome != .done
    }

    private var accent: Color {
        isCancelling ? Theme.amber : Theme.green
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    iOSSettingsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: iOSSettingsMetrics.glyphLabelSpacing) {
                                iOSIconTile(
                                    systemImage: subject.actionIcon,
                                    color: accent,
                                    size: 34,
                                    iconSize: 16
                                )

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(subject.headline)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(Theme.text)

                                    Text(subject.explanation)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.subdued)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer(minLength: 0)
                            }

                            iOSRowDivider()

                            Text("Cadence syncs through your private iCloud database, so this reaches your other devices.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    CadenceSettingsSectionLabel(text: isCancelling ? "What Gets Cancelled" : "What Gets Marked Done")

                    iOSSettingsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: iOSSettingsMetrics.glyphLabelSpacing) {
                                iOSIconTile(
                                    systemImage: subject.icon,
                                    color: Color(hex: subject.colorHex),
                                    size: iOSSettingsMetrics.glyphSlot,
                                    iconSize: 15
                                )

                                Text(subject.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(2)

                                Spacer(minLength: 0)
                            }

                            iOSRowDivider()

                            if let line = subject.summary.settledLine {
                                HStack(spacing: 8) {
                                    Image(systemName: isCancelling ? "xmark.circle" : "checkmark.circle")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(isCancelling ? Theme.red : Theme.green)

                                    Text(line)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Theme.text)

                                    Spacer(minLength: 0)
                                }
                            } else {
                                Text(subject.emptyNote)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.subdued)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    iOSActionButton(
                        title: subject.title,
                        systemImage: subject.actionIcon,
                        role: isCancelling ? .destructive : .primary,
                        size: .regular,
                        tint: isCancelling ? nil : Theme.green,
                        fullWidth: true,
                        action: {
                            dismiss()
                            onConfirm()
                        }
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(subject.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .tint(Theme.blue)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
#endif
