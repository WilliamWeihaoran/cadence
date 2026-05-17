#if os(iOS)
import CloudKit
import SwiftData
import SwiftUI

struct iOSSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var tasks: [AppTask]
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query private var areas: [Area]
    @Query private var projects: [Project]
    @Query private var notes: [Note]
    @State private var accountStatus: CKAccountStatus?
    @State private var accountError: String?
    @State private var isCheckingAccount = false
    @State private var lastChecked: Date?
    @State private var contextEditorMode: iOSContextEditorMode?

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    private var bundleID: String {
        Bundle.main.bundleIdentifier ?? "Unknown"
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cadence")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text("iPad and iPhone companion")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.dim)
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section("Sync") {
                HStack(spacing: 12) {
                    Image(systemName: cloudStatusIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(cloudStatusColor)
                        .frame(width: 30, height: 30)
                        .background(cloudStatusColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(cloudStatusTitle)
                            .foregroundStyle(Theme.text)
                        Text(cloudStatusSubtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.dim)
                    }

                    Spacer()

                    if isCheckingAccount {
                        ProgressView()
                            .tint(Theme.blue)
                    }
                }

                Button {
                    refreshAccountStatus()
                } label: {
                    Label("Check iCloud Status", systemImage: "arrow.clockwise")
                }
                .disabled(isCheckingAccount)

                if let lastChecked {
                    LabeledContent("Last checked", value: lastChecked.formatted(date: .abbreviated, time: .shortened))
                }
            }

            Section("Build") {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Build", value: buildNumber)
                LabeledContent("Bundle ID", value: bundleID)
            }

            Section("Contexts") {
                if activeContexts.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No active contexts")
                            .foregroundStyle(Theme.text)
                        Text("Create one here, then use it when making Areas and Projects.")
                            .font(.caption)
                            .foregroundStyle(Theme.dim)
                    }
                    .padding(.vertical, 4)
                } else {
                    ForEach(activeContexts) { context in
                        iOSSettingsContextRow(context: context)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    archive(context)
                                } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                                .tint(Theme.amber)
                            }
                            .contextMenu {
                                Button {
                                    contextEditorMode = .edit(context)
                                } label: {
                                    Label("Edit Context", systemImage: "square.and.pencil")
                                }

                                Button(role: .destructive) {
                                    archive(context)
                                } label: {
                                    Label("Archive Context", systemImage: "archivebox")
                                }
                            }
                            .onTapGesture {
                                contextEditorMode = .edit(context)
                            }
                    }
                }

                Button {
                    contextEditorMode = .new
                } label: {
                    Label("New Context", systemImage: "square.stack.3d.up.badge.plus")
                }

                if !archivedContexts.isEmpty {
                    ForEach(archivedContexts) { context in
                        iOSSettingsArchivedContextRow(context: context) {
                            restore(context)
                        }
                    }
                }
            }

            Section("Local Data") {
                LabeledContent("Active tasks", value: "\(activeTaskCount)")
                LabeledContent("Completed tasks", value: "\(completedTaskCount)")
                LabeledContent("Inbox tasks", value: "\(inboxTaskCount)")
                LabeledContent("Active contexts", value: "\(activeContextCount)")
                LabeledContent("Active areas", value: "\(activeAreaCount)")
                LabeledContent("Active projects", value: "\(activeProjectCount)")
                LabeledContent("Notes", value: "\(notes.count)")
            }

            Section("Mobile Coverage") {
                iOSSettingsCapabilityRow(title: "Today planning", isReady: true)
                iOSSettingsCapabilityRow(title: "Inbox capture", isReady: true)
                iOSSettingsCapabilityRow(title: "Create/edit/archive contexts", isReady: true)
                iOSSettingsCapabilityRow(title: "Create/edit/archive lists", isReady: true)
                iOSSettingsCapabilityRow(title: "Search", isReady: true)
                iOSSettingsCapabilityRow(title: "Plain notes", isReady: true)
                iOSSettingsCapabilityRow(title: "Calendar timeline", isReady: true)
                iOSSettingsCapabilityRow(title: "Focus timer", isReady: true)
                iOSSettingsCapabilityRow(title: "Pursuits", isReady: true)
                iOSSettingsCapabilityRow(title: "Milestones", isReady: true)
                iOSSettingsCapabilityRow(title: "Habits", isReady: true)
            }
        }
        .navigationTitle("Settings")
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .sheet(item: $contextEditorMode) { mode in
            iOSContextEditorSheet(mode: mode)
        }
        .onAppear {
            if accountStatus == nil && !isCheckingAccount {
                refreshAccountStatus()
            }
        }
    }

    private var activeTaskCount: Int {
        tasks.filter { !$0.isDone && !$0.isCancelled }.count
    }

    private var completedTaskCount: Int {
        tasks.filter(\.isDone).count
    }

    private var inboxTaskCount: Int {
        tasks.filter { $0.area == nil && $0.project == nil && !$0.isDone && !$0.isCancelled }.count
    }

    private var activeContexts: [Context] {
        contexts.filter { !$0.isArchived }
    }

    private var archivedContexts: [Context] {
        contexts.filter(\.isArchived)
    }

    private var activeContextCount: Int {
        activeContexts.count
    }

    private var activeAreaCount: Int {
        areas.filter(\.isActive).count
    }

    private var activeProjectCount: Int {
        projects.filter(\.isActive).count
    }

    private var cloudStatusTitle: String {
        if isCheckingAccount { return "Checking iCloud" }
        if accountError != nil { return "Could not check iCloud" }
        guard let accountStatus else { return "iCloud not checked" }

        switch accountStatus {
        case .available:
            return "iCloud available"
        case .noAccount:
            return "No iCloud account"
        case .restricted:
            return "iCloud restricted"
        case .couldNotDetermine:
            return "iCloud unknown"
        case .temporarilyUnavailable:
            return "iCloud temporarily unavailable"
        @unknown default:
            return "iCloud unknown"
        }
    }

    private var cloudStatusSubtitle: String {
        if let accountError { return accountError }
        guard let accountStatus else {
            return "Check status before relying on TestFlight sync."
        }

        switch accountStatus {
        case .available:
            return "CloudKit should be able to sync Cadence data."
        case .noAccount:
            return "Sign into iCloud on this device to sync."
        case .restricted:
            return "iCloud is restricted by device or account policy."
        case .couldNotDetermine:
            return "Try again or check device network/iCloud settings."
        case .temporarilyUnavailable:
            return "Apple reported iCloud is temporarily unavailable."
        @unknown default:
            return "This device returned an unknown iCloud state."
        }
    }

    private var cloudStatusIcon: String {
        if isCheckingAccount { return "icloud" }
        if accountError != nil { return "exclamationmark.icloud" }
        guard accountStatus == .available else { return "icloud.slash" }
        return "checkmark.icloud"
    }

    private var cloudStatusColor: Color {
        if accountStatus == .available && accountError == nil { return Theme.green }
        if isCheckingAccount { return Theme.blue }
        if accountStatus == nil && accountError == nil { return Theme.dim }
        return Theme.amber
    }

    private func refreshAccountStatus() {
        isCheckingAccount = true
        accountError = nil

        CKContainer.default().accountStatus { status, error in
            Task { @MainActor in
                accountStatus = status
                accountError = error?.localizedDescription
                isCheckingAccount = false
                lastChecked = Date()
            }
        }
    }

    private func archive(_ context: Context) {
        context.isArchived = true
        try? modelContext.save()
    }

    private func restore(_ context: Context) {
        context.isArchived = false
        try? modelContext.save()
    }
}

private enum iOSContextEditorMode: Identifiable {
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

private struct iOSContextEditorSheet: View {
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

private struct iOSSettingsContextRow: View {
    let context: Context

    var body: some View {
        iOSSettingsContextPreview(
            name: context.name.isEmpty ? "Untitled Context" : context.name,
            icon: context.icon,
            colorHex: context.colorHex
        )
    }
}

private struct iOSSettingsArchivedContextRow: View {
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
        .padding(.vertical, 3)
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
        .padding(.vertical, 3)
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

private struct iOSSettingsCapabilityRow: View {
    let title: String
    let isReady: Bool

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(Theme.text)
            Spacer()
            Label(isReady ? "Ready" : "Later",
                  systemImage: isReady ? "checkmark.circle.fill" : "clock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isReady ? Theme.green : Theme.dim)
        }
    }
}
#endif
