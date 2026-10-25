import Foundation

/// Builds a dictionary keyed by a model id, where two rows sharing that id keep the first.
///
/// **Why not `Dictionary(uniqueKeysWithValues:)`** (T-6451). That initializer traps on a duplicate
/// key, and a model `id` here is an app-level attribute with no uniqueness — CloudKit forbids
/// `.unique`, an archive import writes ids verbatim, and a restore or a CloudKit round trip can
/// leave the *same* row present twice. A map built that way over `AppTask` or
/// `MarkdownImageAsset` rows crashed Notes, the task inspector and iOS Focus on every open until
/// the data was fixed, while search (`MarkdownTaskEmbedSupport.titles(for:)`) and export already
/// survived the same rows by keeping the first. Every id-keyed map over live model rows goes
/// through here so the two cannot disagree again.
///
/// First wins, not last: it matches the two pre-existing tolerant sites and
/// `MarkdownImageAssetService.renderAsset(for:in:)`, which resolves an id with `first(where:)`.
nonisolated enum CadenceIdentityMap {
    static func firstWins<Key: Hashable, Value>(_ pairs: some Sequence<(Key, Value)>) -> [Key: Value] {
        Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }
}
