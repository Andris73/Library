//
//  Collection+Convert.swift
//  LibraryKit
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.Library.LibraryKit", category: "Collection+Convert")

extension ItemCollection {
    convenience init?(payload: ItemPayload, type: CollectionType, connectionID: ItemIdentifier.ConnectionID) {
        guard let libraryID = payload.libraryId else {
            logger.warning("Skipping collection conversion for \(payload.id, privacy: .public): missing libraryId")
            return nil
        }
        guard let name = payload.name else {
            logger.warning("Skipping collection conversion for \(payload.id, privacy: .public): missing name")
            return nil
        }

        if (payload.books?.isEmpty ?? true) && (payload.playlistItems?.isEmpty ?? true) {
            logger.debug("Collection \(payload.id, privacy: .public) has no books or playlistItems")
        }

        let items: [Item] = payload.books?.compactMap { Audiobook(payload: $0, libraryID: libraryID, connectionID: connectionID) } ?? payload.playlistItems?.compactMap {
            if let libraryItem = $0.libraryItem, let audiobook = Audiobook(payload: libraryItem, libraryID: libraryID, connectionID: connectionID) {
                audiobook
            } else {
                nil
            }
        } ?? []

        self.init(id: .init(primaryID: payload.id, groupingID: nil, libraryID: libraryID, connectionID: connectionID, type: type.itemType),
                  name: name,
                  description: payload.description,
                  addedAt: Date(timeIntervalSince1970: (payload.createdAt ?? 0) / 1000),
                  items: items)
    }
}
