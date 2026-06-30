import SwiftUI
import AppIntents

@main
struct LibraryApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        let environment = ProcessInfo.processInfo.environment

        #if DEBUG
        if environment["WIPE_CONNECTIONS"] == "YES" {
            PersistenceManager.AuthorizationSubsystem.debugWipeAllConnections()
        }
        #endif

        Library.launchHook()

        Task {
            #if DEBUG
            if environment["FORCE_OFFLINE_MODE"] == "YES" {
                await OfflineMode.shared.ensureAvailabilityEstablished(reason: "FORCE_OFFLINE_MODE launch argument")
                OfflineMode.shared.forceEnable(reason: "FORCE_OFFLINE_MODE launch argument")
            }
            #endif

            if let itemIDDescription = environment["NAVIGATE_TO_ITEM_IDENTIFIER"] {
                await ItemIdentifier(itemIDDescription).navigate()
            }

            if environment["RUN_CONVENIENCE_DOWNLOAD"] == "YES" {
                await PersistenceManager.shared.convenienceDownload.scheduleAll()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct LibraryPackage: AppIntentsPackage {
    static let includedPackages: [any AppIntentsPackage.Type] = [
        LibraryKitPackage.self,
    ]
}
