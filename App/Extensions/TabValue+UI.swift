//
//  TabValue+UI.swift
//  Library
//
//  Created by Rasmus Krämer on 23.09.24.
//

import SwiftUI
extension TabValue {
    var label: String {
        switch self {
            case .audiobookHome:
                String(localized: "panel.home")
            case .audiobookSeries:
                String(localized: "panel.series")
            case .audiobookAuthors:
                String(localized: "panel.authors")
            case .audiobookNarrators:
                String(localized: "panel.narrators")
            case .audiobookBookmarks:
                String(localized: "panel.bookmarks")
            case .audiobookCollections:
                String(localized: "panel.collections")
            case .audiobookGenres:
                String(localized: "panel.genres")
            case .audiobookTags:
                String(localized: "panel.tags")
            case .audiobookLibrary:
                String(localized: "panel.library")
                String(localized: "panel.home")
                String(localized: "panel.latest")
                String(localized: "panel.library")

            case .playlists:
                String(localized: "panel.playlists")

            case .search:
                String(localized: "panel.search")

            case .custom(_, let label):
                label
            case .collection(let collection, _):
                collection.name

            case .downloaded:
                String(localized: "item.downloaded")

            case .multiLibrary:
                String(localized: "panel.multiLibrary")

            case .discover:
                String(localized: "panel.discover")

            case .loading:
                ""
        }
    }

    var image: String {
        switch self {
            case .audiobookHome:
                "house.fill"
            case .audiobookSeries:
                ItemIdentifier.ItemType.series.icon
            case .audiobookAuthors:
                ItemIdentifier.ItemType.author.icon
            case .audiobookNarrators:
                ItemIdentifier.ItemType.narrator.icon
            case .audiobookCollections:
                ItemIdentifier.ItemType.collection.icon
            case .audiobookGenres:
                "theatermasks.fill"
            case .audiobookTags:
                "tag.fill"
            case .audiobookBookmarks:
                "bookmark.fill"
            case .audiobookLibrary:
                "books.vertical.fill"
                "house.fill"
                "calendar.badge.clock"
                "square.split.2x2.fill"

            case .playlists:
                ItemIdentifier.ItemType.playlist.icon
            case .search:
                "magnifyingglass"

            case .custom(let tabValue, _):
                tabValue.image
            case .collection:
                ItemIdentifier.ItemType.collection.icon

            case .downloaded:
                "arrow.down"

            case .multiLibrary:
                "square.grid.3x3.fill"

            case .discover:
                "antenna.radiowaves.left.and.right"

            case .loading:
                "teddybear.fill"
        }
    }
}
