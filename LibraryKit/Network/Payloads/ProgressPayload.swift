//
//  ProgressPayload.swift
//  LibraryKit
//

import Foundation

public struct ProgressPayload: Sendable, Codable {
    public let id: String
    public let libraryItemId: String

    public let progress: Double?

    public let isFinished: Bool
    public let hideFromContinueListening: Bool?

    public let lastUpdate: Int64?
    public let startedAt: Int64?
    public let finishedAt: Int64?
}
