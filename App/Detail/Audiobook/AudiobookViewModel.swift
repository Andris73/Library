//
//  AudiobookViewModel.swift
//  Library
//
//  Created by Rasmus Krämer on 02.02.24.
//

import Foundation
import Combine
import SwiftUI
import OSLog
@Observable @MainActor
final class AudiobookViewModel: Sendable {
    private var observerSubscriptions = Set<AnyCancellable>()

    let logger: Logger
    let signposter: OSSignposter

    private(set) var audiobook: Audiobook

    var library: Library!

    var toolbarVisible: Bool

    private(set) var chapters: [Chapter]

    private(set) var sameAuthor: [(String, [Audiobook])]
    private(set) var sameSeries: [(Audiobook.SeriesFragment, [Audiobook])]
    private(set) var sameNarrator: [(String, [Audiobook])]

    private(set) var explore: [Audiobook]

    private(set) var bookmarks: [Bookmark]

    let sessionLoader: SessionLoader

    private(set) var notifyError: Bool
    private(set) var notifySuccess: Bool

    init(_ audiobook: Audiobook) {
        logger = Logger(subsystem: "com.Library.Library", category: "AudiobookViewModel")
        signposter = OSSignposter(logger: logger)

        self.audiobook = audiobook

        toolbarVisible = false

        chapters = []

        sameAuthor = []
        sameSeries = []
        sameNarrator = []

        explore = []

        bookmarks = []

        sessionLoader = .init(filter: .itemID(audiobook.id))

        notifyError = false
        notifySuccess = false

        PersistenceManager.shared.bookmark.events.changed
            .sink { [weak self] itemID in
                Task { @MainActor [weak self] in
                    guard let self, self.audiobook.id == itemID else {
                        return
                    }

                    await self.loadBookmarks()
                }
            }
            .store(in: &observerSubscriptions)

        ItemEventSource.shared.updated
            .sink { [weak self] connectionID, primaryID, groupingID in
                Task { @MainActor [weak self] in
                    guard let self, self.audiobook.id.isEqual(primaryID: primaryID, groupingID: groupingID, connectionID: connectionID) else {
                        return
                    }

                    self.load(refresh: true)
                }
            }
            .store(in: &observerSubscriptions)
    }
}

extension AudiobookViewModel {
    func load(refresh: Bool) {
        Task {
            await withTaskGroup(of: Void.self) {
                $0.addTask { await self.loadAudiobook() }

                $0.addTask { await self.loadAuthors() }
                $0.addTask { await self.loadSeries() }
                $0.addTask { await self.loadNarrators() }

                if refresh || explore.isEmpty {
                    $0.addTask { await self.loadExplore() }
                }

                $0.addTask { await self.loadBookmarks() }

                if refresh {
                    $0.addTask { await self.sessionLoader.refresh() }
                }
            }

            if refresh {
                try? await Library.refreshItem(itemID: self.audiobook.id)
                self.load(refresh: false)
            }
        }
    }

}

private extension AudiobookViewModel {
    func loadAudiobook() async {
        do {
            let book = try await ABSClient[audiobook.id.connectionID].book(itemID: audiobook.id)

            withAnimation {
                self.audiobook = book as! Audiobook
            }
        } catch {
            logger.warning("Failed to load audiobook \(self.audiobook.id, privacy: .public): \(error, privacy: .public)")
        }
    }

    func loadAuthors() async {
        let resolved = await withTaskGroup {
            let audiobook = audiobook

            for author in audiobook.authors {
                $0.addTask { () -> (String, [Audiobook])? in
                    do {
                        let authorID = try await ABSClient[self.audiobook.id.connectionID].authorID(from: self.audiobook.id.libraryID, name: author)
                        var (audiobooks, _) = try await ABSClient[self.audiobook.id.connectionID].audiobooks(filtered: authorID, sortOrder: .released, ascending: true, limit: 100, page: 0)

                        audiobooks = audiobooks.filter { $0 != audiobook }

                        guard !audiobooks.isEmpty else {
                            return nil
                        }

                        return (author, audiobooks)
                    } catch {
                        self.logger.warning("Failed to load related audiobooks for author \(author, privacy: .public): \(error, privacy: .public)")
                        return nil
                    }
                }
            }

            var resolved = [String: [Audiobook]]()

            for await result in $0 {
                guard let (author, audiobooks) = result else {
                    continue
                }

                resolved[author] = audiobooks
            }

            return resolved.sorted(by: { $0.0 < $1.0 })
        }

        withAnimation {
            self.sameAuthor = resolved
        }
    }

    func loadSeries() async {
        let resolved = await withTaskGroup {
            let audiobook = audiobook

            for series in audiobook.series {
                $0.addTask { () -> (Audiobook.SeriesFragment, [Audiobook])? in
                    do {
                        let seriesID: ItemIdentifier

                        if let id = series.id {
                            seriesID = id
                        } else {
                            seriesID = try await ABSClient[audiobook.id.connectionID].seriesID(from: self.library.id.libraryID, name: series.name)
                        }

                        var (audiobooks, _) = try await ABSClient[audiobook.id.connectionID].audiobooks(filtered: seriesID, sortOrder: nil, ascending: nil, limit: 20, page: 0)

                        audiobooks = audiobooks.filter { $0 != audiobook }

                        guard !audiobooks.isEmpty else {
                            return nil
                        }

                        return (series, audiobooks)
                    } catch {
                        self.logger.warning("Failed to load related audiobooks for series \(series.name, privacy: .public): \(error, privacy: .public)")
                        return nil
                    }
                }
            }

            var resolved = [Audiobook.SeriesFragment: [Audiobook]]()

            for await result in $0 {
                guard let (series, audiobooks) = result else {
                    continue
                }

                resolved[series] = audiobooks
            }

            return resolved.sorted(by: { $0.0.name < $1.0.name })
        }

        withAnimation {
            self.sameSeries = resolved
        }
    }

    func loadNarrators() async {
        let resolved = await withTaskGroup {
            let audiobook = audiobook

            for narrator in audiobook.narrators {
                $0.addTask { () -> (String, [Audiobook])? in
                    do {
                        var audiobooks = try await ABSClient[audiobook.id.connectionID].audiobooks(from: audiobook.id.libraryID, narratorName: narrator, page: 0, limit: 200)

                        audiobooks = audiobooks.filter { $0 != audiobook }

                        guard !audiobooks.isEmpty else {
                            return nil
                        }

                        return (narrator, audiobooks)
                    } catch {
                        self.logger.warning("Failed to load related audiobooks for narrator \(narrator, privacy: .public): \(error, privacy: .public)")
                        return nil
                    }
                }
            }

            var resolved = [String: [Audiobook]]()

            for await result in $0 {
                guard let (narrator, audiobooks) = result else {
                    continue
                }

                resolved[narrator] = audiobooks
            }

            return resolved.sorted(by: { $0.0 < $1.0 })
        }

        withAnimation {
            self.sameNarrator = resolved
        }
    }

    /// Random sample of audiobooks from this book's library, used to surface
    /// other things the user might enjoy. Pull-to-refresh reshuffles because
    /// the underlying `sort=random` API call already bypasses the API cache.
    /// Asking for 11 keeps us at 10 even after dropping the current book.
    func loadExplore() async {
        do {
            let books = try await ABSClient[audiobook.id.connectionID].audiobooksRandom(from: audiobook.id.libraryID, limit: 11)
            let filtered = books.filter { $0 != audiobook }.prefix(10)

            withAnimation {
                self.explore = Array(filtered)
            }
        } catch {
            logger.warning("Failed to load explore audiobooks for \(self.audiobook.id, privacy: .public): \(error, privacy: .public)")
        }
    }

    func loadBookmarks() async {
        guard let bookmarks = try? await PersistenceManager.shared.bookmark[audiobook.id] else {
            notifyError.toggle()

            return
        }

        withAnimation {
            self.bookmarks = bookmarks
        }
    }
}
