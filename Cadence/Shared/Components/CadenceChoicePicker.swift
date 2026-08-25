import SwiftUI

/// The app's one "pick one of these" control: a trigger showing the current value, and a
/// checkmarked popover list behind it.
///
/// **This is iOS's vocabulary, lifted rather than re-invented.** It was `iOSChoiceRow` /
/// `iOSChoicePopoverList` / `iOSChoiceValueButton` / `iOSFittedPopover` in
/// `Cadence/iOS/iOSChoicePicker.swift`, written to replace `Picker(.segmented)` on mobile, and its
/// own doc comment already said it was matching "the checkmarked-popover-list language already
/// used by macOS's `TaskPriorityPickerPopover` / `ContainerPickerBadge`". macOS Settings never got
/// it: it kept `Picker(.menu)` (AppKit chrome, no palette colour) for work hours and a row of
/// saturated filled pills for the default list page. T-20 moved the four types here whole and left
/// the iOS spellings as typealiases, so both platforms present one control rather than two that
/// agree by hand.
///
/// The only platform difference inside is pointer hover, which iOS's copy could not have and
/// macOS's rows need. It is drawn on the *same* layer at the *same* radius as the selection fill —
/// one `RoundedRectangle`, one `backgroundFill` — rather than as a second `.background()`.

/// One option in a `CadenceChoicePopoverList`.
struct CadenceChoiceRow<T: Hashable>: Identifiable {
    let id: AnyHashable
    let value: T
    let title: String
    /// What this option *means*, where the option's name does not already say it.
    ///
    /// This is where a setting's explanation belongs: on the choice it explains, read at the
    /// moment you are choosing — not as a permanent two-line paragraph under the setting's own
    /// label, which is where the iOS settings screen used to keep them and what made two settings
    /// fill a phone. Leave it `nil` whenever the title is self-explanatory; a subtitle that
    /// restates the title is the thing being removed.
    let subtitle: String?
    let systemImage: String?
    let color: Color

    init(
        value: T,
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        color: Color,
        id: AnyHashable? = nil
    ) {
        self.value = value
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.color = color
        self.id = id ?? AnyHashable(title)
    }
}

/// Popover chrome that takes its height from what is actually in it, capped so a long list still
/// scrolls instead of running off the screen.
///
/// Every picker popover used to carry a height that assumed a full list — a flat 320 for the
/// container picker, `rows × 46 + 16` for the generic one. Opening the task composer's list picker
/// on a workspace whose only container is Inbox produced a 320pt panel around a single 44pt row,
/// three quarters of it empty. `ViewThatFits` takes the unscrolled stack whenever it fits inside
/// the cap and falls back to the scrolling one when it does not, so neither end of the range has to
/// be guessed — a one-row picker is one row tall and a 96-row time picker still scrolls.
struct CadenceFittedPopover<Content: View>: View {
    var width: CGFloat = 230
    /// A cap, not a height: past this the content scrolls rather than growing.
    var maxHeight: CGFloat = 380
    let content: Content

    init(width: CGFloat = 230, maxHeight: CGFloat = 380, @ViewBuilder content: () -> Content) {
        self.width = width
        self.maxHeight = maxHeight
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
        .frame(width: width)
        .frame(maxHeight: maxHeight)
        .background(Theme.surfaceElevated)
        .modifier(CadencePopoverCompactAdaptation())
    }
}

/// Keeps the popover an anchored overlay on a compact-width iPhone instead of letting it expand
/// into a sheet. macOS has no compact size class and no such adaptation, so the modifier is not
/// applied there rather than applied to no effect.
private struct CadencePopoverCompactAdaptation: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content.presentationCompactAdaptation(.popover)
        #else
        content
        #endif
    }
}

/// Popover content: a checkmarked, tap-to-select list. Present via `.popover` from a trigger
/// (typically `CadenceChoiceValueButton`).
struct CadenceChoicePopoverList<T: Hashable>: View {
    let rows: [CadenceChoiceRow<T>]
    @Binding var selection: T
    @Binding var isPresented: Bool
    var width: CGFloat = 230

    /// Pointer hover, by row id. Always `nil` where there is no pointer.
    @State private var hoveredRowID: AnyHashable?

    var body: some View {
        CadenceFittedPopover(width: width) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(rows) { row in
                    Button {
                        selection = row.value
                        isPresented = false
                    } label: {
                        HStack(spacing: 8) {
                            if let systemImage = row.systemImage {
                                Image(systemName: systemImage)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(row.color)
                                    .frame(width: 18)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(row.value == selection ? Theme.text : Theme.muted)
                                    .lineLimit(1)
                                if let subtitle = row.subtitle {
                                    Text(subtitle)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.dim)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer(minLength: 8)
                            if row.value == selection {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.blue)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, minHeight: CadenceSettingsRowMetrics.rowHeight, alignment: .leading)
                        // One layer, one radius: selection and hover share this fill rather than
                        // stacking a second `.background()` at a second corner radius.
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(backgroundFill(for: row))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { isInside in
                        if isInside {
                            hoveredRowID = row.id
                        } else if hoveredRowID == row.id {
                            hoveredRowID = nil
                        }
                    }
                }
            }
            .padding(6)
        }
    }

    private func backgroundFill(for row: CadenceChoiceRow<T>) -> Color {
        if row.value == selection {
            return Theme.blue.opacity(0.12)
        }
        if hoveredRowID == row.id {
            return Theme.surfaceHighlight
        }
        return .clear
    }
}

/// Trigger button showing the current value; opens a `CadenceChoicePopoverList`.
struct CadenceChoiceValueButton: View {
    let title: String
    var color: Color = Theme.text
    /// Opt-in touch floor. The label alone is about 18pt tall, so where this button is the *only*
    /// thing tappable in its row — every row on the settings screen — the row's own height has to
    /// be handed to the button or most of it is dead space. Applied inside the label, because a
    /// `contentShape` outside a `Button` does not widen the button's own hit region.
    ///
    /// Defaults to 0 so the rows that already pair this with a second control keep their layout.
    var minHeight: CGFloat = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(color.opacity(0.55))
            }
            .frame(minHeight: minHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
