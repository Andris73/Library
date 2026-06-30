//
//  AuthorizationStrategy.swift
//  LibraryKit
//
//  Created by Rasmus Krämer on 15.08.25.
//

public enum AuthorizationStrategy: Int, Identifiable, Sendable {
    case usernamePassword
    case openID

    public var id: Int {
        rawValue
    }
}
