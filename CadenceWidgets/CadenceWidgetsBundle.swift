import SwiftUI
import WidgetKit

// **Two widgets, not four.** [[T-2078]] retired `CadenceHabitCheckInWidget` and
// `CadenceMilestoneMomentumWidget` along with the habits and goals surfaces they drew. A
// `WidgetBundle` body *is* the registration — a kind that is not listed here is not shipped, and
// WidgetKit has no API to retire a kind gracefully, so an installed tile of either retired kind
// becomes an empty placeholder the owner removes by hand. The `Habit` / `Goal` models and the two
// snapshot-building support types stay, so putting an entry back here is the whole restoration.
@main
struct CadenceWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CadenceTodayTasksWidget()
        CadenceCalendarSnapshotWidget()
    }
}
