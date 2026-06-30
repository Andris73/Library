//
//  ContentView.swift
//  Library
//
//  Created by Rasmus Krämer on 16.09.23.
//

import SwiftUI
import Intents
import CoreSpotlight
import SwiftData
import OSLog

struct ContentView: View {
    let logger = Logger(subsystem: "com.Library.Library", category: "ContentView")

    @Environment(\.scenePhase) private var scenePhase

    @State private var satellite = Satellite.shared
    @State private var connectionStore = ConnectionStore.shared
    @State private var itemNavigationController = ItemNavigationController()

    @State private var tintColor: TintColor = AppSettings.shared.tintColor
    @State private var configuredColorScheme: ConfiguredColorScheme = AppSettings.shared.colorScheme

    @ViewBuilder
    private func applyEnvironment<Content: View>(_ content: Content) -> some View {
        content
            .environment(connectionStore)
            .environment(satellite)
            .environment(itemNavigationController)
    }

    @ViewBuilder
    private func sheetContent(for sheet: Satellite.Sheet) -> some View {
        switch sheet {
            case .preferences:
                SettingsView()
            case .debugPreferences:
                DebugPreferences()
            case .customTabValuePreferences:
                CustomTabValueSheet()
            case .description(let item):
                DescriptionSheet(item: item)
            case .configureGrouping(let itemID):
                GroupingConfigurationSheet(itemID: itemID)
            case .editCollection(let collection):
                EditCollectionSheet(collection: collection)
            case .editCollectionMembership(let itemID):
                CollectionMembershipEditorSheet(itemID: itemID)
            case .addConnection:
                ConnectionAddSheet()
            case .editConnection(let connectionID):
                ConnectionEditSheet(connectionID: connectionID)
            case .reauthorizeConnection(let connectionID):
                ReauthorizeConnectionSheet(connectionID: connectionID)
            case .customizeLibrary(let library, let scope):
                CustomizeLibraryPanelSheet(library: library, scope: scope)
            case .customizeHome(let scope, let libraryType):
                NavigationStack {
                    HomeCustomizationView(scope: scope, libraryType: libraryType)
                }
            case .whatsNew:
                WhatsNewSheet()
            #if DEBUG
            case .debug:
                DebugSheet()
            #endif
        }
    }
    var body: some View {
        ZStack {
            if !connectionStore.didLoad {
                LoadingView()
            } else if connectionStore.connections.isEmpty {
                WelcomeView()
            } else {
                TabRouter()
            }
        }
        .hapticFeedback(.error, trigger: satellite.notifyError)
        .hapticFeedback(.success, trigger: satellite.notifySuccess)
        .sheet(item: satellite.presentedSheet) {
            sheetContent(for: $0)
                .modify(if: ProcessInfo.processInfo.isiOSAppOnMac) {
                    applyEnvironment($0)
                }
        }
        .alert(String(), isPresented: satellite.isWarningAlertPresented) {
            Button("action.dismiss") {
                satellite.cancelWarningAlert()
            }
        } message: {
            if let message = satellite.warningAlertStack.first?.message {
                Text(message)
            }
        }
        .modify {
            applyEnvironment($0)
        }
        .modify(if: tintColor != .Library) {
            $0
                .tint(tintColor.color)
        }
        .modify(if: configuredColorScheme != .system) {
            $0
                .preferredColorScheme(configuredColorScheme == .light ? .light : .dark)
        }
        .onReceive(AppEventSource.shared.appearanceDidChange) {
            tintColor = AppSettings.shared.tintColor
            configuredColorScheme = AppSettings.shared.colorScheme
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                logger.info("Scene is now active")
                AppEventSource.shared.scenePhaseDidChange.send(true)
            } else {
                logger.info("Scene is now inactive")
                AppEventSource.shared.scenePhaseDidChange.send(false)
            }
        }
        .onOpenURL { url in
            URLSchemeHandler.handle(url)
        }
        .onContinueUserActivity(CSQueryContinuationActionType) {
            guard let query = $0.userInfo?[CSSearchQueryString] as? String else {
                logger.warning("Received a malformed query to set the global search from Spotlight")
                return
            }

            logger.info("Setting global search to: \(query) from Spotlight")

            Task {
                try await Task.sleep(for: .seconds(0.6))
                NavigationEventSource.shared.setGlobalSearch.send((query, .global))
            }
        }
        .onContinueUserActivity("com.Library.item") { activity in
            guard let identifier = activity.persistentIdentifier else {
                logger.info("Spotlight activity did not contain a valid persistent identifier")
                return
            }

            logger.info("Received a Spotlight activity for item with identifier: \(identifier)")

            Task {
                try await Task.sleep(for: .seconds(0.6))
                await ItemIdentifier(identifier).navigate()
            }
        }
    }
}

#Preview {
    ContentView()
}
