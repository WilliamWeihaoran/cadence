#if os(macOS)
import SwiftUI

/// The inspector popover's own box: how wide it is and how far its rows sit inside that width.
///
/// `TaskDetailPopover` used to carry both numbers as literals. They are here because the placement
/// rule below is about them: whether a panel opened from one of the inspector's rows lands on top
/// of the rows or clear of them is a question about this column, not about the panel.
nonisolated enum TaskInspectorPopoverMetrics {
    /// Both presentation modes share one width now that the field rows drive the layout.
    static let width: CGFloat = 336
    /// The inset between the popover's edge and its content.
    static let contentInset: CGFloat = 14
    /// The band the inspector actually draws rows in — what a child panel can slice.
    static var contentColumnWidth: CGFloat { width - contentInset * 2 }
}

/// The widths of the panels the inspector opens, for the two that have no metrics type of their
/// own.
///
/// **Why these two are here and the other two are not.** The inspector opens four panels: the date
/// panel (Do and Due), the estimate roller, the priority picker and the recurrence picker. The
/// first two already answer from a named metric — `CadenceDateSelectionMetrics.width(at:)` and
/// `EstimateRollerMetrics.panelWidth(at:scaling:)` — because both are shared controls that grow
/// with type size. The other two are macOS-only panels of fixed width and ended their bodies in a
/// bare `.frame(width: 160)` and `.frame(width: 268)`.
///
/// That mattered because **the whole argument in `TaskInspectorChildPopoverPlacement` is
/// arithmetic over a panel's width against `TaskInspectorPopoverMetrics.contentColumnWidth`**, and
/// half of it was unreadable: T-1510 had to take the priority panel's width out of a view body to
/// do its sums, and T-1480 quoted the recurrence panel as "268" from the same literal. A width a
/// placement rule reasons about has to be a width the placement rule can read (T-1600).
nonisolated enum TaskInspectorPanelMetrics {
    /// `TaskPriorityPickerPopover` — one row per `TaskPriority`, mark, label and tick.
    static let priorityWidth: CGFloat = 160
    /// `TaskRecurrencePickerPanel` — APPLY TO / REPEATS / ENDS.
    static let recurrenceWidth: CGFloat = 268

    /// Every panel the inspector can open, named, at one type size.
    ///
    /// **It is a typed list, and it has to be: a width is a value, not a spelling** (T-1941). Two
    /// of the four are computed from a `DynamicTypeSize` by types that live elsewhere, so nothing
    /// that reads source text can produce this array. What *can* be read out of source is how many
    /// panels there are to have a width — the inspector's child popovers are the ones whose
    /// `arrowEdge:` comes from a `TaskInspectorChildPopoverPlacement` — and
    /// `CadenceInspectorChildPopoverPlacementTests.theEnumeratedPanelsAreCountedAgainstTheInspectorsOwnPopovers`
    /// counts them and fails when this list is one short. Before that, the only test over this list
    /// asserted `count == 4` *against this list*, so a fifth panel was invisible to every relation
    /// asserted over it and nothing went red.
    ///
    /// `dynamicTypeSize` is a parameter rather than `.large` baked in even though the inspector is
    /// macOS-only: the two shared panels genuinely widen with type, and a caller that wants the
    /// desktop reading should have to say so.
    ///
    /// `@MainActor` because `EstimateRollerMetrics.panelWidth(at:scaling:)` is: the roller's
    /// metrics are view code. Nothing here is, so the rest of the type stays `nonisolated`.
    @MainActor
    static func allWidths(at dynamicTypeSize: DynamicTypeSize) -> [(name: String, width: CGFloat)] {
        [
            ("date", CadenceDateSelectionMetrics.width(at: dynamicTypeSize)),
            ("estimate", EstimateRollerMetrics.panelWidth(at: dynamicTypeSize, scaling: .enabled)),
            ("priority", priorityWidth),
            ("recurrence", recurrenceWidth)
        ]
    }
}

/// Where a panel opened from a row *inside* the task inspector is anchored.
///
/// **A macOS popover is its own `NSWindow`.** The inspector is one, and every picker it opens is a
/// second one drawn over the first — nothing clips it to the inspector and nothing hides the
/// inspector behind it. A child anchored on its row's **bottom** edge is centred on that row, and
/// every panel the inspector opens is narrower than the inspector's content column, so the child
/// lands *inside* the column: it covers the middle and leaves the inspector's own rows showing as
/// a sliver down each margin. That is T-1480 — the reader sees the lower popover sliced rather
/// than covered, with the Due row surviving as "Set", Repeat as "er", and the Subtasks and Notes
/// headings as "SUB" and "NOT".
///
/// The arithmetic is the whole argument, and it is not about the panel being too tall: the date
/// panel is `CadenceDateSelectionMetrics.width` wide against a `contentColumnWidth` column, so
/// each surviving sliver is half the difference. Shrinking the panel *widens* the slivers.
///
/// `.besideInspector` anchors on the row's **trailing** edge instead. The rows span the content
/// column exactly — they carry their own inner inset so a hover can wash the full width of the
/// well — so the row's trailing edge is the column's trailing edge, and a panel hung off it opens
/// clear of every row the inspector draws. The arrow still points at the row that opened it, which
/// was never the part that was wrong.
///
/// **T-1722 — the declared edge is not what AppKit does, so the rule cannot be about the edge.**
/// T-1480 and T-1510 both chose an *end* for the panel to leave by and both closed on arithmetic;
/// the first direct reading of the running surface refutes the mechanism they assumed. Measured
/// through `app.popovers` on this Mac, inspector content column x ∈ [1111, 1419]:
///
/// - The **priority tile**, at x ∈ [1111, 1139], declaring `.besideInspector(.leading)`, opened its
///   186pt panel at x ∈ [**1139**, 1325] — flush against the tile's *trailing* edge, strictly
///   inside the column, over every row beneath it.
/// - The **estimate chip**, at x ∈ [1345, 1419], declaring `.besideInspector(.trailing)`, opened
///   its 286pt roller at x ∈ [**1059**, 1345] — flush against the chip's *leading* edge,
///   overhanging the column by 25pt and covering the title row, the list row, Do and Due.
///
/// Both are the exact opposite of what was declared, and **available space does not explain it**:
/// the tile's declared leading side would have put its panel at x ∈ [925, 1111] on a 1512pt
/// display, which fits. The vertical axis is not affected — `.bottom` is honoured as documented,
/// which is why `.belowRow` still means what its name says and why the defect T-1480 photographed
/// was a panel *below* a row. So on the horizontal axis SwiftUI's `arrowEdge:` reaches `NSPopover`
/// inverted, and an API that promises which end a panel leaves by is promising something this
/// repository does not control.
///
/// **What survives is a condition on the ANCHOR, not on the edge.** If the anchor *spans* the
/// content column then both of its ends are the column's ends, so a panel hung off either one
/// clears every row — and it no longer matters which end AppKit picks, or why. A field row spans
/// the column by construction, which is why T-1480's three Schedule rows were right for a reason
/// their own argument did not name and stayed right through the inversion. The two header
/// controls do not span it: a 28pt tile and a fixed-size chip sit at its two ends, and *that* is
/// what had to change. They are presented from the title **row** now, which does span the column,
/// so there is one placement again and no end to choose. `anchorSpansColumn(_:in:)` is that
/// condition, and `CadenceInspectorHeaderPanelPlacementUITests` reads the resulting frames off the
/// running app rather than off this file.
nonisolated enum TaskInspectorChildPopoverPlacement {
    /// Centred under the anchor row. Right when the host is wider than the panel — the list
    /// sheets present these same controls in a window that can absorb one — and wrong inside the
    /// inspector, which cannot.
    case belowRow
    /// Hung off an end of the inspector's content column, so the panel leaves the inspector
    /// instead of opening over its rows.
    ///
    /// **No end, deliberately** — it used to carry one (T-1510) and the running app ignored it.
    /// The case is only correct for an anchor that spans the column, because that is the condition
    /// under which *both* ends are the column's ends; `anchorSpansColumn(_:in:)` states it and
    /// every call site now satisfies it.
    case besideInspector

    /// The edge the view asks `NSPopover` for. A *request*: see the type's own comment for the
    /// measurement showing that the horizontal ones arrive inverted.
    var arrowEdge: Edge {
        switch self {
        case .belowRow: .bottom
        case .besideInspector: .trailing
        }
    }

    /// Whether `anchor` reaches both ends of `column` — the whole of the T-1722 rule.
    ///
    /// When it does, a panel hung off either end lands outside the column and the rows are clear
    /// whichever end the platform picks. When it does not, one of the two ends opens back across
    /// the rows, and which one that is is not something a SwiftUI call site can decide.
    ///
    /// The tolerance is a point: a row and the column it spans are laid out from the same inset,
    /// so they agree exactly in the model and to within rounding on a real surface.
    static func anchorSpansColumn(_ anchor: CGRect, in column: CGRect, tolerance: CGFloat = 1) -> Bool {
        anchor.minX <= column.minX + tolerance && anchor.maxX >= column.maxX - tolerance
    }

    /// Where a panel of `panelSize` lands when it leaves `row` by `edge`, in the inspector's own
    /// coordinate space. Flush against that edge and centred on the other axis, which is how
    /// `NSPopover` places a panel against its positioning rect; the arrow only pushes the panel
    /// further from the row, so ignoring it never flatters a placement.
    ///
    /// **Takes the edge rather than reading one**, because the point of T-1722 is that the app
    /// does not get to know which end the panel will leave by: the useful question is what happens
    /// at *each* end, and a caller that can only ask about the declared one cannot ask it.
    static func panelFrame(anchoredTo row: CGRect, panelSize: CGSize, leavingBy edge: Edge) -> CGRect {
        let origin: CGPoint = switch edge {
        case .bottom: CGPoint(x: row.midX - panelSize.width / 2, y: row.maxY)
        case .top: CGPoint(x: row.midX - panelSize.width / 2, y: row.minY - panelSize.height)
        case .trailing: CGPoint(x: row.maxX, y: row.midY - panelSize.height / 2)
        case .leading: CGPoint(x: row.minX - panelSize.width, y: row.midY - panelSize.height / 2)
        }
        return CGRect(origin: origin, size: panelSize)
    }

    /// The frame for the edge this placement *asks* for. Kept because `.belowRow` is honoured as
    /// declared and is still a claim worth asserting; read `panelFrame(anchoredTo:panelSize:
    /// leavingBy:)` directly for anything horizontal.
    func panelFrame(anchoredTo row: CGRect, panelSize: CGSize) -> CGRect {
        Self.panelFrame(anchoredTo: row, panelSize: panelSize, leavingBy: arrowEdge)
    }

    /// What a panel does to the inspector's content column: nothing, covers it from an edge, or
    /// strands a sliver of it on *both* sides. The third is the defect — "sliced rather than
    /// covered" — and it is the one a reader cannot parse, because the fragments left behind are
    /// the starts and ends of words belonging to rows the panel is otherwise hiding.
    static func occlusion(ofColumn column: CGRect, byPanel panel: CGRect) -> InspectorColumnOcclusion {
        guard column.intersects(panel) else { return .clear }
        let sliverLeading = panel.minX > column.minX
        let sliverTrailing = panel.maxX < column.maxX
        return sliverLeading && sliverTrailing ? .sliced : .covered
    }
}

/// See `TaskInspectorChildPopoverPlacement.occlusion(ofColumn:byPanel:)`.
nonisolated enum InspectorColumnOcclusion: Equatable {
    /// The panel does not touch the inspector's rows.
    case clear
    /// The panel overlaps the column but reaches at least one of its sides, so nothing of the
    /// covered rows is stranded beside it.
    case covered
    /// The panel sits strictly inside the column and leaves a sliver of it showing on both sides.
    case sliced
}

/// Shared metrics for the inspector's "icon / label left / value right" field list.
enum TaskInspectorFieldRowMetrics {
    /// Each row carries its own horizontal inset rather than inheriting one from the recessed
    /// group. That is what lets a hovered row wash the full width of the well: if the group
    /// padded its contents, every hover would be a narrower box drawn inside the well's box.
    static let verticalPadding: CGFloat = 6
    static let minHeight: CGFloat = 32
    /// Fixed leading slot so every label in a group starts on the same x.
    static let iconSlot: CGFloat = 19
    static let iconSize: CGFloat = 12
    static let hoverCornerRadius: CGFloat = 6
    static let labelFont = Font.system(size: 11)
    static let valueFont = Font.system(size: 11)
    static let groupHorizontalPadding: CGFloat = 10
    static let groupCornerRadius: CGFloat = 8
    /// The *trailing* value beside a group label — a count, not an eyebrow — drawn at the
    /// eyebrow's own size so the two sit on one line. The label itself is
    /// `SectionEyebrowLabel(size: .compact)`; there is no second kerning constant here any more
    /// (T-284 — it was 0.54, one of four the 9pt tier had accumulated).
    static let groupLabelFont = SectionEyebrowLabel.Size.compact.font
}

/// Shared metrics for the inspector's `List › Section` breadcrumb. The segments themselves are
/// `ContainerPickerBadge` / `TaskSectionPickerBadge` in `breadcrumbSegment` mode — the same
/// pickers the chips elsewhere present, drawn as bare text.
enum TaskInspectorBreadcrumbMetrics {
    static let font = Font.system(size: 11, weight: .medium)
    static let segmentHeight: CGFloat = 20
    static let segmentHorizontalPadding: CGFloat = 5
    /// Caps one segment so a long list name cannot push the section out of the panel; the text
    /// still takes its intrinsic width when it is shorter.
    static let maxSegmentWidth: CGFloat = 128
    static let hoverCornerRadius: CGFloat = 5
}

/// One line of the inspector overview list: leading glyph, field name, value flush right.
struct TaskInspectorFieldRow<Value: View>: View {
    let label: String
    /// SF Symbol drawn in the fixed leading slot. `nil` leaves the slot empty so rows without
    /// an icon still align with their neighbours.
    var icon: String? = nil
    var iconColor: Color = Theme.dim
    /// Keeps the leading slot when `icon` is `nil`, so one iconless row still lines up with iconed
    /// neighbours. Set `false` for a group where *no* row has an icon — otherwise every label in it
    /// is indented past an empty column.
    var reservesIconSlot: Bool = true
    @ViewBuilder let value: Value

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: TaskInspectorFieldRowMetrics.iconSize))
                        .foregroundStyle(iconColor)
                }
            }
            .frame(width: icon == nil && !reservesIconSlot ? 0 : TaskInspectorFieldRowMetrics.iconSlot, alignment: .leading)

            Text(label)
                .font(TaskInspectorFieldRowMetrics.labelFont)
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 8)

            value
        }
        .padding(.vertical, TaskInspectorFieldRowMetrics.verticalPadding)
        .padding(.horizontal, TaskInspectorFieldRowMetrics.groupHorizontalPadding)
        .frame(maxWidth: .infinity, minHeight: TaskInspectorFieldRowMetrics.minHeight, alignment: .leading)
    }
}

/// Uppercase group heading, optionally with a right-aligned counter ("1/3").
struct TaskInspectorGroupLabel: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            SectionEyebrowLabel(text: title, size: .compact)

            Spacer(minLength: 0)

            if let trailing {
                Text(trailing)
                    .font(TaskInspectorFieldRowMetrics.groupLabelFont)
                    .foregroundStyle(Theme.dim)
                    .monospacedDigit()
            }
        }
    }
}

/// Recessed well that holds a run of field rows (or any inspector content).
struct TaskInspectorRecessedGroup<Content: View>: View {
    var verticalPadding: CGFloat = 0
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceRecessed)
        .clipShape(RoundedRectangle(cornerRadius: TaskInspectorFieldRowMetrics.groupCornerRadius))
    }
}

/// Group heading + recessed well, the standard inspector section shape.
struct TaskInspectorRecessedSection<Content: View>: View {
    let title: String
    var trailing: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TaskInspectorGroupLabel(title: title, trailing: trailing)
            TaskInspectorRecessedGroup {
                content
            }
        }
    }
}

/// Value text for a field row — bright when the field has a value, dim when it is empty.
struct TaskInspectorFieldValueText: View {
    let text: String
    let isSet: Bool

    var body: some View {
        Text(text)
            .font(TaskInspectorFieldRowMetrics.valueFont)
            .foregroundStyle(isSet ? Theme.text : Theme.dim)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

/// Hairline between field rows. Never drawn after the last row of a group.
struct TaskInspectorFieldDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.borderSubtle)
            .frame(height: 1)
            // Matches the rows' own inset so the hairlines still start at the icon column now
            // that the group no longer pads its contents.
            .padding(.horizontal, TaskInspectorFieldRowMetrics.groupHorizontalPadding)
    }
}

/// A field row whose entire surface is a button (opens a picker/menu for that field).
///
/// Uses `.plain`, **not** `.cadencePlain`, so every row in the well hovers identically:
/// `InspectorPickerHover` is the one hover layer. Stacking cadencePlain's radius-10 blue fill +
/// stroke on top of that made the button rows hover heavier than their neighbour and nested a
/// radius-6 wash inside a radius-10 border. One layer, one radius, every row in the well.
struct TaskInspectorFieldButtonRow: View {
    let label: String
    var icon: String? = nil
    /// Semantic tint for the glyph — the colour the field's concept already carries elsewhere in
    /// the app (do = blue, due = red, estimate = purple, actual = green, repeat = amber).
    var iconColor: Color = Theme.dim
    /// See `TaskInspectorFieldRow.reservesIconSlot`.
    var reservesIconSlot: Bool = true
    let valueText: String
    let isSet: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TaskInspectorFieldRow(
                label: label,
                icon: icon,
                iconColor: iconColor,
                reservesIconSlot: reservesIconSlot
            ) {
                TaskInspectorFieldValueText(text: valueText, isSet: isSet)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(InspectorPickerHover(cornerRadius: TaskInspectorFieldRowMetrics.hoverCornerRadius))
    }
}

struct TaskInspectorDateControl: View {
    /// Field name shown on the left (e.g. "Do").
    let label: String
    /// SF Symbol for the row's leading slot.
    var icon: String? = nil
    /// Tint used by the picker's quick pills.
    var activeColor: Color = Theme.blue
    /// See `TaskInspectorFieldRow.reservesIconSlot`.
    var reservesIconSlot: Bool = true
    /// Where the date panel opens relative to this row. The default suits a host wider than the
    /// panel; the task inspector is not one and passes `.besideInspector` (T-1480).
    var childPlacement: TaskInspectorChildPopoverPlacement = .belowRow
    @Binding var isOn: Bool
    @Binding var date: Date

    @State private var showPicker = false
    @State private var viewMonth: Date = Calendar.current.startOfDay(for: Date())

    private let cal = Calendar.current

    private var displayValue: String {
        guard isOn else { return "Set" }
        return DateFormatters.relativeDate(from: DateFormatters.dateKey(from: date))
    }

    var body: some View {
        TaskInspectorFieldButtonRow(
            label: label,
            icon: icon,
            // The glyph reuses the field's own accent rather than taking a second parameter —
            // "Do is blue, Due is red" is one fact, and two knobs could disagree.
            iconColor: activeColor,
            reservesIconSlot: reservesIconSlot,
            valueText: displayValue,
            isSet: isOn
        ) {
            showPicker.toggle()
        }
        .accessibilityIdentifier(CadenceAccessibilityIdentifiers.inspectorPanelControl(label))
        .popover(isPresented: $showPicker, arrowEdge: childPlacement.arrowEdge) {
            pickerPopover
        }
        .onAppear {
            var comps = cal.dateComponents([.year, .month], from: isOn ? date : Date())
            comps.day = 1
            viewMonth = cal.date(from: comps) ?? Date()
        }
    }

    @ViewBuilder
    private var pickerPopover: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                quickPill("Today", offset: 0)
                quickPill("Tomorrow", offset: 1)
                quickPill("This Weekend", weekend: true)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider().background(Theme.borderSubtle)

            MonthCalendarPanel(
                selection: Binding(
                    get: { date },
                    set: {
                        date = $0
                        isOn = true
                        showPicker = false
                    }
                ),
                viewMonth: $viewMonth,
                isOpen: $showPicker
            )

            if isOn {
                Divider().background(Theme.borderSubtle)

                Button {
                    isOn = false
                    showPicker = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Clear date")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Theme.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.cadencePlain)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
        }
        .background(Theme.surfaceElevated)
    }

    @ViewBuilder
    private func quickPill(_ label: String, offset: Int = 0, weekend: Bool = false) -> some View {
        let target: Date = {
            let today = cal.startOfDay(for: Date())
            if weekend {
                let todayWeekday = cal.component(.weekday, from: today)
                if todayWeekday == 7 || todayWeekday == 1 { return today }
                let daysUntilSaturday = (7 - todayWeekday + 7) % 7
                return cal.date(byAdding: .day, value: daysUntilSaturday, to: today) ?? today
            }
            return cal.date(byAdding: .day, value: offset, to: today) ?? today
        }()
        let isSelected = isOn && cal.isDate(date, inSameDayAs: target)

        Button {
            date = target
            isOn = true
            showPicker = false
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? Theme.onColor(for: activeColor) : Theme.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? activeColor : Theme.surface)
                .clipShape(Capsule())
        }
        .buttonStyle(.cadencePlain)
        .modifier(InspectorPickerHover(cornerRadius: 999))
    }
}

/// Group heading + free-form (non-recessed) content, e.g. the Actions row.
struct TaskInspectorSectionGroup<Content: View>: View {
    let title: String
    var trailing: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TaskInspectorGroupLabel(title: title, trailing: trailing)
            content
        }
    }
}

/// The inspector's single hover layer: one neutral wash, one radius, no border.
///
/// It fills with the same `TaskHoverVisuals` raise the task rows elsewhere in the app use, so a
/// hovered inspector row reads as "this row" rather than as an accent-tinted box drawn inside the
/// well's box. Anything that needs a hover here goes through this modifier — never a second
/// `.background()` at a call site.
struct InspectorPickerHover: ViewModifier {
    var cornerRadius: CGFloat = 6
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(TaskHoverVisuals.hoverFill(isHovered: isHovered))
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onHover { isHovered = $0 }
    }
}

/// Estimate as a compact chip for the inspector's title row.
///
/// It used to be a field row inside the SCHEDULE well. An estimate is a property of the task the
/// way its priority is, not a date you pick, so it now sits beside the title with the priority
/// tile — the two things you set while naming the task. Same roller popover either way.
struct TaskInspectorEstimateChip: View {
    @Binding var value: Int
    /// The host's flag for the roller — **the chip does not present it, and that is T-1722.**
    ///
    /// It used to, off its own bounds, and its own bounds are the wrong anchor: the chip sits at
    /// one end of the inspector's content column and does not span it, so one of the two ends a
    /// panel can leave by opens back across the inspector's rows — which is the end the running
    /// app picked. The title row *does* span the column, so `TaskDetailHeaderSection` presents the
    /// roller from there and this stays a button.
    @Binding var isPickerPresented: Bool

    private var isSet: Bool { value > 0 }

    /// The drawn figure and the announced one, from one call — the chip must not be able to say
    /// one duration and show another.
    private var estimateText: String {
        CadenceTaskPresentationSupport.estimateLabel(minutes: value)
    }

    var body: some View {
        Button { isPickerPresented.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.system(size: 10, weight: .semibold))
                    // Purple is the app's planned-time colour, as it was on the old row's glyph.
                    .foregroundStyle(isSet ? Theme.purple : Theme.dim)
                Text(isSet ? estimateText : "Est")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSet ? Theme.text : Theme.dim)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 28)
            .background(Theme.surfaceElevated)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusControlCompact)
                    .strokeBorder(Theme.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact))
            .contentShape(Rectangle())
        }
        .buttonStyle(.cadencePlain)
        // The title beside it is an editable field: without this the chip is treated as flexible
        // and a long title squeezes it down to its glyph.
        .fixedSize()
        // Buttons take key focus under Full Keyboard Access; leaving the chip out of the focus
        // ring means clicking it cannot pull the caret out of a title being typed.
        .focusable(false)
        .accessibilityIdentifier(
            CadenceAccessibilityIdentifiers.inspectorPanelControl(CadenceTaskControlAccessibility.estimate)
        )
        .accessibilityLabel(CadenceTaskControlAccessibility.estimate)
        .accessibilityValue(isSet ? estimateText : "None")
        .help("Estimate")
    }
}

/// The macOS spelling of the app's one estimate roller.
///
/// The roller itself moved to `Shared/Components/EstimatePickerControl.swift` when iPad and iPhone
/// adopted it: there is a single implementation now, and this name only survives so the macOS call
/// sites that predate the move keep reading the way they did.
typealias TaskInspectorEstimateRollerPopover = EstimatePickerPopoverContent


#endif
