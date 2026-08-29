import SwiftUI

/// The **one** labelled-field vocabulary: a titled group, the rows inside it, the hairline between
/// them, and the inset well a typed value sits in.
///
/// **Lifted from iOS rather than invented here (T-20).** These were `iOSEditorSection`,
/// `iOSEditorSectionStyle`, `iOSEditorDivider`, `iOSEditorInlineLabel`, `iOSEditorFieldRow`,
/// `iOSRowDivider` and `iOSSettingsField` in `Cadence/iOS/`, and every one of them already
/// described itself as adopting a decision from the other platform — the inline label's own
/// comment says it is "the vocabulary macOS's `TaskInspectorFieldRow` established". macOS Settings
/// never received the return trip: it kept ad-hoc `VStack`s of bold titles over grey paragraphs,
/// `Divider().background(Theme.borderSubtle)` (which paints the palette colour *under* the system
/// separator, so the line is neither) and three separate private `settingsField` / `tagTextField`
/// spellings of the same inset well. The iOS names survive as typealiases in
/// `iOSDesignSystem.swift` / `iOSSettingsComponents.swift`, so no iOS call site moved.
enum CadenceSettingsRowMetrics {
    /// A finger is 44pt; a pointer is not. This is the one place that difference is spelled, so a
    /// row, a value button and a well cannot each answer it separately.
    ///
    /// macOS reads 34 because a 44pt row beside an 11–13pt label reads as a text *area* rather than
    /// a field, and there is nothing on the desktop that a 34pt target is too small for.
    static var rowHeight: CGFloat {
        #if os(macOS)
        34
        #else
        44
        #endif
    }

    /// Fixed leading slot for a row's glyph, so every label in a group starts on the same x.
    static let glyphSlot: CGFloat = 22
    static let glyphLabelSpacing: CGFloat = 9
    /// Gap between a row's label and the control on its trailing edge.
    static let valueSpacing: CGFloat = 10
}

/// How a field group separates itself from the one above.
enum CadenceFieldSectionStyle {
    /// Fields sit on a raised card. The default, and what every full-screen editor and settings
    /// pane uses.
    case card
    /// Fields sit directly on the sheet, separated by a hairline. For compact sheets where a stack
    /// of cards would read as a stack of unrelated boxes.
    case ruled
}

/// The **one** titled group of fields used by every editor and by macOS Settings.
///
/// There were five of these on iOS — `iOSTrackingPickerSection`, `iOSCalendarBundleEditorSection`,
/// `iOSCalendarEventEditorSection`, `iOSCalendarQuickCreateSection` and their eyebrows — four of
/// them byte-identical apart from the name, and the fifth differing only in whether the fields sat
/// on a card. That difference is the `style` parameter. macOS's `SettingsSectionLabel` + `SettingsCard`
/// pair was a sixth, spelled at every call site instead of once.
struct CadenceFieldSection<Content: View>: View {
    /// `nil` draws the group with its rule and spacing but no eyebrow — for groups whose rows
    /// already name themselves, where a heading would only repeat them. The task inspector's
    /// properties group and its action row are both this: the heading they used to carry said
    /// "Overview", which named nothing the rows did not.
    let title: String?
    var style: CadenceFieldSectionStyle = .card
    var contentSpacing: CGFloat = 0
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: title == nil ? 0 : 10) {
            if let title {
                SectionEyebrowLabel(text: title)
            }

            VStack(alignment: .leading, spacing: contentSpacing) {
                content()
            }
            .modifier(CadenceFieldSectionBody(style: style))
        }
        .modifier(CadenceFieldSectionChrome(style: style))
    }
}

private struct CadenceFieldSectionBody: ViewModifier {
    let style: CadenceFieldSectionStyle

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .card:
            // The card is `CadenceSettingsCard`, not a second spelling of it: this group and a
            // settings card drawn beside it must not be two different rectangles.
            CadenceSettingsCard {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .ruled:
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct CadenceFieldSectionChrome: ViewModifier {
    let style: CadenceFieldSectionStyle

    func body(content: Content) -> some View {
        switch style {
        case .card:
            content
        case .ruled:
            content
                .padding(.top, 12)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Theme.borderSubtle.opacity(0.35))
                        .frame(height: 1)
                }
        }
    }
}

/// Divider between two rows inside a `CadenceFieldSection`.
///
/// It owns the whole gap between two rows — call sites must not add `contentSpacing` on top, or
/// the same space is counted twice. At 9pt each side a 44pt row had a 63pt pitch, which read as a
/// list of mostly-empty rows; 6pt puts it at 57 without letting the rows touch.
struct CadenceFieldDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.borderSubtle.opacity(0.55))
            .frame(height: 1)
            .padding(.vertical, 6)
    }
}

/// Hairline between rows inside a settings card, with an optional inset so it starts at the text
/// rather than cutting across a leading glyph.
///
/// `Divider().background(Theme.borderSubtle)` — the pattern this replaces, and the one macOS
/// Settings still used in five places — leaves the system separator colour painted on top of the
/// palette colour, so the line is neither `borderSubtle` nor predictable across sections. This
/// draws the palette colour and nothing else.
///
/// **The axis is a parameter because the bug is not (T-286).** Four surviving
/// `Divider().background(Theme.borderSubtle)` call sites were spelled across two lines, which is
/// how they walked past a sweep written for the one-line form; two of them — the note-template
/// card's column separator and the Settings rail's edge — were *vertical*, and a horizontal-only
/// replacement is precisely the excuse that would have left them there. A `Divider()` in an
/// `HStack` is the same painted-under hairline turned ninety degrees, not a different component.
struct CadenceRowDivider: View {
    /// Ignored on the vertical axis, where there is no leading glyph to clear.
    var leadingInset: CGFloat = 0
    var axis: Axis = .horizontal

    var body: some View {
        switch axis {
        case .horizontal:
            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(height: 1)
                .padding(.leading, leadingInset)
        case .vertical:
            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(width: 1)
        }
    }
}

/// The **one** inset well a typed value sits in: 12pt of leading air, a row-height floor, the
/// elevated surface, and a `strokeBorder` at the control radius.
///
/// Split out of `CadenceSettingsField` (T-286) because half the wells in Settings have no eyebrow
/// over them and so could not read the titled component: the tag creator's two fields are
/// placeholder-only, and so is the context row's rename field. Those three were the last private
/// spellings of this chrome on macOS — two of them byte-identical to each other at radius 8 with a
/// `.stroke` (which straddles the edge, so the well is 1pt wider than it measures) and the third at
/// radius 7 with 8pt of padding. A modifier is what lets the titled field and the bare field be one
/// rectangle rather than two that agree by hand.
struct CadenceSettingsWell: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .frame(minHeight: CadenceSettingsRowMetrics.rowHeight)
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                    .strokeBorder(Theme.borderSubtle, lineWidth: 1)
            }
    }
}

extension View {
    /// Draws this control inside the shared settings inset well. See `CadenceSettingsWell`.
    func cadenceSettingsWell() -> some View {
        modifier(CadenceSettingsWell())
    }
}

/// A settings card's **status line**: a state glyph, what the state is, one sentence of why, and
/// the action that changes it.
///
/// **Four call sites in three panes wrote this out (T-286).** Notifications drew it twice
/// (authorized, and not), Reminders drew it for calendar access, and Sync drew it for the iCloud
/// account — each with the same 14pt glyph, the same 13pt semibold `Theme.text` title, the same
/// 12pt `Theme.dim` paragraph under `fixedSize`, and the same trailing `SettingsActionButton`.
/// They are the same row, and the only reason they were not already one component is that a
/// *permission* row is not what `CadenceFieldRow` models: it carries a sentence, its glyph is a
/// verdict rather than a field's name, and its trailing control acts rather than edits. So this is
/// a second member of the row vocabulary rather than a bent copy of the first — and it reads the
/// same `rowHeight`, which is the number that made those panes two heights.
struct CadenceSettingsNoticeRow<Trailing: View>: View {
    let systemImage: String
    let tint: Color
    let title: String
    let detail: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            trailing()
        }
        .frame(minHeight: CadenceSettingsRowMetrics.rowHeight)
    }
}

/// A field's name: a **bare glyph in a fixed leading slot**, then a quiet label.
///
/// It used to be a 28pt filled icon tile beside a 14pt semibold `Theme.text` label. Stacked seven
/// deep in the task inspector that read as a column of grey squares shouting the names of fields
/// while the values — the only part that differs from task to task — sat dim on the far right. The
/// fixed slot is what makes every label in a group start on the same x, so the column scans; the
/// glyph carries which field this is, and the caller's `content` carries the answer.
struct CadenceInlineFieldLabel: View {
    let label: String
    let systemImage: String
    /// Defaults to `Theme.dim`, matching the row-metadata rule: colour is for the exceptional
    /// (an overdue due date, a past do date), not for every field that happens to have an icon.
    var color: Color = Theme.dim

    var body: some View {
        HStack(spacing: CadenceSettingsRowMetrics.glyphLabelSpacing) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(color)
                .frame(width: CadenceSettingsRowMetrics.glyphSlot, alignment: .leading)

            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.dim)
        }
    }
}

/// A labelled field row inside a `CadenceFieldSection`: glyph, quiet label, trailing control.
struct CadenceFieldRow<Content: View>: View {
    let label: String
    let systemImage: String
    var color: Color = Theme.dim
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: CadenceSettingsRowMetrics.valueSpacing) {
            CadenceInlineFieldLabel(label: label, systemImage: systemImage, color: color)

            Spacer(minLength: 12)

            content()
        }
        .frame(minHeight: CadenceSettingsRowMetrics.rowHeight)
    }
}

/// Eyebrow label above an inset well — the one field treatment for every settings input.
///
/// Replaces six near-copies. On iOS: `.textFieldStyle(.roundedBorder)` in Tags (UIKit chrome, no
/// palette colour at all), the private `iOSTemplateEditorField`, and the bare `Form` rows in the
/// context editor. On macOS: `SettingsAISection.settingsField` and two `SettingsTagsSection`
/// spellings, each with its own radius and its own idea of the label's colour.
struct CadenceSettingsField<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionEyebrowLabel(text: title)

            content
                .font(.system(size: 14, weight: .medium))
                .textFieldStyle(.plain)
                .foregroundStyle(Theme.text)
                .tint(Theme.blue)
                .cadenceSettingsWell()
        }
    }
}

/// A label/value line inside a settings card — `Version   1.0`.
///
/// **The third component here that draws a row, and the last one that answered its own height.**
/// It was `iOSSettingsInfoRow`, read only by iOS's About screen, and was promoted into
/// `CadenceSettingsSharedViews.swift` when macOS grew an About screen wanting the same row. It sat
/// beside the *card* and the *header* there — chrome — while being a row, and it stated its height
/// as `.padding(.vertical, 10)`: a fourth answer to "how tall is a settings row", arrived at from a
/// different direction, which is why it read 36pt on a platform whose every other settings row is
/// 44. It reads `CadenceSettingsRowMetrics.rowHeight` now, like the field row above it and the
/// inset well below it.
///
/// The value is selectable because the things reported through it (a build number, a bundle
/// identifier) exist to be copied into a bug report.
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
        .frame(minHeight: CadenceSettingsRowMetrics.rowHeight)
    }
}
