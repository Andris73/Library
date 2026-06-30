//
//  ResolveCache.swift
//  LibraryKit
//
//  Created by Rasmus Krämer on 02.05.25.
//

import Combine
import Foundation
import OSLog

public actor ResolveCache: Sendable {
    private let logger = Logger(subsystem: "com.Library.LibraryKit", category: "ResolveCache")
    public let cachePath = LibraryKit.cacheDirectoryURL.appending(path: "Items")

    let memoryCache = NSCache<NSString, Item>()
    private var observerSubscriptions = Set<AnyCancellable>()

    var resolveItemID = [ItemIdentifier: Task<Item, Error>]()

    private init() {
        memoryCache.countLimit = 760
    }

    private func setupObserverSubscriptions() {
        OfflineMode.events.changed
            .sink { [weak self] _ in
                Self.scheduleInvalidation(for: self)
            }
            .store(in: &observerSubscriptions)
    }

    private nonisolated static func scheduleInvalidation(for cache: ResolveCache?) {
        guard let cache else {
            return
        }

        Task { [cache] in
            await cache.invalidate()
        }
    }

    private func invalidate() {
        resolveItemID.removeAll()
        memoryCache.removeAllObjects()
    }

    private enum ResolveError: Error {
        case invalidDiskCached

        case missingNarrator
    }

    public nonisolated static let shared: ResolveCache = {
        let cache = ResolveCache()

        Task {
            await cache.setupObserverSubscriptions()
        }

        return cache
    }()
}

public extension ResolveCache {
    func resolve(_ itemID: ItemIdentifier) async throws -> Item {
        if resolveItemID[itemID] == nil {
            resolveItemID[itemID] = .init {
                logger.info("Attempting to resolve item: \(itemID)")

                if let downloaded = await PersistenceManager.shared.download[itemID] {
                    return downloaded
                } else if let diskCached = await diskCached(primaryID: itemID.primaryID, groupingID: itemID.groupingID, connectionID: itemID.connectionID) {
                    return diskCached
                }

                guard await OfflineMode.shared.isAvailable(itemID.connectionID) else {
                    throw APIClientError.offline
                }

                logger.info("No downloaded or disk cached for \(itemID)")

                let item: Item

                switch itemID.type {
                case .audiobook:
                    item = try await ABSClient[itemID.connectionID].audiobook(with: itemID)
                case .author:
                    item = try await ABSClient[itemID.connectionID].author(with: itemID)
                case .narrator:
                    let narrators = try await ABSClient[itemID.connectionID].narrators(from: itemID.libraryID)
                    let narrator = narrators.first {
                        $0.id == itemID
                    }

                    guard let narrator else {
                        throw ResolveError.missingNarrator
                    }

                    item = narrator
                case .series:
                    item = try await ABSClient[itemID.connectionID].series(with: itemID)
                case .collection, .playlist:
                    item = try await ABSClient[itemID.connectionID].collection(with: itemID)
                }

                store(item: item)

                return item
            }
        }

        return try await resolveItemID[itemID]!.value
    }
}

// MARK: Helper

public extension ResolveCache {
    func flush() async {
        resolveItemID.removeAll()
        memoryCache.removeAllObjects()

        do {
            try FileManager.default.removeItem(at: cachePath)
        } catch CocoaError.fileNoSuchFile, CocoaError.fileReadNoSuchFile {
            // expected: cache may not exist yet
        } catch {
            logger.warning("Failed to remove cache directory \(self.cachePath.path, privacy: .public): \(error, privacy: .public)")
        }
    }
    func invalidate(itemID: ItemIdentifier) {
        let cacheKey = memoryCacheKey(primaryID: itemID.primaryID, groupingID: itemID.groupingID, connectionID: itemID.connectionID)

        resolveItemID.removeValue(forKey: itemID)
        memoryCache.removeObject(forKey: cacheKey)

        do {
            try FileManager.default.removeItem(atPath: diskPath(primaryID: itemID.primaryID, groupingID: itemID.groupingID, connectionID: itemID.connectionID).relativePath)
        } catch CocoaError.fileNoSuchFile, CocoaError.fileReadNoSuchFile {
            // expected: disk cache may not exist
        } catch {
            logger.warning("Failed to remove cached item file for \(itemID, privacy: .public): \(error, privacy: .public)")
        }
    }

    func invalidate(primaryID: ItemIdentifier.PrimaryID, groupingID: ItemIdentifier.GroupingID?, connectionID: ItemIdentifier.ConnectionID) {
        let cacheKey = memoryCacheKey(primaryID: primaryID, groupingID: groupingID, connectionID: connectionID)

        resolveItemID = resolveItemID.filter {
            !($0.key.primaryID == primaryID && $0.key.groupingID == groupingID && $0.key.connectionID == connectionID)
        }

        memoryCache.removeObject(forKey: cacheKey)

        do {
            try FileManager.default.removeItem(atPath: diskPath(primaryID: primaryID, groupingID: groupingID, connectionID: connectionID).relativePath)
        } catch CocoaError.fileNoSuchFile, CocoaError.fileReadNoSuchFile {
            // expected: disk cache may not exist
        } catch {
            logger.warning("Failed to remove cached item file for primaryID=\(primaryID, privacy: .public) groupingID=\(groupingID ?? "<nil>", privacy: .public) connectionID=\(connectionID, privacy: .public): \(error, privacy: .public)")
        }
    }
}

// MARK: Disk & Memory cache

private extension ResolveCache {
    func memoryCacheKey(primaryID: ItemIdentifier.PrimaryID, groupingID: ItemIdentifier.GroupingID?, connectionID: ItemIdentifier.ConnectionID) -> NSString {
        NSString(string: "\(connectionID)_\(primaryID)_\(groupingID ?? "-")")
    }

    func diskPath(connectionID: ItemIdentifier.ConnectionID) -> URL {
        cachePath
            .appending(path: connectionID.urlSafe)
    }
    func diskPath(primaryID: ItemIdentifier.PrimaryID, groupingID: ItemIdentifier.GroupingID?, connectionID: ItemIdentifier.ConnectionID) -> URL {
        diskPath(connectionID: connectionID)
            .appending(path: "\(primaryID)_\(groupingID ?? "-")")
    }

    func diskCached(primaryID: ItemIdentifier.PrimaryID, groupingID: ItemIdentifier.GroupingID?, connectionID: ItemIdentifier.ConnectionID) async -> Item? {
        if let memoryCached = memoryCache.object(forKey: memoryCacheKey(primaryID: primaryID, groupingID: groupingID, connectionID: connectionID)) {
            return memoryCached
        }

        let diskPath = diskPath(primaryID: primaryID, groupingID: groupingID, connectionID: connectionID)

        guard FileManager.default.fileExists(atPath: diskPath.path) else {
            return nil
        }

        let content: Data

        do {
            content = try Data(contentsOf: diskPath)
        } catch {
            logger.warning("Failed to read cached item file at \(diskPath.path, privacy: .public): \(error, privacy: .public)")
            return nil
        }

        do {
            guard let result = try JSONDecoder().decode(DiskCachedItem.self, from: content).item else {
                throw ResolveError.invalidDiskCached
            }

            logger.info("Using disk cache for item \(result.id)")
            return result
        } catch {
            logger.error("Failed to decode cached item file at \(diskPath.path, privacy: .public): \(error, privacy: .public)")

            do {
                try FileManager.default.removeItem(at: diskPath)
            } catch {
                logger.warning("Failed to delete corrupted cache file at \(diskPath.path, privacy: .public): \(error, privacy: .public)")
            }

            return nil
        }
    }
    func store(item: Item) {
        let primaryID = item.id.primaryID
        let groupingID = item.id.groupingID
        let connectionID = item.id.connectionID

        memoryCache.setObject(item, forKey: memoryCacheKey(primaryID: primaryID, groupingID: groupingID, connectionID: connectionID))

        let cached = DiskCachedItem(item: item)

        do {
            let encoded = try JSONEncoder().encode(cached)

            try FileManager.default.createDirectory(at: diskPath(connectionID: connectionID), withIntermediateDirectories: true)
            try encoded.write(to: diskPath(primaryID: primaryID, groupingID: groupingID, connectionID: connectionID))

            logger.info("Stored item \(item.id) on disk")
        } catch {
            logger.error("Failure to cache item: \(error)")
        }
    }
}

private struct DiskCachedItem: Codable {
    let itemID: ItemIdentifier

    let audiobook: Audiobook?
    let series: Series?

    let person: Person?
    let collection: ItemCollection?

    init(item: Item) {
        itemID = item.id

        audiobook = item as? Audiobook
        series = item as? Series

        person = item as? Person
        collection = item as? ItemCollection
    }

    var item: Item? {
        get {
            audiobook ?? series ?? person ?? collection
        }
    }
}
