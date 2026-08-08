#if os(macOS)
import SwiftUI

struct KanbanColumnHeader<DueDatePopover: View, EditorPopover: View>: View {
    let section: TaskSectionConfig
    let activeTaskCount: Int
    let columnColor: Color
    let hideColumnDueDateIfEmpty: Bool
    let sectionDueDateIsOverdue: Bool
    let isPendingCompletion: Bool
    let completionProgress: Double
    @Binding var showHeaderDueDatePicker: Bool
    @Binding var showEditor: Bool
    let onToggleCompletion: () -> Void
    let onOpenDueDatePicker: () -> Void
    let onOpenEditor: () -> Void
    let onHoverChanged: (Bool) -> Void
    @ViewBuilder let dueDatePopover: () -> DueDatePopover
    @ViewBuilder let editorPopover: () -> EditorPopover

    /// Column containers are gone, so the header is the only place the section's color
    /// survives — a single 7pt dot. Everything else is neutral, quiet type.
    private var dotColor: Color {
        section.isCompleted || isPendingCompletion ? Theme.green : columnColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            titleRow

            if !section.dueDate.isEmpty || !hideColumnDueDateIfEmpty {
                dueDateRow
                    .padding(.leading, 14)
            }

            if section.isCompleted || isPendingCompletion {
                Text(section.isCompleted ? "Completed" : "Completing…")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.green)
                    .padding(.leading, 14)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .onHover(perform: onHoverChanged)
    }

    private var titleRow: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)

            Text(section.name.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.4)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 6)

            Text("\(activeTaskCount)")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.dim)
                .monospacedDigit()

            Button(action: onToggleCompletion) {
                TaskCompletionProgressGlyph(
                    icon: section.isCompleted ? "checkmark.circle.fill" : "circle",
                    color: section.isCompleted || isPendingCompletion ? Theme.green : Theme.dim,
                    progress: isPendingCompletion ? completionProgress : nil,
                    size: 12,
                    lineWidth: 1.5
                )
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.cadencePlain)
            .help(section.isCompleted ? "Mark column active" : "Mark column completed")

            Button(action: onOpenEditor) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.cadencePlain)
            .popover(isPresented: $showEditor, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                editorPopover()
            }
        }
    }

    private var dueDateRow: some View {
        Button(action: onOpenDueDatePicker) {
            HStack(spacing: 5) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(section.dueDate.isEmpty ? Theme.dim : Theme.red)
                Text(section.dueDate.isEmpty ? "No due date" : DateFormatters.relativeDate(from: section.dueDate))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(sectionDueDateIsOverdue ? Theme.red : Theme.dim)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.cadencePlain)
        .popover(isPresented: $showHeaderDueDatePicker, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            dueDatePopover()
        }
    }
}

/// Bottom-of-column affordance that replaces the old header "+" button. It is always
/// present — including for empty columns, which otherwise render as nothing now that the
/// column has no container — and routes to the exact same task-creation call.
struct KanbanColumnAddTaskRow: View {
    let isColumnHovered: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .semibold))
                Text("Add task")
                    .font(.system(size: 11, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.dim)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: kanbanCardCornerRadius, style: .continuous)
                    .fill(Theme.surface.opacity(isHovered ? 1 : 0))
            }
            .contentShape(RoundedRectangle(cornerRadius: kanbanCardCornerRadius, style: .continuous))
        }
        .buttonStyle(.cadencePlain)
        .opacity(isColumnHovered || isHovered ? 1 : 0.45)
        .animation(.easeInOut(duration: 0.14), value: isColumnHovered)
        .animation(.easeInOut(duration: 0.14), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

struct KanbanSectionDueDatePickerPopover: View {
    let dueDateKey: String
    @Binding var selection: Date
    @Binding var viewMonth: Date
    @Binding var isPresented: Bool
    let onClear: () -> Void

    var body: some View {
        CadenceQuickDatePopover(
            selection: $selection,
            viewMonth: $viewMonth,
            isOpen: $isPresented,
            showsClear: !dueDateKey.isEmpty,
            onClear: onClear
        )
    }
}

struct KanbanSectionEditorPopover: View {
    let section: TaskSectionConfig
    let editorColorOptions: [String]
    @Binding var editorName: String
    @Binding var editorColorHex: String
    @Binding var editorDueDate: Date
    @Binding var editorHasDueDate: Bool
    let onNameChanged: () -> Void
    let onColorSelected: () -> Void
    let onDueDateChanged: () -> Void
    let onClearDate: () -> Void
    let onToggleCompletion: () -> Void
    let onToggleArchive: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.isDefault ? "Default Column" : "Edit Column")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)

            if section.isDefault {
                Text("Default always stays available and cannot be renamed, archived, or deleted.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                TextField("Column name", text: $editorName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .padding(10)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onChange(of: editorName) { _, _ in onNameChanged() }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                HStack(spacing: 8) {
                    ForEach(editorColorOptions, id: \.self) { hex in
                        Button {
                            editorColorHex = hex
                            onColorSelected()
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 18, height: 18)
                                .overlay {
                                    Circle()
                                        .stroke(editorColorHex == hex ? Theme.text : .clear, lineWidth: 1.5)
                                }
                        }
                        .buttonStyle(.cadencePlain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Due Date")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)

                CadenceDatePicker(
                    selection: $editorDueDate,
                    showsClear: editorHasDueDate,
                    onClear: onClearDate
                )
                    .onChange(of: editorDueDate) { _, _ in
                        editorHasDueDate = true
                        onDueDateChanged()
                    }

                if editorHasDueDate {
                    Button("Clear date", action: onClearDate)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.red)
                        .buttonStyle(.cadencePlain)
                }
            }

            Divider().background(Theme.borderSubtle)

            Button(action: onToggleCompletion) {
                HStack(spacing: 8) {
                    Image(systemName: section.isCompleted ? "arrow.uturn.backward.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(section.isCompleted ? "Mark Section Active" : "Mark Section Completed")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                }
                .foregroundStyle(section.isCompleted ? Theme.blue : Theme.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.cadencePlain)

            if !section.isDefault {
                Button(action: onToggleArchive) {
                    HStack(spacing: 8) {
                        Image(systemName: section.isArchived ? "tray.and.arrow.up.fill" : "archivebox.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text(section.isArchived ? "Unarchive Column" : "Archive Column")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.cadencePlain)

                Button(action: onDelete) {
                    HStack(spacing: 8) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Delete Column")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(Theme.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(Theme.red.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.cadencePlain)
            }
        }
        .padding(14)
        .frame(width: 260)
        .background(Theme.surface)
    }
}
#endif
