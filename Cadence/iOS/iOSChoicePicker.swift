#if os(iOS)
import SwiftUI

/// The four types that used to be declared here — `iOSChoiceRow`, `iOSFittedPopover`,
/// `iOSChoicePopoverList` and `iOSChoiceValueButton` — now live in
/// `Shared/Components/CadenceChoicePicker.swift` and are read by **both** platforms.
///
/// They were written as "shared custom replacements for native SwiftUI `Picker`/
/// `.pickerStyle(.segmented)` controls on iOS, matching the checkmarked-popover-list language
/// already used by macOS's `TaskPriorityPickerPopover` / `ContainerPickerBadge`" — a control that
/// named the desktop vocabulary it was matching while being unreachable from it. macOS Settings
/// went on drawing `Picker(.menu)` for work hours and a row of saturated filled pills for the
/// default list page (T-20). Nothing about them was iOS-specific except the compact-size popover
/// adaptation, which is now one `#if` inside `CadenceFittedPopover`.
///
/// The iOS names stay as typealiases so no call site moved. Do not re-declare a struct here.
typealias iOSChoiceRow<T: Hashable> = CadenceChoiceRow<T>
typealias iOSFittedPopover<Content: View> = CadenceFittedPopover<Content>
typealias iOSChoicePopoverList<T: Hashable> = CadenceChoicePopoverList<T>
typealias iOSChoiceValueButton = CadenceChoiceValueButton

// `iOSSegmentedChoice` used to live here as a second segmented control with its own look. It is now
// a thin layout over `iOSSegmentedPill` in `iOSDesignSystem.swift`, next to the pill group it draws.

/// Container (Inbox / Area / Project) choice, grouped like macOS's `ContainerPickerBadge`.
struct iOSContainerChoicePopover: View {
    let activeAreas: [Area]
    let activeProjects: [Project]
    @Binding var selection: String
    @Binding var isPresented: Bool

    var body: some View {
        iOSFittedPopover(width: 250, maxHeight: 340) {
            VStack(alignment: .leading, spacing: 10) {
                choiceRow(title: "Inbox", tag: "inbox", systemImage: "tray.full.fill", color: Theme.blue)

                if !activeAreas.isEmpty {
                    groupLabel("Areas")
                    ForEach(activeAreas) { area in
                        choiceRow(
                            title: area.name.isEmpty ? CadenceTitleNormalization.defaultAreaName : area.name,
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
                            title: project.name.isEmpty ? CadenceTitleNormalization.defaultProjectName : project.name,
                            tag: "project:\(project.id.uuidString)",
                            systemImage: "checklist",
                            color: Color(hex: project.colorHex)
                        )
                    }
                }
            }
            .padding(10)
        }
    }

    private func groupLabel(_ text: String) -> some View {
        SectionEyebrowLabel(text: text, size: .compact)
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
