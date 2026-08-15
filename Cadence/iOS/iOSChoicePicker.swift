#if os(iOS)
import SwiftUI

/// Shared custom replacements for native SwiftUI `Picker`/`.pickerStyle(.segmented)` controls on
/// iOS, matching the checkmarked-popover-list language already used by macOS's
/// `TaskPriorityPickerPopover` / `ContainerPickerBadge`.

struct iOSChoiceRow<T: Hashable>: Identifiable {
    let id: AnyHashable
    let value: T
    let title: String
    /// What this option *means*, where the option's name does not already say it.
    ///
    /// This is where a setting's explanation belongs: on the choice it explains, read at the
    /// moment you are choosing — not as a permanent two-line paragraph under the setting's own
    /// label, which is where the iOS settings screen used to keep them and what made two settings
    /// fill a phone. Leave it `nil` whenever the title is self-explanatory; a subtitle that
    /// restates the title is the thing being removed.
    let subtitle: String?
    let systemImage: String?
    let color: Color

    init(
        value: T,
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        color: Color,
        id: AnyHashable? = nil
    ) {
        self.value = value
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.color = color
        self.id = id ?? AnyHashable(title)
    }
}

/// Popover content: a checkmarked, tap-to-select list. Present via `.popover` from a trigger
/// (typically `iOSChoiceValueButton`), with `.presentationCompactAdaptation(.popover)` so it
/// stays a small anchored overlay on iPhone instead of expanding into a sheet.
struct iOSChoicePopoverList<T: Hashable>: View {
    let rows: [iOSChoiceRow<T>]
    @Binding var selection: T
    @Binding var isPresented: Bool
    var width: CGFloat = 230

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(rows) { row in
                    Button {
                        selection = row.value
                        isPresented = false
                    } label: {
                        HStack(spacing: 8) {
                            if let systemImage = row.systemImage {
                                Image(systemName: systemImage)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(row.color)
                                    .frame(width: 18)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(row.value == selection ? Theme.text : Theme.muted)
                                    .lineLimit(1)
                                if let subtitle = row.subtitle {
                                    Text(subtitle)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.dim)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer(minLength: 8)
                            if row.value == selection {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.blue)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .background(row.value == selection ? Theme.blue.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
        }
        .frame(width: width, height: min(CGFloat(rows.count) * rowHeight + 16, 380))
        .background(Theme.surfaceElevated)
        .presentationCompactAdaptation(.popover)
    }

    /// Rows are 44pt tall minimum — they are the thing being tapped — and taller again when they
    /// carry an explanation. Sizing the sheet off a flat 42 left the last row half-scrolled.
    private var rowHeight: CGFloat {
        rows.contains { $0.subtitle != nil } ? 62 : 46
    }
}

/// Trigger button showing the current value; opens an `iOSChoicePopoverList`.
struct iOSChoiceValueButton: View {
    let title: String
    var color: Color = Theme.text
    /// Opt-in touch floor. The label alone is about 18pt tall, so where this button is the *only*
    /// thing tappable in its row — every row on the settings screen — the row's own 44pt has to be
    /// handed to the button or most of it is dead space. Applied inside the label, because a
    /// `contentShape` outside a `Button` does not widen the button's own hit region.
    ///
    /// Defaults to 0 so the rows that already pair this with a second control keep their layout.
    var minHeight: CGFloat = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(color.opacity(0.55))
            }
            .frame(minHeight: minHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Custom segmented control replacing `.pickerStyle(.segmented)`.
struct iOSSegmentedChoice<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selection: T
    var color: Color = Theme.blue

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selection == option.value ? Theme.onColor : Theme.dim)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selection == option.value ? color : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Container (Inbox / Area / Project) choice, grouped like macOS's `ContainerPickerBadge`.
struct iOSContainerChoicePopover: View {
    let activeAreas: [Area]
    let activeProjects: [Project]
    @Binding var selection: String
    @Binding var isPresented: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                choiceRow(title: "Inbox", tag: "inbox", systemImage: "tray.full.fill", color: Theme.blue)

                if !activeAreas.isEmpty {
                    groupLabel("Areas")
                    ForEach(activeAreas) { area in
                        choiceRow(
                            title: area.name.isEmpty ? "Untitled Area" : area.name,
                            tag: "area:\(area.id.uuidString)",
                            systemImage: "tray.full.fill",
                            color: Color(hex: area.colorHex)
                        )
                    }
                }

                if !activeProjects.isEmpty {
                    groupLabel("Projects")
                    ForEach(activeProjects) { project in
                        choiceRow(
                            title: project.name.isEmpty ? "Untitled Project" : project.name,
                            tag: "project:\(project.id.uuidString)",
                            systemImage: "checklist",
                            color: Color(hex: project.colorHex)
                        )
                    }
                }
            }
            .padding(10)
        }
        .frame(width: 250, height: 320)
        .background(Theme.surfaceElevated)
        .presentationCompactAdaptation(.popover)
    }

    private func groupLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Theme.dim)
            .padding(.horizontal, 2)
    }

    private func choiceRow(title: String, tag: String, systemImage: String, color: Color) -> some View {
        Button {
            selection = tag
            isPresented = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tag == selection ? Theme.text : Theme.muted)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if tag == selection {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.blue)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tag == selection ? Theme.blue.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif
