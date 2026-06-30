//
//  HomeSectionRenderers.swift
//  Library
//
//  Created by Rasmus Krämer on 19.04.26.
//
//  Shared row views that render the client-derived home sections (downloads).
//  Server rows are rendered directly by `AudiobookHomePanel` because it
//  already holds the fetched `HomeRow<Audiobook>` data. The multi-library
//  panel doesn't pre-fetch — it uses `MultiLibraryServerRow` (below) which
//  fetches the pinned library's home on demand.

import SwiftUI
import OSLog
private let homeSectionRenderersLogger = Logger(subsystem: "com.Library.Library", category: "HomeSectionRenderers")

// MARK: - Content state

/// Reported by client-derived home rows that may render as `EmptyView` when
/// they have nothing to show. The multi-library panel uses these reports to
/// distinguish "still fetching" from "actually empty" so it can keep its
/// loading indicator up until rows have settled, then surface a real empty
/// state instead of a blank scroll view.
enum HomeRowContentState: Equatable, Sendable {
    case loading
    case empty
    case hasContent
}

// MARK: - Wrapper

/// A client-derived home row with a leading title + trailing content.
struct HomeRowContainer<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RowTitle(title: title)
                .padding(.bottom, 12)
                .padding(.horizontal, 20)

            content()
        }
    }
}

/// Inline placeholder text used by rows that have completed their initial load
/// with no items but need to show *something* (e.g. inside a multi-library
/// panel where collapsing would leave the screen blank).
private struct EmptyRowMessage: View {
    let key: LocalizedStringKey
    init(_ key: LocalizedStringKey) { self.key = key }

    var body: some View {
        HStack {
            Text(key)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 20)
    }
}

struct DownloadedAudiobooksRow: View {
    /// When nil, aggregates across all libraries (pinned-tab "Any" semantics).
    let libraryID: LibraryIdentifier?
    let title: String

    @State private var audiobooks: [Audiobook] = []

    var body: some View {
        // Always render. Show the placeholder eagerly (no hasLoaded gate)
        // because returning `EmptyView()` while waiting on the load can cause
        // LazyVStack to skip realizing this row entirely, and then `.task`
        // never fires and the row stays invisible permanently. Mirrors
        // `BookmarksRow` — the brief "no downloads" flicker before the load
        // finishes is acceptable.
        Group {
            if !audiobooks.isEmpty {
                AudiobookRow(title: title, small: false, audiobooks: audiobooks)
            } else {
                HomeRowContainer(title: title) {
                    EmptyRowMessage("home.section.downloadedAudiobooks.empty")
                }
            }
        }
        .task(id: libraryID) { await load() }
        .onReceive(PersistenceManager.shared.download.events.statusChanged) { payload in
            if let libraryID, let (itemID, _) = payload, itemID.libraryID != libraryID.libraryID { return }
            Task { await load() }
        }
    }

    private func load() async {
        let books: [Audiobook]?
        if let libraryID {
            books = try? await PersistenceManager.shared.download.audiobooks(in: libraryID.libraryID)
        } else {
            books = try? await PersistenceManager.shared.download.audiobooks()
        }
        withAnimation {
            audiobooks = books ?? []
        }
    }
}

// MARK: - Pinned Collection / Playlist

/// Resolves a pinned `ItemCollection` (collection or playlist) and renders its
/// items as a home row. Always renders once configured — empty or unreachable
/// collections fall back to a placeholder container so the user can see the
/// section is actually pinned.
///
/// Important: this view does NOT wrap its content in a `NavigationLink`.
/// `AudiobookRow` already contains its own `NavigationLink` (for the "see all"
/// destination when there are >5 audiobooks), and nesting NavigationLinks
/// triggers a collection-view recursive-layout loop (UICollectionView
/// feedback-loop crash).
struct PinnedCollectionRow: View {
    let itemID: ItemIdentifier
    /// Optional override title. When nil, the collection's own name is used.
    let titleOverride: String?

    @State private var collection: ItemCollection?
    @State private var didFail = false

    private var fallbackTitle: String {
        titleOverride ?? String(localized: itemID.type == .playlist
                                ? "home.section.playlist"
                                : "home.section.collection")
    }

    var body: some View {
        Group {
            if let collection {
                let displayTitle = titleOverride ?? collection.name
                if let audiobooks = collection.audiobooks, !audiobooks.isEmpty {
                    AudiobookRow(title: displayTitle, small: false, audiobooks: audiobooks)
                } else {
                    HomeRowContainer(title: displayTitle) {
                        placeholder(textKey: "home.section.collection.empty")
                    }
                }
            } else {
                // Always visible — either a "loading" or "unavailable" state.
                // EmptyView() here would look identical to "the section
                // vanished", which is exactly the feedback we're trying to
                // avoid for an explicitly-pinned collection.
                HomeRowContainer(title: fallbackTitle) {
                    if didFail {
                        placeholder(textKey: "home.section.collection.unavailable")
                    } else {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("loading")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
        }
        .task(id: itemID) { await load() }
        .onReceive(CollectionEventSource.shared.changed) { _ in
            Task { await load() }
        }
    }

    @ViewBuilder
    private func placeholder(textKey: LocalizedStringKey) -> some View {
        HStack {
            Text(textKey)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private func load() async {
        do {
            let item = try await ResolveCache.shared.resolve(itemID)
            if let collection = item as? ItemCollection {
                withAnimation {
                    self.collection = collection
                    self.didFail = false
                }
            } else {
                withAnimation { didFail = true }
            }
        } catch {
            withAnimation { didFail = true }
        }
    }
}

// MARK: - Multi-library Server Row

/// Multi-library variant of a server-driven home row. Single-library panels
/// fetch the whole library's home up-front and dispatch matching rows from a
/// dictionary; the multi-library panel can have N sections pinned to N
/// different libraries, so each row fetches its own library's home on demand.
/// API client caching keeps repeat fetches cheap.
struct MultiLibraryServerRow: View {
    /// Library this row is pinned to. When nil, the row hasn't been assigned a
    /// library yet and renders nothing (the user picks via the customization
    /// sheet's library chip).
    let libraryID: LibraryIdentifier?
    let rowID: String
    /// Title to display while the row is still loading (or if the server
    /// returns no matching row). Falls back to the section's default localized
    /// title so the user always sees a labeled placeholder.
    let fallbackTitle: String

    @State private var audiobookRow: HomeRow<Audiobook>?
    @State private var personRow: HomeRow<Person>?
    @State private var seriesRow: HomeRow<Series>?
    /// Until the first load settles we keep rendering a placeholder rather
    /// than collapsing to `EmptyView`. An eagerly-mounted view that resolves
    /// to `EmptyView` does not reliably run `.task` inside a parent VStack —
    /// always rendering content guarantees the fetch fires.
    @State private var hasLoaded = false

    var body: some View {
        Group {
            if let row = audiobookRow, !row.entities.isEmpty {
                AudiobookRow(title: row.localizedLabel, small: false, audiobooks: row.entities)
            } else if let row = personRow, !row.entities.isEmpty {
                HomeRowContainer(title: row.localizedLabel) {
                    PersonGrid(people: row.entities)
                }
            } else if let row = seriesRow, !row.entities.isEmpty {
                HomeRowContainer(title: row.localizedLabel) {
                    SeriesHGrid(series: row.entities)
                }
            } else if !hasLoaded {
                HomeRowContainer(title: fallbackTitle) {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
            } else {
                EmptyView()
            }
        }
        .task(id: taskKey) {
            await load()
        }
    }

    private var taskKey: String {
        guard let libraryID else { return "_::_::\(rowID)" }
        return "\(libraryID.connectionID)::\(libraryID.libraryID)::\(rowID)"
    }

    private func load() async {
        guard let libraryID else {
            await MainActor.run {
                clearRows()
                hasLoaded = true
            }
            return
        }

        do {
            let home: ([HomeRow<Audiobook>], [HomeRow<Person>], [HomeRow<Series>]) = try await ABSClient[libraryID.connectionID].home(for: libraryID.libraryID)
            let books = await HomeRow.prepareForPresentation(home.0, connectionID: libraryID.connectionID)

            await MainActor.run {
                withAnimation {
                    clearRows()
                    audiobookRow = books.first { $0.id == rowID }
                    personRow = home.1.first { $0.id == rowID }
                    seriesRow = home.2.first { $0.id == rowID }
                    hasLoaded = true
                }
            }
        } catch {
            homeSectionRenderersLogger.warning("MultiLibraryServerRow fetch failed for \(libraryID.libraryID, privacy: .public)/\(rowID, privacy: .public): \(error, privacy: .public)")
            await MainActor.run {
                clearRows()
                hasLoaded = true
            }
        }
    }

    private func clearRows() {
        audiobookRow = nil
        personRow = nil
        seriesRow = nil
    }
}
