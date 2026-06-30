//
//  LibrarySchema.swift
//  LibraryKit
//
//  Created by Rasmus Krämer on 13.04.26.
//

import Foundation
import SwiftData

public enum LibrarySchema: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        .init(1, 0, 0)
    }

    public static var models: [any PersistentModel.Type] {[
        PersistedBook.self,

        PersistedAsset.self,
        PersistedBookmark.self,
        PersistedChapter.self,

        PersistedProgress.self,

        PersistedSearchIndexEntry.self,
        PersistedDiscoveredConnection.self,

        PersistedDominantColor.self,
        PersistedTabCustomization.self,
        PersistedLibraryIndex.self,
        PersistedHomeCustomization.self,

        PersistedConvenienceDownloadRetrieval.self,
        PersistedConvenienceDownloadDownloaded.self,
        PersistedConvenienceDownloadAssociation.self,

        PersistedHideFromContinueListening.self,

        PersistedActiveDownload.self,
    ]}
}
