#if os(iOS)
import SwiftData
import SwiftUI

/// Shared 13pt completion circle used by task rows across iOS: a 1.6pt ring in the task's
/// priority tint while it is open, a solid fill with a knocked-out mark once it is settled.
///
/// It drew **two** states — done and not-done — against macOS's five, so a cancelled task was
/// pixel-identical to an open one on every iOS row, board card, timeline block and inspector,
/// even though the swipe tray, the context menu and the inspector's Cancel button all set that
/// status. `CadenceTaskCompletionGlyph` is now the single decision behind both platforms; this
/// view only draws what it is told.
struct iOSTaskCompletionCircle: View {
    let glyph: CadenceTaskCompletionGlyph
    var diameter: CGFloat = 13

    init(glyph: CadenceTaskCompletionGlyph, diameter: CGFloat = 13) {
        self.glyph = glyph
        self.diameter = diameter
    }

    /// For the controls with no `AppTask` behind them — a `Subtask`'s tick, and the decorative
    /// circles in the swipe tray and the schedule placeholder row.
    init(isDone: Bool, tint: Color, diameter: CGFloat = 13) {
        self.init(glyph: .binary(isDone: isDone, tint: tint), diameter: diameter)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(glyph.isFilled ? glyph.tint : Color.clear)
            if !glyph.isFilled {
                Circle()
                    .stroke(glyph.tint, lineWidth: 1.6)
            }
            mark
        }
        .frame(width: diameter, height: diameter)
    }

    /// macOS gets its mark free, as the knockout inside an SF Symbol; here it is drawn. On a
    /// filled disc that means `Theme.onColor`, which is what the checkmark has always used —
    /// the cancelled cross is the same treatment, not a new one.
    @ViewBuilder
    private var mark: some View {
        switch glyph.mark {
        case .none:
            EmptyView()
        case .dot:
            Circle()
                .fill(glyph.tint)
                .frame(width: diameter * 0.44, height: diameter * 0.44)
        case .checkmark:
            markSymbol("checkmark", scale: 0.6)
        case .cross:
            markSymbol("xmark", scale: 0.55)
        }
    }

    private func markSymbol(_ name: String, scale: CGFloat) -> some View {
        Image(systemName: name)
            .font(.system(size: diameter * scale, weight: .bold))
            .foregroundStyle(glyph.isFilled ? Theme.onColor : glyph.tint)
    }
}

struct iOSFeatureListPane<Content: View>: View {
    let eyebrow: String
    let title: String
    let count: Int
    /// The one empty state this screen has. See `iOSFeatureEmptyState` — it is a value rather than
    /// three loose strings so the detail pane beside this one cannot describe the same empty list
    /// differently (T-533).
    let empty: iOSFeatureEmptyState
    var actionTitle: String? = nil
    var actionSystemImage = "plus"
    var action: (() -> Void)? = nil
    /// Whether this pane is the whole screen rather than the chooser column of a split — the
    /// `role` distinction, and it is asked rather than inferred.
    ///
    /// It **was** inferred, from `onBack != nil`, on the reasoning that a back chevron means a
    /// pushed screen. That held while the only full-width host was the phone's push stack. T-252
    /// added a second: a regular-width pane too narrow to split renders this same list at full
    /// width, as the root of its own stack — a page with nothing behind it to go back to — and the
    /// inference read that as a chooser column and drew the narrower header.
    var isPage = false
    /// Set on iPhone, where this pane is a pushed screen with its navigation bar hidden. See
    /// `iOSHidesCompactNavigationBar()`.
    var onBack: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSPageHeader(
                role: isPage ? .page : .pane,
                eyebrow: eyebrow,
                title: title,
                count: count,
                onBack: onBack
            )
            Divider().background(Theme.borderSubtle)

            if let actionTitle, let action {
                // `.borderedProminent` renders the OS's own capsule at the OS's own height; this is
                // the same primary treatment every other Cadence button uses, at 48pt.
                iOSActionButton(
                    title: actionTitle,
                    systemImage: actionSystemImage,
                    role: .primary,
                    fullWidth: true,
                    action: action
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Divider().background(Theme.borderSubtle)
            }

            if count == 0 {
                iOSEmptyPanel(
                    systemImage: empty.systemImage,
                    title: empty.title,
                    subtitle: empty.subtitle
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        content()
                    }
                    .padding(14)
                }
                .scrollIndicators(.hidden)
            }
        }
        // No width of its own. It used to declare `minWidth: 300, idealWidth: 360` and nothing
        // else, and an `HStack` given two children that are both flexible upwards splits the pane
        // between them: on a 13" iPad in portrait the Goals chooser took 422pt to draw one-line rows
        // while the detail it chooses for wrapped its title. The split surfaces size this from
        // `CadenceRegularSplitLayout`; compact width gives it the whole screen.
        .background(Theme.surface)
    }
}

/// The regular-width chooser-plus-detail split, in one place.
///
/// Goals, Habits and Focus each spelled this out as a bare `HStack { listPane; Divider(); detail }`
/// with no width on either side, which is what let an `HStack` hand a 13" iPad's 844pt pane to the
/// two of them in equal halves. The proportion comes from `CadenceRegularSplitLayout` — measured
/// against the pane, capped so the chooser never outgrows the thing it is choosing for.
///
/// **And since T-252 it also decides whether there is a split at all.** This was the one registered
/// width rule with no "two panes is worse than one" fallback: Today gates to one column at 761,
/// Notes at 601 and Calendar drops its day inspector at 681, while `listPaneWidth` only clamped the
/// *proportion*, so a 646pt portrait pane on the primary target iPad — the same device and
/// orientation where the other three have already folded — went on splitting into a 300pt chooser
/// beside a 345pt detail. The floor is `CadenceRegularSplitLayout.twoPaneMinimumWidth`, derived
/// there from the chooser's own share rather than invented here.
///
/// `narrow` is the surface's own one-column form, not a dropped pane. Dropping the chooser strands
/// the detail on whatever was selected — `CadenceSettingsTemplatesCardLayout`'s case, not
/// `CadenceCalendarPaneLayout`'s — so what each caller passes is the same list it draws on a phone,
/// with rows that push instead of select.
struct iOSFeatureSplitLayout<List: View, Detail: View, Narrow: View>: View {
    @ViewBuilder let list: () -> List
    @ViewBuilder let detail: () -> Detail
    @ViewBuilder let narrow: () -> Narrow

    var body: some View {
        GeometryReader { proxy in
            if CadenceRegularSplitLayout.supportsTwoPanes(paneWidth: proxy.size.width) {
                HStack(spacing: 0) {
                    list()
                        .frame(width: CadenceRegularSplitLayout.listPaneWidth(forPaneWidth: proxy.size.width))
                        .frame(maxHeight: .infinity)

                    Divider().background(Theme.borderSubtle)

                    detail()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                narrow()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// One chooser row, either spelling of "activate me".
///
/// A chooser pane behaves differently on the two shells and in exactly one respect: at regular
/// width the row **selects** and the detail pane beside it changes, and on the phone the row
/// **pushes** the detail onto the tab's stack. Goals and Habits each carried that difference as a
/// second, byte-for-byte copy of their whole list pane — four functions for two panes — which is
/// the shape every drift in this app has started from. The difference is real; its scope is one
/// control, so that is what is parameterised.
///
/// `isSelected` is not a parameter because it is not an independent fact: a pushed row has no
/// persistent selection to show, so the label builder is handed `false` whenever `pushes` is set
/// and cannot disagree with the layout it is in.
///
/// No button style is applied here. Call sites differ — a plain row takes `.iosPressable`, a row
/// with a control layered over it takes `.plain` so the press transform does not drag the overlay
/// with it — and both spellings propagate through this wrapper to the button or link inside.
struct iOSFeatureRowLink<Label: View, Destination: View>: View {
    /// `true` on the compact push stack, `false` in a regular-width split.
    let pushes: Bool
    let select: () -> Void
    @ViewBuilder let destination: () -> Destination
    /// Handed the resolved selection state, so the caller cannot pass a highlight into a pane that
    /// has no selection.
    @ViewBuilder let label: (Bool) -> Label

    var body: some View {
        if pushes {
            NavigationLink {
                destination()
            } label: {
                label(false)
            }
        } else {
            Button(action: select) {
                label(true)
            }
        }
    }
}

/// **The** iOS header row: an eyebrow, a title, and optionally an identity tile, a count, a back
/// chevron and one trailing control.
///
/// It replaces six of these. `iOSPanelHeader`, `iOSCompactPageHeader`, `iOSListsPageHeader`,
/// `iOSListDetailHeader`, `iPadTodayTaskHeader` and `iOSSettingsPageHeader` each drew the same idea
/// and had drifted into six title sizes, two eyebrow sizes, two count badges (one blue capsule,
/// one neutral one) and three ways of spelling the leading tile. The five names that had callers
/// outside this sweep's reach survive as thin wrappers over this; none of them decides anything
/// about appearance any more.
///
/// What survives as a parameter is `role`, and only that: a column inside a split legitimately
/// speaks more quietly than a whole screen. Everything else is `CadencePageHeaderMetrics`, which is
/// outside `#if os(iOS)` so the ramp can be pinned by a test.
///
/// **No subtitle.** `iOSCompactPageHeader` had one and no caller had passed it since the standing
/// rule landed — a line under "All Tasks" explaining that All Tasks is where you review tasks
/// describes the page you are already looking at. Empty states, search results and picker rows are
/// the documented exceptions and none of them is a page header.
struct iOSPageHeader<Trailing: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// What this row is the top of. See `CadencePageHeaderRole`.
    var role: CadencePageHeaderRole = .page
    /// Optional only because Settings' category header sits beside a rail that already names the
    /// category, and an eyebrow there would label the label.
    var eyebrow: String? = nil
    /// A second, sentence-case clause after the eyebrow, separated by a middle dot. Today's day
    /// summary is the one caller: it gives way first when the row is squeezed, so a narrow task
    /// column truncates "· 3 timed" rather than the date.
    var eyebrowDetail: String? = nil
    let title: String
    /// The header's accent. **The count capsule is its only renderer** now that the identity tile
    /// is gone — and it renders it at all only because this parameter was otherwise about to become
    /// dead: a list header passes its own `colorHex`, which is the user's choice and the one thing
    /// on that page that was still theirs. It used to be ignored here, the badge hardcoding
    /// `Theme.blue` while `DesktopPageHeader`'s took its tint; both read the tint now.
    var color: Color = Theme.blue
    var count: Int? = nil
    /// Set on a pushed compact screen whose navigation bar is hidden, so the back control sits on
    /// this row instead of on one of its own above it. See `iOSHidesCompactNavigationBar()`.
    var onBack: (() -> Void)? = nil
    /// `false` where the host is a scroll container that already pads its content — the compact
    /// pages set their own 16pt gutter on the `LazyVStack`, and a header padding itself inside that
    /// would be indented from the rows below it.
    var padded: Bool = true
    /// One trailing control: Today's sort/completed bar, a list's edit button. Deliberately a
    /// single slot rather than arbitrary content — the status badge that used to ride here on the
    /// settings header repeated the first setting on the screen below it.
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        let metrics = CadencePageHeaderMetrics.metrics(
            role: role,
            isRegularWidth: horizontalSizeClass == .regular
        )

        HStack(alignment: .center, spacing: metrics.rowSpacing) {
            if let onBack {
                iOSHeaderBackButton(action: onBack)
                    .padding(.leading, -8)
            }

            VStack(alignment: .leading, spacing: 3) {
                if eyebrow != nil || eyebrowDetail != nil {
                    eyebrowLine(metrics)
                }

                Text(title)
                    .font(.system(size: metrics.titleSize, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            if let count {
                iOSPageHeaderCountBadge(count: count, tint: color, metrics: metrics)
            }

            // Sized before the text column, so a narrow column truncates the title rather than
            // squeezing a 44pt control. Priority, not `.fixedSize()`: at the bottom of the width
            // range the chips still give ground instead of overflowing the row and being clipped.
            trailing()
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, padded ? metrics.horizontalPadding : 0)
        .padding(.top, padded ? metrics.topPadding : 0)
        .padding(.bottom, padded ? metrics.bottomPadding : 0)
    }

    private func eyebrowLine(_ metrics: CadencePageHeaderMetrics) -> some View {
        HStack(spacing: 6) {
            if let eyebrow {
                SectionEyebrowLabel(text: eyebrow)
                    .lineLimit(1)
                    .layoutPriority(1)
            }

            if let eyebrowDetail, !eyebrowDetail.isEmpty {
                Text("· \(eyebrowDetail)")
                    .font(.system(size: metrics.eyebrowSize, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
        }
    }
}

extension iOSPageHeader where Trailing == EmptyView {
    init(
        role: CadencePageHeaderRole = .page,
        eyebrow: String? = nil,
        eyebrowDetail: String? = nil,
        title: String,
        color: Color = Theme.blue,
        count: Int? = nil,
        onBack: (() -> Void)? = nil,
        padded: Bool = true
    ) {
        self.init(
            role: role,
            eyebrow: eyebrow,
            eyebrowDetail: eyebrowDetail,
            title: title,
            color: color,
            count: count,
            onBack: onBack,
            padded: padded,
            trailing: { EmptyView() }
        )
    }
}

/// The one count badge. `iOSListsPageHeader` used the neutral `iOSListCountBadge` instead, whose
/// reasoning ("a second coloured element per row turns a page of lists into a page of colours") is
/// about a *row* in a list of rows — there is one header per screen.
///
/// It counted in `Theme.blue` regardless of the `color` its header was handed, which was invisible
/// while the identity tile beside it was spending that colour. With the tile gone this is where the
/// tint lands, and it is the same rule `DesktopPageHeader` already followed.
private struct iOSPageHeaderCountBadge: View {
    let count: Int
    let tint: Color
    let metrics: CadencePageHeaderMetrics

    var body: some View {
        Text("\(count)")
            .font(.system(size: metrics.countSize, weight: .bold))
            .foregroundStyle(tint)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, metrics.countPaddingH)
            .padding(.vertical, metrics.countPaddingV)
            .background(tint.opacity(CadencePageHeaderMetrics.countFillOpacity))
            .clipShape(Capsule())
    }
}

/// Name only. See `iOSPageHeader`, which this is a `.page`-role spelling of; the hosts are scroll
/// containers that pad their own content, hence `padded: false`.
struct iOSCompactPageHeader: View {
    let eyebrow: String
    /// See `iOSPageHeader.eyebrowDetail`. Today is the caller: it puts the day's summary here at
    /// both widths, having previously drawn it on the tablet and nowhere else.
    var eyebrowDetail: String? = nil
    let title: String
    var color: Color = Theme.blue
    var count: Int? = nil
    var onBack: (() -> Void)? = nil

    var body: some View {
        iOSPageHeader(
            role: .page,
            eyebrow: eyebrow,
            eyebrowDetail: eyebrowDetail,
            title: title,
            color: color,
            count: count,
            onBack: onBack,
            padded: false
        )
    }
}

struct iOSCompactPanelCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
            .shadow(color: Theme.cardElevationShadow, radius: 16, x: 0, y: 8)
    }
}

extension View {
    func iOSCompactPanelCard() -> some View {
        modifier(iOSCompactPanelCardModifier())
    }
}

struct iOSFeatureSummaryRow: View {
    let title: String
    let subtitle: String
    var detail: String? = nil
    let icon: String
    let color: Color
    /// Overrides the trailing value's colour. It follows `color` by default, which is right where
    /// `color` is a calendar's or a list's own `colorHex`. The More tab passes `Theme.dim` for
    /// `color` — its glyphs are navigation chrome — and a value rendered in `dim` would be the
    /// quietest thing in a row whose whole point is the number.
    var detailTint: Color? = nil
    var isSelected = false

    var body: some View {
        HStack(spacing: 10) {
            iOSIconTile(systemImage: icon, color: color, size: 30, iconSize: 14, fillOpacity: 0.11, bordered: false)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(subtitle.isEmpty ? "No context" : subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.subdued)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(detailTint ?? color)
                    .lineLimit(1)
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isSelected ? color.opacity(0.14) : Theme.surfaceElevated.opacity(0.36))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .shadow(color: Theme.cardElevationShadow, radius: 6, x: 0, y: 2)
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: 3)
                    .padding(.vertical, 8)
            }
        }
    }
}


/// One value under one label in a card — goal and habit detail's stat strips, and Settings'
/// overview grids.
///
/// It used to be two tiles with identical signatures: this one and `iOSSettingsMetricTile`, which
/// drew a bare glyph against an icon tile, 19pt against 22pt, and an uppercase kerned label against
/// a sentence-case one. Neither difference was a decision. The composite keeps what each did
/// better — the settings tile's `iOSIconTile` (which is how every other glyph-in-a-square in the
/// app is spelled) and its scale-down on a long value; this one's `SectionEyebrowLabel` in
/// `Theme.subdued`, which is the documented token for the label half of a label/value pair.
struct iOSMetricTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            iOSIconTile(
                systemImage: icon,
                color: color,
                size: 30,
                iconSize: 14,
                fillOpacity: 0.12,
                bordered: false
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                SectionEyebrowLabel(text: title, tint: Theme.subdued)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .cadenceCard(background: Theme.surfaceElevated.opacity(0.72), cornerRadius: Theme.radiusCard, shadowRadius: 10, shadowY: 4)
    }
}

/// The one empty state a chooser-plus-detail screen has, carried as a value so its two panes
/// cannot say different things about the same empty list.
///
/// T-533 was exactly that disagreement: at iPad regular width a new user saw "No goals yet /
/// Create a direction…" in the chooser and "No goal selected / Select an item from the list."
/// beside it, naming a list with no items to select. `iOSFeatureListPane` takes one of these and
/// `iOSFeatureEmptyDetail(matching:)` renders the same value on the detail side.
struct iOSFeatureEmptyState {
    let systemImage: String
    let title: String
    let subtitle: String
}

/// A detail pane with nothing selected. **Two spellings, and the difference is whether there is
/// anything to select.**
///
/// - `init(systemImage:title:)` keeps the house line, "Select an item from the list." It is true
///   only while the chooser beside it has rows — `iOSFocusView.unselectedDetail` reaches it on its
///   second branch, where a chosen subject was deleted out from under a list that still has others
///   (T-519).
/// - `init(matching:)` repeats the chooser's own empty state, for a pane that is reachable **only**
///   with an empty list beside it. Goals and Habits are both that shape: their `selected` falls
///   back through the whole collection, so `nil` means the collection is empty, and the chooser is
///   then drawing its own empty panel. One page, one sentence — the resolution T-519 chose for its
///   first branch.
struct iOSFeatureEmptyDetail: View {
    let systemImage: String
    let title: String
    let subtitle: String

    init(systemImage: String, title: String, subtitle: String = "Select an item from the list.") {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
    }

    init(matching empty: iOSFeatureEmptyState) {
        self.init(systemImage: empty.systemImage, title: empty.title, subtitle: empty.subtitle)
    }

    var body: some View {
        iOSEmptyPanel(
            systemImage: systemImage,
            title: title,
            subtitle: subtitle
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }
}

#endif
