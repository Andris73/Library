//
//  AudnexusClient.swift
//  Library
//
//  Thin client for Audnexus (api.audnex.us) — the keyless, Audible-derived
//  metadata service Audiobookshelf itself uses. Keyed by Audible ASIN, it's the
//  most reliable way to learn a book's series + authoritative position + full
//  release date, since the user's owned audiobooks carry an ASIN far more often
//  than a shared ISBN.
//
//  Per-book only: Audnexus can't enumerate a whole series (no series endpoint),
//  so it enriches the *owned* side; the full roster still comes from Hardcover.
//  Fails open — any error returns nil and the caller falls back to ABS data.
//

import Foundation

struct AudnexusSeries: Sendable {
    let asin: String?
    let name: String
    let position: Double?
}

struct AudnexusBook: Sendable {
    let asin: String
    let title: String
    let releaseYear: Int?
    let series: [AudnexusSeries]
}

enum AudnexusClient {
    /// Look up a book by Audible ASIN. `region` must match the marketplace the
    /// ASIN belongs to or Audnexus returns 404.
    static func book(asin: String, region: String = "us") async -> AudnexusBook? {
        let trimmed = asin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var components = URLComponents(string: "https://api.audnex.us/books/\(trimmed)") else { return nil }
        components.queryItems = [URLQueryItem(name: "region", value: region)]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Library/1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        var series = [AudnexusSeries]()
        for key in ["seriesPrimary", "seriesSecondary"] {
            guard let entry = json[key] as? [String: Any], let name = entry["name"] as? String else { continue }
            let position = (entry["position"] as? String).flatMap { Double($0) } ?? (entry["position"] as? Double)
            series.append(AudnexusSeries(asin: entry["asin"] as? String, name: name, position: position))
        }

        return AudnexusBook(
            asin: trimmed,
            title: (json["title"] as? String) ?? "",
            releaseYear: (json["releaseDate"] as? String).flatMap(year),
            series: series)
    }

    private static func year(_ value: String) -> Int? {
        guard let range = value.range(of: "\\d{4}", options: .regularExpression) else { return nil }
        return Int(value[range])
    }
}
