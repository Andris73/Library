//
//  ABBDetailView.swift
//  Library
//

import SwiftUI
import LibraryKit
import ABBKit
import TransmissionKit

struct ABBDetailView: View {
    let result: ABBSearchResult

    @State private var book: ABBBook?
    @State private var series: ABBSeriesParser.Parsed?
    @State private var isLoading = true
    @State private var downloadProgress: Double = 0
    @State private var isDownloading = false
    @State private var isDownloaded = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else if let error {
                ContentUnavailableView(
                    "Error Loading Book",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if let book {
                VStack(alignment: .leading, spacing: 24) {
                    coverImage(book)
                        .frame(maxWidth: 170)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(book.title)
                            .font(.title2)
                            .bold()

                        if let author = book.author {
                            Text(author)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }

                        if let narrator = book.narrator {
                            Label("Read by \(narrator)", systemImage: "mic")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    attributeChips(book)

                    if let series {
                        seriesLink(series, book: book)
                    }

                    downloadButton(book)

                    if let description = book.bookDescription {
                        section("Description") {
                            Text(description)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if !book.comments.isEmpty {
                        section("Comments") {
                            VStack(spacing: 16) {
                                ForEach(book.comments) { comment in
                                    CommentRow(comment: comment)
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle(result.title)
        .navigationBarTitleDisplayMode(.inline)

        .task {
            await loadDetail()
        }
    }

    // MARK: - Components

    @ViewBuilder
    private func coverImage(_ book: ABBBook) -> some View {
        Color.clear
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                ABBCoverImage(url: book.coverURL) {
                    placeholderCover
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var placeholderCover: some View {
        Rectangle()
            .fill(.secondary.opacity(0.2))
            .overlay {
                Image(systemName: "book")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
            }
    }

    @ViewBuilder
    private func attributeChips(_ book: ABBBook) -> some View {
        let chips: [AttributeChip] = [
            book.format.map { AttributeChip(text: $0, systemImage: "doc") },
            book.bitrate.map { AttributeChip(text: $0, systemImage: "waveform") },
            book.abridged.map { AttributeChip(text: $0, systemImage: "book.closed") },
        ].compactMap { $0 }

        if book.isExplicit || !chips.isEmpty {
            HStack(spacing: 8) {
                if book.isExplicit {
                    Label("Explicit", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(.red)
                        .background(.red.opacity(0.15), in: Capsule())
                }
                ForEach(chips) { chip in
                    Label(chip.text, systemImage: chip.systemImage)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.secondary.opacity(0.15), in: Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private func seriesLink(_ series: ABBSeriesParser.Parsed, book: ABBBook) -> some View {
        NavigationLink(value: NavigationDestination.abbSeries(
            name: series.seriesName,
            author: book.author,
            fallbackDescription: book.bookDescription
        )) {
            HStack(spacing: 12) {
                Image(systemName: "books.vertical.fill")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("View Series")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text(seriesSubtitle(series))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func seriesSubtitle(_ series: ABBSeriesParser.Parsed) -> String {
        if let position = series.position {
            return "\(series.seriesName) · Book \(ABBSeriesParser.formatPosition(position))"
        }
        return series.seriesName
    }

    @ViewBuilder
    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func downloadButton(_ book: ABBBook) -> some View {
        if isDownloaded {
            statusLabel("Downloaded", systemImage: "checkmark.circle.fill", tint: .green)
        } else if isDownloading {
            HStack(spacing: 12) {
                ProgressView(value: downloadProgress)
                    .progressViewStyle(.circular)
                VStack(alignment: .leading) {
                    Text("Downloading")
                        .font(.subheadline)
                    Text("\(Int(downloadProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            Button {
                startDownload(book)
            } label: {
                Label("Download to Transmission", systemImage: "arrow.down.circle")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.tint)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    private func statusLabel(_ title: LocalizedStringKey, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(tint)
            .padding()
            .frame(maxWidth: .infinity)
            .background(.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Loading & downloading

    @MainActor
    private func loadDetail() async {
        isLoading = true
        do {
            guard let abbURLString = AppSettings.shared.abbServerURL,
                  let abbURL = URL(string: abbURLString) else {
                error = "ABB Server URL is not configured."
                isLoading = false
                return
            }
            let html = try await ABBSessionManager.shared.fetchPage(url: result.detailURL)
            let detail = try await Task.detached(priority: .userInitiated) {
                try ABBDetailParser.parseBookDetail(from: html, baseURL: abbURL)
            }.value
            book = detail
            isLoading = false

            await detectSeries(for: detail)
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    /// Detects the series for the book: the ABB title heuristic first (instant,
    /// numbered series), then Hardcover (handles name-only series) when a token
    /// is configured.
    @MainActor
    private func detectSeries(for book: ABBBook) async {
        if let parsed = ABBSeriesParser.parse(title: book.title, author: book.author) {
            series = parsed
            return
        }
        guard let token = AppSettings.shared.hardcoverAPIToken,
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        let cleanedTitle = ABBSeriesParser.titleWithoutAuthor(book.title)
        if let hardcover = await HardcoverClient.fetchBookSeries(title: cleanedTitle, author: book.author, token: token) {
            series = ABBSeriesParser.Parsed(seriesName: hardcover.name, position: hardcover.position)
        }
    }

    private func startDownload(_ book: ABBBook) {
        isDownloading = true
        downloadProgress = 0

        Task { @MainActor in
            do {
                let magnetURI = MagnetURIBuilder.build(
                    infoHash: book.infoHash,
                    trackers: book.trackers,
                    displayName: book.title
                )

                let transmissionURLString = AppSettings.shared.transmissionURL!
                let url = URL(string: transmissionURLString)!
                var credential: URLCredential?
                if let user = AppSettings.shared.transmissionUsername, !user.isEmpty {
                    credential = URLCredential(
                        user: user,
                        password: AppSettings.shared.transmissionPassword ?? "",
                        persistence: .forSession
                    )
                }

                let client = TransmissionClient(baseURL: url, credential: credential)
                let template = AppSettings.shared.downloadPathTemplate
                let downloadPath = DownloadPathBuilder.build(
                    template: template,
                    author: book.author ?? "",
                    narrator: book.narrator ?? "",
                    series: book.series ?? "",
                    title: book.title
                )

                let torrent = try await client.addTorrent(magnetURI: magnetURI, downloadPath: downloadPath)

                await PersistenceManager.shared.downloadTracker.trackDownload(
                    torrentID: torrent.id,
                    infoHash: book.infoHash,
                    title: book.title,
                    author: book.author ?? "",
                    downloadPath: downloadPath
                )

                isDownloading = false
                isDownloaded = true
            } catch {
                isDownloading = false
                self.error = error.localizedDescription
            }
        }
    }
}

private struct AttributeChip: Identifiable {
    let id = UUID()
    let text: String
    let systemImage: String
}

private struct CommentRow: View {
    let comment: ABBComment

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(comment.author)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer(minLength: 8)
                    if let date = comment.date {
                        Text(date)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                if let rating = comment.rating {
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { index in
                            Image(systemName: index < rating ? "star.fill" : "star")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                        }
                    }
                }

                if !comment.body.isEmpty {
                    Text(comment.body)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var avatar: some View {
        if let avatarURL = comment.avatarURL {
            AsyncImage(url: avatarURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    avatarPlaceholder
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
        } else {
            avatarPlaceholder
                .frame(width: 36, height: 36)
        }
    }

    private var avatarPlaceholder: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.secondary)
    }
}
