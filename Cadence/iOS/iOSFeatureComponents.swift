#if os(iOS)
import SwiftData
import SwiftUI

/// Shared 13pt outline completion circle used by task rows across iOS: transparent center
/// with a 1.6pt border in the row's tint color while pending, solid green fill + white
/// checkmark when done (priority/tint color drops once a task is complete).
struct iOSTaskCompletionCircle: View {
    let isDone: Bool
    let tint: Color
    var diameter: CGFloat = 13

    var body: some View {
        ZStack {
            Circle()
                .fill(isDone ? Theme.doneFill : Color.clear)
            if !isDone {
                Circle()
                    .stroke(tint, lineWidth: 1.6)
            }
            if isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: diameter * 0.6, weight: .bold))
                    .foregroundStyle(Theme.onColor)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

struct iOSFeatureListPane<Content: View>: View {
    let eyebrow: String
    let title: String
    let count: Int
    let emptyTitle: String
    let emptySubtitle: String
    let emptyIcon: String
    var actionTitle: String? = nil
    var actionSystemImage = "plus"
    var action: (() -> Void)? = nil
    /// Set on iPhone, where this pane is a pushed screen with its navigation bar hidden. See
    /// `iOSHidesCompactNavigationBar()`.
    var onBack: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // `onBack` is the tell, and it is already documented as "set on iPhone, where this pane
            // is a pushed screen": with it this row is the top of a screen, without it it is the
            // top of a chooser column in a split. That is exactly the `role` distinction, so it is
            // read here rather than asked of every caller.
            iOSPageHeader(
                role: onBack == nil ? .pane : .page,
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
                iOSEmptyPanel(systemImage: emptyIcon, title: emptyTitle, subtitle: emptySubtitle)
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
struct iOSFeatureSplitLayout<List: View, Detail: View>: View {
    @ViewBuilder let list: () -> List
    @ViewBuilder let detail: () -> Detail

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                list()
                    .frame(width: CadenceRegularSplitLayout.listPaneWidth(forPaneWidth: proxy.size.width))
                    .frame(maxHeight: .infinity)

                Divider().background(Theme.borderSubtle)

                detail()
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
/// speaks more quietly than a whole screen. Everything else is `iOSPageHeaderMetrics`, which is
/// outside `#if os(iOS)` so the ramp can be pinned by a test.
///
/// **No subtitle.** `iOSCompactPageHeader` had one and no caller had passed it since the standing
/// rule landed — a line under "All Tasks" explaining that All Tasks is where you review tasks
/// describes the page you are already looking at. Empty states, search results and picker rows are
/// the documented exceptions and none of them is a page header.
struct iOSPageHeader<Trailing: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// What this row is the top of. See `iOSPageHeaderRole`.
    var role: iOSPageHeaderRole = .page
    /// Optional only because Settings' category header sits beside a rail that already names the
    /// category, and an eyebrow there would label the label.
    var eyebrow: String? = nil
    /// A second, sentence-case clause after the eyebrow, separated by a middle dot. Today's day
    /// summary is the one caller: it gives way first when the row is squeezed, so a narrow task
    /// column truncates "· 3 timed" rather than the date.
    var eyebrowDetail: String? = nil
    let title: String
    /// The identity tile the row leads with. A list passes its own glyph and `colorHex`; a page
    /// passes its feature glyph.
    var systemImage: String? = nil
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
        let metrics = iOSPageHeaderMetrics.metrics(
            role: role,
            isRegularWidth: horizontalSizeClass == .regular
        )

        HStack(alignment: .center, spacing: metrics.rowSpacing) {
            if let onBack {
                iOSHeaderBackButton(action: onBack)
                    .padding(.leading, -8)
            }

            if let systemImage {
                iOSIconTile(
                    systemImage: systemImage,
                    color: color,
                    size: metrics.tileSize,
                    iconSize: metrics.iconSize
                )
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
                iOSPageHeaderCountBadge(count: count, metrics: metrics)
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

    private func eyebrowLine(_ metrics: iOSPageHeaderMetrics) -> some View {
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
        role: iOSPageHeaderRole = .page,
        eyebrow: String? = nil,
        eyebrowDetail: String? = nil,
        title: String,
        systemImage: String? = nil,
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
            systemImage: systemImage,
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
/// about a *row* in a list of rows — there is one header per screen, and every other one of them
/// counts in blue.
private struct iOSPageHeaderCountBadge: View {
    let count: Int
    let metrics: iOSPageHeaderMetrics

    var body: some View {
        Text("\(count)")
            .font(.system(size: metrics.countSize, weight: .bold))
            .foregroundStyle(Theme.blue)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, metrics.countPaddingH)
            .padding(.vertical, metrics.countPaddingV)
            .background(Theme.blue.opacity(0.11))
            .clipShape(Capsule())
    }
}

/// Name only. See `iOSPageHeader`, which this is a `.page`-role spelling of; the hosts are scroll
/// containers that pad their own content, hence `padded: false`.
struct iOSCompactPageHeader: View {
    let eyebrow: String
    let title: String
    var systemImage: String? = nil
    var color: Color = Theme.blue
    var count: Int? = nil
    var onBack: (() -> Void)? = nil

    var body: some View {
        iOSPageHeader(
            role: .page,
            eyebrow: eyebrow,
            title: title,
            systemImage: systemImage,
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

struct iOSFeatureEmptyDetail: View {
    let systemImage: String
    let title: String

    var body: some View {
        iOSEmptyPanel(
            systemImage: systemImage,
            title: title,
            subtitle: "Select an item from the list."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }
}

#endif
