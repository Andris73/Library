import SwiftUI
import LibraryKit
import ABBKit

struct ABBGenreView: View {
    let genre: ABBGenre

    @State private var results = [ABBSearchResult]()
    @State private var seenIDs = Set<String>()
    @State private var page = 1
    @State private var hasMore = true
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var error: String?

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 100, maximum: 160), spacing: 16)]
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                ContentUnavailableView(
                    "Error Loading Genre",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if results.isEmpty {
                ContentUnavailableView(
                    "No Books Found",
                    systemImage: "book.closed",
                    description: Text("No books found in \(genre.name).")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(results) { result in
                            NavigationLink(value: NavigationDestination.abbDetail(result)) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Color.clear
                                        .aspectRatio(2.0 / 3.0, contentMode: .fit)
                                        .frame(maxWidth: .infinity)
                                        .overlay {
                                            coverImage(for: result)
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                    Text(result.title)
                                        .font(.caption)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                if result.id == results.last?.id {
                                    Task { await loadMore() }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                    if isLoadingMore {
                        ProgressView()
                            .padding(.vertical, 20)
                    }
                }
            }
        }
        .navigationTitle(genre.name)
        .navigationBarTitleDisplayMode(.inline)

        .task {
            await loadInitial()
        }
    }

    @ViewBuilder
    private func coverImage(for result: ABBSearchResult) -> some View {
        ABBCoverImage(url: result.coverURL) {
            placeholderCover
        }
    }

    private var placeholderCover: some View {
        Rectangle()
            .fill(.secondary.opacity(0.2))
            .overlay {
                Image(systemName: "book")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
    }

    private func abbBaseURL() -> URL? {
        guard let urlString = AppSettings.shared.abbServerURL else { return nil }
        return URL(string: urlString)
    }

    @MainActor
    private func loadInitial() async {
        isLoading = true
        error = nil
        page = 1
        hasMore = true
        seenIDs = []
        do {
            guard let baseURL = abbBaseURL() else {
                error = "ABB Server URL is not configured."
                isLoading = false
                return
            }
            let url = ABBGenreListingParser.genreURL(baseURL: baseURL, slug: genre.slug)
            let html = try await ABBSessionManager.shared.fetchPage(url: url)
            let raw = try await Task.detached(priority: .userInitiated) {
                try ABBGenreListingParser.parseListing(from: html, baseURL: baseURL)
            }.value
            seenIDs = Set(raw.map(\.id))
            hasMore = !raw.isEmpty

            // Show explicit-filtered results immediately, then drop owned titles
            // once the network-backed ownership check completes.
            let explicitFiltered = raw.filteringExplicitIfNeeded()
            results = explicitFiltered
            isLoading = false

            let unowned = await LibraryOwnershipService.filterUnowned(explicitFiltered)
            if unowned != explicitFiltered {
                withAnimation { results = unowned }
            }
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    @MainActor
    private func loadMore() async {
        guard hasMore, !isLoading, !isLoadingMore, let baseURL = abbBaseURL() else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        // Keep fetching pages until we add at least one visible result or run
        // out of pages. Without this, a page whose new items are all filtered
        // out (e.g. all explicit) would leave `results` unchanged, so the
        // endless-scroll trigger (keyed to the last visible row) never re-fires.
        while hasMore {
            let nextPage = page + 1
            do {
                let url = ABBGenreListingParser.genreURL(baseURL: baseURL, slug: genre.slug, page: nextPage)
                let html = try await ABBSessionManager.shared.fetchPage(url: url)
                let more = try await Task.detached(priority: .userInitiated) {
                    try ABBGenreListingParser.parseListing(from: html, baseURL: baseURL)
                }.value
                let newRaw = more.filter { seenIDs.insert($0.id).inserted }
                if newRaw.isEmpty {
                    hasMore = false
                    return
                }
                page = nextPage
                let visible = await newRaw.filteringHiddenIfNeeded()
                if !visible.isEmpty {
                    results += visible
                    return
                }
                // Page was entirely filtered out — continue to the next page.
            } catch {
                hasMore = false
                return
            }
        }
    }
}
