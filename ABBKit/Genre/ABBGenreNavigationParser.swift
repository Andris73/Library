import Foundation
import SwiftSoup

public struct ABBGenreNavigationParser {
    public static func parse(from html: String, baseURL: URL) throws -> [ABBGenre] {
        let doc = try SwiftSoup.parse(html)

        let genreLinks = try selectGenreLinks(doc)
        guard !genreLinks.isEmpty else {
            throw ABBError.parsingFailed(reason: "No genre links found in navigation")
        }

        return try genreLinks.compactMap { link -> ABBGenre? in
            try parseLink(link, baseURL: baseURL)
        }
    }

    private static func selectGenreLinks(_ doc: Document) throws -> Elements {
        let selectors = [
            "#nav-menu .menu-item a[href*='/audio-books/type/']",
            ".nav-menu .menu-item a[href*='/audio-books/type/']",
            ".menu-header-container .menu-item a[href*='/audio-books/type/']",
            "#menu-header-menu a[href*='/audio-books/type/']",
            ".menu a[href*='/audio-books/type/']",
            "a[href*='/audio-books/type/']",
        ]
        for selector in selectors {
            let links = try doc.select(selector)
            if !links.isEmpty { return links }
        }
        return Elements()
    }

    private static func parseLink(_ link: Element, baseURL: URL) throws -> ABBGenre? {
        let href = try link.attr("href")
        guard !href.isEmpty else { return nil }

        guard let url = URL(string: href, relativeTo: baseURL)?.absoluteURL else { return nil }

        let pathComponents = url.pathComponents
        guard let typeIndex = pathComponents.firstIndex(of: "type"),
              typeIndex + 1 < pathComponents.count
        else { return nil }

        let slug = pathComponents[typeIndex + 1].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !slug.isEmpty else { return nil }

        let name = try link.text().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        return ABBGenre(id: slug, name: name, slug: slug)
    }
}
