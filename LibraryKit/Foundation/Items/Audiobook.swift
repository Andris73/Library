//
//  Audiobook.swift
//  LibraryKit
//
//  Created by Rasmus Krämer on 02.10.23.
//

import Foundation

public final class Audiobook: Book, @unchecked Sendable {
    public let subtitle: String?

    public let narrators: [String]
    public let series: [SeriesFragment]

    public let explicit: Bool
    public let abridged: Bool

    /// Audible identifier, when known. The most reliable cross-source key for an
    /// audiobook (ISBNs are usually absent on audio editions).
    public let asin: String?
    public let isbn: String?

    public init(id: ItemIdentifier, name: String, authors: [String], description: String?, genres: [String], addedAt: Date, released: String?, size: Int64?, subtitle: String?, narrators: [String], series: [SeriesFragment], explicit: Bool, abridged: Bool, asin: String? = nil, isbn: String? = nil) {
        self.subtitle = subtitle

        self.narrators = narrators
        self.series = series

        self.explicit = explicit
        self.abridged = abridged

        self.asin = asin
        self.isbn = isbn

        super.init(id: id, name: name, authors: authors, description: description, genres: genres, addedAt: addedAt, released: released, size: size)
    }

    required init(from decoder: Decoder) throws {
        self.subtitle = try decoder.container(keyedBy: CodingKeys.self).decode(String?.self, forKey: .subtitle)
        self.narrators = try decoder.container(keyedBy: CodingKeys.self).decode([String].self, forKey: .narrators)
        self.series = try decoder.container(keyedBy: CodingKeys.self).decode([SeriesFragment].self, forKey: .series)
        self.explicit = try decoder.container(keyedBy: CodingKeys.self).decode(Bool.self, forKey: .explicit)
        self.abridged = try decoder.container(keyedBy: CodingKeys.self).decode(Bool.self, forKey: .abridged)
        self.asin = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(String.self, forKey: .asin)
        self.isbn = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(String.self, forKey: .isbn)

        try super.init(from: decoder)
    }

    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(subtitle, forKey: .subtitle)
        try container.encode(narrators, forKey: .narrators)
        try container.encode(series, forKey: .series)
        try container.encode(explicit, forKey: .explicit)
        try container.encode(abridged, forKey: .abridged)
        try container.encodeIfPresent(asin, forKey: .asin)
        try container.encodeIfPresent(isbn, forKey: .isbn)
    }

    enum CodingKeys: String, CodingKey {
        case subtitle
        case narrators
        case series
        case explicit
        case abridged
        case asin
        case isbn
    }
}

// MARK: - Series Fragment

public extension Audiobook {
    struct SeriesFragment: Identifiable, Codable, Hashable, Sendable {
        public var id: ItemIdentifier?

        public let name: String
        public let sequence: Float?

        public init(id: ItemIdentifier?, name: String, sequence: Float?) {
            self.id = id
            self.name = name
            self.sequence = sequence
        }

        public var formattedName: String {
            if let formattedSequence {
                "\(name) #\(formattedSequence)"
            } else {
                "\(name)"
            }
        }

        public var formattedSequence: String? {
            guard let sequence else {
                return nil
            }

            let formatter = NumberFormatter()
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 2

            return formatter.string(from: NSNumber(value: sequence))
        }
    }
}

// MARK: - Helpers

public extension Audiobook {
    var seriesName: String? {
        if series.isEmpty {
            nil
        } else {
            series.map {
                if let formattedSequence = $0.formattedSequence {
                    return "\($0.name) #\(formattedSequence)"
                }

                return $0.name
            }.formatted(.list(type: .and, width: .short))
        }
    }
}
