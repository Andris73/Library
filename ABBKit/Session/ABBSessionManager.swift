import Foundation

@MainActor
public final class ABBSessionManager {
    public static let shared = ABBSessionManager()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    public func fetchPage(url: URL, timeout: TimeInterval = 30) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let delegate = RedirectDelegate()
        let (data, response) = try await session.data(for: request, delegate: delegate)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ABBError.pageLoadFailed(underlying: URLError(.badServerResponse))
        }

        let statusCode = httpResponse.statusCode
        guard statusCode == 200 else {
            if statusCode == 503 || statusCode == 403 {
                throw ABBError.cloudflareChallengeFailed
            }
            var msg = "Server returned HTTP \(statusCode)"
            if delegate.redirectDestination != nil {
                msg += " (redirected to \(delegate.redirectDestination?.absoluteString ?? "unknown"))"
            }
            throw ABBError.pageLoadFailed(underlying: NSError(domain: NSURLErrorDomain, code: statusCode, userInfo: [NSLocalizedDescriptionKey: msg]))
        }

        guard !data.isEmpty else {
            throw ABBError.parsingFailed(reason: "Empty response from server")
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw ABBError.parsingFailed(reason: "Could not decode response as UTF-8")
        }

        return html
    }
}

private final class RedirectDelegate: NSObject, URLSessionTaskDelegate {
    private(set) var redirectDestination: URL?

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        redirectDestination = request.url
        completionHandler(request)
    }
}
