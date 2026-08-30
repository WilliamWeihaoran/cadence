import Foundation

/// The area half of `CadencePickerSupport` — the two facts that are `Area`'s rather than the
/// picker's, and the name its call site reads it by.
///
/// **T-488.** `iOSListEditorSheet`'s Area row carried the defect T-446 had just removed from its
/// Context row, one line up the same `Form`: the trigger label resolved the selected id against
/// `areas.filter(\.isActive)` while `save()` resolved it against the unfiltered `@Query`, and the
/// popover offered only active areas. Complete or archive an area and every project still filed
/// under it opened showing **"None"** — and saved the inactive area straight back, because the two
/// halves were reading two different arrays. Nothing in the sheet could tell the user which area
/// the project was actually in.
///
/// A second, quieter disagreement went with it: an area with an empty name read "None" in the
/// trigger and "Untitled Area" in the list it opened.
///
/// Both are gone by construction now — one array, one rule — rather than by two call sites being
/// edited to match. See `CadencePickerSupport` for why this is a typealias over a generic instead
/// of a copy of `CadenceContextPickerSupport`.
typealias CadenceAreaPickerSupport = CadencePickerSupport<Area>

extension Area: CadencePickable {
    /// `isActive`, not `!isArchived`: an area has three states and a **completed** one is as
    /// retired from fresh choices as an archived one. That is the fact that differs from
    /// `Context`'s, and copying the context rule across is precisely the bug a near-copy would
    /// have shipped.
    var isOfferableInPicker: Bool { isActive }

    /// Declared in `CadenceTitleNormalization`, in `Models/`, for the same reason `Context`'s is:
    /// it is the tree every target compiles, so it is where a label the app and `CadenceMCPServer`
    /// both show has to live. Typing the words here instead would be a hit in
    /// `CadenceSharedConstantReuseSweepTests`.
    static var untitledPickerName: String { CadenceTitleNormalization.defaultAreaName }
}
