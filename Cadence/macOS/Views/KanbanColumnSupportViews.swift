#if os(macOS)
import SwiftUI

struct KanbanColumnHeader<DueDatePopover: View, EditorPopover: View>: View {
    let section: TaskSectionConfig
    let activeTaskCount: Int
    let columnColor: Color
    let hideColumnDueDateIfEmpty: Bool
    let sectionDueDateIsOverdue: Bool
    let isPendingCompletion: Bool
    @Binding var showHeaderDueDatePicker: Bool
    @Binding var showEditor: Bool
    let onToggleCompletion: () -> Void
    let onOpenDueDatePicker: () -> Void
    let onOpenEditor: () -> Void
    let onCreateTask: () -> Void
    let onHoverChanged: (Bool) -> Void
    @ViewBuilder let dueDatePopover: () -> DueDatePopover
    @ViewBuilder let editorPopover: () -> EditorPopover

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggleCompletion) {
                Image(systemName: section.isCompleted ? "checkmark.circle.fill" : (isPendingCompletion ? "circle.inset.filled" : "circle"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(section.isCompleted || isPendingCompletion ? Theme.green : columnColor.opacity(section.isDefault ? 0.75 : 0.9))
            }
            .buttonStyle(.cadencePlain)
            .padding(.trailing, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(section.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.muted)

                if !section.dueDate.isEmpty || !hideColumnDueDateIfEmpty {
                    Button(action: onOpenDueDatePicker) {
                        HStack(spacing: 5) {
                            Image(systemName: "flag.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.red)
                            Text(section.dueDate.isEmpty ? "No due date" : DateFormatters.relativeDate(from: section.dueDate))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(
                                    section.dueDate.isEmpty
                                        ? Theme.dim
                                        : (sectionDueDateIsOverdue ? Theme.red : Theme.dim)
                                )
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

                if section.isCompleted {
                    Text("Completed")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.green)
                } else if isPendingCompletion {
                    Text("Completing…")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.green)
                }
            }

            Spacer()

            Text("\(activeTaskCount)")
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)

            Button(action: onOpenEditor) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 22, height: 22)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.cadencePlain)
            .popover(isPresented: $showEditor, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                editorPopover()
            }

            Button(action: onCreateTask) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 22, height: 22)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.cadencePlain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .onHover(perform: onHoverChanged)
    }
}

struct KanbanSectionDueDatePickerPopover: View {
    let dueDateKey: String
    @Binding var selection: Date
    let onClear: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            CadenceDatePicker(selection: $selection)
                .padding(10)

            Divider().background(Theme.borderSubtle)

            HStack(spacing: 8) {
                if !dueDateKey.isEmpty {
                    Button("Clear date", action: onClear)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.red)
                        .buttonStyle(.cadencePlain)
                }

                Spacer()

                Button("Done", action: onDone)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                    .buttonStyle(.cadencePlain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .frame(width: 260)
        .background(Theme.surface)
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

                CadenceDatePicker(selection: $editorDueDate)
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
