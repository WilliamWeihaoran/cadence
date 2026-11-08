import SwiftUI

/// The one card every settings pane and every field group is drawn on, both platforms.
///
/// **It was a hard-bordered radius-12 rectangle here and a soft-elevation `Theme.radiusCard` one
/// on iOS (`iOSSettingsCard`), and the iOS file said so in as many words** — "Local stand-in for
/// the shared `CadenceSettingsCard` … the shared component keeps its original hard-border,
/// radius-12 treatment because macOS settings and `iOSInboxView` still rely on it as-is". Half of
/// that had already stopped being true: `iOSInboxView` does not mention this type, and macOS
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

// MARK: - Settings > Tags: an archived tag's row

/// **[[T-12741]]: an archived tag's Settings row says so the same way on both platforms.** The
/// Mac's `SettingsTagRow` drew an "Archived" pill beside the tag's title and kept the title in
/// `Theme.text`; the phone's `iOSTagSettingsRow` dimmed the title to `Theme.muted` and said nothing.
/// Neither choice answers a hardware or input constraint ([[T-8201]]), and the archived CONTEXT
/// rows on the same two Settings screens already agree on both halves -- a muted title and the word
/// "Archived" (`ArchivedContextRow`, `iOSSettingsArchivedContextRow`). The tag rows now take
/// both halves from here: the muted title and the one pill, drawn by the same view.
enum CadenceTagSettingsRowStyle {
    /// The status word an archived tag's row wears beside its title.
    static let archivedStatusLabel = "Archived"

    /// The pill's text, or `nil` for a live tag, which wears none.
    static func statusLabel(isArchived: Bool) -> String? {
        isArchived ? archivedStatusLabel : nil
    }

    /// The tag title's ink: muted once archived, as the archived context rows' titles are.
    static func titleInk(isArchived: Bool) -> Color {
        isArchived ? Theme.muted : Theme.text
    }
}

// MARK: - Settings > Calendar: a calendar switched off

/// **[[T-13261]]: a calendar switched off in Settings > Calendar says so the same way on both
/// platforms, through its title alone.** Both rows muted the title, and the phone's
/// `iOSCalendarSettingsRow` ALSO faded the whole row to 0.68 -- the colour dot, the link menu and
/// the Active switch with it -- where the Mac's `SettingsCalendarRow` kept them at full strength.
/// No hardware or input constraint separates the two ([[T-8201]]), and the fade was the worse
/// half: it greyed the one control that turns the calendar back on, so an enabled switch read as
/// a disabled one. Both rows now take the title ink from here and draw nothing else dimmed.
enum CadenceCalendarSettingsRowStyle {
    /// The calendar title's ink: muted while the calendar is switched off.
    static func titleInk(isActive: Bool) -> Color {
        isActive ? Theme.text : Theme.muted
    }
}

/// The "Archived" pill both tag Settings rows draw beside an archived tag's title. One view, so the
/// two platforms cannot spell it differently again; the size resolves through `cadenceFont`, which
/// leaves the Mac's fixed-scaling surface on its 9pt literal.
struct CadenceTagSettingsStatusPill: View {
    let text: String

    var body: some View {
        Text(text)
            .cadenceFont(.metadata, base: 9, weight: .semibold)
            .foregroundStyle(Theme.dim)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Theme.surfaceElevated.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
