import SwiftUI

/// The geometry of the **Ledger** board card, shared by both platforms' Kanban boards ([[T-8181]]).
///
/// **Why these numbers are here and not in either card.** The two boards drew the same facts in two
/// costumes — iOS a tinted 2×2 `LazyVGrid` of pills, macOS a grey 50/50 chip split — and the pills
/// were the reason they looked unrelated. The Ledger replaces both: a fixed state gutter down the
/// leading edge washed in the list colour, a title, and **one** dim metadata run. Geometry is shared;
/// the interaction model is not, and deliberately so — on macOS every token in the run is a picker
/// (see `CadenceLedgerToken` below), on iPad the run is inert and the card's tap opens the inspector.
///
/// **Nothing here changes height on hover, and that is load-bearing.** Each macOS card is itself a
/// `dropDestination` drawing a 2pt rule at its own top edge (`KanbanColumnSupportViews`), so a card
/// that grows under the pointer slides that rule out from under it. The macOS token affordance is an
/// underline and a cursor change for exactly that reason: `.underline(_:)` draws inside the text's
/// existing line box and costs no layout.
nonisolated enum CadenceLedgerCardMetrics: Sendable {
    /// The state gutter's width. Fixed, as the design says — `gutterWidth(at:scaling:)` is this
    /// number plus what the ring's text role *gained*, so at `.fixed` scaling (the app-wide default)
    /// and at `.large` it is exactly 30 on both platforms.
    static let gutterWidth: CGFloat = 30

    /// One radius for both platforms, where the cards were 7 (macOS) and 18 (iOS).
    ///
    /// **What this does to `CadenceBoardMetadataChipMetrics.cornerRadius(inCardOfRadius:)`** — that
    /// rule stays live and keeps producing two answers, because its remaining callers are the
    /// *event* cards, which keep their platforms' own radii (7 on macOS, 18 on iOS). The task cards
    /// simply stop being one of its inputs. Unifying the two task cards onto one radius without
    /// noticing that would have turned a rule into a constant silently.
    static let cornerRadius: CGFloat = Theme.radiusControl

    /// The title's base point size, and its role for Dynamic Type. macOS drew a hardcoded
    /// `.system(size: 13.5)` here and had no Dynamic Type at all; iOS drew 14/15 through
    /// `cadenceFont`. One size, one role, both platforms.
    static let titleBase: CGFloat = 14

    /// The metadata run. 11pt, per the design.
    static let runBase: CGFloat = 11

    /// The priority mark in the gutter.
    static let priorityBase: CGFloat = 11

    /// The recurrence glyph in the gutter.
    static let recurrenceBase: CGFloat = 9

    /// The completion ring's drawn diameter.
    static let ringBase: CGFloat = 13

    static let gutterSpacing: CGFloat = 4
    static let contentSpacing: CGFloat = 4
    static let contentLeading: CGFloat = 10
    static let contentTrailing: CGFloat = 11
    static let contentVertical: CGFloat = 9

    /// The collapsed card's vertical padding. Twice this plus one 14pt line box is
    /// `collapsedLineHeight`, which is why the struck line comes out at 22 rather than being
    /// clamped to it.
    static let collapsedVertical: CGFloat = 3

    /// A completed card collapses to one struck line of this height — the design's "22pt struck
    /// line". It is a *minimum*, so a wrapped title at an accessibility size still fits.
    static let collapsedLineHeight: CGFloat = 22

    /// What sits between two tokens in the run. One spelling, so a test can assert the run's shape
    /// without re-typing the glyph.
    static let separator = " · "

    /// How a due-date token says it is the **due** date, now that the run carries no glyphs. Without
    /// it `… · Tue · Fri` states two bare days and names neither field.
    static let duePrefix = "Due "

    /// The gutter's wash over the list colour. Dimmer once the task is settled, the way the iOS
    /// card's leading strip already dimmed its tint.
    static func gutterWashOpacity(isSettled: Bool) -> Double {
        isSettled ? 0.07 : 0.17
    }

    /// The gutter width at a given text size. Fixed at `gutterWidth` whenever scaling is off or the
    /// reader is at `.large`; otherwise it grows by what the ring's role gained, so the ring does
    /// not outgrow the column it sits in.
    static func gutterWidth(at dynamicTypeSize: DynamicTypeSize, scaling: CadenceTypographyScaling) -> CGFloat {
        gutterWidth + CadenceTypeScale.growth(.rowTitle, base: ringBase, at: dynamicTypeSize, scaling: scaling)
    }

    /// The colour of one token's text.
    ///
    /// **Only the urgent token is coloured.** Everything else in the run is `Theme.dim`, including
    /// the list name — the list's identity is the gutter wash now, not a tinted glyph, so a coloured
    /// list token would put two colours in a run whose whole point is that one of them means
    /// something. Over-do and overdue are red, today is amber, every ordinary future date is neutral.
    static func color(for token: CadenceLedgerToken) -> Color {
        guard !token.isPlaceholder else { return Theme.dim }
        switch token.emphasis {
        case .neutral: return Theme.dim
        case .attention: return Theme.amber
        case .urgent: return Theme.red
        }
    }
}

/// One token in a Ledger card's metadata run — `9:00a`, `45m`, `Tue`, `#deep-work`.
///
/// `nonisolated` for `CadenceBoardCardChip`'s reason: the project compiles with
/// `-default-isolation MainActor`, and the macOS-built test target has to be able to compare a run
/// built for a card that lives inside `#if os(iOS)`.
nonisolated struct CadenceLedgerToken: Identifiable, Equatable, Sendable {
    /// Which field the token states. The order of the cases is the order the run draws them.
    enum Kind: String, Sendable, CaseIterable {
        case time
        case duration
        case doDay
        case dueDay
        case list
        case tag
    }

    let kind: Kind
    /// Unique within one run. `tag` repeats, so its id carries the tag.
    let id: String
    let text: String
    let emphasis: CadenceBoardCardChip.Emphasis
    /// A token standing in for a field that currently has **no** value, so macOS still has something
    /// to click. The shared run builder only ever produces one when a caller asks for placeholders;
    /// see `CadenceLedgerCardSupport.tokens`.
    var isPlaceholder: Bool = false
}

/// What a Ledger card's run says, decided once and drawn twice.
///
/// **Built on `CadenceBoardCardMetadata.chips(for:showsContainer:dayAlreadyStatedBySurface:todayKey:)`
/// rather than beside it.** That descriptor already owns the two per-board knobs and the urgency
/// rule, and it is the only reason the two boards agree about which dates a card states at all. This
/// maps its chips into run tokens and adds the three facts that are not chips — the slot, the
/// estimate and the tags.
nonisolated enum CadenceLedgerCardSupport {
    /// The run, in draw order: slot, estimate, do day, due day, list, tags.
    ///
    /// `placeholders` is macOS's **empty-field affordance** and nothing else. A bare text run has no
    /// edges to click, so on macOS every token is a hit target — which means a field with no value
    /// would be unreachable from the card, exactly the regression the owner's amendment exists to
    /// prevent. iOS passes `false`: its tokens are inert, so a token standing for nothing would be
    /// noise with no purpose. This is the same asymmetry `CadenceBoardCardMetadata` already records
    /// for the empty `Due` chip, kept on the same side of the line — in the interaction shell.
    static func tokens(
        startMinute: Int,
        estimatedMinutes: Int,
        chips: [CadenceBoardCardChip],
        tagNames: [String],
        placeholders: Bool = false,
        showsEmptyDueDate: Bool = false,
        locale: Locale = .current
    ) -> [CadenceLedgerToken] {
        var tokens: [CadenceLedgerToken] = []

        if startMinute >= 0 {
            tokens.append(
                CadenceLedgerToken(
                    kind: .time,
                    id: Kind.time.rawValue,
                    text: TimeFormatters.compactTimeString(from: startMinute, locale: locale).lowercased(),
                    emphasis: .neutral
                )
            )
        }

        if estimatedMinutes > 0 {
            tokens.append(
                CadenceLedgerToken(
                    kind: .duration,
                    id: Kind.duration.rawValue,
                    text: TimeFormatters.durationLabel(minutes: estimatedMinutes, emptyPlaceholder: estimatePlaceholder),
                    emphasis: .neutral
                )
            )
        } else if placeholders {
            tokens.append(
                CadenceLedgerToken(
                    kind: .duration,
                    id: Kind.duration.rawValue,
                    text: estimatePlaceholder,
                    emphasis: .neutral,
                    isPlaceholder: true
                )
            )
        }

        for chip in chips {
            switch chip.kind {
            case .doDate:
                tokens.append(
                    CadenceLedgerToken(
                        kind: .doDay,
                        id: Kind.doDay.rawValue,
                        text: chip.text,
                        emphasis: chip.emphasis
                    )
                )
            case .dueDate:
                tokens.append(
                    CadenceLedgerToken(
                        kind: .dueDay,
                        id: Kind.dueDay.rawValue,
                        text: CadenceLedgerCardMetrics.duePrefix + chip.text,
                        emphasis: chip.emphasis
                    )
                )
            case .list:
                tokens.append(
                    CadenceLedgerToken(
                        kind: .list,
                        id: Kind.list.rawValue,
                        text: chip.text,
                        emphasis: .neutral
                    )
                )
            }
        }

        if placeholders, showsEmptyDueDate, !chips.contains(where: { $0.kind == .dueDate }) {
            // Draw order, not append order: the empty due token belongs where a real one would be,
            // which is before the list and the tags rather than after them.
            let insertion = tokens.firstIndex { $0.kind == .list || $0.kind == .tag } ?? tokens.endIndex
            tokens.insert(
                CadenceLedgerToken(
                    kind: .dueDay,
                    id: Kind.dueDay.rawValue,
                    text: duePlaceholder,
                    emphasis: .neutral,
                    isPlaceholder: true
                ),
                at: insertion
            )
        }

        for name in tagNames where !name.isEmpty {
            tokens.append(
                CadenceLedgerToken(
                    kind: .tag,
                    id: "tag-\(name)",
                    text: "#\(name)",
                    emphasis: .neutral
                )
            )
        }

        return tokens
    }

    /// What an unset estimate says on macOS. The field's **name**, as the empty due chip has always
    /// done — `0m` and `—` are both values the user cannot have chosen, and a run of dim words is
    /// the wrong place to print a dash.
    static let estimatePlaceholder = "Est"
    /// What an unset due date says on macOS, unchanged from the chip it replaces.
    static let duePlaceholder = "Due"

    private typealias Kind = CadenceLedgerToken.Kind
}

/// The state gutter: the completion ring, the priority mark and the recurrence glyph stacked down a
/// fixed-width strip washed in the list's colour, so the three **states** scan as one vertical
/// column instead of being spread across a card as three unrelated marks.
///
/// The ring is a slot rather than a drawn view because its **control** is genuinely per-platform:
/// macOS's is a `Button` under a pointer, iOS's has a 44pt expanded hit area for a finger. Those are
/// interaction, not geometry; the drawing inside both is `CadenceTaskCompletionCircle` ([[T-8411]])
/// at `CadenceLedgerCardMetrics.ringBase`.
///
/// Priority and recurrence appear on **neither** board card today; this gutter is where they land,
/// and they are new on both platforms.
///
/// **It draws the marks, not the wash.** A column that filled the card's height would have to ask
/// for `maxHeight: .infinity`, and a board card is laid out inside a `ScrollView`'s `VStack`, where
/// an unbounded height proposal is how a fixed-size card becomes a card that eats its column. The
/// wash is a `.background(alignment: .leading)` on the card instead, which takes the card's height
/// from the card rather than proposing one to it.
struct CadenceLedgerCardGutter<Ring: View>: View {
    let priority: TaskPriority
    let isRecurring: Bool
    /// A completed card collapses to one struck line, which has room for the ring and nothing else.
    var isCollapsed: Bool = false
    /// Resolved by the card, so the marks column and the wash behind it cannot read two numbers.
    let width: CGFloat
    @ViewBuilder let ring: () -> Ring

    var body: some View {
        VStack(spacing: CadenceLedgerCardMetrics.gutterSpacing) {
            // The ring gets the gutter's full width so a platform that expands its hit area around
            // it expands into the gutter rather than across the title.
            ring()
                .frame(width: width)

            if !isCollapsed {
                if priority != .none {
                    Text(TaskTitleSupport.priorityMark(for: priority))
                        .cadenceFont(.metadata, base: CadenceLedgerCardMetrics.priorityBase, weight: .bold)
                        .foregroundStyle(Theme.priorityColor(priority))
                        .lineLimit(1)
                        .accessibilityLabel("Priority: \(priority.label)")
                }

                if isRecurring {
                    Image(systemName: "repeat")
                        .cadenceFont(.metadata, base: CadenceLedgerCardMetrics.recurrenceBase, weight: .semibold)
                        .foregroundStyle(Theme.dim)
                        .accessibilityLabel("Repeats")
                }
            }

            Spacer(minLength: 0)
        }
        // The gutter's own top inset matches the content's, so the ring sits on the title's first
        // line rather than on the card's top edge.
        .padding(.top, isCollapsed ? CadenceLedgerCardMetrics.collapsedVertical : CadenceLedgerCardMetrics.contentVertical)
        .frame(width: width)
    }
}

/// The metadata run: one line of dim 11pt text, `9:00a · 45m · Tue · #deep-work`.
///
/// It wraps rather than truncating, through the shared `CadenceWrappingHStack`, because the Calendar
/// Board's pinned rail is **248pt** and a run that truncated there would drop the tag — which is the
/// one token the reader chose themselves. The separator rides with the token before it so a wrapped
/// line never opens on a dangling glyph.
struct CadenceLedgerCardRun<TokenView: View>: View {
    let tokens: [CadenceLedgerToken]
    @ViewBuilder let tokenView: (CadenceLedgerToken) -> TokenView

    var body: some View {
        if !tokens.isEmpty {
            CadenceWrappingHStack(spacing: 0, lineSpacing: 1) {
                ForEach(tokens) { token in
                    HStack(spacing: 0) {
                        tokenView(token)
                        if token.id != tokens.last?.id {
                            Text(CadenceLedgerCardMetrics.separator)
                                .cadenceFont(.metadata, base: CadenceLedgerCardMetrics.runBase, weight: .medium)
                                .foregroundStyle(Theme.dim)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
    }
}

/// One token's text. The whole of what a token *looks* like, so the macOS picker wrapper and the
/// inert iOS token cannot drift into two typefaces.
///
/// `isUnderlined` is macOS's hover state and iOS never sets it — **hover is input, not UI**
/// (`AGENTS.md`, "macOS and iOS are one app on two platforms"): a touch surface has no pointer to
/// park over a token. It is drawn with `.underline(_:)` rather than with a rule or a pill because it
/// takes no layout: see the note on `CadenceLedgerCardMetrics`.
struct CadenceLedgerTokenLabel: View {
    let token: CadenceLedgerToken
    var isUnderlined: Bool = false

    var body: some View {
        Text(token.text)
            .cadenceFont(.metadata, base: CadenceLedgerCardMetrics.runBase, weight: .medium)
            .foregroundStyle(CadenceLedgerCardMetrics.color(for: token))
            .underline(isUnderlined, color: CadenceLedgerCardMetrics.color(for: token))
            .lineLimit(1)
    }
}

/// **The Ledger card itself — one layout, drawn by both platforms.**
///
/// `AGENTS.md`'s standing rule ([[T-8201]]) is that macOS and iOS are one app on two platforms and
/// may differ only where hardware or input forces it, so this is not "shared pieces each card
/// assembles": the anatomy — gutter, title, run, checklist, surface, radius, every spacing — lives
/// here once and neither platform owns a copy of it. What the two platforms pass in are the four
/// things that are genuinely forced, each with the sentence the rule demands:
///
/// - `ring` — macOS's completion control is a `Button` over a hold-to-settle progress arc and iOS's
///   is a circle with a 44pt expanded hit area, because a pointer can press-and-hold on a 13pt
///   target and a fingertip cannot.
/// - `tokenView` — on macOS each token is a picker that underlines under the pointer; on iOS it is
///   inert, because a tappable region inside a tappable card competes with its container on touch
///   but not under a pointer.
/// - `subtasks` — each platform's own subtask row, because ticking a subtask off is a hit target
///   sized for its input device.
/// - `settlingOverlay` — the pending-completion wash. Both platforms pass the one shared
///   `TaskCompletionPendingOverlay` drawing ([[T-8354]]); it stays a slot because each
///   platform's card owns the gate around it.
///
/// `isHovered` is the same thing: a board card has no hover state on a touch device.
struct CadenceLedgerCard<Ring: View, TokenView: View, Subtasks: View, SettlingOverlay: View>: View {
    let title: String
    /// `CadenceTaskCompletionState.isSettled` — done or cancelled. A settled card collapses.
    let isSettled: Bool
    /// Struck through. Not the same question as `isSettled`: macOS strikes a card the moment a
    /// completion starts settling, before the status has changed.
    let isStruckThrough: Bool
    let listColor: Color
    let priority: TaskPriority
    let isRecurring: Bool
    let tokens: [CadenceLedgerToken]
    var isHovered: Bool = false
    @ViewBuilder let ring: () -> Ring
    @ViewBuilder let tokenView: (CadenceLedgerToken) -> TokenView
    @ViewBuilder let subtasks: () -> Subtasks
    @ViewBuilder let settlingOverlay: () -> SettlingOverlay

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling

    private var gutterWidth: CGFloat {
        CadenceLedgerCardMetrics.gutterWidth(at: dynamicTypeSize, scaling: scaling)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CadenceLedgerCardMetrics.cornerRadius, style: .continuous)
    }

    /// Two lines at ordinary sizes; uncapped once the reader is at an accessibility size, where
    /// clipping a title is the thing they asked not to happen.
    private var titleLineLimit: Int? {
        scaling == .enabled && CadenceTypeScale.isAccessibilitySize(dynamicTypeSize) ? nil : 2
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            CadenceLedgerCardGutter(
                priority: priority,
                isRecurring: isRecurring,
                isCollapsed: isSettled,
                width: gutterWidth,
                ring: ring
            )

            content
                .padding(.leading, CadenceLedgerCardMetrics.contentLeading)
                .padding(.trailing, CadenceLedgerCardMetrics.contentTrailing)
                .padding(.vertical, isSettled ? CadenceLedgerCardMetrics.collapsedVertical : CadenceLedgerCardMetrics.contentVertical)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: isSettled ? collapsedHeight : nil)
        .fixedSize(horizontal: false, vertical: true)
        // **One `.background`, with the wash stacked inside it.** Two chained `.background`
        // modifiers do not layer the way they read: each one goes BEHIND the last, so an opaque
        // card fill written after the gutter wash hides it completely. Measured on
        // `Cadence-iPhone15` 2026-10-28 — every pixel of the card came back `Theme.surface`,
        // gutter included. The wash takes the card's own height from here rather than asking for
        // `maxHeight: .infinity` inside the gutter; see `CadenceLedgerCardGutter`.
        .background(alignment: .leading) {
            ZStack(alignment: .leading) {
                (isHovered ? Theme.surfaceElevated : Theme.surface)
                Rectangle()
                    .fill(listColor.opacity(CadenceLedgerCardMetrics.gutterWashOpacity(isSettled: isSettled)))
                    .frame(width: gutterWidth)
            }
        }
        .overlay { settlingOverlay() }
        .overlay { shape.strokeBorder(Theme.borderSubtle, lineWidth: 1) }
        .clipShape(shape)
        .contentShape(shape)
    }

    /// A completed card collapses to a struck line. Nothing else survives it: the run restates
    /// dates for work that is over, and a checklist under a finished task is a list of things that
    /// no longer need doing.
    @ViewBuilder
    private var content: some View {
        if isSettled {
            titleText
        } else {
            VStack(alignment: .leading, spacing: CadenceLedgerCardMetrics.contentSpacing) {
                titleText
                CadenceLedgerCardRun(tokens: tokens, tokenView: tokenView)
                subtasks()
            }
        }
    }

    private var titleText: some View {
        Text(title)
            .cadenceFont(.rowTitle, base: CadenceLedgerCardMetrics.titleBase, weight: .semibold)
            .foregroundStyle(isSettled ? Theme.dim : Theme.text)
            .strikethrough(isStruckThrough, color: Theme.dim)
            .lineLimit(isSettled ? 1 : titleLineLimit)
            .fixedSize(horizontal: false, vertical: scaling == .enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var collapsedHeight: CGFloat {
        CadenceTypeScale.height(
            CadenceLedgerCardMetrics.collapsedLineHeight,
            holding: .rowTitle,
            textBase: CadenceLedgerCardMetrics.titleBase,
            at: dynamicTypeSize,
            scaling: scaling
        )
    }
}

/// The tags a Ledger run states, as plain names.
///
/// Separate from `CadenceLedgerCardSupport` because that enum is `nonisolated` and this reads an
/// `AppTask`'s relationships — the same split `CadenceBoardCardMetadata` makes against the chip it
/// builds, and for the same reason: the value half is the half a test compares.
///
/// The cap is `CadenceTaskPresentationSupport.rowTagLimit`, the figure the task rows already use,
/// so no board decides for itself how much of a task fits. The **slug** is what a `#tag` run states
/// rather than the display name: `#deep-work` is one token and `#deep work` is two words that read
/// as the end of the run plus a stray.
enum CadenceLedgerTagTokens {
    static func names(for task: AppTask) -> [String] {
        TagSupport.uniqueBySlug(task.sortedTags)
            .prefix(CadenceTaskPresentationSupport.rowTagLimit)
            .map { $0.slug.isEmpty ? $0.name : $0.slug }
            .filter { !$0.isEmpty }
    }
}
