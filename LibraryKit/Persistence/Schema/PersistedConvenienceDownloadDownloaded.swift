//
//  PersistedConvenienceDownloadDownloaded.swift
//  LibraryKit
//
//  Created by Rasmus Krämer on 04.05.26.
//

import Foundation
import SwiftData

extension LibrarySchema {
    @Model
    public final class PersistedConvenienceDownloadDownloaded {
        #Index<PersistedConvenienceDownloadDownloaded>([\.configurationID])
        #Unique<PersistedConvenienceDownloadDownloaded>([\.configurationID])

        public private(set) var configurationID: String
        public var itemIDsData: Data

        public init(configurationID: String, itemIDsData: Data) {
            self.configurationID = configurationID
            self.itemIDsData = itemIDsData
        }
    }
}
