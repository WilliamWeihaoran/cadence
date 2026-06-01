#if os(macOS)
enum MarkdownEditorSyncTiming {
    static let derivedStateRefreshDelay: UInt64 = 150_000_000
    static let fallbackContentCommitDelay: UInt64 = 15_000_000_000
}
#endif
