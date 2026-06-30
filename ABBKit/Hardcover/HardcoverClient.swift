import Foundation
import os

public struct HardcoverSeriesBook: Sendable, Hashable {
    public let position: Double?
    public let title: String

    public init(position: Double?, title: String) {
        self.position = position
        self.title = title
    }
}

public struct HardcoverSeries: Sendable, Hashable {
    public let name: String
    public let description: String?
    /// Books in series order (position ascending), including translated/edition
    /// duplicates that share a position.
    public let books: [HardcoverSeriesBook]

    public init(name: String, description: String?, books: [HardcoverSeriesBook]) {
        self.name = name
        self.description = description
        self.books = books
    }
}

/// The series a single book belongs to, as reported by Hardcover.
public struct HardcoverBookSeries: Sendable, Hashable {
    public let name: String
    public let slug: String?
    public let position: Double?

    public init(name: String, slug: String?, position: Double?) {
        self.name = name
        self.slug = slug
        self.position = position
    }
}

/// Minimal client for the Hardcover GraphQL API (https://docs.hardcover.app).
///
/// Uses a user-supplied personal API token. Hardcover disables `_ilike` and
/// caps query depth at 3, so series lookup is a two-step flow: a Typesense-backed
/// `search` to resolve the series slug, then a shallow relational query for the
/// ordered roster and description. All failures are surfaced as `nil`/throws so
/// callers can fall back to AudiobookBay-only behavior.
public struct HardcoverClient {
    public static let endpoint = URL(string: "https://api.hardcover.app/v1/graphql")!

    private static let logger = Logger(subsystem: "com.bookwave.ABBKit", category: "Hardcover")

    public enum HardcoverError: Error {
        case invalidToken
        case requestFailed(status: Int)
        case decodingFailed
    }

    /// Validates a token by running the documented `me` query, returning the
    /// account username on success.
    public static func verifyToken(_ token: String) async throws -> String {
        let json = try await perform(query: "query { me { username } }", variables: [:], token: token)
        let data = json["data"] as? [String: Any]
        if let array = data?["me"] as? [[String: Any]], let username = array.first?["username"] as? String {
            return username
        }
        if let object = data?["me"] as? [String: Any], let username = object["username"] as? String {
            return username
        }
        throw HardcoverError.invalidToken
    }

    /// Best-effort series lookup by name (optionally disambiguated by author).
    /// Returns `nil` on any failure.
    public static func fetchSeries(name: String, author: String? = nil, token: String) async -> HardcoverSeries? {
        do {
            let searchQuery = "query Search($q: String!) { search(query: $q, query_type: \"Series\", per_page: 5) { results } }"
            let searchJSON = try await perform(query: searchQuery, variables: ["q": name], token: token)
            guard let slug = bestSeriesSlug(from: searchJSON, wanted: name, author: author) else { return nil }

            return await fetchSeries(slug: slug, fallbackName: name, token: token)
        } catch {
            return nil
        }
    }

    /// Fetches a series roster + description directly by slug.
    public static func fetchSeries(slug: String, fallbackName: String, token: String) async -> HardcoverSeries? {
        do {
            let rosterQuery = """
            query Roster($slug: String!) {
              series(where: {slug: {_eq: $slug}}, limit: 1) {
                name
                description
                book_series(order_by: {position: asc}) {
                  position
                  book { title }
                }
              }
            }
            """
            let rosterJSON = try await perform(query: rosterQuery, variables: ["slug": slug], token: token)

            guard let data = rosterJSON["data"] as? [String: Any],
                  let seriesArray = data["series"] as? [[String: Any]],
                  let series = seriesArray.first else {
                return nil
            }

            let seriesName = (series["name"] as? String) ?? fallbackName
            let description = (series["description"] as? String)?.trimmedNonEmpty

            var books = [HardcoverSeriesBook]()
            if let bookSeries = series["book_series"] as? [[String: Any]] {
                for entry in bookSeries {
                    guard let book = entry["book"] as? [String: Any], let title = book["title"] as? String else { continue }
                    let position = entry["position"] as? Double
                    books.append(HardcoverSeriesBook(position: position, title: title))
                }
            }

            return HardcoverSeries(name: seriesName, description: description, books: books)
        } catch {
            return nil
        }
    }

    /// Detects the series a single book belongs to (name, slug, position) via a
    /// Book search. Useful for name-only series where the AudiobookBay title has
    /// no number. Returns `nil` on any failure or no confident match.
    public static func fetchBookSeries(title: String, author: String?, token: String) async -> HardcoverBookSeries? {
        do {
            let searchQuery = "query Search($q: String!) { search(query: $q, query_type: \"Book\", per_page: 5) { results } }"
            let json = try await perform(query: searchQuery, variables: ["q": title], token: token)

            guard let data = json["data"] as? [String: Any],
                  let search = data["search"] as? [String: Any] else { return nil }
            var results: [String: Any]?
            if let object = search["results"] as? [String: Any] {
                results = object
            } else if let string = search["results"] as? String, let stringData = string.data(using: .utf8) {
                results = (try? JSONSerialization.jsonObject(with: stringData)) as? [String: Any]
            }
            guard let hits = results?["hits"] as? [[String: Any]] else { return nil }

            let titleLower = title.lowercased()
            let authorLower = author?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            var best: (series: HardcoverBookSeries, score: Int)?

            for hit in hits {
                guard let document = hit["document"] as? [String: Any],
                      let featuredSeries = document["featured_series"] as? [String: Any],
                      let seriesObject = featuredSeries["series"] as? [String: Any],
                      let seriesName = seriesObject["name"] as? String else {
                    continue
                }

                // When the author is known, require it to match to avoid linking
                // to a same-titled book from a different author/series.
                if let authorLower, !authorLower.isEmpty {
                    let authors = (document["author_names"] as? [String])?.map { $0.lowercased() } ?? []
                    let matches = authors.contains { $0.contains(authorLower) || authorLower.contains($0) }
                    if !matches { continue }
                }

                let documentTitle = (document["title"] as? String)?.lowercased() ?? ""
                var score = 0
                if documentTitle == titleLower {
                    score += 3
                } else if !documentTitle.isEmpty, titleLower.contains(documentTitle) || documentTitle.contains(titleLower) {
                    score += 1
                }

                let slug = seriesObject["slug"] as? String
                let position = (featuredSeries["position"] as? Double) ?? (document["featured_series_position"] as? Double)
                let candidate = HardcoverBookSeries(name: seriesName, slug: slug, position: position)
                if best == nil || score > best!.score {
                    best = (candidate, score)
                }
            }

            return best?.series
        } catch {
            return nil
        }
    }

    // MARK: - Internals

    private static func bestSeriesSlug(from json: [String: Any], wanted: String, author: String?) -> String? {
        guard let data = json["data"] as? [String: Any],
              let search = data["search"] as? [String: Any] else {
            return nil
        }

        var results: [String: Any]?
        if let object = search["results"] as? [String: Any] {
            results = object
        } else if let string = search["results"] as? String, let data = string.data(using: .utf8) {
            results = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }

        guard let hits = results?["hits"] as? [[String: Any]] else { return nil }

        let wantedLower = wanted.lowercased()
        let authorLower = author?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var best: (slug: String, score: Int)?
        for hit in hits {
            guard let document = hit["document"] as? [String: Any],
                  let slug = document["slug"] as? String,
                  let name = document["name"] as? String else {
                continue
            }
            let nameLower = name.lowercased()
            var score: Int
            if nameLower == wantedLower {
                score = 3
            } else if nameLower.contains(wantedLower) || wantedLower.contains(nameLower) {
                score = 2
            } else {
                continue
            }
            // Disambiguate same-named series (e.g. two "Fleabag" series) by author.
            if let authorLower, !authorLower.isEmpty,
               let documentAuthor = (document["author_name"] as? String)?.lowercased(), !documentAuthor.isEmpty,
               documentAuthor.contains(authorLower) || authorLower.contains(documentAuthor) {
                score += 2
            }
            if best == nil || score > best!.score {
                best = (slug, score)
            }
        }
        return best?.slug
    }

    private static func perform(query: String, variables: [String: Any], token: String) async throws -> [String: Any] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let authorization = trimmed.lowercased().hasPrefix("bearer ") ? trimmed : "Bearer \(trimmed)"
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.setValue("Library (https://github.com/Andris73/Library)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let body: [String: Any] = ["query": query, "variables": variables]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HardcoverError.requestFailed(status: -1)
        }
        guard http.statusCode == 200 else {
            logger.error("Hardcover HTTP \(http.statusCode, privacy: .public)")
            if http.statusCode == 401 { throw HardcoverError.invalidToken }
            throw HardcoverError.requestFailed(status: http.statusCode)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HardcoverError.decodingFailed
        }
        if let errors = json["errors"] as? [[String: Any]], !errors.isEmpty {
            let messages = errors.compactMap { $0["message"] as? String }.joined(separator: "; ")
            logger.error("Hardcover GraphQL errors: \(messages, privacy: .public)")
        }
        return json
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
