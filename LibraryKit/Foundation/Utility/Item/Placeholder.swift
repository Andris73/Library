//
//  Placeholder.swift
//  LibraryKit
//
//  Created by Rasmus Krämer on 31.08.24.
//

import Foundation

public extension Audiobook {
    static let placeholder: Audiobook = .init(
        id: .init(primaryID: "placeholder", groupingID: "placeholder", libraryID: "placeholder", connectionID: "placeholder", type: .audiobook),
        name: "Placeholder",
        authors: [],
        description: nil,
        genres: [],
        addedAt: .now,
        released: nil,
        size: nil,
        duration: 0,
        subtitle: nil,
        narrators: [],
        series: [],
        explicit: false,
        abridged: false)
}

public extension ItemIdentifier {
    var isPlaceholder: Bool {
        primaryID == "placeholder"
    }
}
