//
//  ABBCoverImage.swift
//  Library
//
//  A small cached image view for AudiobookBay cover art. Discover mounts
//  many shelves at once, and the stock `AsyncImage` (backed by an
//  uncached `URLSession.shared`) tends to leave covers stuck on the
//  placeholder on cellular when dozens fire simultaneously. This routes
//  every cover through a shared, disk+memory-cached loader with bounded
//  per-host concurrency, so covers load once and stay loaded.
//

import SwiftUI
import UIKit

actor ABBImageLoader {
    static let shared = ABBImageLoader()

    private let cache = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 128 * 1024 * 1024)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
        cache.countLimit = 400
    }

    func image(for url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        if let existing = inFlight[url] {
            return await existing.value
        }

        let task = Task<UIImage?, Never> { [session, cache] in
            guard let (data, _) = try? await session.data(from: url),
                  let image = UIImage(data: data) else {
                return nil
            }
            cache.setObject(image, forKey: url as NSURL)
            return image
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        return image
    }
}

/// Renders a cached AudiobookBay cover, filling its frame. Clipping and
/// sizing are the caller's responsibility (mirrors `AsyncImage` usage).
struct ABBCoverImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            image = nil
            guard let url else { return }
            image = await ABBImageLoader.shared.image(for: url)
        }
    }
}
