//
//  API+Item.swift
//  LibraryKit
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.Library.LibraryKit", category: "API+Item")

extension APIClient {
    func item(itemID: ItemIdentifier) async throws -> ItemPayload {
        try await item(primaryID: itemID.primaryID, groupingID: itemID.groupingID)
    }

    func item(primaryID: ItemIdentifier.PrimaryID, groupingID: ItemIdentifier.GroupingID?) async throws -> ItemPayload {
        try await response(APIRequest(path: "api/items/\(groupingID ?? primaryID)", method: .get, query: [
            URLQueryItem(name: "expanded", value: "1"),
        ]))
    }
}

public extension APIClient {
    func book(itemID: ItemIdentifier) async throws -> Book {
        let payload = try await item(primaryID: itemID.primaryID, groupingID: itemID.groupingID)

        guard let book = Audiobook(payload: payload, libraryID: itemID.libraryID, connectionID: connectionID) else {
            logger.warning("Failed to convert book for \(itemID, privacy: .public): missing required fields")
            throw APIClientError.notFound
        }

        return book
    }

    func items(in library: LibraryIdentifier, search: String) async throws -> ([Audiobook], [Person], [Person], [Series]) {
        let payload = try await response(APIRequest<SearchResponse>(path: "api/libraries/\(library.libraryID)/search", method: .get, query: [
            URLQueryItem(name: "q", value: search),
        ]))

        return (
            payload.book?.compactMap { Audiobook(payload: $0.libraryItem, libraryID: library.libraryID, connectionID: connectionID) } ?? [],
            payload.authors?.compactMap { Person(author: $0, connectionID: connectionID) } ?? [],
            payload.narrators?.map { Person(narrator: $0, libraryID: library.libraryID, connectionID: library.connectionID) } ?? [],
            payload.series?.compactMap { Series(item: $0.series, audiobooks: $0.books, libraryID: library, connectionID: connectionID) } ?? []
        )
    }

    func coverRequest(from itemID: ItemIdentifier, width: Int) async throws -> APIRequest<DataResponse> {
        let path: String

        switch itemID.type {
        case .author:
            path = "api/authors/\(itemID.primaryID)/image"
        default:
            path = "api/items/\(itemID.primaryID)/cover"
        }

        return APIRequest(path: path, method: .get, query: [
            URLQueryItem(name: "width", value: width.description),
        ])
    }

    func cover(from itemID: ItemIdentifier, width: Int) async throws -> Data {
        try await response(coverRequest(from: itemID, width: width)).data
    }

    func pdfRequest(from itemID: ItemIdentifier, ino: String) async throws -> APIRequest<DataResponse> {
        APIRequest<DataResponse>(path: "api/items/\(itemID.apiItemID)/ebook/\(ino)", method: .get, ttl: 20)
    }

    func pdf(from itemID: ItemIdentifier, ino: String) async throws -> Data {
        try await response(pdfRequest(from: itemID, ino: ino)).data
    }

    func audioTrackRequest(from itemID: ItemIdentifier, ino: String) async throws -> URLRequest {
        try await request(APIRequest<DataResponse>(path: "api/items/\(itemID.apiItemID)/file/\(ino)", method: .get))
    }
}
