import Foundation

public struct ABBBook: Sendable, Hashable {
    public let id: String
    public let title: String
    public let url: URL
    public let author: String?
    public let narrator: String?
    public let series: String?
    public let seriesPosition: String?
    public let year: String?
    public let bookDescription: String?
    public let coverURL: URL?
    public let infoHash: String
    public let trackers: [String]
    public let size: String?
    public let language: String?
    public let bitrate: String?
    public let format: String?
    /// e.g. "Unabridged" / "Abridged".
    public let abridged: String?
    public let comments: [ABBComment]
    public let isExplicit: Bool

    public init(
        id: String,
        title: String,
        url: URL,
        author: String? = nil,
        narrator: String? = nil,
        series: String? = nil,
        seriesPosition: String? = nil,
        year: String? = nil,
        bookDescription: String? = nil,
        coverURL: URL? = nil,
        infoHash: String,
        trackers: [String] = [],
        size: String? = nil,
        language: String? = nil,
        bitrate: String? = nil,
        format: String? = nil,
        abridged: String? = nil,
        comments: [ABBComment] = [],
        isExplicit: Bool = false
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.author = author
        self.narrator = narrator
        self.series = series
        self.seriesPosition = seriesPosition
        self.year = year
        self.bookDescription = bookDescription
        self.coverURL = coverURL
        self.infoHash = infoHash
        self.trackers = trackers
        self.size = size
        self.language = language
        self.bitrate = bitrate
        self.format = format
        self.abridged = abridged
        self.comments = comments
        self.isExplicit = isExplicit
    }
}
