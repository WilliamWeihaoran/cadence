#if os(iOS)
import CloudKit
import SwiftData
import SwiftUI

struct iOSSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
    @State private var selectedCategory: iOSSettingsCategory = .sync

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
        Group {
            if horizontalSizeClass == .regular {
                HStack(spacing: 0) {
                    iOSSettingsRail(selectedCategory: $selectedCategory)

                    Divider().background(Theme.borderSubtle)

                    settingsDetailScroll
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        settingsHeader
                        iOSSettingsCompactCategoryPicker(selectedCategory: $selectedCategory)
                        selectedSectionContent
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle("Settings")
        .background(Theme.bg.ignoresSafeArea())
        .sheet(item: $contextEditorMode) { mode in
            iOSContextEditorSheet(mode: mode)
        }
        .onAppear {
            if accountStatus == nil && !isCheckingAccount {
                refreshAccountStatus()
            }
        }
    }

    private var settingsDetailScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                settingsHeader
                selectedSectionContent
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var settingsHeader: some View {
        CadenceSettingsHeader(
            title: selectedCategory.title,
            subtitle: selectedCategory.detailDescription,
            icon: selectedCategory.icon,
            tint: selectedCategory.tint
        ) {
            switch selectedCategory {
            case .sync:
                CadenceSettingsStatusBadge(title: cloudStatusTitle, isActive: accountStatus == .available && accountError == nil)
            case .organization:
                CadenceSettingsStatusBadge(title: "\(activeContextCount) contexts", isActive: activeContextCount > 0)
            case .data:
                CadenceSettingsStatusBadge(title: "\(activeTaskCount) active", isActive: activeTaskCount > 0)
            case .coverage:
                CadenceSettingsStatusBadge(title: "Companion", isActive: true)
            case .about:
                CadenceSettingsStatusBadge(title: "Build \(buildNumber)", isActive: true)
            }
        }
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        switch selectedCategory {
        case .sync:
            syncSection
        case .organization:
            organizationSection
        case .data:
            dataSection
        case .coverage:
            coverageSection
        case .about:
            aboutSection
        }
    }

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            CadenceSettingsSectionLabel(text: "iCloud")
            CadenceSettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: cloudStatusIcon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(cloudStatusColor)
                            .frame(width: 34, height: 34)
                            .background(cloudStatusColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(cloudStatusTitle)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.text)
                            Text(cloudStatusSubtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)

                        if isCheckingAccount {
                            ProgressView()
                                .tint(Theme.blue)
                        }
                    }

                    HStack {
                        Button {
                            refreshAccountStatus()
                        } label: {
                            Label("Check iCloud Status", systemImage: "arrow.clockwise")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.blue)
                        .disabled(isCheckingAccount)

                        Spacer()

                        if let lastChecked {
                            Text("Last checked \(lastChecked.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.dim)
                        }
                    }
                }
            }
        }
    }

    private var organizationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CadenceSettingsSectionLabel(text: "Contexts")
                Spacer()
                Button {
                    contextEditorMode = .new
                } label: {
                    Label("New Context", systemImage: "plus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.blue)
            }

            CadenceSettingsCard {
                VStack(spacing: 0) {
                    if activeContexts.isEmpty {
                        iOSSettingsEmptyRow(
                            title: "No active contexts",
                            subtitle: "Create one here, then use it when making areas and projects."
                        )
                    } else {
                        ForEach(activeContexts) { context in
                            Button {
                                contextEditorMode = .edit(context)
                            } label: {
                                iOSSettingsContextRow(context: context)
                            }
                            .buttonStyle(.plain)
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

                            if context.id != activeContexts.last?.id {
                                Divider().background(Theme.borderSubtle)
                            }
                        }
                    }
                }
            }

            if !archivedContexts.isEmpty {
                CadenceSettingsSectionLabel(text: "Archived Contexts")
                CadenceSettingsCard {
                    VStack(spacing: 0) {
                        ForEach(archivedContexts) { context in
                            iOSSettingsArchivedContextRow(context: context) {
                                restore(context)
                            }

                            if context.id != archivedContexts.last?.id {
                                Divider().background(Theme.borderSubtle)
                            }
                        }
                    }
                }
            }
        }
    }

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            CadenceSettingsSectionLabel(text: "Local Data")
            CadenceSettingsCard {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    iOSSettingsMetricTile(title: "Active tasks", value: "\(activeTaskCount)", icon: "checklist", color: Theme.blue)
                    iOSSettingsMetricTile(title: "Completed", value: "\(completedTaskCount)", icon: "checkmark.circle.fill", color: Theme.green)
                    iOSSettingsMetricTile(title: "Inbox", value: "\(inboxTaskCount)", icon: "tray.fill", color: Theme.blue)
                    iOSSettingsMetricTile(title: "Contexts", value: "\(activeContextCount)", icon: "square.stack.3d.up.fill", color: Theme.red)
                    iOSSettingsMetricTile(title: "Areas", value: "\(activeAreaCount)", icon: "folder.fill", color: Theme.green)
                    iOSSettingsMetricTile(title: "Projects", value: "\(activeProjectCount)", icon: "flag.fill", color: Theme.amber)
                    iOSSettingsMetricTile(title: "Notes", value: "\(notes.count)", icon: "doc.text.fill", color: Theme.purple)
                }
            }
        }
    }

    private var coverageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            CadenceSettingsSectionLabel(text: "Mobile Coverage")
            CadenceSettingsCard {
                VStack(spacing: 0) {
                    ForEach(iOSMobileCapability.readyCapabilities, id: \.self) { title in
                        iOSSettingsCapabilityRow(title: title, isReady: true)
                        if title != iOSMobileCapability.readyCapabilities.last {
                            Divider().background(Theme.borderSubtle)
                        }
                    }
                }
            }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            CadenceSettingsSectionLabel(text: "Build")
            CadenceSettingsCard {
                VStack(spacing: 0) {
                    iOSSettingsInfoRow(title: "Version", value: appVersion)
                    Divider().background(Theme.borderSubtle)
                    iOSSettingsInfoRow(title: "Build", value: buildNumber)
                    Divider().background(Theme.borderSubtle)
                    iOSSettingsInfoRow(title: "Bundle ID", value: bundleID)
                }
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

private enum iOSSettingsCategory: String, CaseIterable, Identifiable {
    case sync
    case organization
    case data
    case coverage
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sync: return "Sync"
        case .organization: return "Organization"
        case .data: return "Local Data"
        case .coverage: return "Coverage"
        case .about: return "About"
        }
    }

    var subtitle: String {
        switch self {
        case .sync: return "iCloud status."
        case .organization: return "Contexts and groups."
        case .data: return "Counts and storage."
        case .coverage: return "Mobile feature surface."
        case .about: return "Version and bundle."
        }
    }

    var detailDescription: String {
        switch self {
        case .sync:
            return "Check whether this device can use iCloud and CloudKit for Cadence sync."
        case .organization:
            return "Manage the top-level contexts shared by areas, projects, tasks, and habits."
        case .data:
            return "Review the local workspace counts currently visible on this device."
        case .coverage:
            return "Track which companion app workflows are currently implemented on iPhone and iPad."
        case .about:
            return "Review the installed app version and bundle details for TestFlight diagnostics."
        }
    }

    var icon: String {
        switch self {
        case .sync: return "icloud.fill"
        case .organization: return "square.stack.3d.up.fill"
        case .data: return "chart.bar.doc.horizontal.fill"
        case .coverage: return "iphone.and.arrow.forward"
        case .about: return "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .sync: return Theme.blue
        case .organization: return Theme.red
        case .data: return Theme.green
        case .coverage: return Theme.purple
        case .about: return Theme.amber
        }
    }
}

private enum iOSMobileCapability {
    static let readyCapabilities = [
        "Today planning",
        "Inbox capture",
        "Create/edit/archive contexts",
        "Create/edit/archive lists",
        "Search",
        "Plain notes",
        "Calendar timeline",
        "Focus timer",
        "Pursuits",
        "Milestones",
        "Habits"
    ]
}

private struct iOSSettingsRail: View {
    @Binding var selectedCategory: iOSSettingsCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text("Preferences, organization, sync, and TestFlight diagnostics.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                ForEach(iOSSettingsCategory.allCases) { category in
                    iOSSettingsRailButton(
                        category: category,
                        isSelected: selectedCategory == category
                    ) {
                        selectedCategory = category
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 22)
        .frame(width: 260)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface.opacity(0.58))
    }
}

private struct iOSSettingsRailButton: View {
    let category: iOSSettingsCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(category.tint.opacity(isSelected ? 0.22 : 0.14))
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: category.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(category.tint)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? Theme.text : Theme.text.opacity(0.92))
                    Text(category.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Theme.surfaceElevated : Color.clear)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? category.tint.opacity(0.36) : Theme.borderSubtle.opacity(0.001), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct iOSSettingsCompactCategoryPicker: View {
    @Binding var selectedCategory: iOSSettingsCategory

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(iOSSettingsCategory.allCases) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: category.icon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(category.title)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(selectedCategory == category ? Theme.text : Theme.dim)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(selectedCategory == category ? category.tint.opacity(0.22) : Theme.surface)
                        )
                        .overlay {
                            Capsule()
                                .stroke(selectedCategory == category ? category.tint.opacity(0.36) : Theme.borderSubtle, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollIndicators(.hidden)
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

private struct iOSSettingsEmptyRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .frame(width: 32, height: 32)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

private struct iOSSettingsMetricTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 30, height: 30)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .padding(13)
        .frame(minHeight: 104, alignment: .topLeading)
        .background(Theme.surfaceElevated.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(color.opacity(0.18), lineWidth: 1)
        }
    }
}

private struct iOSSettingsInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.dim)

            Spacer(minLength: 0)

            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.vertical, 10)
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
        .padding(.vertical, 10)
    }
}
#endif
