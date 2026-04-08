#if os(macOS)
import SwiftUI

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

struct TildeSectionPickerRow: View {
    let section: String
    let isHighlighted: Bool
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: section.caseInsensitiveCompare(TaskSectionDefaults.defaultName) == .orderedSame
                      ? "square.grid.2x2" : "rectangle.split.3x1")
                    .font(.system(size: 11)).foregroundStyle(Theme.dim).frame(width: 16)
                Text(section).font(.system(size: 13)).foregroundStyle(Theme.text)
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

struct TildeSectionSearchPanel: View {
    let sections: [String]
    let selectedSectionName: String
    let onSelect: (String) -> Void
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var highlightIdx = 0
    @FocusState private var isSearchFocused: Bool

    private var filtered: [String] {
        query.isEmpty ? sections : sections.filter { $0.lowercased().hasPrefix(query.lowercased()) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Button("") { if !filtered.isEmpty { highlightIdx = min(highlightIdx + 1, filtered.count - 1) } }
                    .keyboardShortcut("=", modifiers: [.command, .shift])
                Button("") { highlightIdx = max(highlightIdx - 1, 0) }
                    .keyboardShortcut("-", modifiers: [.command, .shift])
            }
            .frame(width: 0, height: 0).clipped()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.dim)
                TextField("Search sections…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .focused($isSearchFocused)
                    .onSubmit { selectHighlighted() }
                    .onKeyPress(.upArrow) { highlightIdx = max(highlightIdx - 1, 0); return .handled }
                    .onKeyPress(.downArrow) {
                        if !filtered.isEmpty { highlightIdx = min(highlightIdx + 1, filtered.count - 1) }
                        return .handled
                    }
                    .onKeyPress(.tab) { onDismiss(); return .handled }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.dim.opacity(0.5))
                    }.buttonStyle(.cadencePlain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            Divider().background(Theme.borderSubtle)

            VStack(spacing: 2) {
                ForEach(filtered, id: \.self) { section in
                    TildeSectionPickerRow(
                        section: section,
                        isHighlighted: filtered.firstIndex(of: section) == highlightIdx,
                        isSelected: selectedSectionName.caseInsensitiveCompare(section) == .orderedSame,
                        action: { onSelect(section) }
                    )
                }
            }
            .padding(.vertical, 6)
        }
        .frame(minWidth: 200)
        .background(Theme.surfaceElevated)
        .onAppear { DispatchQueue.main.async { isSearchFocused = true } }
        .onChange(of: query) { _, _ in highlightIdx = 0 }
    }

    private func selectHighlighted() {
        guard !filtered.isEmpty else { return }
        onSelect(filtered[min(highlightIdx, filtered.count - 1)])
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
        if isDoDate && cal.isDateInToday(date) { return .yellow }
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
                        .foregroundStyle(isOn ? effectiveIconColor : Theme.dim)
                    ZStack(alignment: .leading) {
                        Text(label).font(.system(size: 12)).opacity(0)
                        Text("Tomorrow").font(.system(size: 12, weight: .semibold)).opacity(0)
                        if isOn {
                            Text(displayLabel)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(isDoDate && cal.isDateInToday(date) ? .yellow : activeColor)
                        } else {
                            Text(label)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.dim)
                        }
                    }
                    .fixedSize()
                }
                .padding(.leading, 8)
                .padding(.trailing, 8)
                .padding(.vertical, 5)
                .background(
                    isOn
                        ? activeColor.opacity(isDoDate && cal.isDateInToday(date) ? 0.0 : 0.1)
                        : (isHovered ? activeColor.opacity(0.06) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(isOn ? activeColor.opacity(0.25) : Theme.borderSubtle.opacity(isHovered ? 0.8 : 0), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 7))
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
                .foregroundStyle(isSelected ? .white : Theme.muted)
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
