//
//  Satellite.swift
//  Library
//
//  Created by Rasmus Krämer on 25.01.25.
//

import SwiftUI
import Combine
import OSLog
@Observable @MainActor
final class Satellite {
    let logger = Logger(subsystem: "com.Library.LibraryKit", category: "Satellite")

    private let settings = AppSettings.shared

    // MARK: Navigation

    private(set) var sheetStack = [Sheet]()
    var warningAlertStack = [WarningAlert]()

    var settingsNavigationPath = NavigationPath()

    private(set) var isLoadingAlert = false

    // MARK: State

    private(set) var busy = [ItemIdentifier: Int]()
    private(set) var totalLoading = 0

    var notifyError = false
    var notifySuccess = false

    private var persistentSubscriptions = Set<AnyCancellable>()

    // MARK: Init

    private init() {
        PersistenceManager.shared.authorization.events.connectionUnauthorized
            .sink { [weak self] connectionID in
                Task { @MainActor [weak self] in
                    self?.present(.reauthorizeConnection(connectionID))
                }
            }
            .store(in: &persistentSubscriptions)

        NavigationEventSource.shared.setGlobalSearch
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.dismissSheet()
                }
            }
            .store(in: &persistentSubscriptions)

        #if DEBUG
        AppEventSource.shared.shake
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.present(.debug)
                }
            }
            .store(in: &persistentSubscriptions)
        #endif
    }

    // MARK: General Purpose

    enum SatelliteError: Error {
        case missingItem
    }

    public func isLoading(observing itemID: ItemIdentifier) -> Bool {
        totalLoading > 0 || busy[itemID] ?? 0 > 0 || itemID.isPlaceholder
    }

    private func startWorking(on itemID: ItemIdentifier) {
        let current = busy[itemID]

        withAnimation {
            if current == nil {
                busy[itemID] = 1
            } else {
                busy[itemID]! += 1
            }
        }
    }
    private func endWorking(on itemID: ItemIdentifier, successfully: Bool?) {
        guard let current = busy[itemID] else {
            logger.warning("Ending work on \(itemID, privacy: .public) but no longer busy")
            return
        }

        withAnimation {
            busy[itemID] = current - 1
        }

        if let successfully {
            if successfully {
                notifySuccess.toggle()
            } else {
                notifyError.toggle()
            }
        }
    }
}

// MARK: Sheet & Alert

extension Satellite {
    enum Sheet: Identifiable, Equatable {
        case preferences
        case debugPreferences
        case customTabValuePreferences

        case description(Item)
        case configureGrouping(ItemIdentifier)

        case editCollection(ItemCollection)
        case editCollectionMembership(ItemIdentifier)

        case addConnection
        case editConnection(ItemIdentifier.ConnectionID)
        case reauthorizeConnection(ItemIdentifier.ConnectionID)

        case customizeLibrary(Library, PersistenceManager.CustomizationSubsystem.TabValueCustomizationScope)
        case customizeHome(HomeScope, LibraryMediaType?)

        case whatsNew

        #if DEBUG
        case debug
        #endif

        var id: String {
            switch self {
                case .preferences:
                    "preferences"
                case .debugPreferences:
                    "debugPreferences"
                case .customTabValuePreferences:
                    "customTabValuePreferences"

                case .description(let item):
                    "description-\(item.id)"
                case .configureGrouping(let itemID):
                    "configureGrouping-\(itemID)"

                case .editCollection(let collection):
                    "editCollection-\(collection.id)"
                case .editCollectionMembership(let itemID):
                    "editCollectionMembership-\(itemID)"

                case .addConnection:
                    "addConnection"
                case .editConnection(let connectionID):
                    "editConnection-\(connectionID)"
                case .reauthorizeConnection(let connectionID):
                    "reauthorizeConnection-\(connectionID)"

                case .customizeLibrary(let library, let scope):
                    "customizeLibrary-\(library.id)-\(scope.id)"
                case .customizeHome(let scope, _):
                    "customizeHome-\(scope.key)"

                case .whatsNew:
                    "whatsNew"

                #if DEBUG
                case .debug:
                    "debug"
                #endif
            }
        }
    }
    enum WarningAlert {
        case message(String)
        case termsOfServiceChanged

        var message: String {
            switch self {
                case .message(let message):
                    message
                case .termsOfServiceChanged:
                    "Library's Terms of Service and Privacy Policy have been updated to better align with legal requirements. Please take a moment to review the revised documents to continue using the app. There are no changes to app functionality, and our privacy practices remain unchanged."
            }
        }

        var actions: [WarningAction] {
            switch self {
                case .message:
                    [.dismiss]
                case .termsOfServiceChanged:
                    [.acknowledge, .learnMore(URL(string: "https://github.com/rasmuslos/Library/issues/320")!)]
            }
        }

        enum WarningAction: Identifiable, Hashable, Equatable, Codable {
            case dismiss
            case acknowledge
            case learnMore(URL)

            var id: String {
                switch self {
                    case .acknowledge:
                        "H_acknowledge"
                    case .learnMore(let url):
                        "I_learnMore_\(url.absoluteString)"
                    case .dismiss:
                        "Q_dissmiss"
                }
            }
        }
    }

    var isSheetPresented: Bool {
        !sheetStack.isEmpty
    }
    var presentedSheet: Binding<Sheet?> {
        .init {
            self.sheetStack.first
        } set: {
            if let sheet = $0, self.sheetStack.first != sheet {
                self.present(sheet)
            } else if $0 == nil {
                self.dismissSheet()
            }
        }
    }
    var isWarningAlertPresented: Binding<Bool> {
        .init {
            !self.warningAlertStack.isEmpty
        } set: { _ in }
    }

    func present(_ sheet: Sheet) {
        if sheetStack.first != .preferences {
            settingsNavigationPath = NavigationPath()
        }

        sheetStack.insert(sheet, at: 0)
    }
    func warn(_ warning: WarningAlert) {
        warningAlertStack.insert(warning, at: 0)
    }

    func dismissSheet() {
        guard !sheetStack.isEmpty else {
            return
        }

        if sheetStack.first == .preferences {
            settingsNavigationPath = NavigationPath()
        }

        sheetStack.removeFirst()
    }
    func dismissSheet(id: String) {
        sheetStack.removeAll { $0.id == id }
    }

    func cancelWarningAlert() {
        guard !warningAlertStack.isEmpty else {
            return
        }

        warningAlertStack.removeFirst()
    }
    func confirmWarningAlert() {
        guard let warningAlert = warningAlertStack.first else {
            return
        }

        Task {
            isLoadingAlert = true

            switch warningAlert {
                case .message:
                    break

                case .termsOfServiceChanged:
                    settings.lastToSUpdate = LibraryKit.currentToSVersion
            }

            self.warningAlertStack.removeFirst()

            isLoadingAlert = false
        }
    }
}

// MARK: Progress

extension Satellite {
    func markAsFinished(_ itemID: ItemIdentifier) {
        Task {
            startWorking(on: itemID)

            do {
                try await PersistenceManager.shared.progress.markAsCompleted(itemID)

                endWorking(on: itemID, successfully: true)
            } catch {
                logger.warning("Failed to mark \(itemID, privacy: .public) as finished: \(error, privacy: .public)")
                endWorking(on: itemID, successfully: false)
            }
        }
    }
    func markAsUnfinished(_ itemID: ItemIdentifier) {
        Task {
            startWorking(on: itemID)

            do {
                try await PersistenceManager.shared.progress.markAsListening(itemID)
                endWorking(on: itemID, successfully: true)
            } catch {
                logger.warning("Failed to mark \(itemID, privacy: .public) as unfinished: \(error, privacy: .public)")
                endWorking(on: itemID, successfully: false)
            }
        }
    }
    func deleteProgress(_ itemID: ItemIdentifier) {
        Task {
            startWorking(on: itemID)

            do {
                try await PersistenceManager.shared.progress.delete(itemID: itemID)
                endWorking(on: itemID, successfully: true)
            } catch {
                logger.warning("Failed to delete progress for \(itemID, privacy: .public): \(error, privacy: .public)")
                endWorking(on: itemID, successfully: false)
            }
        }
    }
}

// MARK: Download

extension Satellite {
    func download(itemID: ItemIdentifier) {
        Task {
            let status = await PersistenceManager.shared.download.status(of: itemID)

            guard status == .none else {
                return
            }

            startWorking(on: itemID)

            do {
                try await PersistenceManager.shared.download.download(itemID)
                endWorking(on: itemID, successfully: true)
            } catch {
                logger.error("Failed to download item \(itemID, privacy: .public): \(error)")
                endWorking(on: itemID, successfully: false)
            }
        }
    }

    func removeDownload(itemID: ItemIdentifier, force: Bool) {
        Task {
            guard force || !(await PersistenceManager.shared.convenienceDownload.isManaged(itemID: itemID)) else {
                notifyError.toggle()
                return
            }

            do {
                try await PersistenceManager.shared.download.remove(itemID)

                notifySuccess.toggle()
            } catch {
                logger.warning("Failed to remove download for \(itemID, privacy: .public): \(error, privacy: .public)")
                notifyError.toggle()
            }
        }
    }
    func removeConvenienceDownloadConfigurations(from itemID: ItemIdentifier) {
        Task {
            startWorking(on: itemID)

            await PersistenceManager.shared.convenienceDownload.removeConfigurations(associatedWith: itemID)
            removeDownload(itemID: itemID, force: true)

            endWorking(on: itemID, successfully: true)
        }
    }
}

extension Satellite {
    static let shared = Satellite()
}
