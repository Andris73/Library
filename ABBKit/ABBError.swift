import Foundation

public enum ABBError: LocalizedError {
    case invalidURL
    case pageLoadFailed(underlying: Error)
    case parsingFailed(reason: String)
    case cloudflareChallengeFailed
    case timedOut
    case noInfoHashFound
    case notLoggedIn

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid AudiobookBay URL"
        case .pageLoadFailed(let error):
            return "Failed to load page: \(error.localizedDescription)"
        case .parsingFailed(let reason):
            return "Failed to parse page: \(reason)"
        case .cloudflareChallengeFailed:
            return "Cloudflare challenge could not be completed"
        case .timedOut:
            return "Request timed out"
        case .noInfoHashFound:
            return "No info hash found on this page"
        case .notLoggedIn:
            return "Not logged into AudiobookBay"
        }
    }
}
