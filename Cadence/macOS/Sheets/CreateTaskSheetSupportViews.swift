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
                selection: Binding(get: { date }, set: { date = $0; isOn = true; showPicker = false }),
                viewMonth: $viewMonth,
                isOpen: $showPicker
            )

            if isOn {
                Button("Clear date") { isOn = false; showPicker = false }
                    .buttonStyle(.cadencePlain)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.red)
                    .padding(.bottom, 10)
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
                .foregroundStyle(isSelected ? Theme.onColor : Theme.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Theme.blue : Theme.surface)
                .clipShape(Capsule())
        }
        .buttonStyle(.cadencePlain)
        .modifier(CreateTaskPickerHover(cornerRadius: 999))
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
