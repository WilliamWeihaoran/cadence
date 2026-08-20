#if os(iOS)
import SwiftUI

enum iOSSettingsCategory: String, CaseIterable, Identifiable {
    case navigation
    case sync
    case data
    case calendar
    case reminders
    case notifications
    case organization
    case lists
    case tags
    case templates
    case ai
    case coverage
    case about

    var id: String { rawValue }

    /// Every category mobile offers, grouped, in the order the list draws them. The grouping is
    /// declared once in `Shared` (`CadenceMobileSettingsLayout`) so the iPhone list and the iPad
    /// rail cannot end up filing the same destination under different headings.
    /// Computed rather than a `static let`: a stored static's initializer runs in a nonisolated
    /// context, and everything in this target is main-actor by default. A dozen-odd cases is not
    /// worth a caching dance.
    static var groups: [iOSSettingsCategoryGroup] {
        CadenceMobileSettingsLayout.groups.map { group in
            iOSSettingsCategoryGroup(
                title: group.title,
                categories: group.kinds.compactMap { iOSSettingsCategory(kind: $0) }
            )
        }
    }

    /// `nil` for the two categories that are genuinely macOS-shell concerns and have no mobile
    /// screen: `sidebar` (there is no sidebar to configure on iPhone, and the iPad one is not
    /// user-arranged) and `account` (Sign in with Apple is a macOS-only entitlement here).
    ///
    /// This comment used to name a third, `reminders`, and calling it a shell concern is what
    /// kept Apple Reminders unreachable from iOS Settings: EventKit reminders are fully
    /// available on iOS, `RemindersManager` never touched AppKit, and the usage-description key
    /// already shipped in the shared `Info.plist`. Nothing was missing but this classification.
    /// Deliberately an exhaustive `switch` rather than the reflective
    /// `allCases.first(where: { $0.sharedKind == kind })` it used to be. That spelling turned a
    /// missing mobile case into a silent `nil` — `groups` `compactMap`s, so the category just
    /// stopped being drawn, with nothing to notice it. Written out, adding a
    /// `CadenceSettingsCategoryKind` fails to build here until someone states whether mobile has
    /// a screen for it. The macOS-built test target cannot see this file at all, so a compile
    /// error is the only check available on this half; the shared half is pinned by
    /// `CadenceMobileSettingsLayout.desktopOnly`.
    init?(kind: CadenceSettingsCategoryKind) {
        switch kind {
        case .navigation: self = .navigation
        case .sync: self = .sync
        case .dataSafety: self = .data
        case .calendar: self = .calendar
        case .reminders: self = .reminders
        case .notifications: self = .notifications
        case .contexts: self = .organization
        case .lists: self = .lists
        case .tags: self = .tags
        case .templates: self = .templates
        case .ai: self = .ai
        case .coverage: self = .coverage
        case .about: self = .about
        case .sidebar, .account: return nil
        }
    }

    var sharedKind: CadenceSettingsCategoryKind {
        switch self {
        case .navigation: return .navigation
        case .sync: return .sync
        case .data: return .dataSafety
        case .calendar: return .calendar
        case .reminders: return .reminders
        case .notifications: return .notifications
        case .organization: return .contexts
        case .lists: return .lists
        case .tags: return .tags
        case .templates: return .templates
        case .ai: return .ai
        case .coverage: return .coverage
        case .about: return .about
        }
    }

    var title: String {
        sharedKind.title
    }


    var icon: String {
        sharedKind.icon
    }

    var tint: Color {
        sharedKind.tint
    }
}

struct iOSSettingsCategoryGroup: Identifiable {
    let title: String
    let categories: [iOSSettingsCategory]

    var id: String { title }
}

enum iOSMobileCapabilityStatus: String, CaseIterable, Identifiable {
    case ready
    case partial
    case later

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ready: return "Ready"
        case .partial: return "Partial"
        case .later: return "Later"
        }
    }

    var systemImage: String {
        switch self {
        case .ready: return "checkmark.circle.fill"
        case .partial: return "wrench.and.screwdriver.fill"
        case .later: return "clock.fill"
        }
    }

    var color: Color {
        switch self {
        case .ready: return Theme.green
        case .partial: return Theme.amber
        case .later: return Theme.dim
        }
    }
}

struct iOSMobileCapability: Identifiable, Hashable {
    let title: String
    let detail: String
    let status: iOSMobileCapabilityStatus

    var id: String { title }

    static let all: [iOSMobileCapability] = [
        iOSMobileCapability(title: "Today planning", detail: "Capture, sort, complete, notes, samples, and timeline inspector.", status: .ready),
        iOSMobileCapability(title: "All Tasks", detail: "Review active/completed work, edit tasks, and use shared task presentation.", status: .ready),
        iOSMobileCapability(title: "Inbox capture", detail: "Quick add, triage, completion, and scheduling basics.", status: .ready),
        iOSMobileCapability(title: "Lists", detail: "Areas/projects, list detail, Kanban, links, and lifecycle restore.", status: .ready),
        iOSMobileCapability(title: "Search", detail: "Find tasks, notes, and feature destinations from mobile.", status: .ready),
        iOSMobileCapability(title: "Markdown notes", detail: "Live rendering, raw edit, preview, formatting, images, references, tables, and templates.", status: .ready),
        iOSMobileCapability(title: "Settings", detail: "Theme, navigation defaults, calendar, tags, templates, sync, AI, data, and about.", status: .ready),
        iOSMobileCapability(title: "Focus timer", detail: "Mobile focus surface exists, but still needs deeper desktop parity testing.", status: .partial),
        iOSMobileCapability(title: "Calendar", detail: "Timeline/month/board, quick create, event editing, and empty-slot creation exist; drag/resize parity remains.", status: .partial),
        iOSMobileCapability(title: "Goals", detail: "Create/edit top-level goals with nested milestones and habits; desktop timeline parity still needs polish.", status: .partial),
        iOSMobileCapability(title: "Habits", detail: "Create/edit and toggle habits; deeper analytics and Mac polish remain.", status: .partial),
        iOSMobileCapability(title: "CloudKit sync", detail: "Uses the shared container, but needs manual device/relaunch verification before TestFlight.", status: .partial),
        iOSMobileCapability(title: "App Store metadata", detail: "Icons and public support/privacy links are present; screenshots and final review notes remain.", status: .partial),
        iOSMobileCapability(title: "Desktop editor parity", detail: "The AppKit editor cannot be reused directly; mobile now shares markdown behavior through SwiftUI/UIKit surfaces.", status: .partial),
        iOSMobileCapability(title: "Global desktop commands", detail: "Global hotkeys, hover affordances, and macOS command surfaces are intentionally desktop-only.", status: .later)
    ]

    static func count(for status: iOSMobileCapabilityStatus) -> Int {
        all.filter { $0.status == status }.count
    }

    static func items(for status: iOSMobileCapabilityStatus) -> [iOSMobileCapability] {
        all.filter { $0.status == status }
    }
}

/// Sizing for the settings category rail and the rows inside settings cards.
///
/// Mirrors macOS's `SettingsRailMetrics`, which derives its row geometry from
/// `SidebarMetrics` so the two narrow columns of destinations cannot drift apart. iOS has
/// no sidebar metrics to borrow, so the values are restated here — but the *decisions* are
/// the same ones: rows on the shared radius scale, one glyph slot, one label x.
enum iOSSettingsMetrics {
    /// Every control in settings is finger-sized even when its painted chrome is smaller;
    /// the extra height goes into the hit area, not the pill.
    static let minimumTapTarget: CGFloat = 44
    static let rowHorizontalPadding: CGFloat = 10
    static let rowVerticalPadding: CGFloat = 9
    static let glyphSlot: CGFloat = 32
    static let glyphLabelSpacing: CGFloat = 12
    /// Left edge of a card row's text column, so a divider drawn under it starts at the
    /// text rather than cutting across the glyph.
    static let rowTextInset: CGFloat = glyphSlot + glyphLabelSpacing
}

/// Hairline between rows inside a settings card.
///
/// `Divider().background(Theme.borderSubtle)` — the pattern this replaces — leaves the
/// system separator colour painted on top of the palette colour, so the line is neither
/// `borderSubtle` nor predictable across sections. This draws the palette colour and
/// nothing else.
struct iOSRowDivider: View {
    var leadingInset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Theme.borderSubtle)
            .frame(height: 1)
            .padding(.leading, leadingInset)
    }
}

/// Eyebrow label above an inset well — the one field treatment for every settings input.
/// Replaces three near-copies: `.textFieldStyle(.roundedBorder)` in Tags (UIKit chrome,
/// no palette colour at all), the private `iOSTemplateEditorField`, and the bare `Form`
/// rows in the context editor.
struct iOSSettingsField<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionEyebrowLabel(text: title)

            content
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.text)
                .tint(Theme.blue)
                .padding(.horizontal, 12)
                .frame(minHeight: iOSSettingsMetrics.minimumTapTarget)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                        .strokeBorder(Theme.borderSubtle, lineWidth: 1)
                }
        }
    }
}

/// One swatch strip for every user-owned `colorHex` picked in settings (tags, contexts).
/// The swatch itself is a user colour; everything around it comes from `Theme`.
struct iOSSettingsColorSwatchRow: View {
    @Binding var selectedHex: String
    var options: [String] = TagSupport.colorOptions

    /// A stored colour that is no longer offered still shows as selected rather than
    /// silently reading as "none of these".
    private var offered: [String] {
        let stored = selectedHex.trimmingCharacters(in: .whitespaces)
        guard !stored.isEmpty,
              !options.contains(where: { $0.caseInsensitiveCompare(stored) == .orderedSame }) else {
            return options
        }
        return options + [stored]
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                ForEach(offered, id: \.self) { option in
                    Button {
                        selectedHex = option
                    } label: {
                        Circle()
                            .fill(Color(hex: option))
                            .frame(width: 26, height: 26)
                            .overlay {
                                Circle()
                                    .strokeBorder(
                                        Theme.text,
                                        lineWidth: isSelected(option) ? 2 : 0
                                    )
                            }
                            .frame(
                                width: iOSSettingsMetrics.minimumTapTarget,
                                height: iOSSettingsMetrics.minimumTapTarget
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.iosPressable)
                    .accessibilityLabel(option)
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private func isSelected(_ option: String) -> Bool {
        TagSupport.normalizedColorHex(selectedHex).caseInsensitiveCompare(option) == .orderedSame
    }
}

struct iOSSettingsRail: View {
    @Binding var selectedCategory: iOSSettingsCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // No standfirst under the title: a line reading "Preferences and workspace
            // controls" only restates the word above it.
            Text("Settings")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, iOSSettingsMetrics.rowHorizontalPadding)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(iOSSettingsCategory.groups) { group in
                        iOSSettingsRailGroup(
                            group: group,
                            selectedCategory: $selectedCategory
                        )
                    }
                }
                .padding(.bottom, 10)
            }
            .scrollIndicators(.hidden)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 20)
        .frame(width: 248)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface.opacity(0.58))
    }
}

private struct iOSSettingsRailGroup: View {
    let group: iOSSettingsCategoryGroup
    @Binding var selectedCategory: iOSSettingsCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionEyebrowLabel(text: group.title)
                .padding(.horizontal, iOSSettingsMetrics.rowHorizontalPadding)

            VStack(spacing: 2) {
                ForEach(group.categories) { category in
                    iOSSettingsRailButton(
                        category: category,
                        isSelected: selectedCategory == category
                    ) {
                        selectedCategory = category
                    }
                }
            }
        }
    }
}

private struct iOSSettingsRailButton: View {
    let category: iOSSettingsCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: iOSSettingsMetrics.glyphLabelSpacing) {
                // Neutral until this is the row you are on. Tinting all twelve at once
                // spends the accent on the list instead of on the selection — the same
                // call macOS's rail makes.
                Image(systemName: category.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? category.tint : Theme.dim)
                    .frame(width: 22)

                Text(category.title)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, iOSSettingsMetrics.rowHorizontalPadding)
            .padding(.vertical, iOSSettingsMetrics.rowVerticalPadding)
            .frame(maxWidth: .infinity, minHeight: iOSSettingsMetrics.minimumTapTarget, alignment: .leading)
            // One selection layer, one radius: the fill was previously doubled with a
            // tinted stroke drawn at an all-but-invisible 0.001 opacity when unselected.
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                    .fill(isSelected ? Theme.surfaceElevated : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.iosPressable)
        .accessibilityIdentifier("settings.category.\(category.rawValue)")
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }
}

/// The iPhone settings top level: every category as a row you can read, grouped under quiet
/// eyebrows.
///
/// This replaces a horizontally scrolling chip strip. Twelve destinations in a sideways scroller
/// showed two and a half of them — the third clipped mid-word at "Data Safe…" — and gave no way to
/// know the rest existed. A vertical list is the right shape for a set this size and it is what
/// the iPad rail beside it has always been; the two now read from one grouping.
///
/// Category glyphs keep their colour here (the rail tints only the selected row) because in a list
/// with no selection the colour is what makes twelve near-identical rows scannable.
struct iOSSettingsCategoryList: View {
    let select: (iOSSettingsCategory) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(iOSSettingsCategory.groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    SectionEyebrowLabel(text: group.title)
                        .padding(.horizontal, 4)

                    iOSSettingsCard {
                        VStack(spacing: 0) {
                            ForEach(group.categories) { category in
                                Button {
                                    select(category)
                                } label: {
                                    iOSSettingsCategoryRow(category: category)
                                }
                                .buttonStyle(.iosPressable)
                                .accessibilityIdentifier("settings.category.\(category.rawValue)")

                                if category.id != group.categories.last?.id {
                                    iOSRowDivider(leadingInset: iOSSettingsMetrics.rowTextInset)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct iOSSettingsCategoryRow: View {
    let category: iOSSettingsCategory

    var body: some View {
        HStack(spacing: iOSSettingsMetrics.glyphLabelSpacing) {
            iOSIconTile(
                systemImage: category.icon,
                color: category.tint,
                size: iOSSettingsMetrics.glyphSlot,
                iconSize: 14
            )

            Text(category.title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(1)

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.dim)
        }
        .padding(.vertical, iOSSettingsMetrics.rowVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: iOSSettingsMetrics.minimumTapTarget, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct iOSSettingsEmptyRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .frame(width: 32, height: 32)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))

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

/// Name only. See `iOSMetricTile`, which this and it were two spellings of — same four properties,
/// same job, different glyph treatment, value size and label case.
struct iOSSettingsMetricTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        iOSMetricTile(title: title, value: value, icon: icon, color: color)
    }
}

struct iOSSettingsInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            // Label half of a label/value pair: `subdued`, not `dim` — `dim` is for
            // genuinely de-emphasized content, and these labels are ordinary reading text.
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.subdued)

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

struct iOSSettingsCapabilityRow: View {
    let capability: iOSMobileCapability

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: capability.status.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(capability.status.color)
                .frame(width: 28, height: 28)
                .background(capability.status.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(capability.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(capability.detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Text(capability.status.title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(capability.status.color)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(capability.status.color.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }
}

// MARK: - Soft-elevation card shell

/// Local stand-in for the shared `CadenceSettingsCard` (`Shared/CadenceSettingsSharedViews.swift`).
/// The shared component keeps its original hard-border, radius-12 treatment because macOS
/// settings and `iPadInboxView` still rely on it as-is. **Every** iOS settings section now
/// uses this instead — `iOSCalendarSettingsSection` and `iOSNotificationsSettingsSection`
/// were the last two holdouts — so the surface reads as one card family on the shared
/// radius scale with soft elevation rather than a hairline border.
struct iOSSettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusCard, shadowRadius: 14, shadowY: 6)
    }
}

/// Local stand-in for the shared `CadenceSettingsHeader`, same layout, riding on
/// `iOSSettingsCard`'s soft-elevation styling instead of the shared hard-border card.
///
/// It used to take arbitrary trailing content, and every caller passed a
/// `CadenceSettingsStatusBadge` — which, on the category the app opens to, was a green pill
/// repeating the value of the *first setting on the screen below it*. A header that answers a
/// question the next row answers is a second place for the same fact to go stale, so the slot is
/// gone rather than parameterised.
struct iOSSettingsPageHeader: View {
    /// Only set where this header is the top of a pushed screen whose navigation bar is hidden, so
    /// the word "Settings" survives the bar it used to live in. Elsewhere the title alone is the
    /// category name and an eyebrow would just label the label.
    var eyebrow: String? = nil
    let title: String
    let icon: String
    let tint: Color
    /// Set on iPhone, where this row is the top of the screen. See
    /// `iOSHidesCompactNavigationBar()`.
    var onBack: (() -> Void)? = nil

    var body: some View {
        // `iOSSettingsCard` supplies the padding, hence `padded: false`; everything inside the card
        // is the shared header. It used to draw its own rounded square instead of `iOSIconTile` and
        // set its title `.semibold` at 18pt while the other five page headers were bold — two
        // differences with no reason behind either.
        iOSSettingsCard {
            iOSPageHeader(
                eyebrow: eyebrow,
                title: title,
                systemImage: icon,
                color: tint,
                onBack: onBack,
                padded: false
            )
        }
    }
}
#endif
