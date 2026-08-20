// PrivacyDataResetService moved to Services/CadencePrivacyDataResetService.swift so iOS and macOS
// share one "delete my data" — it imported only Foundation and SwiftData and had no AppKit in it,
// so the `#if os(macOS)` was an accident of where it was written, and the shipped privacy policy
// promised iOS a reset it could not reach. (Prefixed file, unprefixed type, exactly like
// Services/CadenceRemindersManager.swift; this tombstone owns the old name.)
