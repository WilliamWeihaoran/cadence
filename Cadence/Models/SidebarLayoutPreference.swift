import SwiftData
import Foundation

/// The user's sidebar layout: which nav rows they want to see, and in what order.
///
/// **A `@Model` rather than `@AppStorage` because the owner asked for it to follow them across
/// devices** (T-1274). `mainSidebarWidth` stays device-local — a window's width is about the
/// window — but *which sections I use* is about the person, and they use a Mac, an iPhone and an
/// iPad.
///
/// **Additive by construction.** CloudKit has been in Production since 2026-09-05 and this project
/// has no `SchemaMigrationPlan`, so the layout could not be a re-type of anything already stored.
/// A new model type adds a record type and changes no existing column, which is the one shape that
/// cannot cost a device its data.
///
/// ## Why two strings rather than a to-many
///
/// A to-many of ordered rows would be four more CloudKit records for a preference that is two short
/// lists, and every reader would have to sort them. These are the same comma-separated
/// `CadenceFeatureDestination` raw values the device-local `sidebarTabOrder` / `sidebarHiddenTabs`
/// preferences already hold, so the parse is one shared spelling
/// (`CadenceSidebarLayoutPreferenceStore`) and the legacy local values remain readable as the
/// fallback for a device that has never synced one of these rows.
///
/// ## What a destination missing from `orderRaw` means
///
/// **Nothing happens to it.** `orderRaw` names only what the user actually dragged, so a
/// destination the string has never seen — including a case a future build adds to
/// `CadenceFeatureDestination` — keeps its declared slot in
/// `CadenceSidebarLayout.primaryDestinations` and stays visible. Visibility is opt-*out*:
/// `hiddenRaw` lists what to hide, so an unseen row is a row that is shown. The alternative, a
/// stored "visible" list, would silently hide every future destination on every device that still
/// held an older list.
///
/// Raw values this build does not recognise are dropped on read rather than preserved, which is the
/// deliberate cost of that choice: a row added by a newer build and reordered there loses its slot
/// (not its visibility) on an older one.
///
/// ## Duplicates
///
/// Two devices can each create a row before either sees the other's. There is no unique constraint
/// to lean on — CloudKit forbids them — so the reader picks **the most recently updated row**, with
/// the `id` string as the tie-break so every device picks the same one. Writes go to the picked
/// row, which keeps it the newest; the losers are inert rather than deleted, because deleting a row
/// another device is mid-sync with is how a preference becomes a data-loss bug.
@Model final class SidebarLayoutPreference {
    var id: UUID = UUID()
    /// Comma-separated `CadenceFeatureDestination` raw values, in the order the user dragged them.
    /// Names only the rows the user moved; see the type's note on absent destinations.
    var orderRaw: String = ""
    /// Comma-separated `CadenceFeatureDestination` raw values the user has hidden.
    var hiddenRaw: String = ""
    var createdAt: Date = Date()
    /// The last edit on any device. The newest row wins when more than one exists.
    var updatedAt: Date = Date()

    init(orderRaw: String = "", hiddenRaw: String = "", updatedAt: Date = Date()) {
        self.orderRaw = orderRaw
        self.hiddenRaw = hiddenRaw
        self.createdAt = updatedAt
        self.updatedAt = updatedAt
    }
}
