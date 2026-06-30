//
//  ProgressEntity.swift
//  LibraryKit
//
//  Created by Rasmus Krämer on 17.09.24.
//

import Foundation

public struct ProgressEntity: Sendable {
    public let id: String

    public let connectionID: String

    public let primaryID: String
    public let groupingID: String?

    public let progress: Percentage

    public let startedAt: Date?
    public let lastUpdate: Date
    public let finishedAt: Date?

    public init(id: String, connectionID: String, primaryID: String, groupingID: String?, progress: Percentage, startedAt: Date?, lastUpdate: Date, finishedAt: Date?) {
        self.id = id
        self.connectionID = connectionID

        self.primaryID = primaryID
        self.groupingID = groupingID

        self.progress = progress

        self.startedAt = startedAt
        self.lastUpdate = lastUpdate
        self.finishedAt = finishedAt
    }

    public var isFinished: Bool {
        progress >= 1
    }
}
