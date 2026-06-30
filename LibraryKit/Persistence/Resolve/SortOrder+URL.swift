//
//  SortOrder+URL.swift
//  LibraryKit
//
//  Created by Rasmus Krämer on 14.11.24.
//

import Foundation

extension AudiobookSortOrder {
    var queryValue: String {
        switch self {
        case .sortName:
            "media.metadata.title"
        case .authorName:
            "media.metadata.authorName"
        case .released:
            "media.metadata.publishedYear"
        case .added:
            "addedAt"
        }
    }
}

extension AuthorSortOrder {
    var queryValue: String {
        switch self {
        case .firstNameLastName:
            "name"
        case .lastNameFirstName:
            "lastFirst"
        case .bookCount:
            "numBooks"
        case .added:
            "addedAt"
        }
    }
}

extension SeriesSortOrder {
    var queryValue: String {
        switch self {
        case .sortName:
            "name"
        case .bookCount:
            "numBooks"
        case .added:
            "addedAt"
        }
    }
}
