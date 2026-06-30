//
//  FilterSort.swift
//  LibraryKit
//
//  Created by Rasmus Krämer on 02.07.24.
//

import Foundation

public enum ItemDisplayType: Int, Identifiable, Hashable, Codable, Sendable, CaseIterable {
    case grid
    case list

    public var id: Int {
        rawValue
    }

    public var next: Self {
        switch self {
        case .grid:
                .list
        case .list:
                .grid
        }
    }
}

public enum ItemFilter: Int, Identifiable, Hashable, Codable, Sendable, CaseIterable {
    case all
    case active
    case finished
    case notFinished

    public var id: Int {
        rawValue
    }
}

public enum AudiobookSortOrder: String, Identifiable, Hashable, Codable, Sendable, CaseIterable {
    case sortName
    case authorName
    case released
    case added
    public var id: String {
        rawValue
    }
}

public enum AuthorSortOrder: Int, Identifiable, Hashable, Codable, Sendable, CaseIterable {
    case firstNameLastName
    case lastNameFirstName
    case bookCount
    case added

    public var id: Int {
        rawValue
    }
}

public enum NarratorSortOrder: Int, Identifiable, Hashable, Codable, Sendable, CaseIterable {
    case name
    case bookCount

    public var id: Int {
        rawValue
    }
}

public enum SeriesSortOrder: String, Identifiable, Hashable, Codable, Sendable, CaseIterable {
    case sortName
    case bookCount
    case added

    public var id: String {
        rawValue
    }
}

public enum BookmarkSortOrder: Int, Identifiable, Hashable, Codable, Sendable, CaseIterable {
    case name
    case bookmarkCount

    public var id: Int {
        rawValue
    }
}


