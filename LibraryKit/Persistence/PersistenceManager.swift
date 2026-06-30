//
//  PersistenceManager.swift
//  LibraryKit
//
//  Created by Rasmus Krämer on 02.10.23.
//

import Foundation
import OSLog
import SwiftData
import Intents
import AppIntents

public final class PersistenceManager: Sendable {
    let logger = Logger(subsystem: "com.Library.LibraryKit", category: "PersistenceManager")

    public let modelContainer: ModelContainer

    public let authorization: AuthorizationSubsystem

    public let progress: ProgressSubsystem

    public let download: DownloadSubsystem
    public let convenienceDownload: ConvenienceDownloadSubsystem

    public let item: ItemSubsystem
    public let bookmark: BookmarkSubsystem

    public let customization: CustomizationSubsystem
    public let homeCustomization: HomeCustomizationSubsystem

    public let downloadTracker: DownloadTrackerSubsystem

    public let webSocket: WebSocketSubsystem

    private init() {
        let schema = Schema(versionedSchema: LibrarySchema.self)

        let modelConfiguration = ModelConfiguration("Library",
                           schema: schema,
                           isStoredInMemoryOnly: false,
                           allowsSave: true,
                           groupContainer: LibraryKit.enableCentralized ? .identifier(LibraryKit.groupContainer) : .none,
                           cloudKitDatabase: .none)

        modelContainer = try! ModelContainer(for: schema, migrationPlan: nil, configurations: [
            modelConfiguration,
        ])

        authorization = .init(modelContainer: modelContainer)

        progress = .init(modelContainer: modelContainer)

        download = .init(modelContainer: modelContainer)
        convenienceDownload = .init(modelContainer: modelContainer)

        item = .init(modelContainer: modelContainer)
        bookmark = .init(modelContainer: modelContainer)

        customization = .init(modelContainer: modelContainer)
        homeCustomization = .init(modelContainer: modelContainer)

        downloadTracker = .init(modelContainer: modelContainer)

        webSocket = .init()

        Task { [convenienceDownload] in
            await convenienceDownload.bootstrap()
        }
    }

    public func remove(itemID: ItemIdentifier) async {
        await bookmark.remove(itemID: itemID)
        await progress.remove(itemID: itemID)

        do {
            try await download.remove(itemID)
        } catch {
            logger.warning("Failed to remove download while removing item \(itemID, privacy: .public): \(error, privacy: .public)")
        }
        await convenienceDownload.remove(itemID: itemID, configurationID: nil)

        await item.removePersistedData(itemID: itemID)

        do {
            try await IntentDonationManager.shared.deleteDonations(matching: .entityIdentifier(EntityIdentifier(for: ItemEntity.self, identifier: itemID)))
        } catch {
            logger.debug("Failed to delete ItemEntity intent donations for \(itemID, privacy: .public): \(error, privacy: .public)")
        }

        do {
            try await INInteraction.delete(with: itemID.description)
        } catch {
            logger.debug("Failed to delete INInteraction for \(itemID, privacy: .public): \(error, privacy: .public)")
        }

        NSUserActivity.deleteSavedUserActivities(withPersistentIdentifiers: [itemID.description]) {}

        await ResolveCache.shared.flush()
    }
    public func remove(connectionID: ItemIdentifier.ConnectionID) async {
        await bookmark.remove(connectionID: connectionID)
        await progress.remove(connectionID: connectionID)

        await download.remove(connectionID: connectionID)
        await convenienceDownload.purge(connectionID: connectionID)

        await authorization.remove(connectionID: connectionID)

        await ResolveCache.shared.flush()
    }
    public func removeAllDownloads() async throws {
        try await download.removeAll()
        await convenienceDownload.purge()
    }

    public func refreshItem(itemID: ItemIdentifier) async throws {
        await ResolveCache.shared.invalidate(itemID: itemID)
        await item.purgeCachedData(itemID: itemID)
        await item.invalidate()
    }
    public func invalidateCache() async throws {
        await item.purgeCachedData()
        await item.invalidate()

        await customization.purgeAll()
        await homeCustomization.purgeAll()

        try await download.invalidateStatusCache()
    }
}

enum PersistenceError: Error {
    case missing
    case existing

    case busy
    case blocked

    case notPermitted

    case unsupportedItemType
    case unsupportedDownloadCodec

    case serverNotFound
    case keychainInsertFailed
    case keychainRetrieveFailed
}

// MARK: Singleton

public extension PersistenceManager {
    static let shared = PersistenceManager()
}
