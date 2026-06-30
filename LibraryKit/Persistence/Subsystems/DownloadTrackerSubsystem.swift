//
//  DownloadTrackerSubsystem.swift
//  LibraryKit
//

import Combine
import Foundation
import OSLog
import SwiftData

typealias PersistedActiveDownload = LibrarySchema.PersistedActiveDownload

extension PersistenceManager {
    public final actor DownloadTrackerSubsystem: ModelActor {
        public final class EventSource: @unchecked Sendable {
            public let downloadsChanged = PassthroughSubject<Void, Never>()

            init() {}
        }

        public let modelExecutor: any SwiftData.ModelExecutor
        public let modelContainer: SwiftData.ModelContainer

        let logger: Logger
        public nonisolated let events = EventSource()

        init(modelContainer: SwiftData.ModelContainer) {
            let modelContext = ModelContext(modelContainer)
            self.modelExecutor = DefaultSerialModelExecutor(modelContext: modelContext)
            self.modelContainer = modelContainer
            self.logger = Logger(subsystem: "com.Library.LibraryKit", category: "DownloadTracker")
        }
    }
}

public extension PersistenceManager.DownloadTrackerSubsystem {
    func trackDownload(torrentID: Int, infoHash: String, title: String, author: String, downloadPath: String) {
        let existing = fetch(infoHash: infoHash)
        if let existing {
            existing.torrentID = torrentID
            existing.title = title
            existing.author = author
            existing.downloadPath = downloadPath
            existing.status = "downloading"
            existing.progress = 0
            existing.isFinished = false
        } else {
            modelContext.insert(PersistedActiveDownload(
                torrentID: torrentID,
                infoHash: infoHash,
                title: title,
                author: author,
                downloadPath: downloadPath
            ))
        }
        save()
        events.downloadsChanged.send()
    }

    func updateProgress(infoHash: String, progress: Double, status: String) {
        guard let download = fetch(infoHash: infoHash) else { return }
        download.progress = progress
        download.status = status
        if progress >= 1.0 || status == "seeding" || status == "stopped" {
            download.isFinished = true
        }
        save()
        events.downloadsChanged.send()
    }

    func updateProgress(torrentID: Int, progress: Double, status: String) {
        guard let download = fetch(torrentID: torrentID) else { return }
        download.progress = progress
        download.status = status
        if progress >= 1.0 || status == "seeding" || status == "stopped" {
            download.isFinished = true
        }
        save()
        events.downloadsChanged.send()
    }

    func removeDownload(infoHash: String) {
        guard let download = fetch(infoHash: infoHash) else { return }
        modelContext.delete(download)
        save()
        events.downloadsChanged.send()
    }

    func removeDownload(torrentID: Int) {
        guard let download = fetch(torrentID: torrentID) else { return }
        modelContext.delete(download)
        save()
        events.downloadsChanged.send()
    }
}

public extension PersistenceManager.DownloadTrackerSubsystem {
    var activeDownloads: [LibrarySchema.PersistedActiveDownload] {
        let descriptor = FetchDescriptor<LibrarySchema.PersistedActiveDownload>(
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    var inProgressDownloads: [LibrarySchema.PersistedActiveDownload] {
        let descriptor = FetchDescriptor<LibrarySchema.PersistedActiveDownload>(
            predicate: #Predicate { !$0.isFinished },
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    var finishedDownloads: [LibrarySchema.PersistedActiveDownload] {
        let descriptor = FetchDescriptor<LibrarySchema.PersistedActiveDownload>(
            predicate: #Predicate { $0.isFinished },
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}

private extension PersistenceManager.DownloadTrackerSubsystem {
    func fetch(infoHash: String) -> PersistedActiveDownload? {
        var descriptor = FetchDescriptor<PersistedActiveDownload>(
            predicate: #Predicate { $0.infoHash == infoHash }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    func fetch(torrentID: Int) -> PersistedActiveDownload? {
        var descriptor = FetchDescriptor<PersistedActiveDownload>(
            predicate: #Predicate { $0.torrentID == torrentID }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    func save() {
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save download tracker context: \(error, privacy: .public)")
        }
    }
}
