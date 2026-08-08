#if os(iOS)
import SwiftUI

struct iOSTrackingEditorShell<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let title: String
    let canSave: Bool
    let tint: Color
    let save: () -> Void
    @ViewBuilder let content: Content

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                editorContent
                    .padding(isRegularWidth ? 20 : 18)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .tint(tint)
        }
    }

    @ViewBuilder
    private var editorContent: some View {
        if isRegularWidth {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 16, alignment: .top),
                    GridItem(.flexible(), spacing: 16, alignment: .top)
                ],
                alignment: .leading,
                spacing: 16
            ) {
                content
            }
            .frame(maxWidth: 980, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .top)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
        }
    }
}

struct iOSTrackingTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var axis: Axis = .horizontal

    var body: some View {
        iOSTrackingPickerSection(title: title) {
            field
                .textInputAutocapitalization(.sentences)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Theme.surfaceElevated.opacity(0.62))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
        }
    }

    @ViewBuilder
    private var field: some View {
        if axis == .vertical {
            TextField(placeholder, text: $text, axis: axis)
                .lineLimit(3...6)
        } else {
            TextField(placeholder, text: $text, axis: axis)
                .lineLimit(1)
        }
    }
}

struct iOSTrackingPickerSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.dim)
                .textCase(.uppercase)
                .kerning(0.8)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusCard, shadowRadius: 12, shadowY: 5)
        }
    }
}

struct iOSTrackingDateRangeSection: View {
    @Binding var startDate: Date
    @Binding var endDate: Date

    var body: some View {
        iOSTrackingPickerSection(title: "Dates") {
            HStack {
                Text("Start")
                Spacer()
                CadenceDatePicker(selection: $startDate)
            }
            Divider().background(Theme.borderSubtle.opacity(0.55)).padding(.vertical, 8)
            HStack {
                Text("End")
                Spacer()
                CadenceDatePicker(selection: $endDate)
            }
            .onChange(of: endDate) { _, newValue in
                if newValue < startDate {
                    endDate = startDate
                }
            }
        }
        .onChange(of: startDate) { _, newValue in
            if endDate < newValue {
                endDate = newValue
            }
        }
    }
}

struct iOSHabitFrequencyEditor: View {
    let frequencyType: HabitFrequency
    @Binding var selectedDays: Set<Int>
    @Binding var timesPerWeek: Int
    @Binding var monthlyDay: Int
    @State private var showTimesPerWeekPicker = false
    @State private var showMonthlyDayPicker = false

    private let weekdays = [
        (1, "M"), (2, "T"), (3, "W"), (4, "T"), (5, "F"), (6, "S"), (7, "S")
    ]

    var body: some View {
        switch frequencyType {
        case .daily:
            Text("Every day")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.dim)
        case .daysOfWeek:
            HStack(spacing: 7) {
                ForEach(weekdays, id: \.0) { day, label in
                    Button {
                        if selectedDays.contains(day) {
                            selectedDays.remove(day)
                        } else {
                            selectedDays.insert(day)
                        }
                    } label: {
                        Text(label)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(selectedDays.contains(day) ? Theme.text : Theme.dim)
                            .frame(width: 34, height: 34)
                            .background(selectedDays.contains(day) ? Theme.blue.opacity(0.22) : Theme.surfaceElevated)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        case .timesPerWeek:
            HStack {
                Text("Times per week")
                Spacer()
                iOSChoiceValueButton(title: "\(timesPerWeek)", color: Theme.text) {
                    showTimesPerWeekPicker = true
                }
                .popover(isPresented: $showTimesPerWeekPicker) {
                    iOSChoicePopoverList(
                        rows: (1...14).map { count in
                            iOSChoiceRow(value: count, title: "\(count)", color: Theme.blue)
                        },
                        selection: $timesPerWeek,
                        isPresented: $showTimesPerWeekPicker
                    )
                }
            }
        case .monthly:
            HStack {
                Text("Day of month")
                Spacer()
                iOSChoiceValueButton(title: "\(monthlyDay)", color: Theme.text) {
                    showMonthlyDayPicker = true
                }
                .popover(isPresented: $showMonthlyDayPicker) {
                    iOSChoicePopoverList(
                        rows: (1...31).map { day in
                            iOSChoiceRow(value: day, title: "\(day)", color: Theme.blue)
                        },
                        selection: $monthlyDay,
                        isPresented: $showMonthlyDayPicker
                    )
                }
            }
        }
    }
}

struct iOSTrackingIconGrid: View {
    @Binding var selection: String
    private let icons = ["sparkles", "star.fill", "flag.fill", "flame.fill", "book.fill", "figure.run", "heart.fill", "brain.head.profile", "paintbrush.fill", "briefcase.fill", "leaf.fill", "music.note"]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
            ForEach(icons, id: \.self) { icon in
                Button {
                    selection = icon
                } label: {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selection == icon ? Theme.text : Theme.dim)
                        .frame(height: 36)
                        .frame(maxWidth: .infinity)
                        .background(selection == icon ? Theme.blue.opacity(0.22) : Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct iOSTrackingColorGrid: View {
    @Binding var selection: String
    private let colors = ["#4a9eff", "#a78bfa", "#4ecb71", "#ffb84d", "#ff6b6b", "#38d5c7", "#f472b6", "#94a3b8"]

    var body: some View {
        HStack(spacing: 9) {
            ForEach(colors, id: \.self) { color in
                Button {
                    selection = color
                } label: {
                    Circle()
                        .fill(Color(hex: color))
                        .frame(width: 30, height: 30)
                        .overlay {
                            Circle()
                                .strokeBorder(selection == color ? Theme.text : Color.clear, lineWidth: 2)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
#endif
