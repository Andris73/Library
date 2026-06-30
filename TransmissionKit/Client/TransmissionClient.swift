import Foundation

public actor TransmissionClient {
    private let session: URLSession
    private let baseURL: URL
    private var sessionID: String?
    private var credential: URLCredential?

    public init(baseURL: URL, credential: URLCredential? = nil) {
        self.baseURL = baseURL.appendingPathComponent("transmission/rpc")
        self.credential = credential
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    public func updateCredential(_ credential: URLCredential?) {
        self.credential = credential
    }

    public func testConnection() async throws -> Bool {
        _ = try await sendRPC(method: "session-get", arguments: [:])
        return true
    }

    @discardableResult
    public func addTorrent(magnetURI: String, downloadPath: String? = nil) async throws -> TorrentInfo {
        var args: [String: Any] = ["filename": magnetURI]
        if let downloadPath {
            args["download-dir"] = downloadPath
        }
        let response = try await sendRPC(method: "torrent-add", arguments: args)

        guard let arguments = response["arguments"] as? [String: Any] else {
            throw TransmissionError.invalidResponse
        }

        if let added = arguments["torrent-added"] as? [String: Any] {
            return try parseTorrentInfo(added)
        }
        if let duplicate = arguments["torrent-duplicate"] as? [String: Any] {
            return try parseTorrentInfo(duplicate)
        }

        throw TransmissionError.rpcError(message: "Torrent was not added")
    }

    private static let torrentFields = [
        "id", "name", "hashString", "status", "percentDone",
        "rateDownload", "rateUpload", "error", "errorString",
        "uploadRatio", "seedRatioLimit", "seedRatioMode",
    ]

    public func getTorrent(id: Int) async throws -> TorrentInfo {
        let response = try await sendRPC(method: "torrent-get", arguments: [
            "ids": [id],
            "fields": Self.torrentFields,
        ])

        guard let arguments = response["arguments"] as? [String: Any],
              let torrents = arguments["torrents"] as? [[String: Any]],
              let first = torrents.first else {
            throw TransmissionError.torrentNotFound
        }

        return try parseTorrentInfo(first)
    }

    /// Fetches the current state of multiple torrents in one request. Torrents
    /// that no longer exist are simply absent from the result.
    public func getTorrents(ids: [Int]) async throws -> [TorrentInfo] {
        guard !ids.isEmpty else { return [] }
        let response = try await sendRPC(method: "torrent-get", arguments: [
            "ids": ids,
            "fields": Self.torrentFields,
        ])

        guard let arguments = response["arguments"] as? [String: Any],
              let torrents = arguments["torrents"] as? [[String: Any]] else {
            return []
        }

        return torrents.compactMap { try? parseTorrentInfo($0) }
    }

    public func removeTorrent(id: Int, deleteData: Bool = false) async throws {
        try await sendRPC(method: "torrent-remove", arguments: [
            "ids": [id],
            "delete-local-data": deleteData
        ])
    }

    private func sendRPC(method: String, arguments: [String: Any]) async throws -> [String: Any] {
        let body: [String: Any] = [
            "method": method,
            "arguments": arguments
        ]

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let sessionID {
            request.setValue(sessionID, forHTTPHeaderField: "X-Transmission-Session-Id")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        if let credential {
            request.setValue(
                "Basic \(Data("\(credential.user ?? ""):\(credential.password ?? "")".utf8).base64EncodedString())",
                forHTTPHeaderField: "Authorization"
            )
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TransmissionError.invalidResponse
        }

        if httpResponse.statusCode == 409 {
            guard let newSessionID = httpResponse.allHeaderFields["X-Transmission-Session-Id"] as? String else {
                throw TransmissionError.sessionIDMissing
            }
            sessionID = newSessionID
            return try await sendRPC(method: method, arguments: arguments)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw TransmissionError.authenticationFailed
            }
            throw TransmissionError.rpcError(message: "HTTP \(httpResponse.statusCode)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TransmissionError.invalidResponse
        }

        if let result = json["result"] as? String, result != "success" {
            throw TransmissionError.rpcError(message: result)
        }

        return json
    }

    private func parseTorrentInfo(_ dict: [String: Any]) throws -> TorrentInfo {
        guard let id = dict["id"] as? Int,
              let name = dict["name"] as? String,
              let hashString = dict["hashString"] as? String else {
            throw TransmissionError.invalidResponse
        }

        let status = TorrentStatus(rawValue: dict["status"] as? Int ?? 0) ?? .stopped
        let percentDone = dict["percentDone"] as? Double ?? 0
        let rateDownload = dict["rateDownload"] as? Int64 ?? 0
        let rateUpload = dict["rateUpload"] as? Int64 ?? 0
        let error = dict["error"] as? Int ?? 0
        let errorString = dict["errorString"] as? String
        let uploadRatio = dict["uploadRatio"] as? Double ?? -1
        let seedRatioLimit = dict["seedRatioLimit"] as? Double ?? 0
        let seedRatioMode = dict["seedRatioMode"] as? Int ?? 0

        return TorrentInfo(
            id: id,
            name: name,
            hashString: hashString,
            status: status,
            percentDone: percentDone,
            rateDownload: rateDownload,
            rateUpload: rateUpload,
            error: error,
            errorString: errorString,
            uploadRatio: uploadRatio,
            seedRatioLimit: seedRatioLimit,
            seedRatioMode: seedRatioMode
        )
    }
}
