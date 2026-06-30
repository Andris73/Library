//
//  HomeCustomizationSubsystem.swift
//  LibraryKit
//
//  Created by Rasmus Krämer on 19.04.26.
//

import Combine
import Foundation
import SwiftData
import OSLog

typealias PersistedHomeCustomization = LibrarySchema.PersistedHomeCustomization

extension PersistenceManager {
    @ModelActor
    public final actor HomeCustomizationSubsystem: Sendable {
        public final class EventSource: @unchecked Sendable {
            public let invalidateSections = PassthroughSubject<HomeScope, Never>()

            init() {}
        }

        let logger = Logger(subsystem: "com.Library.LibraryKit", category: "HomeCustomizationSubsystem")
        public nonisolated let events = EventSource()
    }
}

public extension PersistenceManager.HomeCustomizationSubsystem {
    // MARK: - Available kinds

    /// Every kind that can appear in a start page for the given library type.
    /// Server-row kinds are reported using the canonical row ids the server
    /// sends; the UI renders whatever rows the server has actually returned.
    ///
    /// Only kinds that can actually surface content for the given library type
    /// are returned.
    nonisolated func availableKinds(for libraryType: LibraryMediaType) -> [HomeSectionKind] {
        switch libraryType {
        case .audiobooks:
            [
                .serverRow(id: "continue-listening"),
                .serverRow(id: "continue-series"),
                .serverRow(id: "recent-series"),
                .serverRow(id: "recently-added"),
                .serverRow(id: "listen-again"),
                .serverRow(id: "discover"),
                .serverRow(id: "newest-authors"),
                .downloadedAudiobooks,
            ]
        }
    }

    // MARK: - Defaults

    /// Default section list used when a scope has no saved customization.
    /// `continue-listening` is always first — it surfaces in-progress items,
    /// which is the most common reason to open the app.
    nonisolated func defaultSections(for libraryType: LibraryMediaType) -> [HomeSection] {
        switch libraryType {
        case .audiobooks:
            [
                .init(kind: .serverRow(id: "continue-listening")),
                .init(kind: .serverRow(id: "continue-series")),
                .init(kind: .serverRow(id: "recent-series")),
                .init(kind: .serverRow(id: "recently-added")),
                .init(kind: .serverRow(id: "listen-again")),
                .init(kind: .serverRow(id: "discover")),
                .init(kind: .serverRow(id: "newest-authors")),
                .init(kind: .downloadedAudiobooks),
            ]
        }
    }

    /// The multi-library panel defaults to the cross-library client-derived
    /// rows. Server rows aren't included because they require a specific
    /// library — the user adds them per-library from the editor.
    nonisolated func defaultMultiLibrarySections() -> [HomeSection] {
        [
            .init(kind: .continueReading),
            .init(kind: .downloadedAudiobooks),
        ]
    }

    /// Kinds available in the multi-library panel. Server rows are included
    /// here too — when added in this scope they require a specific library
    /// (the row picker on each row enforces that). Collection/playlist rows
    /// are added via the dedicated picker flow in the editor.
    nonisolated func availableMultiLibraryKinds() -> [HomeSectionKind] {
        [
            .listenNowAudiobooks,
            .downloadedAudiobooks,
            .serverRow(id: "continue-listening"),
            .serverRow(id: "continue-series"),
            .serverRow(id: "recent-series"),
            .serverRow(id: "recently-added"),
            .serverRow(id: "newest-episodes"),
            .serverRow(id: "listen-again"),
            .serverRow(id: "discover"),
            .serverRow(id: "newest-authors"),
        ]
    }

    // MARK: - Read / write

    func sections(for scope: HomeScope, libraryType: LibraryMediaType?) -> [HomeSection] {
        let scopeKey = scope.key

        let entity: PersistedHomeCustomization?
        do {
            entity = try modelContext.fetch(FetchDescriptor<PersistedHomeCustomization>(predicate: #Predicate { $0.scopeKey == scopeKey })).first
        } catch {
            logger.warning("Failed to fetch home customization for \(scopeKey, privacy: .public); falling back to defaults: \(error, privacy: .public)")
            entity = nil
        }

        if let entity {
            do {
                return try JSONDecoder().decode([HomeSection].self, from: entity.sectionsData)
            } catch {
                logger.warning("Failed to decode home customization for \(scopeKey, privacy: .public); falling back to defaults: \(error, privacy: .public)")
            }
        }

        switch scope {
        case .library:
            return defaultSections(for: libraryType ?? .audiobooks)
        case .multiLibrary:
            return defaultMultiLibrarySections()
        }
    }

    func setSections(_ sections: [HomeSection]?, for scope: HomeScope) async throws {
        let scopeKey = scope.key

        if let sections {
            let data = try JSONEncoder().encode(sections)

            if let existing = try modelContext.fetch(FetchDescriptor<PersistedHomeCustomization>(predicate: #Predicate { $0.scopeKey == scopeKey })).first {
                existing.sectionsData = data
            } else {
                modelContext.insert(PersistedHomeCustomization(scopeKey: scopeKey, sectionsData: data))
            }
        } else {
            try modelContext.delete(model: PersistedHomeCustomization.self, where: #Predicate { $0.scopeKey == scopeKey })
        }

        try modelContext.save()

        let broadcastScope = scope
        await MainActor.run {
            events.invalidateSections.send(broadcastScope)
        }
    }

    func purgeAll() {
        do {
            try modelContext.delete(model: PersistedHomeCustomization.self)
        } catch {
            logger.warning("Failed to delete persisted home customizations: \(error, privacy: .public)")
        }
        do {
            try modelContext.save()
        } catch {
            logger.warning("Failed to save context after purging home customizations: \(error, privacy: .public)")
        }
    }
}
