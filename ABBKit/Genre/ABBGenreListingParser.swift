import Foundation
import SwiftSoup

public struct ABBGenreListingParser {
    public static func parseListing(from html: String, baseURL: URL) throws -> [ABBSearchResult] {
        let doc = try SwiftSoup.parse(html)

        let rows = try selectListingRows(doc)
        return try rows.compactMap { row -> ABBSearchResult? in
            try parseRow(row, baseURL: baseURL)
        }
    }

    public static func genreURL(baseURL: URL, slug: String, page: Int = 1) -> URL {
        var path = "audio-books/type/\(slug)/"
        if page > 1 {
            path += "page/\(page)/"
        }
        return URL(string: path, relativeTo: baseURL)?.absoluteURL ?? baseURL.appendingPathComponent(path)
    }

    private static func selectListingRows(_ doc: Document) throws -> Elements {
        let selectors = [
            "#content div.post",
            "#content .post",
            ".post",
        ]
        for selector in selectors {
            let posts = try doc.select(selector)
            if !posts.isEmpty { return posts }
        }
        return Elements()
    }

    private static func parseRow(_ row: Element, baseURL: URL) throws -> ABBSearchResult? {
        let titleElement = try row.select(".postTitle h2 a, .post-title h2 a, h2 a, .entry-title a").first()
        guard let titleElement else { return nil }

        let href = try titleElement.attr("href")
        guard !href.isEmpty else { return nil }

        let detailURL: URL
        if href.hasPrefix("http") || href.hasPrefix("https") {
            guard let url = URL(string: href) else { return nil }
            detailURL = url
        } else {
            guard let url = URL(string: href, relativeTo: baseURL)?.absoluteURL else { return nil }
            detailURL = url
        }

        let title = try titleElement.text().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        let id = detailURL.lastPathComponent
        let postContent = try row.select(".postContent, .entry-content, .post-excerpt").first()?.text() ?? ""

        let author = extractField(from: postContent, field: "Author") ?? (try? row.select(".author, [class*=author]").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines))
        let narrator = extractField(from: postContent, field: "Narrator") ?? (try? row.select(".narrator, [class*=narrator]").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines))
        let series = extractField(from: postContent, field: "Series") ?? (try? row.select(".series, [class*=series]").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines))
        let year = extractField(from: postContent, field: "Year") ?? (try? row.select(".year, [class*=year]").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines))

        let coverURL = try row.select("img[src]").first().flatMap { img -> URL? in
            let src = try img.attr("src")
            return URL(string: src, relativeTo: baseURL)?.absoluteURL
        }

        let infoHash = try row.select("[class*=hash], .info-hash, code").first()?.text()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let postInfo = try row.select(".postInfo").first()?.text() ?? ""
        let isExplicit = ABBExplicit.isExplicit(postInfo: postInfo)

        return ABBSearchResult(
            id: id,
            title: title,
            detailURL: detailURL,
            author: author,
            narrator: narrator,
            series: series,
            year: year,
            coverURL: coverURL,
            infoHash: infoHash,
            isExplicit: isExplicit
        )
    }

    private static func extractField(from text: String, field: String) -> String? {
        let pattern = "\(field):\\s*([^\\n]+)"
        guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let match = text[range]
        let value = match.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\(field):", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
