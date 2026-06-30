import ABBKit
import LibraryKit

extension Array where Element == ABBSearchResult {
    /// Drops titles flagged explicit when the user has enabled the content
    /// filter. A no-op otherwise.
    func filteringExplicitIfNeeded() -> [ABBSearchResult] {
        guard AppSettings.shared.hideExplicitContent else { return self }
        return filter { !$0.isExplicit }
    }
}
