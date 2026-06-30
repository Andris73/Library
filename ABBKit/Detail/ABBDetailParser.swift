import Foundation
import SwiftSoup

public struct ABBDetailParser {
    private static let defaultTrackers = [
        "udp://tracker.opentrackr.org:1337/announce",
        "udp://tracker.internetwarriors.net:1337/announce",
        "udp://tracker.leechers-paradise.org:6969/announce",
        "udp://tracker.coppersurfer.tk:6969/announce",
        "udp://tracker.pirateparty.gr:6969/announce",
        "udp://tracker.cyberia.is:6969/announce",
    ]

    public static func parseBookDetail(from html: String, baseURL: URL) throws -> ABBBook {
        let doc = try SwiftSoup.parse(html)

        guard let infoHash = try extractInfoHash(from: doc) else {
            throw ABBError.noInfoHashFound
        }

        let title = try extractTitle(from: doc)
        let id = UUID().uuidString

        let link = try doc.select("link[rel=canonical]").first()
            .flatMap { e -> URL? in
                let href = try e.attr("href")
                return href.isEmpty ? nil : URL(string: href)
            } ?? doc.select("meta[property='og:url']").first()
            .flatMap { e -> URL? in
                let content = try e.attr("content")
                return content.isEmpty ? nil : URL(string: content)
            } ?? baseURL

        let author = try doc.select("span.author, .desc [itemprop=author].author").first()?.text()
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? doc.select(".author, [class*=author]").first()?.text()
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        let narrators = try doc.select("span.narrator").map {
            try $0.text().trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        let narrator: String?
        if narrators.isEmpty {
            narrator = try doc.select(".narrator, [class*=narrator]").first()?.text()
                .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        } else {
            narrator = narrators.joined(separator: ", ")
        }

        let format = try doc.select("span.format, [itemprop=encodingFormat]").first()?.text()
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let bitrate = try doc.select("span.bitrate, [itemprop=bitrate]").first()?.text()
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let abridged = try doc.select("span.is_abridged").first()?.text()
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let language = try doc.select("span.language, [itemprop=inLanguage]").first()?.text()
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        let description = try extractDescription(from: doc)
        let size = try extractFileSize(from: doc)

        let coverURL = try doc.select("img[itemprop=image]").first()
            .flatMap { img -> URL? in
                let src = try img.attr("src")
                return src.isEmpty ? nil : URL(string: src, relativeTo: baseURL)?.absoluteURL
            } ?? doc.select("meta[property='og:image']").first()
            .flatMap { e -> URL? in
                let content = try e.attr("content")
                return content.isEmpty ? nil : URL(string: content)
            } ?? doc.select(".postContent .center img, img.cover, [class*=cover] img, .poster img").first()
            .flatMap { img -> URL? in
                let src = try img.attr("src")
                return src.isEmpty ? nil : URL(string: src, relativeTo: baseURL)?.absoluteURL
            }

        let trackers = try extractTrackers(from: doc)
        let comments = try extractComments(from: doc, baseURL: baseURL)
        let isExplicit = ABBExplicit.isExplicit(detail: doc)

        return ABBBook(
            id: id,
            title: title,
            url: link,
            author: author,
            narrator: narrator,
            series: nil,
            seriesPosition: nil,
            year: nil,
            bookDescription: description,
            coverURL: coverURL,
            infoHash: infoHash,
            trackers: trackers,
            size: size,
            language: language,
            bitrate: bitrate,
            format: format,
            abridged: abridged,
            comments: comments,
            isExplicit: isExplicit
        )
    }

    /// The `.desc` block leads with a metadata paragraph (author/format/etc.)
    /// followed by the actual synopsis paragraphs. Keep only the paragraphs
    /// that don't carry the metadata spans.
    private static func extractDescription(from doc: Document) throws -> String? {
        guard let container = try doc.select(".desc, [itemprop=description]").first() else {
            return try doc.select(".description, #description, article p").first()?.text()
                .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }

        var paragraphs = [String]()
        for paragraph in try container.select("p") {
            let metadataSpanCount = try paragraph.select(".author, .narrator, .format, .bitrate, .is_abridged").size()
            if metadataSpanCount > 0 { continue }
            let text = try paragraph.text().trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { paragraphs.append(text) }
        }

        if paragraphs.isEmpty {
            return try container.text().trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        return paragraphs.joined(separator: "\n\n")
    }

    private static func extractFileSize(from doc: Document) throws -> String? {
        for row in try doc.select("table tr") {
            let cells = try row.select("td")
            guard cells.size() >= 2 else { continue }
            let label = try cells.get(0).text().lowercased()
            if label.contains("file size") {
                return try cells.get(1).text().trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            }
        }
        return nil
    }

    private static func extractComments(from doc: Document, baseURL: URL) throws -> [ABBComment] {
        var comments = [ABBComment]()
        for item in try doc.select("ul.commentList > li, .commentList li[itemprop=review]") {
            guard let author = try item.select(".commentAuthor, [itemprop=name]").first()?.text()
                .trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty else {
                continue
            }

            let date = try item.select("[itemprop=dateCreated]").first()?.text()
                .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            let body = try item.select("[itemprop=reviewBody]").first()?.text()
                .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? item.select(".commentRight p").last()?.text().trimmingCharacters(in: .whitespacesAndNewlines)
                ?? ""
            let filledStars = try item.select("img[src*=star_on]").size()
            let avatarURL = try item.select(".commentLeft img, img.avatar").first()
                .flatMap { img -> URL? in
                    let src = try img.attr("src")
                    return src.isEmpty ? nil : URL(string: src, relativeTo: baseURL)?.absoluteURL
                }
            let rawID = (try? item.attr("id")) ?? ""
            let id = rawID.isEmpty ? UUID().uuidString : rawID

            comments.append(ABBComment(
                id: id,
                author: author,
                date: date,
                rating: filledStars > 0 ? filledStars : nil,
                body: body,
                avatarURL: avatarURL
            ))
        }
        return comments
    }

    private static func extractTitle(from doc: Document) throws -> String {
        if let ogTitle = try doc.select("meta[property='og:title']").first() {
            let content = try ogTitle.attr("content").trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty { return content }
        }
        if let h1 = try doc.select(".postTitle h1, .entry-title, h1").first() {
            return try h1.text().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "Unknown"
    }

    static func extractInfoHash(from doc: Document) throws -> String? {
        if let magnetLink = try doc.select("a[href^='magnet:']").first() {
            let href = try magnetLink.attr("href")
            if let hash = extractHashFromMagnet(href) {
                return hash
            }
        }
        if let magnetEl = try doc.select("#magnetLink").first() {
            let text = try magnetEl.text().trimmingCharacters(in: .whitespacesAndNewlines)
            if isValidHash(text) { return text }
        }
        if let codeEl = try doc.select("code").first() {
            let text = try codeEl.text().trimmingCharacters(in: .whitespacesAndNewlines)
            if isValidHash(text) { return text }
        }
        let bodyText = try doc.text()
        let pattern = /[a-fA-F0-9]{40}/
        if let match = bodyText.firstMatch(of: pattern) {
            return String(match.output)
        }
        return nil
    }

    private static func extractHashFromMagnet(_ magnet: String) -> String? {
        guard let range = magnet.range(of: "urn:btih:") else { return nil }
        let hash = magnet[range.upperBound...].prefix(40)
        return String(hash)
    }

    private static func isValidHash(_ hash: String) -> Bool {
        hash.count == 40 && hash.allSatisfy { $0.isHexDigit }
    }

    private static func extractTrackers(from doc: Document) throws -> [String] {
        var trackers: [String] = []
        for el in try doc.select("a[href^='udp://'], a[href^='http://tracker'], a[href^='https://tracker'], .tracker-list li, .trackers a") {
            let text = try el.attr("href").nilIfEmpty ?? el.text().nilIfEmpty
            if let text, text.hasPrefix("udp://") || text.hasPrefix("http") {
                trackers.append(text)
            }
        }
        return trackers.isEmpty ? defaultTrackers : trackers
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
