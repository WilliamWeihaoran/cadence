#if os(macOS)
import SwiftUI
import SwiftData

struct CreateListSheet: View {
    let context: Context

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var listType: ListType = .area
    @State private var selectedColor = ListType.area.defaultColor
    @State private var selectedIcon = "folder.fill"
    @State private var dueDate: Date = Date()
    @State private var hasDueDate: Bool = false
    @State private var hideDueDateIfEmpty = true
    @State private var hideSectionDueDateIfEmpty = true

    enum ListType: String, CaseIterable {
        case area = "Area"
        case project = "Project"

        var description: String {
            switch self {
            case .area:    return "Ongoing responsibility, no end date"
            case .project: return "Finite effort with a clear outcome"
            }
        }
        var defaultIcon: String {
            switch self {
            case .area:    return "folder.fill"
            case .project: return "checklist"
            }
        }
        /// The model default for the type, read from `CadenceColorPalette` rather than respelled.
        ///
        /// Both arms were hex literals until T-246 — `#4ecb71` beside a `projectDefault` that had
        /// just been pointed at `Theme.greenHex`, which is the exact shape T-166 found in the
        /// sidebar's tints. A value test cannot see this: the literals matched their tokens
        /// exactly, so nothing was wrong on screen and nothing would have been until the next time
        /// a default moved and took only one of its two spellings with it.
        var defaultColor: String {
            switch self {
            case .area:    return CadenceColorPalette.areaDefault
            case .project: return CadenceColorPalette.projectDefault
            }
        }
    }

    var body: some View {
        ListEditorSheetShell(
            title: "New List",
            titleTrailing: "in \(context.name)",
            confirmTitle: "Create",
            isConfirmDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty,
            onConfirm: create
        ) {
            HStack(spacing: 8) {
                ForEach(ListType.allCases, id: \.self) { type in
                    TypeButton(type: type, isSelected: listType == type) {
                        listType = type
                        selectedIcon = type.defaultIcon
                        selectedColor = type.defaultColor
                    }
                }
            }

            ListEditorIdentityHeader(
                name: $name,
                colorHex: $selectedColor,
                icon: $selectedIcon,
                placeholder: listType == .area ? "Area name…" : "Project name…"
            )

            TaskInspectorRecessedGroup {
                if listType == .project {
                    TaskInspectorDateControl(
                        label: "Due",
                        reservesIconSlot: false,
                        isOn: $hasDueDate,
                        date: $dueDate
                    )
                    TaskInspectorFieldDivider()
                }

                ListEditorCheckRow(
                    label: "Hide empty task due date",
                    isOn: $hideDueDateIfEmpty
                )

                TaskInspectorFieldDivider()
                ListEditorCheckRow(
                    label: "Hide empty column due date",
                    isOn: $hideSectionDueDateIfEmpty
                )
            }
        }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        switch listType {
        case .area:
            let area = Area(name: trimmed, context: context, colorHex: selectedColor, icon: selectedIcon)
            area.order = nextListOrder
            area.hideDueDateIfEmpty = hideDueDateIfEmpty
            area.hideSectionDueDateIfEmpty = hideSectionDueDateIfEmpty
            modelContext.insert(area)
        case .project:
            let project = Project(name: trimmed, context: context, colorHex: selectedColor)
            project.icon = selectedIcon
            project.order = nextListOrder
            project.hideDueDateIfEmpty = hideDueDateIfEmpty
            project.hideSectionDueDateIfEmpty = hideSectionDueDateIfEmpty
            if hasDueDate { project.dueDate = DateFormatters.dateKey(from: dueDate) }
            modelContext.insert(project)
        }
        dismiss()
    }

    private var nextListOrder: Int {
        let areaOrders = (context.areas ?? []).map(\.order)
        let projectOrders = (context.projects ?? []).map(\.order)
        return ((areaOrders + projectOrders).max() ?? -1) + 1
    }
}

// MARK: - Type Button

private struct TypeButton: View {
    let type: CreateListSheet.ListType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(type.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.blue : Theme.text)
                Text(type.description)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Theme.blue.opacity(0.1) : Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Theme.blue.opacity(0.5) : Theme.borderSubtle)
            )
        }
        .buttonStyle(.cadencePlain)
    }
}
#endif
