//
//  LibraryOwnershipService.swift
//  Library
//
//  Decides whether an AudiobookBay result is already in the user's
//  Audiobookshelf library, so Discover shelves can hide titles the user
//  already owns. Backed by the app's online library search
//  (`LibraryKit.globalSearch`) with a session cache to keep the cost
//  bounded. Fails open: if ownership can't be determined (offline, error),
//  the title is shown.
//
//  AudiobookBay titles carry a lot of noise the server search chokes on
//  (subtitles, "Book 3", "(Unabridged)", a trailing " - Author"). We strip
//  that down to a core title before searching so the server actually
//  returns the matching book, then compare on word sets — authors included —
//  so "Rowling, J.K." and "J. K. Rowling" still line up.
//

import Foundation
import LibraryKit
import ABBKit

enum LibraryOwnershipService {
    private actor Cache {
        static let shared = Cache()
        private var owned: [String: Bool] = [:]

        func value(for key: String) -> Bool? { owned[key] }
        func set(_ value: Bool, for key: String) { owned[key] = value }
    }

    /// Returns only the results the user does **not** already own. A no-op when
    /// the setting is off.
    static func filterUnowned(_ results: [ABBSearchResult]) async -> [ABBSearchResult] {
        guard AppSettings.shared.hideOwnedTitles, !results.isEmpty else { return results }

        let flags = await withTaskGroup(of: (String, Bool).self) { group in
            var requested = Set<String>()
            for result in results {
                let cacheKey = key(title: result.title, author: result.author)
                guard requested.insert(cacheKey).inserted else { continue }
                let title = result.title
                let author = result.author
                group.addTask { (cacheKey, await isOwned(title: title, author: author)) }
            }
            var map = [String: Bool]()
            for await (cacheKey, owned) in group {
                map[cacheKey] = owned
            }
            return map
        }

        return results.filter { !(flags[key(title: $0.title, author: $0.author)] ?? false) }
    }

    static func isOwned(title: String, author: String?) async -> Bool {
        let cacheKey = key(title: title, author: author)
        if let cached = await Cache.shared.value(for: cacheKey) { return cached }
        let owned = await compute(title: title, author: author)
        await Cache.shared.set(owned, for: cacheKey)
        return owned
    }

    // MARK: - Internals

    private static func compute(title: String, author: String?) async -> Bool {
        let core = coreTitle(title)
        let queryTokens = tokens(core)
        guard !queryTokens.isEmpty else { return false }

        // Search the server with the cleaned core title. The noisy original
        // ("…: Subtitle, Book 3 (Unabridged)") frequently returns nothing.
        let items = (try? await LibraryKit.globalSearch(
            query: core,
            includeOnlineSearchResults: true,
            allowedItemTypes: [.audiobook])) ?? []
        guard !items.isEmpty else { return false }

        let authorTokens = author.map { tokens($0) } ?? []

        for case let book as Audiobook in items {
            let bookTokens = tokens(coreTitle(book.name))
            guard titlesMatch(queryTokens, bookTokens) else { continue }

            // With no author to disambiguate on either side, a title match is
            // enough. Otherwise require the author word sets to overlap.
            guard !authorTokens.isEmpty else { return true }
            let bookAuthorTokens = Set(book.authors.flatMap { tokens($0) })
            guard !bookAuthorTokens.isEmpty else { return true }
            if authorsMatch(authorTokens, bookAuthorTokens) { return true }
        }
        return false
    }

    /// Strips an AudiobookBay title down to the words that actually identify the
    /// book: drops the trailing " - Author", bracketed asides, series/volume
    /// markers, and edition words. The colon subtitle is kept — for series
    /// titles like "Mistborn: The Hero of Ages" the distinguishing part is after
    /// the colon, so dropping it would collapse every book to the series name.
    private static func coreTitle(_ title: String) -> String {
        var value = ABBSeriesParser.titleWithoutAuthor(title)
        value = value.replacingOccurrences(of: "\\([^)]*\\)", with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: "\\[[^\\]]*\\]", with: " ", options: .regularExpression)
        // "Book 3", "Vol. 2", "Volume 4", "Part 5", "#6" and anything after them.
        value = value.replacingOccurrences(
            of: "(?i)\\b(book|vol|volume|part|episode|no|number)\\b\\.?\\s*#?\\d+.*$",
            with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: "#\\s*\\d+.*$", with: " ", options: .regularExpression)
        value = value.replacingOccurrences(
            of: "(?i)\\b(unabridged|abridged|audiobook|a novel)\\b",
            with: " ", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Two titles match when one is a substring of the other or their
    /// significant word sets coincide (subset, ≥ 2 shared words).
    private static func titlesMatch(_ a: Set<String>, _ b: Set<String>) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }

        let aJoined = a.sorted().joined(separator: " ")
        let bJoined = b.sorted().joined(separator: " ")
        if aJoined.contains(bJoined) || bJoined.contains(aJoined) { return true }

        let shared = a.intersection(b)
        let smaller = min(a.count, b.count)
        return shared.count == smaller && smaller >= 2
    }

    /// Author word sets match order-independently ("Rowling, J.K." vs
    /// "J. K. Rowling") as long as they share the bulk of their words.
    private static func authorsMatch(_ a: Set<String>, _ b: Set<String>) -> Bool {
        let shared = a.intersection(b)
        guard !shared.isEmpty else { return false }
        let smaller = min(a.count, b.count)
        return shared.count >= max(1, smaller - 1)
    }

    private static func key(title: String, author: String?) -> String {
        normalize(coreTitle(title)) + "|" + normalize(author ?? "")
    }

    /// Lowercased alphanumeric words, dropping a few articles/conjunctions that
    /// add no signal to a title comparison.
    private static func tokens(_ value: String) -> Set<String> {
        let stopwords: Set<String> = ["the", "a", "an", "of", "and", "to", "in"]
        return Set(normalize(value).split(separator: " ").map(String.init))
            .subtracting(stopwords)
    }

    private static func normalize(_ value: String) -> String {
        let lowered = value.lowercased()
        let mapped = lowered.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }
}

extension Array where Element == ABBSearchResult {
    /// Applies both the explicit-content filter (sync) and the
    /// already-owned filter (async, network-backed) per the user's settings.
    func filteringHiddenIfNeeded() async -> [ABBSearchResult] {
        await LibraryOwnershipService.filterUnowned(filteringExplicitIfNeeded())
    }
}
