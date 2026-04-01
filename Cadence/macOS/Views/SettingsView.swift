#if os(macOS)
import SwiftUI
import SwiftData
import EventKit

struct SettingsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(CalendarManager.self) private var calendarManager
    @AppStorage("listDetailDefaultPage") private var listDetailDefaultPage = ListDetailPage.tasks.rawValue
    @AppStorage("sidebarHiddenTabs") private var sidebarHiddenTabsRaw = ""
    @Query(sort: \Area.order)    private var areas:    [Area]
    @Query(sort: \Project.order) private var projects: [Project]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PanelHeader(eyebrow: "Settings", title: "Appearance & Integrations")
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                appearanceSection
                    .padding(.horizontal, 24)

                navigationSection
                    .padding(.horizontal, 24)

                sidebarTabsSection
                    .padding(.horizontal, 24)

                calendarSection
                    .padding(.horizontal, 24)
            }
            .padding(.bottom, 32)
        }
        .background(Theme.bg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Calendar Section

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsCard {
                HStack(alignment: .top, spacing: 14) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.blue.opacity(0.18))
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "paintpalette.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Theme.blue)
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Dark Themes")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text("Pick the dark palette that best fits your workspace. Changes apply across the app immediately.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }
            }

            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 220), spacing: 16, alignment: .top)
                ],
                spacing: 16
            ) {
                ForEach(ThemeOption.allCases) { option in
                    themeOptionCard(option)
                }
            }
        }
    }

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header card
            settingsCard {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.purple.opacity(0.18))
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "calendar")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Theme.purple)
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Apple Calendar")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text("Scheduled tasks sync to Apple Calendar when their area or project has a linked calendar.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    authBadge
                }
            }

            if calendarManager.isAuthorized {
                // Areas
                if !areas.isEmpty {
                    sectionLabel("Areas")
                    settingsCard {
                        VStack(spacing: 0) {
                            ForEach(Array(areas.enumerated()), id: \.element.id) { index, area in
                                CalendarLinkRow(
                                    icon: area.icon,
                                    name: area.name,
                                    color: Color(hex: area.colorHex),
                                    linkedCalendarID: Binding(
                                        get: { area.linkedCalendarID },
                                        set: { area.linkedCalendarID = $0 }
                                    ),
                                    calendars: calendarManager.availableCalendars
                                )
                                if index < areas.count - 1 {
                                    Divider()
                                        .background(Theme.borderSubtle)
                                        .padding(.leading, 44)
                                }
                            }
                        }
                    }
                }

                // Projects
                let activeProjects = projects.filter { !$0.isDone }
                if !activeProjects.isEmpty {
                    sectionLabel("Projects")
                    settingsCard {
                        VStack(spacing: 0) {
                            ForEach(Array(activeProjects.enumerated()), id: \.element.id) { index, project in
                                CalendarLinkRow(
                                    icon: project.icon,
                                    name: project.name,
                                    color: Color(hex: project.colorHex),
                                    linkedCalendarID: Binding(
                                        get: { project.linkedCalendarID },
                                        set: { project.linkedCalendarID = $0 }
                                    ),
                                    calendars: calendarManager.availableCalendars
                                )
                                if index < activeProjects.count - 1 {
                                    Divider()
                                        .background(Theme.borderSubtle)
                                        .padding(.leading, 44)
                                }
                            }
                        }
                    }
                }
            } else {
                // Not authorized — show grant or redirect button
                settingsCard {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.amber)
                            .font(.system(size: 14))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(calendarManager.isDenied ? "Access denied" : "Calendar access required")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.text)
                            Text(calendarManager.isDenied
                                 ? "Open System Settings → Privacy & Security → Calendars to allow access."
                                 : "Cadence needs permission to create and sync calendar events.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if calendarManager.isDenied {
                            Button("Open Settings") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                            }
                            .buttonStyle(.cadencePlain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Theme.dim)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            Button("Grant Access") {
                                Task { await calendarManager.requestAccess() }
                            }
                            .buttonStyle(.cadencePlain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Theme.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
    }

    private var navigationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsCard {
                HStack(alignment: .top, spacing: 14) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.green.opacity(0.16))
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "rectangle.stack.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Theme.green)
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("List Opening Page")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text("Choose which page new lists open on by default. Once you visit a specific list, Cadence still remembers that list's most recently opened page.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }
            }

            settingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Default List Page")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.dim)

                    HStack(spacing: 10) {
                        ForEach(ListDetailPage.allCases) { page in
                            Button {
                                listDetailDefaultPage = page.rawValue
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: page.icon)
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(page.rawValue)
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(listDetailDefaultPage == page.rawValue ? .white : Theme.dim)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(minHeight: 34)
                                .contentShape(Rectangle())
                                .background(listDetailDefaultPage == page.rawValue ? Theme.blue : Theme.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                            }
                            .buttonStyle(.cadencePlain)
                        }
                    }
                }
            }
        }
    }

    private var hiddenTabs: Set<SidebarStaticDestination> {
        Set(sidebarHiddenTabsRaw.split(separator: ",").compactMap { SidebarStaticDestination(rawValue: String($0)) })
    }

    private func toggleTab(_ destination: SidebarStaticDestination) {
        var set = hiddenTabs
        if set.contains(destination) { set.remove(destination) } else { set.insert(destination) }
        sidebarHiddenTabsRaw = set.map(\.rawValue).joined(separator: ",")
    }

    private var sidebarTabsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsCard {
                HStack(alignment: .top, spacing: 14) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.amber.opacity(0.16))
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "sidebar.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Theme.amber)
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Sidebar Tabs")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text("Choose which tabs appear in the sidebar. Hidden tabs are still accessible by re-enabling them here.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }
            }

            settingsCard {
                VStack(spacing: 0) {
                    let allToggleable = SidebarStaticDestination.allCases
                    ForEach(Array(allToggleable.enumerated()), id: \.element.id) { index, destination in
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(destination.color.opacity(0.15))
                                .frame(width: 30, height: 30)
                                .overlay {
                                    Image(systemName: destination.icon)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(destination.color)
                                }
                            Text(destination.label)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.text)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { !hiddenTabs.contains(destination) },
                                set: { _ in toggleTab(destination) }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .tint(Theme.blue)
                        }
                        .padding(.vertical, 10)
                        if index < allToggleable.count - 1 {
                            Divider().background(Theme.borderSubtle).padding(.leading, 42)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var authBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(calendarManager.isAuthorized ? Theme.green : Theme.dim)
                .frame(width: 7, height: 7)
            Text(calendarManager.isAuthorized ? "Connected" : "Not connected")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(calendarManager.isAuthorized ? Theme.green : Theme.dim)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background((calendarManager.isAuthorized ? Theme.green : Theme.dim).opacity(0.12))
        .clipShape(Capsule())
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.dim)
            .kerning(0.8)
    }

    @ViewBuilder
    private func themeOptionCard(_ option: ThemeOption) -> some View {
        let isSelected = themeManager.selectedTheme == option

        Button {
            themeManager.selectedTheme = option
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ForEach(Array(option.previewColors.enumerated()), id: \.offset) { _, color in
                        RoundedRectangle(cornerRadius: 6)
                            .fill(color)
                            .frame(height: 34)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(option.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        if isSelected {
                            Text("Active")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Theme.blue)
                                .clipShape(Capsule())
                        }
                    }

                    Text(option.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Theme.blue.opacity(0.7) : Theme.borderSubtle, lineWidth: isSelected ? 1.4 : 1)
            }
        }
        .buttonStyle(.cadencePlain)
    }

    @ViewBuilder
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Theme.borderSubtle, lineWidth: 1)
            )
    }
}

// MARK: - Calendar Link Row

private struct CalendarLinkRow: View {
    let icon: String
    let name: String
    let color: Color
    @Binding var linkedCalendarID: String
    let calendars: [EKCalendar]

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(0.18))
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(color)
                }

            Text(name)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)

            Spacer()

            CadenceCalendarPickerButton(
                calendars: calendars,
                selectedID: $linkedCalendarID,
                style: .compact
            )
            .fixedSize()
        }
        .padding(.vertical, 10)
    }
}
#endif
