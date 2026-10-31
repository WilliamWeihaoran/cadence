#if os(macOS)
import SwiftUI

struct CreateTaskPanelSurface: View {
    let seed: TaskCreationSeed
    let dismissAction: (() -> Void)?
    let successAction: (() -> Void)?

    init(
        seed: TaskCreationSeed,
        dismissAction: (() -> Void)? = nil,
        successAction: (() -> Void)? = nil
    ) {
        self.seed = seed
        self.dismissAction = dismissAction
        self.successAction = successAction
    }

    var body: some View {
        CreateTaskSheet(
            seed: seed,
            dismissAction: dismissAction,
            successAction: successAction
        )
            .ignoresSafeArea()
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.borderSubtle.opacity(0.95), lineWidth: 1)
            }
            .shadow(color: Theme.overlayCardShadow, radius: 34, x: 0, y: 18)
            .shadow(color: Theme.blue.opacity(0.08), radius: 18, x: 0, y: 0)
    }
}

/// The one macOS priority control: the create sheet's flag chip and the calendar quick-create
/// inspector's value row are the same popover behind two triggers.
///
/// **T-1433.** `CreateTaskSheet` owned this as a private `priorityMarkButton` plus its own
/// `@State showPriorityPicker`, and the quick-create popover needed a priority field. Re-typing
/// the list beside a second piece of presentation state is the drift [[T-1412]] spent a ticket
/// undoing for the tag chip, so the sheet's control moved here and grew a second *trigger* rather
/// than a second implementation. The menu below — mark, name, checkmark, hover — is the sheet's,
/// unchanged.
struct TaskPriorityPicker: View {
    /// What the button looks like. The menu behind it is the same either way.
    enum Trigger {
        /// A bare flag glyph, sized for the create sheet's chip row beside the title field.
        case markGlyph
        /// The priority's name, for a labelled field row that already draws its own glyph.
        case value
    }

    @Binding var selection: TaskPriority
    var trigger: Trigger = .markGlyph

    @State private var isOpen = false

    var body: some View {
        triggerButton
            .popover(isPresented: $isOpen, arrowEdge: .top) { choices }
    }

    /// **The value trigger is `CadenceChoiceValueButton`, and its words are
    /// `CadenceTaskComposerSupport.priorityValueLabel`.** Both are already decided elsewhere: the
    /// button is the trigger `CadenceStartTimeFieldRow` uses one row above this one, and the
    /// helper's own note records why a labelled priority field spells the word rather than showing
    /// the `!!` mark — *"the tile is already captioned Priority, so the line under it answers"*.
    /// The iOS composer's priority tile reads the same helper, so the two composers cannot come to
    /// disagree about what "no priority" is called.
    @ViewBuilder
    private var triggerButton: some View {
        switch trigger {
        case .markGlyph:
            Button { isOpen.toggle() } label: {
                Image(systemName: "flag.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(valueColor)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Priority")
            }
            .buttonStyle(.cadencePlain)
        case .value:
            CadenceChoiceValueButton(
                title: CadenceTaskComposerSupport.priorityValueLabel(selection),
                color: valueColor
            ) {
                isOpen = true
            }
        }
    }

    private var valueColor: Color {
        selection == .none ? Theme.dim : Theme.priorityColor(selection)
    }

    private var choices: some View {
        TaskPriorityChoiceList(selection: selection) { p in
            selection = p
            isOpen = false
        }
    }
}

/// **The one macOS priority menu** -- every `TaskPriority` with its mark, its name, a checkmark and
/// a blue fill on the current one, and `CreateTaskPickerHover`'s plate under the pointer.
///
/// **[[T-9292]].** `TaskPriorityPicker` drew these rows inline, and the note embed card's Priority
/// field drew KanbanPriorityPickerPopover, a line-for-line copy that had lost the selected-row
/// fill, the clip and the hover plate -- so the same field lit under the pointer in the New Task
/// sheet and stayed dark on a note's task card. The rows live here now and both triggers present
/// this one declaration; `onPick` is the trigger's business (a binding plus a close for the
/// picker, a guarded commit for the embed card), the rows are not.
struct TaskPriorityChoiceList: View {
    let selection: TaskPriority
    let onPick: (TaskPriority) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(TaskPriority.allCases, id: \.self) { p in
                Button {
                    onPick(p)
                } label: {
                    HStack(spacing: 8) {
                        Text(TaskTitleSupport.priorityMark(for: p))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(p == .none ? Theme.dim : Theme.priorityColor(p))
                            .frame(width: 24, alignment: .leading)
                        Text(p.label).font(.system(size: 13)).foregroundStyle(Theme.text)
                        Spacer()
                        if selection == p {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.blue)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .background(selection == p ? Theme.blue.opacity(0.08) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.cadencePlain)
                .modifier(CreateTaskPickerHover())
            }
        }
        .padding(.vertical, 6).frame(minWidth: 140).background(Theme.surfaceElevated)
    }
}

struct TildeContainerPickerRow: View {
    let icon: String
    let name: String
    let color: Color
    let isHighlighted: Bool
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(color).frame(width: 16)
                Text(name).font(.system(size: 13)).foregroundStyle(Theme.text)
                Spacer()
                if isHighlighted {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.blue)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.cadencePlain)
        .onHover { isHovered = $0 }
    }

    private var rowBackground: Color {
        if isHighlighted { return Theme.blue.opacity(0.08) }
        if isHovered { return Theme.blue.opacity(0.06) }
        return .clear
    }
}

/// The month a date chip's grid opens on: the chip's own date when it has one, otherwise today's.
///
/// **T-8105.** `TaskDateChip` and the inspector's `TaskInspectorDateControl` each computed this in
/// `onAppear` only, so once the date moved to another month the grid kept opening on the old one
/// with no day highlighted. Both now ask this on appear *and* every time the panel opens.
enum TaskDateChipMonthSupport {
    static func viewMonth(isOn: Bool, date: Date, now: Date = Date(), calendar: Calendar = .current) -> Date {
        monthStart(for: isOn ? date : now, calendar: calendar)
    }
}

struct TaskDateChip: View {
    let label: String
    let icon: String
    var activeColor: Color = Theme.blue
    @Binding var isOn: Bool
    @Binding var date: Date
    @Binding var showPicker: Bool

    @State private var viewMonth: Date = Calendar.current.startOfDay(for: Date())
    @State private var isHovered = false

    private let cal = Calendar.current

    private var isDoDate: Bool { icon == "calendar" }

    private var effectiveIcon: String {
        guard isOn, isDoDate else { return icon }
        return cal.isDateInToday(date) ? "star.fill" : icon
    }

    private var effectiveIconColor: Color {
        guard isOn else { return Theme.dim }
        if isDoDate && cal.isDateInToday(date) { return Theme.amber }
        return activeColor
    }

    private var displayLabel: String {
        guard isOn else { return label }
        return DateFormatters.relativeDate(from: DateFormatters.dateKey(from: date))
    }

    var body: some View {
        HStack(spacing: 0) {
            Button { showPicker.toggle() } label: {
                HStack(spacing: 5) {
                    Image(systemName: effectiveIcon)
                        .font(.system(size: 11))
                        .foregroundStyle(isOn ? effectiveIconColor : (isHovered ? Theme.muted : Theme.dim))
                    if isOn {
                        Text(displayLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isDoDate && cal.isDateInToday(date) ? Theme.amber : activeColor)
                            .fixedSize()
                    }
                }
                .padding(.leading, 8)
                .padding(.trailing, 8)
                .padding(.vertical, 5)
                .background(
                    isOn
                        ? activeColor.opacity(isDoDate && cal.isDateInToday(date) ? 0.0 : 0.1)
                        : Color.clear
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusControlCompact)
                        .strokeBorder(isOn ? activeColor.opacity(0.25) : Theme.borderSubtle, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact))
            }
            .buttonStyle(.cadencePlain)
            .onHover { isHovered = $0 }
            .popover(isPresented: $showPicker, arrowEdge: .top) { pickerPopover }
        }
        .onAppear { viewMonth = TaskDateChipMonthSupport.viewMonth(isOn: isOn, date: date) }
        // T-8105: the pills, Cmd+T / Cmd+D and the Cmd+Shift+= nudge all move `date` without the
        // grid, so re-anchor every time the panel opens rather than only when the chip appeared.
        .onChange(of: showPicker) {
            if showPicker { viewMonth = TaskDateChipMonthSupport.viewMonth(isOn: isOn, date: date) }
        }
    }

    /// The shared quick-date popover, tinted with this chip's accent ([[T-9212]]). Picking a pill
    /// or a day turns the chip on; Clear turns it off. An unset chip's `date` is only where the
    /// grid opens, so nothing reads as picked and there is nothing to clear ([[T-9211]]).
    private var pickerPopover: some View {
        CadenceQuickDatePopover(
            selection: Binding(get: { date }, set: { date = $0; isOn = true }),
            viewMonth: $viewMonth,
            isOpen: $showPicker,
            showsClear: isOn,
            onClear: { isOn = false },
            hasSelection: isOn,
            tint: activeColor
        )
    }
}

struct CreateTaskPickerHover: ViewModifier {
    var cornerRadius: CGFloat = 6
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isHovered ? Theme.blue.opacity(0.06) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onHover { isHovered = $0 }
    }
}
#endif
