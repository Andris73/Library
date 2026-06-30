//
//  TrendingShelf.swift
//  Library
//
//  Renders a single "Trending in {genre}" shelf on the Discover tab.
//  Scrapes the AudiobookBay genre page (via `ABBGenreListingParser`)
//  and shows the first ten results in a horizontal row.
//
//  Tapping the title pushes the full `ABBGenreView` (the same
//  destination the genre pill row uses), so the trending row and the
//  pill row share a single deep-dive surface.
//

import SwiftUI
import LibraryKit
import ABBKit

struct TrendingShelf: View {
    let genre: ABBGenre

    @State private var results = [ABBSearchResult]()
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: NavigationDestination.abbGenre(genre)) {
                HStack(spacing: 8) {
                    Text("Trending in \(genre.name)")
                        .font(.headline)
                    Image(systemName: "chevron.right")
                        .symbolVariant(.circle.fill)
                        .font(.caption)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)
            .padding(.horizontal, 20)

            content
        }
        .task {
            await load()
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 200)
        } else if let error {
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
            .padding(.horizontal, 20)
        } else if results.isEmpty {
            Text("No trending books found.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            ABBSearchResultHGrid(results: results)
        }
    }

    @MainActor
    private func load() async {
        guard let baseURLString = AppSettings.shared.abbServerURL,
              let baseURL = URL(string: baseURLString) else {
            isLoading = false
            return
        }

        do {
            let url = ABBGenreListingParser.genreURL(baseURL: baseURL, slug: genre.slug)
            let html = try await ABBSessionManager.shared.fetchPage(url: url)
            let parsed = try await Task.detached(priority: .userInitiated) {
                try ABBGenreListingParser.parseListing(from: html, baseURL: baseURL)
            }.value

            // Show explicit-filtered results immediately, then drop titles the
            // user already owns once the (network-backed) check completes.
            let explicitFiltered = parsed.filteringExplicitIfNeeded()
            results = Array(explicitFiltered.prefix(10))
            isLoading = false

            let unowned = Array((await LibraryOwnershipService.filterUnowned(explicitFiltered)).prefix(10))
            if unowned != results {
                withAnimation { results = unowned }
            }
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }
}
