//
//  ABBSeriesView.swift
//  Library
//

import SwiftUI
import LibraryKit
import ABBKit

struct ABBSeriesView: View {
    let seriesName: String
    let author: String?
    let fallbackDescription: String?

    @State private var entries = [SeriesEntry]()
    @State private var isOrdered = false
    @State private var isLoading = true
    @State private var error: String?
    @State private var hardcoverDescription: String?

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else if let error {
                ContentUnavailableView(
                    "Error Loading Series",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    if let aboutText {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("About")
                                .font(.headline)
                            Text(aboutText)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .lineLimit(6)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if entries.isEmpty {
                        ContentUnavailableView(
                            "No Books Found",
                            systemImage: "books.vertical",
                            description: Text("Couldn't find other books in \(seriesName).")
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(isOrdered ? "Books in this Series" : "More in this Series")
                                .font(.headline)

                            VStack(spacing: 0) {
                                ForEach(entries) { entry in
                                    NavigationLink(value: NavigationDestination.abbDetail(entry.result)) {
                                        SeriesBookRow(entry: entry)
                                    }
                                    .buttonStyle(.plain)

                                    if entry.id != entries.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle(seriesName)
        .navigationBarTitleDisplayMode(.large)

        .task {
            await load()
        }
    }

    /// Prefer a real Hardcover series description; otherwise a short synopsis
    /// from the originating book.
    private var aboutText: String? {
        if let hardcoverDescription, !hardcoverDescription.isEmpty {
            return hardcoverDescription
        }
        return synopsis
    }

    /// A short, single-paragraph synopsis derived from the originating book's
    /// (often very long) description.
    private var synopsis: String? {
        guard let fallbackDescription, !fallbackDescription.isEmpty else { return nil }
        let firstParagraph = fallbackDescription
            .components(separatedBy: "\n\n")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let result = (firstParagraph?.isEmpty == false ? firstParagraph : fallbackDescription)
        return result
    }

    @MainActor
    private func load() async {
        isLoading = true
        error = nil
        do {
            guard let urlString = AppSettings.shared.abbServerURL, let baseURL = URL(string: urlString),
                  let searchURL = ABBSearchParser.searchURL(baseURL: baseURL, query: seriesName) else {
                error = "ABB Server URL is not configured."
                isLoading = false
                return
            }

            let html = try await ABBSessionManager.shared.fetchPage(url: searchURL)
            // A series with no matching search rows should show the empty state,
            // not a hard error, so swallow parse-level "no rows" failures. Parse
            // off the main actor to keep navigation responsive.
            let results = await Task.detached(priority: .userInitiated) {
                (try? ABBSearchParser.parseResults(from: html, baseURL: baseURL)) ?? []
            }.value

            let normalizedSeries = seriesName.lowercased()
            var seen = Set<String>()
            var collected = [SeriesEntry]()

            for result in results {
                let cleaned = ABBSeriesParser.titleWithoutAuthor(result.title).lowercased()
                guard cleaned.contains(normalizedSeries) else { continue }
                guard !seen.contains(cleaned) else { continue }
                seen.insert(cleaned)

                let position = ABBSeriesParser.parse(title: result.title, author: result.author)?.position
                collected.append(SeriesEntry(result: result, position: position))
            }

            collected.sort { lhs, rhs in
                switch (lhs.position, rhs.position) {
                case let (left?, right?):
                    return left < right
                case (nil, .some):
                    return false
                case (.some, nil):
                    return true
                case (nil, nil):
                    return lhs.result.title.localizedCaseInsensitiveCompare(rhs.result.title) == .orderedAscending
                }
            }

            entries = collected
            isOrdered = !collected.isEmpty && collected.allSatisfy { $0.position != nil }
            isLoading = false

            // Best-effort: enrich with a real Hardcover series description and
            // ordering (handles name-only series the ABB title can't order).
            if let token = AppSettings.shared.hardcoverAPIToken,
               !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let hardcover = await HardcoverClient.fetchSeries(name: seriesName, author: author, token: token) {
                hardcoverDescription = hardcover.description
                if !hardcover.books.isEmpty {
                    let reordered = Self.applyHardcoverOrdering(collected, hardcoverBooks: hardcover.books)
                    entries = reordered
                    isOrdered = !reordered.isEmpty && reordered.allSatisfy { $0.position != nil }
                }
            }
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }
}

struct SeriesEntry: Identifiable, Hashable {
    let result: ABBSearchResult
    let position: Double?

    var id: String { result.id }
}

extension ABBSeriesView {
    /// Re-orders ABB results using Hardcover's authoritative positions, matching
    /// each ABB title to a Hardcover roster title. Unmatched entries keep their
    /// ABB position.
    static func applyHardcoverOrdering(_ input: [SeriesEntry], hardcoverBooks: [HardcoverSeriesBook]) -> [SeriesEntry] {
        var mapped = input.map { entry -> SeriesEntry in
            let abbTitle = ABBSeriesParser.titleWithoutAuthor(entry.result.title)
            if let position = hardcoverPosition(for: abbTitle, in: hardcoverBooks) {
                return SeriesEntry(result: entry.result, position: position)
            }
            return entry
        }

        mapped.sort { lhs, rhs in
            switch (lhs.position, rhs.position) {
            case let (left?, right?):
                if left == right {
                    return lhs.result.title.localizedCaseInsensitiveCompare(rhs.result.title) == .orderedAscending
                }
                return left < right
            case (nil, .some):
                return false
            case (.some, nil):
                return true
            case (nil, nil):
                return lhs.result.title.localizedCaseInsensitiveCompare(rhs.result.title) == .orderedAscending
            }
        }
        return mapped
    }

    private static func hardcoverPosition(for abbTitle: String, in books: [HardcoverSeriesBook]) -> Double? {
        let abbNormalized = normalizeTitle(abbTitle)
        guard !abbNormalized.isEmpty else { return nil }

        var best: (position: Double, length: Int)?
        for book in books {
            guard let position = book.position else { continue }
            let hardcoverNormalized = normalizeTitle(book.title)
            guard hardcoverNormalized.count >= 4 else { continue }
            if abbNormalized.contains(hardcoverNormalized) || hardcoverNormalized.contains(abbNormalized) {
                let length = min(hardcoverNormalized.count, abbNormalized.count)
                if best == nil || length > best!.length {
                    best = (position, length)
                }
            }
        }
        return best?.position
    }

    private static func normalizeTitle(_ title: String) -> String {
        let lowered = title.lowercased()
        let mapped = lowered.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }
}

private struct SeriesBookRow: View {
    let entry: SeriesEntry

    var body: some View {
        HStack(spacing: 12) {
            Color.clear
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .frame(width: 50)
                .overlay { cover }
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                if let position = entry.position {
                    Text("Book \(ABBSeriesParser.formatPosition(position))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(entry.result.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let year = entry.result.year {
                    Text(year)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var cover: some View {
        ABBCoverImage(url: entry.result.coverURL) {
            coverPlaceholder
        }
    }

    private var coverPlaceholder: some View {
        Rectangle()
            .fill(.secondary.opacity(0.2))
            .overlay {
                Image(systemName: "book")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
    }
}
