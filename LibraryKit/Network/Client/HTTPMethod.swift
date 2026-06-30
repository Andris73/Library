//
//  HTTPMethod.swift
//  LibraryKit
//

import Foundation

public enum HTTPMethod: Sendable {
    case get
    case post
    case patch
    case delete

    var value: String {
        switch self {
        case .get: "GET"
        case .post: "POST"
        case .patch: "PATCH"
        case .delete: "DELETE"
        }
    }
}
