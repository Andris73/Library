//
//  NewInSeriesShelf.swift
//  Library
//
//  Shows books missing from series the user already has in their
//  Audiobookshelf library — the next entries to download. Backed by
//  `SeriesTrackingService` (Audiobookshelf series + Hardcover roster) and
//  rendered as standard AudiobookBay cards, so tapping one opens the same
//  book detail page as every other Discover shelf.
//
//  Gated on a Hardcover token by the caller; if there's nothing missing the
//  shelf renders nothing rather than an empty card.
//

import SwiftUI
import OSLog
import LibraryKit
import ABBKit

struct NewInSeriesShelf: View {
    private static let logger = Logger(subsystem: "com.Library.app", category: "SeriesTracking")

    @State private var results = [ABBSearchResult]()
    @State private var isLoading = true
    @State private var hasToken = true
    @State private var trace = ""

    var body: some View {
        Group {
            if isLoading {
                shelf {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            } else if !hasToken {
                shelf {
                    Text("Add a Hardcover API token in the ABB Server settings to see the next books in the series you're listening to.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                }
            } else if !results.isEmpty {
                shelf {
                    ABBSearchResultHGrid(results: results)
                }
            } else {
                shelf {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("You're caught up — nothing new in the series you're listening to.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if !trace.isEmpty {
                            Text(trace)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                }
            }
        }
        .task {
            await load()
        }
    }

    @ViewBuilder
    private func shelf<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New in Your Series")
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 20)

            content()
        }
    }

    @MainActor
    private func load() async {
        let token = (AppSettings.shared.hardcoverAPIToken ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        hasToken = !token.isEmpty
        guard hasToken else {
            Self.logger.info("shelf: no hardcover token configured, showing prompt")
            results = []
            isLoading = false
            return
        }

        let outcome = await SeriesTrackingService.missingFromTrackedSeries(token: token)
        results = outcome.results
        trace = outcome.trace
        Self.logger.info("shelf: \(results.count, privacy: .public) results")
        isLoading = false
    }
}
