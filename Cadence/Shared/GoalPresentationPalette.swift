import SwiftUI

/// Colour for a goal's *kind* badge. Lived in `macOS/Views/GoalPickerViews.swift`, which meant iOS
/// had no way to say "this is an ongoing direction" in the same colour — so it said nothing at all.
enum GoalKindPalette {
    static func color(for kind: GoalKind) -> Color {
        switch kind {
        case .ongoing: return Theme.purple
        case .completable: return Theme.green
        case .maintenance: return Theme.blue
        }
    }
}

/// Colour and label for a goal's *status* badge. Extracted from macOS's `GoalStatusBadge` so the
/// two platforms cannot disagree about what "paused" looks like.
enum GoalStatusPalette {
    static func color(for status: GoalStatus) -> Color {
        switch status {
        case .active: return Theme.blue
        case .paused: return Theme.amber
        case .done: return Theme.green
        }
    }

    /// Uppercased because the badge is a chip, not a sentence.
    static func badgeLabel(for status: GoalStatus) -> String {
        switch status {
        case .active: return "ACTIVE"
        case .paused: return "PAUSED"
        case .done: return "DONE"
        }
    }
}
