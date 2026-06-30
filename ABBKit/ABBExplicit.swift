import Foundation
import SwiftSoup

/// Detects whether an AudiobookBay item is flagged explicit. ABB marks such
/// titles with a "Sex Scenes" category: a `/audio-books/type/sex-scenes/`
/// link on detail pages, and plain text in the `Category:` line of listing
/// and search rows.
enum ABBExplicit {
    static let categoryName = "Sex Scenes"
    static let categorySlug = "sex-scenes"

    /// Detail page: categories are real anchors inside `div.postInfo`.
    static func isExplicit(detail doc: Document) -> Bool {
        if let anchors = try? doc.select("div.postInfo a[href*=\(categorySlug)]"), !anchors.array().isEmpty {
            return true
        }
        if let anchors = try? doc.select("div.postInfo a[rel~=category]") {
            for anchor in anchors.array() {
                if let text = try? anchor.text(), text.caseInsensitiveCompare(categoryName) == .orderedSame {
                    return true
                }
            }
        }
        return false
    }

    /// Listing/search row: categories are plain text in `.postInfo`, ahead of
    /// the `Language:` portion (keywords live after it and are ignored).
    static func isExplicit(postInfo text: String) -> Bool {
        let categoryPart = text.components(separatedBy: "Language:").first ?? text
        return categoryPart.range(of: categoryName, options: .caseInsensitive) != nil
    }
}
