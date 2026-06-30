//
//  PersistedActiveDownload.swift
//  LibraryKit
//

import Foundation
import SwiftData

extension LibrarySchema {
    @Model
    public final class PersistedActiveDownload {
        #Index<PersistedActiveDownload>([\.torrentID], [\.infoHash], [\.status])
        #Unique<PersistedActiveDownload>([\.infoHash])

        public var torrentID: Int
        public private(set) var infoHash: String
        public var title: String
        public var author: String
        public var status: String
        public var progress: Double
        public var addedAt: Date
        public var downloadPath: String
        public var isFinished: Bool

        public init(
            torrentID: Int,
            infoHash: String,
            title: String,
            author: String,
            status: String = "downloading",
            progress: Double = 0,
            addedAt: Date = .now,
            downloadPath: String = "",
            isFinished: Bool = false
        ) {
            self.torrentID = torrentID
            self.infoHash = infoHash
            self.title = title
            self.author = author
            self.status = status
            self.progress = progress
            self.addedAt = addedAt
            self.downloadPath = downloadPath
            self.isFinished = isFinished
        }
    }
}
