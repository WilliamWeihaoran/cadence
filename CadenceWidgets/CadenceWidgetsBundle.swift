import SwiftUI
import WidgetKit

@main
struct CadenceWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CadenceTodayTasksWidget()
        CadenceHabitCheckInWidget()
        CadenceMilestoneMomentumWidget()
        CadenceCalendarSnapshotWidget()
    }
}
