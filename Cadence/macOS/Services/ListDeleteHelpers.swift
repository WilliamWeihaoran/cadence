// Moved to `Cadence/Services/CadenceListDeleteHelpers.swift` (T-187): the three list/context
// delete cascades are cross-platform and were behind an `#if os(macOS)` that nothing in them
// needed, which is what left iOS unable to delete a list or a context at all.
