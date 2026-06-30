//
//  DiscoverPanel.swift
//  Library
//

import SwiftUI
import LibraryKit
import ABBKit
import TransmissionKit

struct DiscoverPanel: View {
    @State private var searchText = ""
    @State private var searchResults = [ABBSearchResult]()
    @State private var isSearching = false
    @State private var showABBSheet = false
    @State private var showTransmissionSheet = false
    @State private var activeDownloads = [LibrarySchema.PersistedActiveDownload]()
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?

    @State private var genres = [ABBGenre]()
    @State private var isLoadingGenres = false

    private var isConfigured: Bool {
        AppSettings.shared.abbServerURL != nil && AppSettings.shared.transmissionURL != nil
    }

    /// Cap on the number of "Trending in {genre}" shelves rendered at once.
    /// Each shelf scrapes an ABB genre page on appear, so an unbounded number
    /// of pinned genres would fan out into many concurrent network fetches
    /// every time Discover opens.
    private static let maxTrendingShelves = 4

    /// Genres the user has pinned, in pin order, restricted to the
    /// currently-loaded `genres` list. Drives the per-pinned-genre
    /// trending shelves below the pill row.
    private var pinnedGenres: [ABBGenre] {
        AppSettings.shared.pinnedGenreSlugs
            .compactMap { slug in genres.first { $0.slug == slug } }
    }


    var body: some View {
        // Eager VStack (not LazyVStack) so each shelf's `.task` is
        // guaranteed to fire on first mount — the same reason
        // `MultiLibraryHomePanel` uses an eager VStack for its rows.
        // The total section count is small (pills + N trending shelves
        // + search/downloads), so eager mount is fine.
        ScrollView {
            VStack(spacing: 16) {
                if !isConfigured {
                    notConfiguredEmptyState
                } else {
                    configuredContent
                }
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer)
        .navigationTitle("Discover")
        .largeTitleDisplayMode()

        .toolbar {
            if isConfigured {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("ABB Server", systemImage: "antenna.radiowaves.left.and.right") {
                            showABBSheet = true
                        }
                        Button("Transmission", systemImage: "arrow.down.circle") {
                            showTransmissionSheet = true
                        }
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .sheet(isPresented: $showABBSheet) {
            ABBConfigurationSheet()
        }
        .sheet(isPresented: $showTransmissionSheet) {
            TransmissionConfigurationSheet()
        }
        .task {
            await loadActiveDownloads()
        }
        .task {
            await loadGenres()
        }
        .task {
            await pollDownloads()
        }
        .onReceive(PersistenceManager.shared.downloadTracker.events.downloadsChanged.receive(on: RunLoop.main)) { _ in
            Task { await loadActiveDownloads() }
        }
        .onChange(of: searchText) {
            searchTask?.cancel()
            searchError = nil
            performSearch(query: searchText)
        }
    }

    @ViewBuilder
    private var configuredContent: some View {
        if !genres.isEmpty {
            GenrePillRow(genres: genres)
                .padding(.vertical, 8)
        } else if isLoadingGenres {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding(.vertical, 8)
        }

        // While a search is active, results take over the top of the page so
        // they're immediately visible; the browse shelves are hidden until the
        // query is cleared.
        if isSearchActive {
            searchSection
        } else {
            if !pinnedGenres.isEmpty {
                ForEach(pinnedGenres.prefix(Self.maxTrendingShelves)) { genre in
                    TrendingShelf(genre: genre)
                }
            }

            NewInSeriesShelf()
        }

        if !activeDownloads.isEmpty {
            activeDownloadsSection
        }
    }

    private var isSearchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var searchSection: some View {
        if isSearching {
            HStack(spacing: 8) {
                ProgressView()
                Text("Searching…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
        }

        if let error = searchError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
        }

        if !searchResults.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Results")
                    .font(.headline)
                    .padding(.horizontal, 20)

                ForEach(searchResults) { result in
                    NavigationLink(value: NavigationDestination.abbDetail(result)) {
                        ABBSearchResultRow(result: result)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .padding(.horizontal, 20)
                }
            }
        }
    }

    @ViewBuilder
    private var activeDownloadsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active Downloads")
                .font(.headline)
                .padding(.horizontal, 20)

            ForEach(activeDownloads, id: \.infoHash) { download in
                ActiveDownloadRow(download: download)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)

                Divider()
                    .padding(.horizontal, 20)
            }
        }
    }

    private var notConfiguredEmptyState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 40)

            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Discover Audiobooks")
                .font(.headline)
            Text("Configure an AudiobookBay source and a Transmission client to search and download audiobooks directly.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("ABB Server URL") {
                    showABBSheet = true
                }
                .buttonStyle(.bordered)
                Button("Transmission") {
                    showTransmissionSheet = true
                }
                .buttonStyle(.bordered)
            }

            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 20)
    }

    private func performSearch(query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            isSearching = false
            searchError = nil
            return
        }

        isSearching = true
        searchResults = []

        searchTask = Task { @MainActor in
            do {
                try Task.checkCancellation()

                guard let urlString = AppSettings.shared.abbServerURL, let url = URL(string: urlString),
                      let searchURL = ABBSearchParser.searchURL(baseURL: url, query: query) else {
                    searchError = "ABB Server URL is not configured."
                    isSearching = false
                    return
                }

                try Task.checkCancellation()
                let html = try await ABBSessionManager.shared.fetchPage(url: searchURL)

                try Task.checkCancellation()
                let results = try await Task.detached(priority: .userInitiated) {
                    try ABBSearchParser.parseResults(from: html, baseURL: url)
                }.value

                try Task.checkCancellation()
                // Show explicit-filtered results immediately, then drop titles
                // already in the library once the network-backed check returns.
                let explicitFiltered = results.filteringExplicitIfNeeded()
                searchResults = explicitFiltered
                isSearching = false
                searchError = explicitFiltered.isEmpty ? "No results found for \"\(query)\"." : nil

                let unowned = await LibraryOwnershipService.filterUnowned(explicitFiltered)
                try Task.checkCancellation()
                if unowned != explicitFiltered {
                    withAnimation { searchResults = unowned }
                    if unowned.isEmpty {
                        searchError = "You already have every result for \"\(query)\" in your library."
                    }
                }
            } catch is CancellationError {
                isSearching = false
            } catch {
                searchError = "Search failed: \(error.localizedDescription)"
                isSearching = false
            }
        }
    }

    @MainActor
    private func loadActiveDownloads() async {
        activeDownloads = await PersistenceManager.shared.downloadTracker.activeDownloads
    }

    /// Polls Transmission while Discover is visible, updating each tracked
    /// download's progress/status and removing ones that have finished seeding
    /// (or vanished from the server). Idles cheaply when there's nothing to do.
    private func pollDownloads() async {
        while !Task.isCancelled {
            let downloads = await PersistenceManager.shared.downloadTracker.activeDownloads
            guard !downloads.isEmpty, let client = makeTransmissionClient() else {
                try? await Task.sleep(for: .seconds(4))
                continue
            }

            let trackedIDs = downloads.map(\.torrentID)
            let torrents = (try? await client.getTorrents(ids: trackedIDs)) ?? []
            await applyTorrentUpdates(torrents, trackedIDs: trackedIDs)

            try? await Task.sleep(for: .seconds(2.5))
        }
    }

    private func applyTorrentUpdates(_ torrents: [TorrentInfo], trackedIDs: [Int]) async {
        let tracker = PersistenceManager.shared.downloadTracker
        let byID = Dictionary(torrents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for id in trackedIDs {
            guard let info = byID[id] else {
                // Torrent is gone from the server — drop it from the list.
                await tracker.removeDownload(torrentID: id)
                continue
            }

            let downloaded = info.percentDone >= 1.0
            let doneSeeding = info.isSeeding && info.seedProgress >= 1.0
            let stoppedAfterComplete = downloaded && info.status == .stopped
            if doneSeeding || stoppedAfterComplete {
                await tracker.removeDownload(torrentID: id)
                continue
            }

            // During seeding the bar resets to seed progress; otherwise it tracks
            // the download percentage.
            let progress = info.isSeeding ? info.seedProgress : info.percentDone
            await tracker.updateProgress(torrentID: id, progress: progress, status: info.status.persistedKey)
        }
    }

    private func makeTransmissionClient() -> TransmissionClient? {
        guard let urlString = AppSettings.shared.transmissionURL, let url = URL(string: urlString) else {
            return nil
        }
        var credential: URLCredential?
        if let user = AppSettings.shared.transmissionUsername, !user.isEmpty {
            credential = URLCredential(
                user: user,
                password: AppSettings.shared.transmissionPassword ?? "",
                persistence: .forSession)
        }
        return TransmissionClient(baseURL: url, credential: credential)
    }

    @MainActor
    private func loadGenres() async {
        isLoadingGenres = true
        do {
            guard let urlString = AppSettings.shared.abbServerURL, let url = URL(string: urlString) else {
                isLoadingGenres = false
                return
            }
            let html = try await ABBSessionManager.shared.fetchPage(url: url)
            genres = try ABBGenreNavigationParser.parse(from: html, baseURL: url)
        } catch {
            genres = []
        }
        isLoadingGenres = false
    }
}

struct GenrePillRow: View {
    let genres: [ABBGenre]

    private var pinnedSlugs: [String] {
        AppSettings.shared.pinnedGenreSlugs
    }

    /// Pinned genres first (in the order they were pinned), then the rest
    /// sorted alphabetically by name.
    private var orderedGenres: [ABBGenre] {
        let pinned = pinnedSlugs
        let pinnedGenres = pinned.compactMap { slug in genres.first { $0.slug == slug } }
        let rest = genres
            .filter { !pinned.contains($0.slug) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return pinnedGenres + rest
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(orderedGenres) { genre in
                    let isPinned = pinnedSlugs.contains(genre.slug)
                    NavigationLink(value: NavigationDestination.abbGenre(genre)) {
                        HStack(spacing: 4) {
                            if isPinned {
                                Image(systemName: "pin.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(genre.name)
                                .font(.subheadline)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.secondary.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            togglePin(genre)
                        } label: {
                            if isPinned {
                                Label("Unpin Genre", systemImage: "pin.slash")
                            } else {
                                Label("Pin Genre", systemImage: "pin")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .scrollClipDisabled()
    }

    private func togglePin(_ genre: ABBGenre) {
        var slugs = AppSettings.shared.pinnedGenreSlugs
        if let index = slugs.firstIndex(of: genre.slug) {
            slugs.remove(at: index)
        } else {
            slugs.append(genre.slug)
        }
        AppSettings.shared.pinnedGenreSlugs = slugs
    }
}

struct ABBSearchResultRow: View {
    let result: ABBSearchResult

    var body: some View {
        HStack(spacing: 12) {
            ABBCoverImage(url: result.coverURL) {
                Rectangle()
                    .fill(.secondary.opacity(0.2))
                    .overlay {
                        Image(systemName: "book")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: 48, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.headline)
                    .lineLimit(2)
                if let author = result.author {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let year = result.year {
                    Text(year)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct ActiveDownloadRow: View {
    let download: LibrarySchema.PersistedActiveDownload

    private var isSeeding: Bool { download.status == "seeding" }
    private var fraction: Double { max(0, min(download.progress, 1)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(download.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if !download.author.isEmpty {
                    Text(download.author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            ProgressView(value: fraction)
                .tint(isSeeding ? .green : .blue)

            HStack(spacing: 4) {
                Image(systemName: statusIcon)
                    .font(.caption2)
                    .foregroundStyle(isSeeding ? .green : .secondary)
                Text(statusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
    }

    private var statusIcon: String {
        switch download.status {
        case "seeding": "arrow.up.circle"
        case "stopped": "pause.circle"
        default: "arrow.down.circle"
        }
    }

    private var statusLabel: String {
        switch download.status {
        case "downloading": "Downloading"
        case "seeding": "Seeding"
        case "stopped": "Stopped"
        default: download.status.capitalized
        }
    }
}
