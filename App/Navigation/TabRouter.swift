//
//  TabRouter.swift
//  Library
//
//  Created by Rasmus Krämer on 23.09.24.
//

import SwiftUI
import LibraryKit

struct TabRouter: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Environment(Satellite.self) private var satellite
    @Environment(ConnectionStore.self) private var connectionStore
    @Environment(ItemNavigationController.self) private var itemNavigationController

    @AppStorage("com.Library.tabCustomization")
    private var customization: TabViewCustomization

    @State private var viewModel = TabRouterViewModel()

    private var hideSearchTab: Bool {
        AppSettings.shared.hideSearchTab
    }

    var isCompact: Bool {
        horizontalSizeClass == .compact
    }
    var isCompactAndReady: Bool {
        if isCompact {
            viewModel.tabValue != nil
        } else {
            false
        }
    }
    private var isDiscoverTabVisible: Bool {
        true
    }
    private var compactTabBarWouldOverflow: Bool {
        guard isCompact, let selectedLibraryID = viewModel.selectedLibraryID else {
            return false
        }

        let libraryTabCount = viewModel.tabBar[selectedLibraryID]?.count ?? 0
        let pinnedTabCount = viewModel.pinnedTabsActive ? viewModel.pinnedTabValues.count : 0
        let searchTabCount = hideSearchTab ? 0 : 1
        let discoverTabCount = isDiscoverTabVisible ? 1 : 0

        return libraryTabCount + pinnedTabCount + searchTabCount + discoverTabCount > 5
    }

    var connections: [FriendlyConnection] {
        connectionStore.connections
    }
    var onlineConnections: [FriendlyConnection] {
        connections.filter { !isOffline($0.id) }
    }
    var offlineConnections: [ItemIdentifier.ConnectionID] {
        connectionStore.offlineConnections
    }
    func isOffline(_ id: ItemIdentifier.ConnectionID) -> Bool {
        offlineConnections.contains(id)
    }

    var isAtLeastOneConnectionSynchronized: Bool {
        viewModel.currentConnectionStatus.values.contains(true)
    }

    @ViewBuilder
    private func placeholder(step: LocalizedStringKey? = nil, task: @escaping () async -> Void) -> some View {
        LoadingView(step: step)
            .task {
                await task()
            }
    }
    @ViewBuilder
    private func errorView(startOfflineTimeout: Bool) -> some View {
        ErrorView()
            .toolbarVisibility(isCompact ? .hidden : .automatic, for: .tabBar)
    }

    @ViewBuilder
    static func panel(for tab: TabValue) -> some View {
        switch tab {
            case .audiobookHome:
                AudiobookHomePanel()
            case .audiobookSeries:
                AudiobookSeriesPanel()
            case .audiobookAuthors:
                AudiobookAuthorsPanel()
            case .audiobookNarrators:
                AudiobookNarratorsPanel()
            case .audiobookBookmarks:
                AudiobookBookmarksPanel()
            case .audiobookCollections:
                CollectionsPanel(type: .collection)
            case .audiobookGenres:
                AudiobookGenresPanel()
            case .audiobookTags:
                AudiobookTagsPanel()
            case .audiobookLibrary:
                AudiobookLibraryPanel()

            case .collection(let collection, _):
                CollectionView(collection)
            case .playlists:
                CollectionsPanel(type: .playlist)

            case .downloaded:
                DownloadedPanel()

            case .custom(let tabValue, _):
                AnyView(erasing: panel(for: tabValue))

            case .multiLibrary:
                MultiLibraryHomePanel()

            case .discover:
                DiscoverPanel()
        }
    }
    private func tab(for tab: TabValue) -> some TabContent<TabValue?> {
        Tab(tab.label, systemImage: tab.image, value: tab) {
            if case .multiLibrary = tab {
                NavigationStackWrapper(tab: tab) {
                    Self.panel(for: tab)
                }
            } else if let libraryID = tab.libraryID, let library = viewModel.libraryLookup[libraryID] {
                if let isSynchronized = viewModel.currentConnectionStatus[libraryID.connectionID] {
                    if isSynchronized {
                        NavigationStackWrapper(tab: tab) {
                            Self.panel(for: tab)
                        }
                        .environment(\.library, library)
                    } else {
                        errorView(startOfflineTimeout: true)
                    }
                } else {
                    loadingView(startOfflineTimeout: true, step: "loading.step.syncing")
                        .task {
                            viewModel.synchronize(connectionID: libraryID.connectionID)
                        }
                }
            } else {
                errorView(startOfflineTimeout: false)
            }
        }
    }

    private func tabCustomizationID(for tab: TabValue) -> String {
        "tab_\(tab.id)"
    }
    private func libraryCustomizationID(for library: LibraryIdentifier) -> String {
        "library_\(library.id)"
    }
    private func sidebarSectionLabel(for library: Library, connection: FriendlyConnection) -> String {
        if onlineConnections.count == 1 {
            library.name
        } else {
            "\(library.name) (\(connection.name))"
        }
    }

    private func sidebarTabs() -> some TabContent<TabValue?> {
        ForEach(onlineConnections) { connection in
            if let libraries = viewModel.connectionLibraries[connection.id] {
                ForEach(libraries) { library in
                    if let sideBarTabs = viewModel.sideBar[library.id] {
                        TabSection(sidebarSectionLabel(for: library, connection: connection)) {
                            ForEach(sideBarTabs) {
                                tab(for: $0)
                                    .customizationID(tabCustomizationID(for: $0))
                            }
                        }
                        .customizationID(libraryCustomizationID(for: library.id))
                    }
                }
            }
        }
    }

    var body: some View {
        Group {
            if viewModel.connectionLibraries.isEmpty {
                placeholder(step: "loading.step.libraries") {
                    await viewModel.loadLibraries()
                }
            } else if isCompact, !isCompactAndReady {
                placeholder(step: "loading.step.preparing") {
                    viewModel.selectLastOrFirstCompactLibrary()
                }
            } else if !isCompact, viewModel.tabValue == nil {
                placeholder(step: "loading.step.preparing") {
                    viewModel.selectLastOrFirstSidebarLibrary()
                }
            } else {
                tabView
            }
        }
        .environment(viewModel)
        .environment(\.optionalTabRouter, viewModel)
        .onChange(of: itemNavigationController.itemID, initial: true) {
            guard let itemID: ItemIdentifier = itemNavigationController.consume() else {
                return
            }

            let targetLibraryID = LibraryIdentifier.convertItemIdentifierToLibraryIdentifier(itemID)
            if viewModel.tabValue?.libraryID != targetLibraryID {
                if isCompact {
                    viewModel.selectFirstCompactTab(for: targetLibraryID, allowPinned: true)
                } else {
                    viewModel.selectFirstSidebarTab(for: targetLibraryID, allowPinned: true)
                }
            }

            viewModel.navigateToWhenReady = itemID
            navigateToWaitingItemID()
        }
        .onChange(of: viewModel.tabValue) {
            navigateToWaitingItemID()
        }
        .onChange(of: viewModel.currentConnectionStatus) {
            navigateToWaitingItemID()
        }
        .onChange(of: itemNavigationController.search?.0, initial: true) {
            navigateToWaitingSearch()
        }
        .onChange(of: viewModel.selectedLibraryID) {
           navigateToWaitingSearch()
        }
    }

    @ViewBuilder
    private var tabView: some View {
        TabView(selection: $viewModel.tabValue) {
            if isCompact {
                if let selectedLibraryID = viewModel.selectedLibraryID, let tabBar = viewModel.tabBar[selectedLibraryID] {
                    ForEach(tabBar) {
                        tab(for: $0)
                    }
                    .hidden(!isCompactAndReady || viewModel.pinnedTabsActive)
                }
            } else {
                sidebarTabs()
            }

            ForEach(viewModel.pinnedTabValues) {
                tab(for: $0)
            }
            .hidden(isCompact ? !viewModel.pinnedTabsActive && isCompactAndReady : false)

            Tab(value: .search, role: .search) {
                NavigationStack {
                    SearchPanel()
                }
            }
            .hidden(hideSearchTab || (isCompact ? !isCompactAndReady || compactTabBarWouldOverflow : false))

            Tab(TabValue.discover.label, systemImage: TabValue.discover.image, value: .discover) {
                NavigationStackWrapper(tab: .discover) {
                    DiscoverPanel()
                }
            }
            .hidden(!isDiscoverTabVisible || (isCompact ? !isCompactAndReady : false))
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewCustomization($customization)
        .tabViewSidebarFooter {
            Divider()
                .padding(.top, 8)

            Button {
                satellite.present(.preferences)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "gearshape")
                        .imageScale(.large)
                    Text("preferences")
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .padding(.vertical, 8)
        }
        .modify {
            if #available(iOS 26, *) {
                $0
                    .tabBarMinimizeBehavior(.onScrollDown)
            } else {
                $0
            }
        }
    }

    func navigateToWaitingItemID() {
        guard let libraryID = viewModel.tabValue?.libraryID, let navigateToWhenReady = viewModel.navigateToWhenReady else {
            return
        }

        guard viewModel.currentConnectionStatus[navigateToWhenReady.connectionID] == true else {
            return
        }

        guard libraryID == .convertItemIdentifierToLibraryIdentifier(navigateToWhenReady) else {
            return
        }

        viewModel.navigateToWhenReady = nil

        Task {
            try await Task.sleep(for: .seconds(0.4))
            NavigationEventSource.shared.deferredNavigate.send(navigateToWhenReady)
        }
    }
    func navigateToWaitingSearch() {
        guard viewModel.selectedLibraryID != nil, itemNavigationController.search != nil else {
            return
        }

        viewModel.tabValue = .search
    }
}

struct OptionalTabRouterEnvironmentKey: EnvironmentKey {
    public static let defaultValue: TabRouterViewModel? = nil
}

extension EnvironmentValues {
    var optionalTabRouter: TabRouterViewModel? {
        get { self[OptionalTabRouterEnvironmentKey.self] }
        set { self[OptionalTabRouterEnvironmentKey.self] = newValue }
    }
}

#if DEBUG
#Preview {
    TabRouter()
        .previewEnvironment()
}
#endif
