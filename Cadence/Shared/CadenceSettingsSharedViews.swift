import SwiftUI

/// The one card every settings pane and every field group is drawn on, both platforms.
///
/// **It was a hard-bordered radius-12 rectangle here and a soft-elevation `Theme.radiusCard` one
/// on iOS (`iOSSettingsCard`), and the iOS file said so in as many words** — "Local stand-in for
/// the shared `CadenceSettingsCard` … the shared component keeps its original hard-border,
/// radius-12 treatment because macOS settings and `iPadInboxView` still rely on it as-is". Half of
/// that had already stopped being true: `iPadInboxView` does not mention this type, and macOS
/// Settings was the only caller left. T-20 gave the shared card the soft treatment and made the
/// iOS spelling a wrapper, so there is one rectangle rather than two.
///
/// `padding` is the one genuine difference and it is a parameter rather than a fork: macOS insets
/// 14 and iOS 16, and `CadenceSettingsTemplatesCardLayoutTests` models both chrome chains down to
/// the point, so the two figures are measured rather than accidental.
struct CadenceSettingsCard<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder let content: Content

    init(padding: CGFloat = 14, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .cadenceCard(
                background: Theme.surface,
                cornerRadius: Theme.radiusCard,
                shadowRadius: 14,
                shadowY: 6
            )
    }
}

struct CadenceSettingsSectionLabel: View {
    let text: String

    var body: some View {
        SectionEyebrowLabel(text: text)
    }
}

#if os(macOS)
/// The Settings detail column's category header: a `.page`-role `DesktopPageHeader` inside the
/// shared settings card.
///
/// macOS-only, like its one caller `SettingsDetailHeader` — iOS has `iOSSettingsPageHeader`, which
/// is the same wrapper over `iOSPageHeader`, and reached this shape first.
///
/// It used to draw its own rounded square at 42/17 and set its title `.semibold` at 18pt while the
/// other three macOS headers were bold at 22 — a header whose identity tile outweighed its own
/// name, and a fourth glyph ratio. The card supplies the padding, hence `padded: false`.
///
/// **It also used to take arbitrary trailing content, and every one of the nine callers passed a
/// status badge.** On the category the app opens to, that badge was a green pill repeating the
/// value of the *first setting on the screen below it* — "Connected" over a Calendar card whose
/// first line says the same, "Key saved" over an AI card whose first line says the same. iOS
/// deleted the slot in `775833d` for exactly that reason, and left the argument behind: a header
/// that answers the question the next row answers is a second place for one fact to go stale.
/// T-20 removed it here too, along with `CadenceSettingsStatusBadge` and the macOS
/// `SettingsStatusBadge` wrapper — deleted rather than left unused, because a parameter that still
/// compiles and draws nothing is how the page-header `subtitle` survived long enough to need
/// removing three times.
struct CadenceSettingsHeader: View {
    let title: String
    let tint: Color

    var body: some View {
        CadenceSettingsCard {
            DesktopPageHeader(
                role: .page,
                title: title,
                tint: tint,
                padded: false,
                background: nil
            ) {
                EmptyView()
            }
        }
    }
}
#endif

/// One label/value line inside a settings card — `Version   1.0`.
///
/// Shared rather than per-platform: it was `iOSSettingsInfoRow`, read only by iOS's About screen,
/// and macOS's new About screen wants exactly the same row. The value is selectable because the
/// things reported through it (a build number, a bundle identifier) exist to be copied into a
/// bug report.
struct CadenceSettingsInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            // Label half of a label/value pair: `subdued`, not `dim` — `dim` is for
            // genuinely de-emphasized content, and these labels are ordinary reading text.
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.subdued)

            Spacer(minLength: 0)

            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.vertical, 10)
    }
}
