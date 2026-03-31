#if os(macOS)
import SwiftUI
import EventKit

// MARK: - Popover body

/// The list of calendars to embed inside a .popover().
/// Selecting a row writes to selectedID and can optionally close the popover.
struct CadenceCalendarPickerList: View {
    let calendars: [EKCalendar]
    @Binding var selectedID: String
    var allowNone: Bool = true
    /// Called after the user taps a row so the parent can dismiss the popover.
    var onPick: (() -> Void)? = nil

    /// Calendars grouped by their account/source, each group sorted by name.
    private var groups: [(source: String, cals: [EKCalendar])] {
        var dict: [String: [EKCalendar]] = [:]
        for cal in calendars {
            let src = cal.source?.title ?? "Other"
            dict[src, default: []].append(cal)
        }
        return dict
            .map { (source: $0.key, cals: $0.value.sorted { $0.title < $1.title }) }
            .sorted { $0.source < $1.source }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if allowNone {
                row(id: "", label: "None", color: nil)
                Divider().background(Theme.borderSubtle).padding(.vertical, 2)
            }
            ForEach(groups, id: \.source) { group in
                Text(group.source.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .kerning(0.6)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(group.cals, id: \.calendarIdentifier) { cal in
                    row(
                        id: cal.calendarIdentifier,
                        label: cal.title,
                        color: Color(cgColor: cal.cgColor)
                    )
                }
            }
        }
        .padding(.vertical, 4)
        .frame(minWidth: 210)
    }

    @ViewBuilder
    private func row(id: String, label: String, color: Color?) -> some View {
        let isSelected = selectedID == id
        Button {
            selectedID = id
            onPick?()
        } label: {
            HStack(spacing: 10) {
                Group {
                    if let color {
                        Circle().fill(color)
                    } else {
                        Circle().strokeBorder(Theme.dim.opacity(0.45), lineWidth: 1.5)
                    }
                }
                .frame(width: 10, height: 10)

                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                    .lineLimit(1)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.blue)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(minHeight: 30)
            .background(isSelected ? Theme.blue.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.cadencePlain)
        .modifier(CalendarPickerRowHover())
        .padding(.horizontal, 4)
    }
}

// MARK: - Button + popover combo

/// Drop-in replacement for any calendar picker in the app.
/// Shows the selected calendar's real iCal color and name; opens a styled popover on tap.
struct CadenceCalendarPickerButton: View {
    let calendars: [EKCalendar]
    @Binding var selectedID: String
    var allowNone: Bool = true
    /// Pass `.compact` for tighter padding (e.g. inside table rows).
    var style: CadenceCalendarPickerStyle = .standard

    @State private var showPicker = false

    private var selected: EKCalendar? {
        calendars.first { $0.calendarIdentifier == selectedID }
    }

    var body: some View {
        Button { showPicker.toggle() } label: {
            HStack(spacing: style.dotLabelSpacing) {
                // Color dot
                Group {
                    if let cal = selected {
                        Circle().fill(Color(cgColor: cal.cgColor))
                    } else {
                        Circle().strokeBorder(Theme.dim.opacity(0.45), lineWidth: 1.5)
                    }
                }
                .frame(width: style.dotSize, height: style.dotSize)

                // Label
                Text(selected?.title ?? "No calendar")
                    .font(.system(size: style.fontSize))
                    .foregroundStyle(selected != nil ? Theme.text : Theme.dim)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: style.chevronSize, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, style.hPad)
            .padding(.vertical, style.vPad)
            .frame(minHeight: style == .compact ? 28 : 32)
            .contentShape(Rectangle())
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: style.cornerRadius).stroke(Theme.borderSubtle))
        }
        .buttonStyle(.cadencePlain)
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            ScrollView {
                CadenceCalendarPickerList(
                    calendars: calendars,
                    selectedID: $selectedID,
                    allowNone: allowNone,
                    onPick: { showPicker = false }
                )
            }
            .frame(maxHeight: 320)
            .background(Theme.surface)
        }
    }
}

// MARK: - Style tokens

enum CadenceCalendarPickerStyle {
    case standard   // EditListSheet, standalone usage
    case compact    // CalendarLinkRow, QuickCreate popovers

    var fontSize: CGFloat     { self == .compact ? 12 : 13 }
    var dotSize: CGFloat      { self == .compact ? 9 : 10 }
    var dotLabelSpacing: CGFloat { self == .compact ? 6 : 8 }
    var chevronSize: CGFloat  { self == .compact ? 8 : 9 }
    var hPad: CGFloat         { self == .compact ? 9 : 10 }
    var vPad: CGFloat         { self == .compact ? 5 : 9 }
    var cornerRadius: CGFloat { self == .compact ? 7 : 8 }
}

private struct CalendarPickerRowHover: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Theme.blue.opacity(0.06) : Color.clear)
            )
            .onHover { isHovered = $0 }
    }
}
#endif
