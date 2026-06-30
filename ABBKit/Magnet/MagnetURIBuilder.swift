import Foundation

public struct MagnetURIBuilder {
    public static func build(infoHash: String, trackers: [String], displayName: String? = nil) -> String {
        var components = URLComponents()
        components.scheme = "magnet"
        components.queryItems = [
            URLQueryItem(name: "xt", value: "urn:btih:\(infoHash)")
        ]
        if let displayName, !displayName.isEmpty {
            components.queryItems?.append(
                URLQueryItem(name: "dn", value: displayName)
            )
        }
        for tracker in trackers {
            components.queryItems?.append(
                URLQueryItem(name: "tr", value: tracker)
            )
        }
        return components.url?.absoluteString ?? "magnet:?xt=urn:btih:\(infoHash)"
    }
}
