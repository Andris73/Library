//
//  DownloadedPanel.swift
//  Library
//
//  Created by Rasmus Krämer on 10.01.26.
//

import SwiftUI
struct DownloadedPanel: View {
    @Environment(\.library) private var library

    @State private var audiobooks = [Audiobook]()

    var isEmpty: Bool {
        audiobooks.isEmpty
    }

    var body: some View {
        Group {
            if isEmpty {
                EmptyCollectionView()
            } else {
                List {
                    ForEach(audiobooks) {
                        AudiobookList.Row(audiobook: $0)
                    }

                    if !audiobooks.isEmpty {
                        PanelItemCountLabel(total: audiobooks.count, type: .audiobook)
                    }
                }
                .listStyle(.plain)
                .navigationLinkIndicatorVisibility(.hidden)
            }
        }
        .navigationTitle("item.downloaded")
        .largeTitleDisplayMode()
        .task {
            load()
        }
        .refreshable {
            load()
        }
        .onReceive(PersistenceManager.shared.download.events.statusChanged) { _ in
            load()
        }
    }

    private func load() {
        Task {
            guard let library else {
                #if DEBUG
                audiobooks = .init(repeating: .fixture, count: 3)
                #endif

                return
            }

            audiobooks = try await PersistenceManager.shared.download.audiobooks(in: library.id.libraryID)
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        DownloadedPanel()
    }
    .previewEnvironment()
}
#endif
