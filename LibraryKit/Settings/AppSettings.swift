//
//  AppSettings.swift
//  LibraryKit
//
//  Created by Rasmus Krämer on 13.04.26.
//

import Foundation
import Observation
import OSLog

// `@unchecked Sendable` rationale: every property is backed by `UserDefaults`
// which is thread-safe, and primitive Bool/Int writes are atomic. The in-memory
// `@Observable` shadow is read/written from many contexts (MainActor UI,
// actor-isolated subsystems). Pinning to `@MainActor` would be the type-safe
// choice but cascades through every framework that reads from a non-MainActor
// context (PlaybackReporter, ConvenienceDownloadSubsystem, etc.). Revisit when
// those callers are themselves moved to MainActor or when a settings-snapshot
// pattern is introduced.
@Observable
public final class AppSettings: @unchecked Sendable {
    public static let shared = AppSettings()

    @ObservationIgnored private let suite: UserDefaults
    @ObservationIgnored private let logger = Logger(subsystem: "com.Library.LibraryKit", category: "AppSettings")

    // MARK: - Settings

    public var removeFinishedDownloads = true {
        didSet { suite.set(removeFinishedDownloads, forKey: "removeFinishedDownloads") }
    }

    public var forceAspectRatio = false {
        didSet { suite.set(forceAspectRatio, forKey: "forceAspectRatio") }
    }

    public var groupAudiobooksInSeries = true {
        didSet { suite.set(groupAudiobooksInSeries, forKey: "groupAudiobooksInSeries") }
    }

    // MARK: Advanced

    public var enableSerifFont = true {
        didSet { suite.set(enableSerifFont, forKey: "enableSerifFont") }
    }

    public var showSingleEntryGroupedSeries = true {
        didSet { suite.set(showSingleEntryGroupedSeries, forKey: "showSingleEntryGroupedSeries") }
    }

    public var itemImageStatusPercentageText = false {
        didSet { suite.set(itemImageStatusPercentageText, forKey: "itemImageStatusPercentageText") }
    }

    public var allowCellularDownloads = false {
        didSet { suite.set(allowCellularDownloads, forKey: "allowCellularDownloads") }
    }

    public var tintColor: TintColor = .Library {
        didSet { encodeCodable(tintColor, forKey: "tintColor") }
    }

    public var colorScheme: ConfiguredColorScheme = .system {
        didSet { suite.set(colorScheme.rawValue, forKey: "colorScheme") }
    }

    public var enableConvenienceDownloads = true {
        didSet { suite.set(enableConvenienceDownloads, forKey: "enableConvenienceDownloads") }
    }

    public var listenTimeTarget = 30 {
        didSet { suite.set(listenTimeTarget, forKey: "listenTimeTarget") }
    }

    // MARK: - Filtering & Sorting

    public var audiobooksAscending = false {
        didSet { suite.set(audiobooksAscending, forKey: "audiobooksAscending") }
    }

    public var audiobooksSortOrder: AudiobookSortOrder = .added {
        didSet { suite.set(audiobooksSortOrder.rawValue, forKey: "audiobookSortOrder") }
    }

    public var audiobooksFilter: ItemFilter = .all {
        didSet { suite.set(audiobooksFilter.rawValue, forKey: "audiobooksFilter") }
    }

    public var audiobooksRestrictToPersisted = false {
        didSet { suite.set(audiobooksRestrictToPersisted, forKey: "audiobooksRestrictToPersisted") }
    }

    public var audiobooksDisplayType: ItemDisplayType = .list {
        didSet { suite.set(audiobooksDisplayType.rawValue, forKey: "audiobooksDisplayType") }
    }

    public var authorsAscending = true {
        didSet { suite.set(authorsAscending, forKey: "authorsAscending") }
    }

    public var authorsSortOrder: AuthorSortOrder = .firstNameLastName {
        didSet { suite.set(authorsSortOrder.rawValue, forKey: "authorsSortOrder") }
    }

    public var narratorsAscending = true {
        didSet { suite.set(narratorsAscending, forKey: "narratorsAscending") }
    }

    public var narratorsSortOrder: NarratorSortOrder = .name {
        didSet { suite.set(narratorsSortOrder.rawValue, forKey: "narratorsSortOrder") }
    }

    public var seriesSortOrder: SeriesSortOrder = .sortName {
        didSet { suite.set(seriesSortOrder.rawValue, forKey: "seriesSortOrder") }
    }

    public var seriesAscending = true {
        didSet { suite.set(seriesAscending, forKey: "seriesAscending") }
    }

    public var seriesDisplayType: ItemDisplayType = .grid {
        didSet { suite.set(seriesDisplayType.rawValue, forKey: "seriesDisplayType") }
    }

    public var bookmarksAscending = true {
        didSet { suite.set(bookmarksAscending, forKey: "bookmarksAscending") }
    }

    public var bookmarksSortOrder: BookmarkSortOrder = .name {
        didSet { suite.set(bookmarksSortOrder.rawValue, forKey: "bookmarksSortOrder") }
    }

    public var genresAscending = true {
        didSet { suite.set(genresAscending, forKey: "genresAscending") }
    }

    public var tagsAscending = true {
        didSet { suite.set(tagsAscending, forKey: "tagsAscending") }
    }

    // MARK: - Widgets (shared suite)

    public var spotlightIndexCompletionDate: Date? = nil {
        didSet { suite.set(spotlightIndexCompletionDate, forKey: "spotlightIndexCompletionDate") }
    }

    public var lastConvenienceDownloadRun: Date? = nil {
        didSet { suite.set(lastConvenienceDownloadRun, forKey: "lastConvenienceDownloadRun") }
    }

    public var lastBuild: String? = nil {
        didSet { suite.set(lastBuild, forKey: "lastBuild") }
    }

    public var lastToSUpdate: Int? = nil {
        didSet { suite.set(lastToSUpdate, forKey: "lastToSUpdate") }
    }

    public var lastWhatsNewVersion: Int? = nil {
        didSet { suite.set(lastWhatsNewVersion, forKey: "lastWhatsNewVersion") }
    }

    public var lastCheckedServerVersion: String? = nil {
        didSet { suite.set(lastCheckedServerVersion, forKey: "lastCheckedServerVersion") }
    }

    public var pinnedTabValues: [TabValue] = [] {
        didSet { encodeCodable(pinnedTabValues, forKey: "pinnedTabValues") }
    }

    public var isOffline = false {
        didSet { suite.set(isOffline, forKey: "isOffline") }
    }

    // MARK: - Multiplatform keys

    public var lastTabValue: TabValue? = nil {
        didSet { encodeCodable(lastTabValue, forKey: "lastTabValue") }
    }

    public var hiddenLibraries: Set<LibraryIdentifier> = [] {
        didSet { encodeCodable(hiddenLibraries, forKey: "hiddenLibraries") }
    }

    public var carPlayTabBarLibraries: [Library]? = nil {
        didSet { encodeCodable(carPlayTabBarLibraries, forKey: "carPlayTabBarLibraries") }
    }

    public var carPlayShowOtherLibraries = true {
        didSet { suite.set(carPlayShowOtherLibraries, forKey: "carPlayShowOtherLibraries") }
    }

    public var enableHapticFeedback = true {
        didSet { suite.set(enableHapticFeedback, forKey: "enableHapticFeedback") }
    }

    public var hideSearchTab = false {
        didSet { suite.set(hideSearchTab, forKey: "hideSearchTab") }
    }

    // MARK: - AudiobookBay & Transmission

    public var abbServerURL: String? = nil {
        didSet { suite.set(abbServerURL, forKey: "abbServerURL") }
    }

    public var transmissionURL: String? = nil {
        didSet { suite.set(transmissionURL, forKey: "transmissionURL") }
    }

    public var transmissionUsername: String? = nil {
        didSet { suite.set(transmissionUsername, forKey: "transmissionUsername") }
    }

    public var transmissionPassword: String? = nil {
        didSet { suite.set(transmissionPassword, forKey: "transmissionPassword") }
    }

    public var downloadPathTemplate: String = "{author}/{series}/{title}" {
        didSet { suite.set(downloadPathTemplate, forKey: "downloadPathTemplate") }
    }

    /// Slugs of Discover genres the user has pinned, in pinned order. Pinned
    /// genres are shown first in the genre pill row.
    public var pinnedGenreSlugs: [String] = [] {
        didSet { suite.set(pinnedGenreSlugs, forKey: "pinnedGenreSlugs") }
    }

    /// A user-supplied Hardcover API token, used to enrich Discover series
    /// pages with real series metadata (descriptions, ordering).
    public var hardcoverAPIToken: String? = nil {
        didSet { suite.set(hardcoverAPIToken, forKey: "hardcoverAPIToken") }
    }

    /// When enabled, titles AudiobookBay flags with a "Sex Scenes" category are
    /// hidden from Discover search, genre listings, and shelves.
    public var hideExplicitContent: Bool = false {
        didSet { suite.set(hideExplicitContent, forKey: "hideExplicitContent") }
    }

    /// When enabled, Discover shelves hide titles already present in the user's
    /// Audiobookshelf library.
    public var hideOwnedTitles: Bool = true {
        didSet { suite.set(hideOwnedTitles, forKey: "hideOwnedTitles") }
    }

    // MARK: - Init

    private init() {
        suite = LibraryKit.enableCentralized
            ? (UserDefaults(suiteName: LibraryKit.groupContainer) ?? .standard)
            : .standard

        // Load persisted values (didSet does NOT fire during init)

        removeFinishedDownloads = suite.object(forKey: "removeFinishedDownloads") as? Bool ?? true
        forceAspectRatio = suite.object(forKey: "forceAspectRatio") as? Bool ?? false
        groupAudiobooksInSeries = suite.object(forKey: "groupAudiobooksInSeries") as? Bool ?? true

        enableSerifFont = suite.object(forKey: "enableSerifFont") as? Bool ?? true
        showSingleEntryGroupedSeries = suite.object(forKey: "showSingleEntryGroupedSeries") as? Bool ?? true
        itemImageStatusPercentageText = suite.object(forKey: "itemImageStatusPercentageText") as? Bool ?? false
        lockSeekBar = suite.object(forKey: "lockSeekBar") as? Bool ?? false
        replaceVolumeWithTotalProgress = suite.object(forKey: "replaceVolumeWithTotalProgress") as? Bool ?? true
        allowCellularDownloads = suite.object(forKey: "allowCellularDownloads") as? Bool ?? false
        if let val: [Double] = decodeCodable(forKey: "sleepTimerIntervals") { sleepTimerIntervals = val }
        sleepTimerExtendInterval = suite.object(forKey: "sleepTimerExtendInterval") as? Double ?? 1200
        sleepTimerExtendChapterAmount = suite.object(forKey: "sleepTimerExtendChapterAmount") as? Int ?? 1
        extendSleepTimerByPreviousSetting = suite.object(forKey: "extendSleepTimerByPreviousSetting") as? Bool ?? true

        if let val: TintColor = decodeCodable(forKey: "tintColor") { tintColor = val }
        if let raw = suite.object(forKey: "colorScheme") as? Int,
           let val = ConfiguredColorScheme(rawValue: raw) { colorScheme = val }

        enableConvenienceDownloads = suite.object(forKey: "enableConvenienceDownloads") as? Bool ?? true
        listenTimeTarget = suite.object(forKey: "listenTimeTarget") as? Int ?? 30

        audiobooksAscending = suite.object(forKey: "audiobooksAscending") as? Bool ?? false
        if let raw = suite.object(forKey: "audiobookSortOrder") as? String,
           let val = AudiobookSortOrder(rawValue: raw) { audiobooksSortOrder = val }
        if let raw = suite.object(forKey: "audiobooksFilter") as? Int,
           let val = ItemFilter(rawValue: raw) { audiobooksFilter = val }
        audiobooksRestrictToPersisted = suite.object(forKey: "audiobooksRestrictToPersisted") as? Bool ?? false
        if let raw = suite.object(forKey: "audiobooksDisplayType") as? Int,
           let val = ItemDisplayType(rawValue: raw) { audiobooksDisplayType = val }

        authorsAscending = suite.object(forKey: "authorsAscending") as? Bool ?? true
        if let raw = suite.object(forKey: "authorsSortOrder") as? Int,
           let val = AuthorSortOrder(rawValue: raw) { authorsSortOrder = val }

        narratorsAscending = suite.object(forKey: "narratorsAscending") as? Bool ?? true
        if let raw = suite.object(forKey: "narratorsSortOrder") as? Int,
           let val = NarratorSortOrder(rawValue: raw) { narratorsSortOrder = val }

        if let raw = suite.object(forKey: "seriesSortOrder") as? String,
           let val = SeriesSortOrder(rawValue: raw) { seriesSortOrder = val }
        seriesAscending = suite.object(forKey: "seriesAscending") as? Bool ?? true
        if let raw = suite.object(forKey: "seriesDisplayType") as? Int,
           let val = ItemDisplayType(rawValue: raw) { seriesDisplayType = val }

        bookmarksAscending = suite.object(forKey: "bookmarksAscending") as? Bool ?? true
        if let raw = suite.object(forKey: "bookmarksSortOrder") as? Int,
           let val = BookmarkSortOrder(rawValue: raw) { bookmarksSortOrder = val }

        genresAscending = suite.object(forKey: "genresAscending") as? Bool ?? true
        tagsAscending = suite.object(forKey: "tagsAscending") as? Bool ?? true

        spotlightIndexCompletionDate = suite.object(forKey: "spotlightIndexCompletionDate") as? Date
        lastConvenienceDownloadRun = suite.object(forKey: "lastConvenienceDownloadRun") as? Date
        lastBuild = suite.string(forKey: "lastBuild")
        lastToSUpdate = suite.object(forKey: "lastToSUpdate") as? Int
        lastWhatsNewVersion = suite.object(forKey: "lastWhatsNewVersion") as? Int
        lastCheckedServerVersion = suite.string(forKey: "lastCheckedServerVersion")
        if let val: [TabValue] = decodeCodable(forKey: "pinnedTabValues") { pinnedTabValues = val }
        isOffline = suite.object(forKey: "isOffline") as? Bool ?? false

        lastTabValue = decodeCodable(forKey: "lastTabValue")
        if let val: Set<LibraryIdentifier> = decodeCodable(forKey: "hiddenLibraries") { hiddenLibraries = val }
        carPlayTabBarLibraries = decodeCodable(forKey: "carPlayTabBarLibraries")
        carPlayShowOtherLibraries = suite.object(forKey: "carPlayShowOtherLibraries") as? Bool ?? true
        enableHapticFeedback = suite.object(forKey: "enableHapticFeedback") as? Bool ?? true
        hideSearchTab = suite.object(forKey: "hideSearchTab") as? Bool ?? false

        abbServerURL = suite.string(forKey: "abbServerURL")
        transmissionURL = suite.string(forKey: "transmissionURL")
        transmissionUsername = suite.string(forKey: "transmissionUsername")
        transmissionPassword = suite.string(forKey: "transmissionPassword")
        downloadPathTemplate = suite.object(forKey: "downloadPathTemplate") as? String ?? "{author}/{series}/{title}"
        pinnedGenreSlugs = suite.stringArray(forKey: "pinnedGenreSlugs") ?? []
        hardcoverAPIToken = suite.string(forKey: "hardcoverAPIToken")
        hideExplicitContent = suite.object(forKey: "hideExplicitContent") as? Bool ?? false
        hideOwnedTitles = suite.object(forKey: "hideOwnedTitles") as? Bool ?? true
    }
}

// MARK: - JSON Encoding/Decoding Helpers

private extension AppSettings {
    func decodeCodable<T: Decodable>(forKey key: String) -> T? {
        guard let data = suite.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            logger.warning("Failed to decode AppSettings value for key \(key, privacy: .public): \(error, privacy: .public)")
            return nil
        }
    }

    func encodeCodable<T: Encodable>(_ value: T?, forKey key: String) {
        guard let value else {
            suite.removeObject(forKey: key)
            return
        }

        do {
            let data = try JSONEncoder().encode(value)
            suite.set(data, forKey: key)
        } catch {
            logger.warning("Failed to encode AppSettings value for key \(key, privacy: .public): \(error, privacy: .public)")
        }
    }
}

public enum ConfiguredColorScheme: Int, Codable, Sendable, CaseIterable, Hashable {
    case system
    case light
    case dark
}


