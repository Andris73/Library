import Foundation

public struct ABBSearchResult: Sendable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let detailURL: URL
    public let author: String?
    public let narrator: String?
    public let series: String?
    public let year: String?
    public let coverURL: URL?
    public let infoHash: String?
    public let isExplicit: Bool

    public init(
        id: String,
        title: String,
        detailURL: URL,
        author: String? = nil,
        narrator: String? = nil,
        series: String? = nil,
        year: String? = nil,
        coverURL: URL? = nil,
        infoHash: String? = nil,
        isExplicit: Bool = false
    ) {
        self.id = id
        self.title = title
        self.detailURL = detailURL
        self.author = author
        self.narrator = narrator
        self.series = series
        self.year = year
        self.coverURL = coverURL
        self.infoHash = infoHash
        self.isExplicit = isExplicit
    }
}
