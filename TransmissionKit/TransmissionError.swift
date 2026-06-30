import Foundation

public enum TransmissionError: LocalizedError {
    case invalidURL
    case connectionFailed(underlying: Error)
    case sessionIDMissing
    case rpcError(message: String)
    case invalidResponse
    case authenticationFailed
    case torrentNotFound

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Transmission RPC URL"
        case .connectionFailed(let error):
            return "Connection failed: \(error.localizedDescription)"
        case .sessionIDMissing:
            return "Could not obtain Transmission session ID"
        case .rpcError(let message):
            return "Transmission RPC error: \(message)"
        case .invalidResponse:
            return "Invalid response from Transmission"
        case .authenticationFailed:
            return "Transmission authentication failed"
        case .torrentNotFound:
            return "Torrent not found in Transmission"
        }
    }
}
