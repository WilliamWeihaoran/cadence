import SwiftUI

/// **The colour a list-board column's dot draws, decided once for both boards** ([[T-11221]],
/// one app on two platforms, [[T-8201]]).
///
/// The two boards each spelled this. The Mac's section column drew Default in `Theme.dim` and
/// every other column in its stored hex, turning green while it was completed or settling; the iOS
/// board drew every configured column -- Default included -- in its stored hex, so the same list's
/// Default column was a neutral grey dot on the Mac and a slate-blue one on an iPad. A column's
/// colour is not a pointer, touch or width question, so there is one answer: Default is neutral,
/// which is the Mac's reading. The model does not force Default's hex: `Area`/`Project`'s
/// `normalizedSectionConfigs` refills it with `TaskSectionDefaults.defaultColorHex` only when it
/// is EMPTY, so whatever Default stores is either that colour nobody chose or a pick that no board
/// draws -- which is why neither column editor offers Default a colour ([[T-11222]] (c),
/// [[T-12070]]).
///
/// A value rather than a `Color` so `CadenceTests`, which builds for macOS and never compiles
/// `Cadence/iOS/`, can pin the decision both boards read.
nonisolated enum CadenceBoardColumnTint: Equatable, Sendable {
    /// Completed, or settling into it: `Theme.green`.
    case completed
    /// The Default column, which has no colour of its own: `Theme.dim`.
    case neutral
    /// A configured column's own colour.
    case section(hex: String)
    /// A column the list no longer configures -- a name that exists only on a task -- which has no
    /// colour to read, so it takes the list's. No board draws such a column since [[T-11222]] (b)
    /// filed its cards under Default (`ListBoardCardFiling`); kept as the nil-config answer.
    case listAccent

    /// The column's own colour, before its lifecycle: what the Mac column's chrome and drop ring are
    /// tinted with.
    static func base(for config: TaskSectionConfig?) -> CadenceBoardColumnTint {
        guard let config else { return .listAccent }
        return config.isDefault ? .neutral : .section(hex: config.colorHex)
    }

    /// The header dot: the base colour, or green once the column is completed or settling.
    static func dot(
        for config: TaskSectionConfig?,
        isPendingCompletion: Bool = false
    ) -> CadenceBoardColumnTint {
        if config?.isCompleted == true || isPendingCompletion { return .completed }
        return base(for: config)
    }

    @MainActor func color(listAccent: Color) -> Color {
        switch self {
        case .completed: Theme.green
        case .neutral: Theme.dim
        case .section(let hex): Color(hex: hex)
        case .listAccent: listAccent
        }
    }
}

/// **The "Completed" / "Completing…" line under a column's header** ([[T-11221]]).
///
/// The Mac's section column has always said it; the iOS board turned the dot green over a
/// completed column and said nothing, so the only word for the state was on one platform. The iOS
/// board has no control that completes a column (that is the list editor's), but a column completed
/// on the Mac syncs, and what it reads is not an input question.
nonisolated enum CadenceBoardColumnLifecycleCopy {
    static let completed = "Completed"
    static let completing = "Completing…"

    /// `nil` for an open column, which draws no line.
    static func label(isCompleted: Bool, isPendingCompletion: Bool = false) -> String? {
        if isCompleted { return completed }
        if isPendingCompletion { return completing }
        return nil
    }
}

/// **Which completion control a column offers, decided once for both column editors** ([[T-13101]],
/// one app on two platforms, [[T-8201]]).
///
/// The iOS list editor gave an archived column one button, Unarchive, because completing a column
/// whose open work archiving already cancelled is a second settle over that work. The Mac's
/// Show Archived board drew the same column with its header completion circle, the editor
/// popover's "Complete Column" / "Reopen Column" and the Cmd+Return route all still live, so an
/// archived column could be completed or reopened while staying archived on one platform and not
/// the other. Neither a pointer nor a touch answers which transitions a column has, so there is one
/// rule: Default has no lifecycle (`TaskSectionConfig.supportsLifecycle`, T-268), an archived
/// column offers only Unarchive, and every other column offers Complete or Reopen.
nonisolated enum CadenceBoardColumnLifecycleOffer {
    static func offersCompletionToggle(supportsLifecycle: Bool, isArchived: Bool) -> Bool {
        supportsLifecycle && !isArchived
    }

    static func offersCompletionToggle(_ config: TaskSectionConfig) -> Bool {
        offersCompletionToggle(supportsLifecycle: config.supportsLifecycle, isArchived: config.isArchived)
    }
}

/// The one drawing of that line, as `CadenceBoardColumnDueDateLine` is the one drawing of the due
/// date above it.
struct CadenceBoardColumnLifecycleLine: View {
    let label: String

    var body: some View {
        Text(label)
            .cadenceFont(.metadata, base: 9, weight: .semibold)
            .foregroundStyle(Theme.green)
    }
}
