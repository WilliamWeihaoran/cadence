#if os(iOS)
import SwiftUI

/// A header title that **is** the date control: a bold label, a `chevron.down`, blue when you are
/// away from now, and a popover whose first row is the way back.
///
/// This is one view because it shipped twice. `2929867` built it for the mobile Notes header, where
/// the title had been the constant word "Notes" and there was no way to reach yesterday's daily
/// note; `ecfc9a3` built it again for the calendar, where deleting the `‹ ➤ ›` cluster from all four
/// surfaces meant the title had to carry jump-to-today before the cluster could go. The second one
/// says so in its own doc comment — the two were "the same shape" down to the 280pt popover and its
/// 34pt Today row, and stayed apart only because generalising meant editing the other agent's file.
/// `AGENTS.md`: one shared component over near-copies.
///
/// **What the two callers actually differ by**, and therefore what is parameterised:
///
/// - **The label and "am I at now".** Notes reads a tab and a `"yyyy-MM-dd"` key
///   (`CadenceNoteDateNavigation`); the calendar reads a `Date` in a unit
///   (`CadenceCalendarDateTitleSupport`). Both arithmetics already live in `Shared/` and are tested
///   there, so this view takes their answers rather than a way to compute them.
/// - **What a picked day means.** Month's bound value is a *week row start*, not a day, so it needs
///   `pickerDate` (what the popover opens on) and `anchor` (what a pick writes back) to be different
///   functions. Every other surface binds the day it is showing, which is what the defaults are.
/// - **Type size.** Two presets, `.page` and `.inline` — see `iOSDateJumpTitleMetrics`. This is the
///   one place the two surfaces were allowed to keep a difference, because it is a difference in the
///   room they have rather than in the control.
///
/// The binding is a `Date` even though Notes stores a `"yyyy-MM-dd"` string: one of the two had to
/// convert, and a header owning a formatter is worse than a call site owning a two-line `Binding`.
/// `MonthCalendarPanel` speaks `Date` regardless.
struct iOSDateJumpTitle: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// What the surface is showing, in whatever unit that surface reads — a day for Notes and the
    /// timed grids, a week row for Month. `anchor` is what reconciles the two.
    @Binding var date: Date
    /// Already formatted. See the note above on why this is a string rather than a closure.
    let label: String
    /// Drives the blue: without it a week in March is indistinguishable at a glance from this one,
    /// and on Notes you can write today's entry into a week-old page.
    let isAtNow: Bool
    var metrics: iOSDateJumpTitleMetrics = .page
    /// The popover's first row. "Today" everywhere except Notes' Weekly tab, where the thing you
    /// are returning to is a week.
    var nowTitle: String = "Today"
    /// Defaults to `"\(label). Choose a date"`.
    var accessibilityLabel: String? = nil
    /// The day the popover opens on, given the bound value. Not the identity on Month: the bound
    /// value there is a layout position the user never chose, and opening the picker on it would
    /// light up July 27 under a grid reading "August".
    var pickerDate: (Date) -> Date = { Calendar.current.startOfDay(for: $0) }
    /// The inverse — what a picked day means for the bound value. Picking any day of August in
    /// Month scrolls the grid to August's first row, not to the week that day falls in.
    var anchor: (Date) -> Date = { Calendar.current.startOfDay(for: $0) }

    @State private var isOpen = false
    @State private var viewMonth = Date()
    /// The day the popover's calendar is on, held separately from `date` because on Month the two
    /// are not the same kind of thing.
    @State private var pickerSelection = Date()

    private var fontSize: CGFloat {
        horizontalSizeClass == .regular ? metrics.regularFontSize : metrics.compactFontSize
    }

    var body: some View {
        Button {
            syncPicker()
            isOpen = true
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundStyle(isAtNow ? Theme.text : Theme.blue)
                    .lineLimit(1)
                    .minimumScaleFactor(metrics.minimumScaleFactor)

                Image(systemName: "chevron.down")
                    .font(.system(size: metrics.chevronSize, weight: .semibold))
                    .foregroundStyle(isAtNow ? Theme.dim : Theme.blue)
            }
            // Deliberately **not** `.fixedSize()`: on Notes the tab strip holds the higher layout
            // priority, so if the row runs out of room the date is what gives ground. `fixedSize`
            // here would make it refuse, and an `HStack` does not shrink a view that refuses — it
            // overflows and clips.
            .contentShape(Rectangle())
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel(accessibilityLabel ?? "\(label). Choose a date")
        // `.top`, not the `.bottom` every other `CadenceDatePicker` call site uses. The arrow edge
        // names the popover's *own* edge, so `.bottom` puts the panel above its anchor — fine for a
        // control in the middle of a form, wrong for one in the top chrome, where it opened off the
        // top of the screen with only its arrow visible.
        .popover(isPresented: $isOpen, arrowEdge: .top) {
            iOSDateJumpPopover(
                selection: pickedDate,
                viewMonth: $viewMonth,
                isOpen: $isOpen,
                isAtNow: isAtNow,
                nowTitle: nowTitle,
                onNow: { date = anchor(Date()) }
            )
            // Same reason `CadenceDatePicker` sets it: compact width would otherwise promote a
            // 256×294 calendar to a full-height sheet.
            .presentationCompactAdaptation(.popover)
        }
    }

    /// A binding rather than `onChange(of: pickerSelection)`, so only a **pick** writes back.
    /// Seeding the picker when the popover opens would otherwise look like one: on Month the seed
    /// round-trips through `displayedMonth` → `topRow`, so merely opening the panel mid-month would
    /// snap the grid to that month's first row without the user touching anything.
    private var pickedDate: Binding<Date> {
        Binding(
            get: { pickerSelection },
            set: { newValue in
                pickerSelection = newValue
                date = anchor(newValue)
            }
        )
    }

    private func syncPicker() {
        let seed = pickerDate(date)
        pickerSelection = seed
        var components = Calendar.current.dateComponents([.year, .month], from: seed)
        components.day = 1
        viewMonth = Calendar.current.date(from: components) ?? Date()
    }
}

/// Type size for `iOSDateJumpTitle`. Two presets, because the control appears in two kinds of row
/// and the difference between them is room rather than style.
struct iOSDateJumpTitleMetrics {
    var regularFontSize: CGFloat
    var compactFontSize: CGFloat
    var chevronSize: CGFloat
    /// `1` means no scaling — the label truncates, or gives ground to a neighbour with higher
    /// layout priority.
    var minimumScaleFactor: CGFloat

    /// A surface's own title, with the row largely to itself: the four calendar surfaces. It scales
    /// rather than truncating, because "August 2026" losing its year names no month.
    static let page = iOSDateJumpTitleMetrics(
        regularFontSize: 21,
        compactFontSize: 18,
        chevronSize: 10,
        minimumScaleFactor: 0.72
    )

    /// A title sharing its row with other controls: the Notes header, where 390pt holds the date,
    /// four tabs and sometimes a back control.
    ///
    /// 15 on the phone, where the widest label this can hold is a week range — `Aug 10–16`, about
    /// 88pt at 17pt bold against roughly 84pt of room once the tabs have taken theirs. At 17 it
    /// truncated to "Aug 1…", which names no week at all.
    static let inline = iOSDateJumpTitleMetrics(
        regularFontSize: 17,
        compactFontSize: 15,
        chevronSize: 9,
        minimumScaleFactor: 1
    )
}

/// The calendar behind the title, plus the one shortcut that matters.
///
/// Deliberately *not* `CadenceQuickDatePopover`, whose pills are Today / Tomorrow / This Weekend —
/// tomorrow's daily note is a thing you can reach but rarely want, "this weekend" means nothing to
/// a weekly note, and on the calendar the middle of the deleted `‹ ➤ ›` cluster was `location.fill`,
/// which is one destination. A single way back to now is what a surface that scrolls arbitrarily far
/// needs and what a bare calendar makes you hunt for.
private struct iOSDateJumpPopover: View {
    @Binding var selection: Date
    @Binding var viewMonth: Date
    @Binding var isOpen: Bool
    let isAtNow: Bool
    let nowTitle: String
    let onNow: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if !isAtNow {
                Button {
                    onNow()
                    isOpen = false
                } label: {
                    Text(nowTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.blue)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.iosPressable)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 6)

                Divider().background(Theme.borderSubtle)
            }

            // `inlineStyle` because this popover already owns its width and its background. Without
            // it the panel pins itself to 256pt and paints its own `surfaceElevated` inside a
            // container the popover had sized differently — the weekday row drew above the panel's
            // rounded top and the next month's heading spilled past its bottom corner.
            MonthCalendarPanel(selection: $selection, viewMonth: $viewMonth, isOpen: $isOpen, inlineStyle: true)
                // The panel leads with its weekday row and no inset of its own, which sat flush
                // against the popover's rounded top edge.
                .padding(.top, 10)
        }
        .frame(width: 280)
        .background(Theme.surfaceElevated)
    }
}
#endif
