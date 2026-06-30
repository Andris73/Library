import Foundation

public struct TorrentInfo: Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let hashString: String
    public let status: TorrentStatus
    public let percentDone: Double
    public let rateDownload: Int64
    public let rateUpload: Int64
    public let error: Int
    public let errorString: String?
    /// Current upload ratio, or -1 when unknown.
    public let uploadRatio: Double
    public let seedRatioLimit: Double
    /// 0 = use global setting, 1 = use this torrent's `seedRatioLimit`, 2 = seed forever.
    public let seedRatioMode: Int

    public init(
        id: Int,
        name: String,
        hashString: String,
        status: TorrentStatus,
        percentDone: Double,
        rateDownload: Int64 = 0,
        rateUpload: Int64 = 0,
        error: Int = 0,
        errorString: String? = nil,
        uploadRatio: Double = -1,
        seedRatioLimit: Double = 0,
        seedRatioMode: Int = 0
    ) {
        self.id = id
        self.name = name
        self.hashString = hashString
        self.status = status
        self.percentDone = percentDone
        self.rateDownload = rateDownload
        self.rateUpload = rateUpload
        self.error = error
        self.errorString = errorString
        self.uploadRatio = uploadRatio
        self.seedRatioLimit = seedRatioLimit
        self.seedRatioMode = seedRatioMode
    }

    public var isComplete: Bool { percentDone >= 1.0 }
    public var isSeeding: Bool { status == .seeding || status == .seedWaiting }

    /// The upload ratio that counts as "done seeding". When the torrent has no
    /// explicit ratio limit, a ratio of 1.0 is treated as complete.
    public var seedTarget: Double {
        (seedRatioMode == 1 && seedRatioLimit > 0) ? seedRatioLimit : 1.0
    }

    /// Seeding progress in 0...1 toward `seedTarget`.
    public var seedProgress: Double {
        guard uploadRatio >= 0 else { return 0 }
        return min(uploadRatio / max(seedTarget, 0.01), 1.0)
    }
}

public enum TorrentStatus: Int, Sendable, Hashable {
    case stopped = 0
    case checkWaiting = 1
    case checking = 2
    case downloadWaiting = 3
    case downloading = 4
    case seedWaiting = 5
    case seeding = 6
    case isolated = 7

    public var isActive: Bool {
        switch self {
        case .downloading, .seeding, .checking: true
        default: false
        }
    }

    /// Stable string key persisted in `PersistedActiveDownload.status` and read
    /// by the Active Downloads UI.
    public var persistedKey: String {
        switch self {
        case .seeding, .seedWaiting: "seeding"
        case .stopped, .isolated: "stopped"
        default: "downloading"
        }
    }
}
