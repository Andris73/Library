//
//  ItemSubsystem.swift
//  LibraryKit
//
//  Created by Rasmus Krämer on 27.02.25.
//

import Foundation
import SwiftUI
import SwiftData
import OSLog

import RFVisuals

typealias PersistedDominantColor = LibrarySchema.PersistedDominantColor
typealias PersistedLibraryIndex = LibrarySchema.PersistedLibraryIndex

extension PersistenceManager {
    @ModelActor
    public final actor ItemSubsystem: Sendable {
        let logger = Logger(subsystem: "com.Library.LibraryKit", category: "ItemSubsystem")

        var colorCache = [ItemIdentifier: Task<Color?, Never>]()
    }
}

public extension PersistenceManager.ItemSubsystem {
    func dominantColor(of itemID: ItemIdentifier) async -> Color? {
        #if DEBUG
        if itemID.libraryID == "fixture" {
            return .orange
        }
        #endif

        if colorCache[itemID] == nil {
            colorCache[itemID] = .init {
                let key = itemID.description

                if let stored = try? self.modelContext.fetch(FetchDescriptor<PersistedDominantColor>(predicate: #Predicate { $0.itemID == key })).first {
                    return Color(red: stored.red, green: stored.green, blue: stored.blue)
                }

                let size: ImageSize = .regular

                guard let image = await ImageLoader.shared.platformImage(for: .init(itemID: itemID, size: size)) else {
                    return nil
                }

                let result: Color?

                guard let colors = try? await RFKVisuals.extractDominantColors(6, image: image) else {
                    return nil
                }

                let prepared = RFKVisuals.prepareForFiltering(colors)

                result = prepared.filter { $0.brightness > 0.3 && $0.saturation > 0.4 }.randomElement()?.color
                    ?? prepared.filter { $0.brightness > 0.3 && $0.saturation > 0.2 }.randomElement()?.color

                guard let result else {
                    return nil
                }

                let resolved = result.resolve(in: .init())

                let entity = PersistedDominantColor(itemID: key, red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue))
                self.modelContext.insert(entity)

                do {
                    try self.modelContext.save()
                } catch {
                    self.logger.error("Failed to store color for \(itemID): \(error)")
                }

                return result
            }
        }

        let color = await colorCache[itemID]?.value

        if color == nil {
            // A nil result is transient (image not loaded yet, or extraction failed),
            // so don't keep it cached — let a later request recompute the color.
            colorCache[itemID] = nil
        }

        return color
    }

    func libraryIndexMetadata(for libraryID: LibraryIdentifier) -> LibraryIndexMetadata? {
        let key = "\(libraryID.libraryID)-\(libraryID.connectionID)"

        guard let entity = try? modelContext.fetch(FetchDescriptor<PersistedLibraryIndex>(predicate: #Predicate { $0.libraryKey == key })).first else { return nil }

        return LibraryIndexMetadata(page: entity.page, totalItemCount: entity.totalItemCount, startDate: entity.startDate, endDate: entity.endDate)
    }
    func setLibraryIndexMetadata(_ metadata: LibraryIndexMetadata?, for libraryID: LibraryIdentifier) throws {
        let key = "\(libraryID.libraryID)-\(libraryID.connectionID)"

        if let metadata {
            if let existing = try modelContext.fetch(FetchDescriptor<PersistedLibraryIndex>(predicate: #Predicate { $0.libraryKey == key })).first {
                existing.page = metadata.page
                existing.totalItemCount = metadata.totalItemCount
                existing.startDate = metadata.startDate
                existing.endDate = metadata.endDate
            } else {
                modelContext.insert(PersistedLibraryIndex(libraryKey: key, page: metadata.page, totalItemCount: metadata.totalItemCount, startDate: metadata.startDate, endDate: metadata.endDate))
            }
        } else {
            try modelContext.delete(model: PersistedLibraryIndex.self, where: #Predicate { $0.libraryKey == key })
        }

        try modelContext.save()
    }

    func libraryIndexedIDs(for libraryID: LibraryIdentifier, subset: String) -> [ItemIdentifier] {
        let key = "\(libraryID.libraryID)-\(libraryID.connectionID)-\(subset)"

        guard let entity = try? modelContext.fetch(FetchDescriptor<PersistedLibraryIndex>(predicate: #Predicate { $0.libraryKey == key })).first,
              let data = entity.indexedIDsData else { return [] }

        return (try? JSONDecoder().decode([ItemIdentifier].self, from: data)) ?? []
    }
    func setLibraryIndexedIDs(_ IDs: [ItemIdentifier], for libraryID: LibraryIdentifier, subset: String) throws {
        let key = "\(libraryID.libraryID)-\(libraryID.connectionID)-\(subset)"
        let data = try JSONEncoder().encode(IDs)

        if let existing = try modelContext.fetch(FetchDescriptor<PersistedLibraryIndex>(predicate: #Predicate { $0.libraryKey == key })).first {
            existing.indexedIDsData = data
        } else {
            let entity = PersistedLibraryIndex(libraryKey: key, page: 0, indexedIDsData: data)
            modelContext.insert(entity)
        }

        try modelContext.save()
    }

    struct LibraryIndexMetadata: Codable, Sendable {
        public var page = 0
        public var totalItemCount: Int!

        public var startDate: Date?
        public var endDate: Date?

        public init() {
            totalItemCount = nil
        }

        init(page: Int, totalItemCount: Int?, startDate: Date?, endDate: Date?) {
            self.page = page
            self.totalItemCount = totalItemCount
            self.startDate = startDate
            self.endDate = endDate
        }

        public var isFinished: Bool {
            endDate != nil
        }
    }
}

extension PersistenceManager.ItemSubsystem {
    func invalidate() {
        colorCache.removeAll()
    }

    public func resetLibraryIndices() throws {
        try modelContext.delete(model: PersistedLibraryIndex.self)
        try modelContext.save()
    }

    func removePersistedData(itemID: ItemIdentifier) {
        let key = itemID.description

        try? modelContext.delete(model: PersistedDominantColor.self, where: #Predicate { $0.itemID == key })

        try? modelContext.save()
    }

    func purgeCachedData(itemID: ItemIdentifier) {
        let key = itemID.description

        try? modelContext.delete(model: PersistedDominantColor.self, where: #Predicate { $0.itemID == key })

        try? modelContext.save()
    }

    func purgeCachedData() {
        try? modelContext.delete(model: PersistedDominantColor.self)

        try? modelContext.save()
    }
}
