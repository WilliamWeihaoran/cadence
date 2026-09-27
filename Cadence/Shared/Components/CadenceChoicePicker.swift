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
///
/// **`id` is derived from `value`, and there is no way to hand one in (T-490).** It used to default
/// to `AnyHashable(title)` with an override parameter, and 32 of the 35 call sites took the
/// default — so two options whose *displayed* titles happened to match collapsed into a single
/// `ForEach` identity and one of them stopped drawing. That is not hypothetical copy: an area or
/// goal with no name renders as "Untitled Area" / "Untitled Milestone", so two unnamed ones are two
/// rows with one title.
///
/// The parameter is gone rather than made mandatory. A required `id:` is 35 authors answering a
/// question the type can answer once, and the answer is always the same: `value` is already
/// `Hashable`, it is already what `selection` is compared against, and a picker offering two rows
/// with the same `value` is broken at the binding before it is broken at the identity. Deriving it
/// here also makes identity *stable* across a rename — the row keeps its place when its title
/// changes, which is what `ForEach` identity is for.
struct CadenceChoiceRow<T: Hashable>: Identifiable {
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

    var id: AnyHashable { AnyHashable(value) }

    init(
        value: T,
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        color: Color
    ) {
        self.value = value
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.color = color
    }
}

/// Every number this panel draws, once the reader has a text size (T-1410).
///
/// **The panel is `.enabled`, not "whatever it inherited".** T-1398 measured that the migration
/// flag crosses a `.popover` while `\.dynamicTypeSize` is re-read from the host window, and closed
/// the resulting mismatch by pinning this panel to `.fixed`. Pinning stopped a grown label sitting
/// in a rigid box; it did not convert anything, so a reader with Larger Text on got a scaled sheet
/// that opened an unscaled picker. This is the conversion: the frame, the rows and the fonts all
/// come from here, and `CadenceFittedPopover` states `.cadenceScaledTypography()` so the type the
/// rows draw and the numbers this type returns are the same answer.
///
/// The geometry functions take `scaling:` so the *contrast* is testable from `CadenceTests` — the
/// views themselves always pass `.enabled`, because a converted panel is converted wherever it is
/// opened from. On macOS `\.dynamicTypeSize` never leaves `.large`, so every number below is the
/// literal it replaced there (T-1399).
/// Not `nonisolated`: `rowMinHeight` reads `CadenceSettingsRowMetrics.rowHeight`, which is
/// main-actor-isolated by this target's `SWIFT_APPROACHABLE_CONCURRENCY` default, and a
/// nonisolated static cannot initialise from one. Every reader here is a view body already.
enum CadenceChoicePopoverMetrics {
    /// The generic picker's panel width, and the grouped container picker's.
    static let width: CGFloat = 230
    static let containerWidth: CGFloat = 250

    /// A **cap on a scroll**, not a height — which is why it stays a constant while everything
    /// else here moves.
    ///
    /// `CadenceFittedPopover` takes the unscrolled stack whenever it fits under this and falls back
    /// to a `ScrollView` when it does not, so the cap is the point past which the panel stops
    /// growing and starts scrolling. Growing *it* with the type is the one change that would make
    /// an accessibility size worse: the popover would leave the screen instead of scrolling, and a
    /// popover that has left the screen has no cap at all.
    static let maxHeight: CGFloat = 380
    static let containerMaxHeight: CGFloat = 340

    /// The sizes the rows were drawn at before they could move, kept as the bases the roles read.
    static let titleSize: CGFloat = 14
    static let subtitleSize: CGFloat = 11
    static let glyphSize: CGFloat = 12
    /// Leading slot the row's glyph is centred in, so every title in the list starts on one x.
    static let glyphSlot: CGFloat = 18
    static let rowVerticalPadding: CGFloat = 9

    /// The panel widens by what its title gained, not by what it was multiplied by: 230pt around a
    /// 14pt row is mostly gutter and chrome, and tripling the gutter is how an accessibility size
    /// becomes a panel wider than the phone.
    static func width(
        _ base: CGFloat,
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CGFloat {
        CadenceTypeScale.height(base, holding: .rowTitle, textBase: titleSize, at: dynamicTypeSize, scaling: scaling)
    }

    static func glyphSlot(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CGFloat {
        CadenceTypeScale.height(glyphSlot, holding: .rowTitle, textBase: glyphSize, at: dynamicTypeSize, scaling: scaling)
    }

    /// One line at every ordinary size; two once the reader's text size is an accessibility
    /// setting.
    ///
    /// A 39pt title in a 255pt panel does not fit on one line, and the alternative to a second line
    /// is `minimumScaleFactor` — shrinking the text back down, which is precisely what the reader
    /// asked not to happen. Same call `CadenceValueTileMetrics.valueLineLimit` makes (T-1364).
    static func titleLineLimit(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> Int {
        guard scaling == .enabled, CadenceTypeScale.isAccessibilitySize(dynamicTypeSize) else { return 1 }
        return 2
    }

    /// What one line of the row's title occupies.
    static func titleLineHeight(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CGFloat {
        CadenceTypeScale.lineHeight(.rowTitle, base: titleSize, at: dynamicTypeSize, scaling: scaling)
    }

    /// The text this row must hold: as many lines as it is allowed, plus its own padding.
    static func rowTextHeight(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CGFloat {
        CGFloat(titleLineLimit(at: dynamicTypeSize, scaling: scaling))
            * titleLineHeight(at: dynamicTypeSize, scaling: scaling)
            + rowVerticalPadding * 2
    }

    /// The row's floor: whichever is larger of the platform's touch target and the text in it.
    ///
    /// Two reasons rather than one, and they change places as the type grows. At the sizes the app
    /// was drawn at the touch target wins and the row is the 44 (34 on macOS) it always was; past
    /// roughly `accessibility1` the text wins, which is the "font grew, box did not" case stated as
    /// arithmetic instead of found in a screenshot.
    static func rowMinHeight(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> CGFloat {
        max(
            CadenceSettingsRowMetrics.rowHeight(at: dynamicTypeSize, scaling: scaling),
            rowTextHeight(at: dynamicTypeSize, scaling: scaling)
        )
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
    /// The width at the default text size. What is drawn is this plus what a row title gained —
    /// see `CadenceChoicePopoverMetrics.width(_:at:scaling:)`.
    var width: CGFloat = CadenceChoicePopoverMetrics.width
    /// A cap, not a height: past this the content scrolls rather than growing.
    var maxHeight: CGFloat = CadenceChoicePopoverMetrics.maxHeight
    let content: Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        width: CGFloat = CadenceChoicePopoverMetrics.width,
        maxHeight: CGFloat = CadenceChoicePopoverMetrics.maxHeight,
        @ViewBuilder content: () -> Content
    ) {
        self.width = width
        self.maxHeight = maxHeight
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
        .frame(width: CadenceChoicePopoverMetrics.width(width, at: dynamicTypeSize, scaling: .enabled))
        .frame(maxHeight: maxHeight)
        .background(Theme.surfaceElevated)
        // **T-1410, and it replaces the `.cadenceFixedTypography()` T-1398 put here.** T-1398
        // measured that the migration flag crosses a `.popover` while `\.dynamicTypeSize` is
        // re-read from the host window, so this panel arrived from a converted sheet carrying
        // `.enabled` over a literal `width: 230` and rows fixed at 14 — a group eyebrow resolving
        // to ~28pt above them. Pinning it stopped that and converted nothing: the reader who turned
        // Larger Text on still got a scaled sheet opening an unscaled picker.
        //
        // It is converted now, and the shape it converted *to* is the one it already had. The
        // panel is intrinsically sized and scrolls past a cap, so the cap is the only literal left
        // — deliberately, because a cap that grew with the type would put the panel off the screen
        // rather than scroll it. Everything else comes from `CadenceChoicePopoverMetrics`, which
        // the rows read too, so the frame and the font cannot disagree.
        .cadenceScaledTypography()
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
///
/// **Two forms, and the difference is who may close it ([[T-656]], [[T-727]]).**
///
/// The ordinary form takes a `Binding` and closes on the tap. That is what picking *means* for the
/// thirty-odd pickers here whose selection is a draft field on a sheet: the write cannot be
/// refused, so closing claims nothing and waiting for an answer would be worse than the defect.
///
/// The other form is `init(rows:selection:isPresented:width:failureNotice:select:)`, for a picker
/// whose write reaches the store. There the close **is** the success report — the popover is the
/// only thing on screen that changes — so it happens only when `select` answers `true`, and the
/// popover stays open over a refusal with `failureNotice` under the rows. Four of this app's
/// pickers are that shape; `CadenceChoicePickerDismissalTests` names them.
///
/// The committing form takes the current value rather than a `Binding`, deliberately: a writable
/// binding beside a `select` closure is two write paths, and the defect this fixes was a mutation
/// hidden in a binding's *setter* where nothing could see it.
struct CadenceChoicePopoverList<T: Hashable>: View {
    let rows: [CadenceChoiceRow<T>]
    @Binding var selection: T
    @Binding var isPresented: Bool
    var width: CGFloat = CadenceChoicePopoverMetrics.width
    /// Drawn under the rows when the last pick was refused. Always `nil` on a draft picker, which
    /// has nothing that can be refused.
    var failureNotice: String?
    /// `nil` on a draft picker: the row writes `selection` and closes. Non-`nil` on a committing
    /// one: the row hands the value to this instead, and closes only if it answers `true`.
    private let select: ((T) -> Bool)?

    /// The draft form. The row writes through `selection` and the popover closes.
    init(
        rows: [CadenceChoiceRow<T>],
        selection: Binding<T>,
        isPresented: Binding<Bool>,
        width: CGFloat = CadenceChoicePopoverMetrics.width
    ) {
        self.rows = rows
        self._selection = selection
        self._isPresented = isPresented
        self.width = width
        self.failureNotice = nil
        self.select = nil
    }

    /// The committing form. `selection` is read-only here — it is what draws the checkmark — and
    /// `select` is the only write. The popover closes when `select` answers `true`.
    init(
        rows: [CadenceChoiceRow<T>],
        selection: T,
        isPresented: Binding<Bool>,
        width: CGFloat = CadenceChoicePopoverMetrics.width,
        failureNotice: String? = nil,
        select: @escaping (T) -> Bool
    ) {
        self.rows = rows
        self._selection = .constant(selection)
        self._isPresented = isPresented
        self.width = width
        self.failureNotice = failureNotice
        self.select = select
    }

    /// Pointer hover, by row id. Always `nil` where there is no pointer.
    @State private var hoveredRowID: AnyHashable?

    /// The rows are built *outside* `CadenceFittedPopover`'s scope, so the numbers here name
    /// `.enabled` rather than reading it back: this list and that chrome are one panel and it is
    /// converted. The fonts below go through the environment the chrome installs, which is the same
    /// answer arriving by the other route.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        CadenceFittedPopover(width: width) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(rows) { row in
                    Button {
                        pick(row.value)
                    } label: {
                        HStack(spacing: 8) {
                            if let systemImage = row.systemImage {
                                Image(systemName: systemImage)
                                    .cadenceFont(.rowTitle, base: CadenceChoicePopoverMetrics.glyphSize, weight: .semibold)
                                    .foregroundStyle(row.color)
                                    .frame(width: CadenceChoicePopoverMetrics.glyphSlot(at: dynamicTypeSize, scaling: .enabled))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title)
                                    .cadenceFont(.rowTitle)
                                    .foregroundStyle(row.value == selection ? Theme.text : Theme.muted)
                                    .lineLimit(CadenceChoicePopoverMetrics.titleLineLimit(at: dynamicTypeSize, scaling: .enabled))
                                if let subtitle = row.subtitle {
                                    Text(subtitle)
                                        .cadenceFont(.metadata, base: CadenceChoicePopoverMetrics.subtitleSize, weight: .regular)
                                        .foregroundStyle(Theme.dim)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer(minLength: 8)
                            if row.value == selection {
                                Image(systemName: "checkmark")
                                    .cadenceFont(.rowTitle, base: CadenceChoicePopoverMetrics.glyphSize, weight: .semibold)
                                    .foregroundStyle(Theme.blue)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, CadenceChoicePopoverMetrics.rowVerticalPadding)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: CadenceChoicePopoverMetrics.rowMinHeight(at: dynamicTypeSize, scaling: .enabled),
                            alignment: .leading
                        )
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
                if let failureNotice {
                    CadenceInlineFailureNotice(text: failureNotice)
                        .padding(.horizontal, 12)
                        .padding(.top, 2)
                }
            }
            .padding(6)
        }
    }

    /// The one place a row tap is answered, so the two forms cannot drift apart.
    private func pick(_ value: T) {
        guard let select else {
            selection = value
            isPresented = false
            return
        }
        if select(value) {
            isPresented = false
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
