import Foundation

public struct ABBComment: Sendable, Identifiable, Hashable {
    public let id: String
    public let author: String
    public let date: String?
    /// Number of filled stars (0...5), when the comment carries a rating.
    public let rating: Int?
    public let body: String
    public let avatarURL: URL?

    public init(
        id: String,
        author: String,
        date: String? = nil,
        rating: Int? = nil,
        body: String,
        avatarURL: URL? = nil
    ) {
        self.id = id
        self.author = author
        self.date = date
        self.rating = rating
        self.body = body
        self.avatarURL = avatarURL
    }
}
