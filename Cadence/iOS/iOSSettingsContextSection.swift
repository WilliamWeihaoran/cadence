#if os(iOS)
import SwiftData
import SwiftUI

enum iOSContextEditorMode: Identifiable {
    case new
    case edit(Context)

    var id: String {
        switch self {
        case .new:
            return "new-context"
        case .edit(let context):
            return "context-\(context.id)"
        }
    }
}

struct iOSContextEditorSheet: View {
    let mode: iOSContextEditorMode
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Context.order) private var contexts: [Context]
    @State private var name = ""
    @State private var icon = "square.stack.fill"
    @State private var colorHex = "#4a9eff"
    @State private var hasLoaded = false

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Context") {
                    TextField("Name", text: $name)
                    TextField("SF Symbol", text: $icon)
                        .textInputAutocapitalization(.never)
                    TextField("Color hex", text: $colorHex)
                        .textInputAutocapitalization(.never)
                }

                Section {
                    iOSSettingsContextPreview(
                        name: trimmedName.isEmpty ? "Context" : trimmedName,
                        icon: normalizedIcon,
                        colorHex: normalizedColor
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle(isEditing ? "Edit Context" : "New Context")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear(perform: load)
        }
        .preferredColorScheme(.dark)
    }

    private func load() {
        guard !hasLoaded else { return }
        hasLoaded = true

        switch mode {
        case .new:
            name = ""
            icon = "square.stack.fill"
            colorHex = "#4a9eff"
        case .edit(let context):
            name = context.name
            icon = context.icon
            colorHex = context.colorHex
        }
    }

    private func save() {
        switch mode {
        case .new:
            let context = Context(name: trimmedName, colorHex: normalizedColor, icon: normalizedIcon)
            context.order = nextContextOrder()
            modelContext.insert(context)
        case .edit(let context):
            context.name = trimmedName
            context.icon = normalizedIcon
            context.colorHex = normalizedColor
        }

        try? modelContext.save()
        dismiss()
    }

    private var normalizedIcon: String {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "square.stack.fill" : trimmed
    }

    private var normalizedColor: String {
        let trimmed = colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#"), trimmed.count == 7 else {
            return "#4a9eff"
        }
        return trimmed
    }

    private func nextContextOrder() -> Int {
        (contexts.map(\.order).max() ?? -1) + 1
    }
}

struct iOSSettingsContextRow: View {
    let context: Context

    var body: some View {
        iOSSettingsContextPreview(
            name: context.name.isEmpty ? "Untitled Context" : context.name,
            icon: context.icon,
            colorHex: context.colorHex
        )
    }
}

struct iOSSettingsArchivedContextRow: View {
    let context: Context
    let restore: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            iOSSettingsContextIcon(icon: context.icon, colorHex: context.colorHex, opacity: 0.42)

            VStack(alignment: .leading, spacing: 3) {
                Text(context.name.isEmpty ? "Untitled Context" : context.name)
                    .foregroundStyle(Theme.muted)
                Text("Archived")
                    .font(.caption)
                    .foregroundStyle(Theme.amber)
            }

            Spacer()

            Button("Restore", action: restore)
                .font(.caption.weight(.semibold))
        }
        .padding(.vertical, 10)
    }
}

private struct iOSSettingsContextPreview: View {
    let name: String
    let icon: String
    let colorHex: String

    var body: some View {
        HStack(spacing: 12) {
            iOSSettingsContextIcon(icon: icon, colorHex: colorHex)

            Text(name)
                .foregroundStyle(Theme.text)

            Spacer()
        }
        .padding(.vertical, 10)
    }
}

private struct iOSSettingsContextIcon: View {
    let icon: String
    let colorHex: String
    var opacity: Double = 1

    var body: some View {
        let tint = Color(hex: colorHex)

        Image(systemName: icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(tint.opacity(opacity))
            .frame(width: 32, height: 32)
            .background(tint.opacity(0.12 * opacity))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
#endif
