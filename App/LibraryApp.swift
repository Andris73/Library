import SwiftUI
import LibraryKit

@main
struct LibraryApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        Library.launchHook()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
