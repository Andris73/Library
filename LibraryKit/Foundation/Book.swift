//
//  Book.swift
//  LibraryKit
//
//  Created by Rasmus Krämer on 09.10.23.
//

import Foundation

public class Book: Item, @unchecked Sendable {
    public let size: Int64?

    init(id: ItemIdentifier, name: String, authors: [String], description: String?, genres: [String], addedAt: Date, released: String?, size: Int64?) {
        self.size = size

        super.init(id: id, name: name, authors: authors, description: description, genres: genres, addedAt: addedAt, released: released)
    }

    required init(from decoder: Decoder) throws {
        self.size = try decoder.container(keyedBy: CodingKeys.self).decode(Int64.self, forKey: .size)

        try super.init(from: decoder)
    }

    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(size, forKey: .size)
    }

    enum CodingKeys: String, CodingKey {
        case size
    }
}
