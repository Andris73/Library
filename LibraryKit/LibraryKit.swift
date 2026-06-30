import Foundation
import OSLog
import AppIntents
import UIKit

@_exported import RFVisuals

public struct LibraryKit {
    public static let logger = Logger(subsystem: "com.library.LibraryKit", category: "LibraryKit")
}

public struct LibraryKitPackage: AppIntentsPackage {}

// MARK: Configuration

public extension LibraryKit {
    static let groupContainer: String = {
        if let identifier = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String, !identifier.isEmpty {
            return identifier
        }

        #if DEBUG
        return "group.com.library.development"
        #else
        return "group.com.library"
        #endif
    }()

    #if ENABLE_CENTRALIZED
    static let enableCentralized = true
    #else
    static let enableCentralized = false
    #endif

    static let clientBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    static let clientVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

    static let isWidgetExtension: Bool = {
        guard let nsExtension = Bundle.main.infoDictionary?["NSExtension"] as? [String: Any] else {
            return false
        }
        return nsExtension["NSExtensionPointIdentifier"] as? String == "com.apple.widgetkit-extension"
    }()

    #if canImport(UIKit)
    @MainActor
    static let osVersion = UIDevice.current.systemVersion
    #endif

    static let model: String = {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.compactMap { $0.value as? Int8 }.map { String(UnicodeScalar(UInt8($0))) }.joined().trimmingCharacters(in: .controlCharacters)
    }()
}
