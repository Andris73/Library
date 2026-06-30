//
//  SeriesTrackingService.swift
//  Library
//
//  Powers the "New in Your Series" shelf. Looks at the series the user is
//  actively progressing through — their in-progress and recently-finished
//  audiobooks, the same signal behind the home screen's Continue Listening /
//  Continue Series shelves — asks Hardcover for each series' full roster, and
//  surfaces the books they don't have yet, resolved to AudiobookBay results so
//  they can be downloaded.
//
//  We read progress entities and resolve each to a full Audiobook rather than
//  scraping the home shelves: Audiobookshelf's minified home payloads routinely
//  drop the series metadata, so the full item is the only reliable source of a
//  book's series.
//
//  Audiobookshelf only knows what's in the library, so the canonical book list
//  has to come from Hardcover; the shelf is gated on a Hardcover token by its
//  caller. Everything is bounded (series count, missing-book count) and cached
//  for an hour so we stay well under Hardcover's 60 req/min.
//

import Foundation
import OSLog
import LibraryKit
import ABBKit

enum SeriesTrackingService {
    private static let logger = Logger(subsystem: "com.Library.app", category: "SeriesTracking")

    private actor Cache {
        static let shared = Cache()
        private var entry: (results: [ABBSearchResult], storedAt: Date)?
        private let lifetime: TimeInterval = 60 * 60

        func cached() -> [ABBSearchResult]? {
            guard let entry, entry.storedAt.distance(to: .now) < lifetime else { return nil }
            return entry.results
        }
        func store(_ results: [ABBSearchResult]) { entry = (results, .now) }
    }

    private struct TrackedSeries: Sendable {
        let name: String
        let author: String?
        let ownedTitles: [String]
        /// Highest series position the user already owns. Suggestions must come
        /// after this.
        let maxOwnedPosition: Double?
        /// Latest publication year owned, used to order suggestions when the
        /// series has no usable position numbers.
        let maxOwnedYear: Int?
    }

    /// A book to look for on AudiobookBay. `minYear`, when set, requires the
    /// resolved result's year to be at least that — the position-less fallback.
    private struct Candidate: Sendable {
        let title: String
        let seriesName: String
        let author: String?
        let minYear: Int?
    }

    /// Outcome of one AudiobookBay resolve, carrying diagnostics so an empty
    /// result can be told apart from "search returned nothing".
    private struct ResolveAttempt: Sendable {
        let result: ABBSearchResult?
        let rawCount: Int
        let bestScore: Double
        let query: String
        let htmlLen: Int
    }

    private struct SeriesRef: Sendable {
        let name: String
        let fragmentID: ItemIdentifier?
        let connectionID: ItemIdentifier.ConnectionID
        let libraryID: String
    }

    /// Results plus a short stage-by-stage trace, shown in the shelf's empty
    /// state so an unexpectedly-empty result can be diagnosed on-device.
    struct Outcome: Sendable {
        let results: [ABBSearchResult]
        let trace: String
    }

    private struct TrackResult: Sendable {
        let series: [TrackedSeries]
        let entities: Int
        let books: Int
        let refs: Int
    }

    /// For the series the user is actively listening to, resolve the roster
    /// books they're missing to downloadable AudiobookBay results. Owned-filtered
    /// and deduped.
    static func missingFromTrackedSeries(
        token: String,
        maxSeries: Int = 8,
        maxResults: Int = 18
    ) async -> Outcome {
        if let cached = await Cache.shared.cached() { return Outcome(results: cached, trace: "") }

        let tracked = await trackedSeries(limit: maxSeries)
        let series = tracked.series
        let head = "entities:\(tracked.entities) books:\(tracked.books) refs:\(tracked.refs)"
        guard !series.isEmpty else { return Outcome(results: [], trace: "\(head) series:0") }

        let perSeries = await withTaskGroup(of: (rosterFound: Bool, candidates: [Candidate]).self) { group in
            for entry in series {
                group.addTask { await missingTitles(for: entry, token: token) }
            }
            var all = [(rosterFound: Bool, candidates: [Candidate])]()
            for await part in group { all.append(part) }
            return all
        }
        let rosters = perSeries.filter { $0.rosterFound }.count
        let missing = perSeries.flatMap { $0.candidates }

        // Dedupe by title across series before the (network-heavy) resolve step.
        var seenTitle = Set<String>()
        let uniqueCandidates = missing.filter { seenTitle.insert(normalize($0.title)).inserted }

        let capped = Array(uniqueCandidates.prefix(maxResults))
        logger.info("missing titles: \(capped.map(\.title).joined(separator: " | "), privacy: .public)")
        // Resolve each missing book on AudiobookBay, serially (ABB sits behind
        // Cloudflare and dislikes concurrent hits).
        var attempts = [ResolveAttempt]()
        for candidate in capped {
            attempts.append(await resolveCandidate(candidate))
        }
        let resolved = attempts.compactMap { $0.result }
        let abbRaw = attempts.reduce(0) { $0 + max(0, $1.rawCount) }
        let abbBest = attempts.map { $0.bestScore }.max() ?? 0
        let searchDbg = attempts.map { "\($0.rawCount)" }.joined(separator: ",")
        let htmlMax = attempts.map(\.htmlLen).max() ?? 0
        let queriesDbg = attempts.map(\.query).joined(separator: " || ")

        // Safety net: a different edition could still be in the library, so run
        // the owned/explicit filter before showing anything. Dedupe by id.
        let visible = await resolved.filteringHiddenIfNeeded()
        var seen = Set<String>()
        let unique = visible.filter { seen.insert($0.id).inserted }

        let trace = "\(head) series:\(series.count) rosters:\(rosters) missing:\(uniqueCandidates.count) abb:\(resolved.count) raw:\(abbRaw) best:\(String(format: "%.2f", abbBest)) shown:\(unique.count) searches:[\(searchDbg)] html:\(htmlMax)\nq: \(queriesDbg)"
        logger.info("missing: \(trace, privacy: .public)")

        if !unique.isEmpty { await Cache.shared.store(unique) }
        return Outcome(results: unique, trace: trace)
    }

    // MARK: - Internals

    /// The series the user is actively progressing through, derived from their
    /// in-progress and recently-finished audiobooks. Each is resolved to its full
    /// owned roster so the missing-book diff is accurate.
    private static func trackedSeries(limit: Int) async -> TrackResult {
        let active = (try? await PersistenceManager.shared.progress.activeProgressEntities) ?? []
        let recent = (try? await PersistenceManager.shared.progress.recentlyFinishedEntities) ?? []
        let entities = active + recent
        logger.info("tracked: \(active.count, privacy: .public) active + \(recent.count, privacy: .public) finished entities")
        guard !entities.isEmpty else { return TrackResult(series: [], entities: 0, books: 0, refs: 0) }

        // Resolve each progress entity to a full Audiobook.
        let audiobooks: [Audiobook] = await withTaskGroup(of: Audiobook?.self) { group in
            for entity in entities {
                group.addTask {
                    // Resolve by primary/grouping/connection (not a fabricated
                    // ItemIdentifier with an empty libraryID, whose network path
                    // fails) so the full Audiobook — with its series — comes back.
                    let item = try? await ResolveCache.shared.resolve(
                        primaryID: entity.primaryID,
                        groupingID: entity.groupingID,
                        connectionID: entity.connectionID)
                    return item as? Audiobook
                }
            }
            var out = [Audiobook]()
            for await book in group {
                if let book { out.append(book) }
            }
            return out
        }

        // Unique series (by name) the user is actively listening to.
        var seen = Set<String>()
        var refs = [SeriesRef]()
        for book in audiobooks {
            guard let fragment = book.series.first else { continue }
            guard seen.insert(fragment.name.lowercased()).inserted else { continue }
            refs.append(SeriesRef(
                name: fragment.name,
                fragmentID: fragment.id,
                connectionID: book.id.connectionID,
                libraryID: book.id.libraryID))
        }
        logger.info("tracked: \(audiobooks.count, privacy: .public) audiobooks -> \(refs.count, privacy: .public) unique series")
        guard !refs.isEmpty else { return TrackResult(series: [], entities: entities.count, books: audiobooks.count, refs: 0) }

        let capped = Array(refs.prefix(limit))
        let resolved: [TrackedSeries] = await withTaskGroup(of: TrackedSeries?.self) { group in
            for ref in capped {
                group.addTask { await roster(for: ref) }
            }
            var out = [TrackedSeries]()
            for await tracked in group {
                if let tracked { out.append(tracked) }
            }
            return out
        }
        logger.info("tracked: resolved \(resolved.count, privacy: .public) series rosters")
        return TrackResult(series: resolved, entities: entities.count, books: audiobooks.count, refs: refs.count)
    }

    /// Fetch a series' full owned roster, using the series id from the book when
    /// present and falling back to a name lookup otherwise. Lists books via the
    /// items endpoint (filtered by series) rather than the single-series
    /// endpoint, which doesn't reliably carry the books array.
    private static func roster(for ref: SeriesRef) async -> TrackedSeries? {
        let seriesID: ItemIdentifier
        if let fragmentID = ref.fragmentID, !fragmentID.libraryID.isEmpty {
            seriesID = fragmentID
        } else if !ref.libraryID.isEmpty,
                  let byName = try? await ABSClient[ref.connectionID].seriesID(from: ref.libraryID, name: ref.name) {
            seriesID = byName
        } else {
            return nil
        }

        let books = (try? await ABSClient[ref.connectionID].audiobooks(
            filtered: seriesID, sortOrder: nil, ascending: nil, limit: nil, page: nil).0) ?? []
        guard !books.isEmpty else { return nil }

        let lowerName = ref.name.lowercased()
        // Prefer Audnexus (keyed by the owned book's ASIN) for an authoritative
        // series position and full release date; fall back to the ABS sequence
        // and published year when there's no ASIN or no Audnexus hit.
        let enriched: [(position: Double?, year: Int?)] = await withTaskGroup(of: (Double?, Int?).self) { group in
            for book in books {
                group.addTask {
                    let absPosition = (book.series.first { $0.name.lowercased() == lowerName } ?? book.series.first)?
                        .sequence.map(Double.init)
                    let absYear = year(book.released)
                    guard let asin = book.asin, !asin.isEmpty,
                          let audnexus = await AudnexusClient.book(asin: asin) else {
                        return (absPosition, absYear)
                    }
                    let match = audnexus.series.first { $0.name.lowercased() == lowerName } ?? audnexus.series.first
                    return (match?.position ?? absPosition, audnexus.releaseYear ?? absYear)
                }
            }
            var out = [(Double?, Int?)]()
            for await pair in group { out.append(pair) }
            return out
        }
        let maxOwnedPosition = enriched.compactMap { $0.position }.max()
        let maxOwnedYear = enriched.compactMap { $0.year }.max()

        return TrackedSeries(
            name: ref.name,
            author: books.first?.authors.first,
            ownedTitles: books.map(\.name),
            maxOwnedPosition: maxOwnedPosition,
            maxOwnedYear: maxOwnedYear)
    }

    private static func missingTitles(for tracked: TrackedSeries, token: String) async -> (rosterFound: Bool, candidates: [Candidate]) {
        guard let hardcover = await HardcoverClient.fetchSeries(name: tracked.name, author: tracked.author, token: token),
              !hardcover.books.isEmpty else {
            logger.info("series '\(tracked.name, privacy: .public)': no hardcover roster")
            return (false, [])
        }

        let ownedNorm = tracked.ownedTitles.map(normalize).filter { !$0.isEmpty }
        var seen = Set<String>()
        var result = [Candidate]()

        for book in hardcover.books {
            let bookNorm = normalize(book.title)
            guard bookNorm.count >= 4 else { continue }
            // Hardcover rosters carry edition/translation duplicates per slot.
            guard seen.insert(bookNorm).inserted else { continue }

            let owned = ownedNorm.contains { owned in
                owned == bookNorm || owned.contains(bookNorm) || bookNorm.contains(owned)
            }
            if owned { continue }

            if let position = book.position {
                // Skip .5 / novella entries — retro-padding the user doesn't want.
                if position.truncatingRemainder(dividingBy: 1) != 0 { continue }
                if let maxOwned = tracked.maxOwnedPosition {
                    // Position is authoritative: only books later than what's owned.
                    if position > maxOwned {
                        result.append(Candidate(title: book.title, seriesName: tracked.name, author: tracked.author, minYear: nil))
                    }
                    continue
                }
            }
            // No usable position ordering — fall back to a publication-year guard.
            result.append(Candidate(title: book.title, seriesName: tracked.name, author: tracked.author, minYear: tracked.maxOwnedYear))
        }
        logger.info("series '\(tracked.name, privacy: .public)': roster \(hardcover.books.count, privacy: .public), owned \(tracked.ownedTitles.count, privacy: .public) (max pos \(tracked.maxOwnedPosition ?? -1, privacy: .public), year \(tracked.maxOwnedYear ?? -1, privacy: .public)), missing \(result.count, privacy: .public)")
        return (true, result)
    }

    /// Search AudiobookBay for a missing book (by author + title, the strongest
    /// signal) and pick the best-covering release. `rawCount` is the number of
    /// search results, or -1 when the fetch itself failed (so an empty result
    /// can be told apart from a blocked request).
    private static func resolveCandidate(_ candidate: Candidate) async -> ResolveAttempt {
        // Query ABB with series + title + author as clean lowercase words
        // (e.g. "awaken online armageddon travis bagwell") — the form that
        // matches ABB's posts.
        let query = searchQuery(for: candidate)
        guard !query.isEmpty,
              let urlString = AppSettings.shared.abbServerURL,
              let base = URL(string: urlString) else {
            return ResolveAttempt(result: nil, rawCount: 0, bestScore: 0, query: query, htmlLen: 0)
        }

        // Try the ?s= query form (verified working on mirrors like
        // audiobookbay.lu) first, then the /search/ path form, taking whichever
        // returns results.
        var fetchFailed = false
        var results = [ABBSearchResult]()
        var htmlLen = 0
        for url in [altSearchURL(base: base, query: query), ABBSearchParser.searchURL(baseURL: base, query: query)] {
            guard let url else { continue }
            guard let html = try? await ABBSessionManager.shared.fetchPage(url: url) else {
                fetchFailed = true
                continue
            }
            htmlLen = max(htmlLen, html.count)
            let parsed = await Task.detached(priority: .userInitiated) {
                (try? ABBSearchParser.parseResults(from: html, baseURL: base)) ?? []
            }.value
            if !parsed.isEmpty {
                results = parsed
                break
            }
        }
        logger.info("abb '\(query, privacy: .public)': \(results.count, privacy: .public) results (html \(htmlLen, privacy: .public))")
        guard !results.isEmpty else {
            return ResolveAttempt(result: nil, rawCount: fetchFailed ? -1 : 0, bestScore: 0, query: query, htmlLen: htmlLen)
        }

        // Token-overlap (not substring) so a release padded with series, author,
        // narrator, or format words still matches the wanted book.
        let scored = results.map { (result: $0, score: TitleMatching.score(wanted: candidate.title, candidate: $0.title)) }
        let bestScore = scored.map { $0.score }.max() ?? 0
        guard let match = scored.filter({ $0.score >= 0.75 }).max(by: { $0.score < $1.score })?.result else {
            return ResolveAttempt(result: nil, rawCount: results.count, bestScore: bestScore, query: query, htmlLen: htmlLen)
        }
        // Year-fallback guard: when position couldn't order it, require the
        // result to be at least as new as the latest book owned.
        if let minYear = candidate.minYear, let resultYear = year(match.year), resultYear < minYear {
            return ResolveAttempt(result: nil, rawCount: results.count, bestScore: bestScore, query: query, htmlLen: htmlLen)
        }
        return ResolveAttempt(result: match, rawCount: results.count, bestScore: bestScore, query: query, htmlLen: htmlLen)
    }

    /// The `?s=` query-parameter search form, matching the working browser URL
    /// exactly: `{base}/?s=awaken+online+armageddon+travis+bagwell&cat=undefined,undefined`.
    private static func altSearchURL(base: URL, query: String) -> URL? {
        let baseString = base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let plus = query.replacingOccurrences(of: " ", with: "+")
        return URL(string: "\(baseString)/?s=\(plus)&cat=undefined,undefined")
    }

    /// Builds an ABB search query from series + title + author as deduplicated,
    /// punctuation-free lowercase words (the form ABB matches on), e.g.
    /// "awaken online armageddon travis bagwell".
    private static func searchQuery(for candidate: Candidate) -> String {
        var words = [String]()
        var seen = Set<String>()
        for part in [candidate.seriesName, candidate.title, candidate.author].compactMap({ $0 }) {
            let folded = part.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            let mapped = folded.unicodeScalars.map { scalar -> Character in
                CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
            }
            for word in String(mapped).split(separator: " ").map(String.init) where seen.insert(word).inserted {
                words.append(word)
            }
        }
        return words.joined(separator: " ")
    }

    /// First four-digit year in a string ("2021", "2021-05-01" -> 2021).
    private static func year(_ value: String?) -> Int? {
        guard let value, let range = value.range(of: "\\d{4}", options: .regularExpression) else { return nil }
        return Int(value[range])
    }

    private static func normalize(_ value: String) -> String {
        let lowered = value.lowercased()
        let mapped = lowered.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }
}
