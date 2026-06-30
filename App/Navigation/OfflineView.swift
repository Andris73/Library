//
//  OfflineView.swift
//  Library
//
//  Created by Rasmus Krämer on 05.04.25.
//

import SwiftUI
struct OfflineView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var audiobooks = [Audiobook]()
    @State private var availableWidth: CGFloat = 0

    private let targetContentWidth: CGFloat = 720

    private var horizontalRowInset: CGFloat {
        guard horizontalSizeClass == .regular, availableWidth > targetContentWidth else { return 12 }
        return max(12, (availableWidth - targetContentWidth) / 2)
    }

    @ViewBuilder
    private var preferencesButton: some View {
        Button("preferences", systemImage: "gearshape") {
            Satellite.shared.present(.preferences)
        }
    }

    var body: some View {
        GeometryReader { geometryProxy in
            NavigationStack {
                List {
                    if !audiobooks.isEmpty {
                        Section {
                            ForEach(audiobooks) { audiobook in
                                ItemNavigationCell(item: audiobook)
                                    .listRowInsets(.init(top: 12, leading: horizontalRowInset, bottom: 12, trailing: horizontalRowInset))
                                    .modifier(ItemStatusModifier(item: audiobook, hoverEffect: nil))
                            }
                        }
                    }

                    preferencesButton
                }
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onChange(of: proxy.size.width, initial: true) {
                                availableWidth = proxy.size.width
                            }
                    }
                }
                .navigationTitle("panel.offline")
                .largeTitleDisplayMode()
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        preferencesButton
                    }
                }
            }
            .onAppear {
                loadItems()
            }
            .refreshable {
                loadItems()
            }
            .onReceive(PersistenceManager.shared.download.events.statusChanged) { _ in
                loadItems()
            }
        }
    }

    private func loadItems() {
        Task {
            let books = (try? await PersistenceManager.shared.download.audiobooks()) ?? []

            withAnimation {
                self.audiobooks = books
            }
        }
    }
}

#if DEBUG
#Preview {
    OfflineView()
        .previewEnvironment()
}
#endif
