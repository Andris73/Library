//
//  SettingsView.swift
//  Library
//

import SwiftUI
struct SettingsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Bindable private var satellite = Satellite.shared

    @State private var sidebarSelection: SettingsPage?

    @ViewBuilder
    private var connectionPreferences: some View {
        List {
            SettingsPageHeader(title: "connection.manage", systemImage: "server.rack", color: .teal)

            ConnectionManager()
        }
        .navigationTitle("connection.manage")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func label(_ label: LocalizedStringKey, systemImage: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color.gradient, in: .rect(cornerRadius: 7))

            Text(label)
        }
    }

    @ViewBuilder
    private func destination(for page: SettingsPage) -> some View {
        switch page {
        case .appearance:
            AppearanceSettingsView()
        case .connections:
            connectionPreferences
        case .discover:
            DiscoverPreferences()
        case .downloads:
            DownloadSettingsView()
        case .hiddenLibraries:
            LibraryVisibilityPreferences()
        case .tabs:
            TabValuePreferences()
        case .advanced:
            AdvancedSettingsView()
        case .support:
            DebugPreferences()
        #if DEBUG
        case .debug:
            DebugSettingsView()
        #endif
        }
    }

    @ViewBuilder
    private func sidebarList(useNavigationLinks: Bool) -> some View {
        Group {
            if useNavigationLinks {
                List {
                    sidebarRows(useNavigationLinks: true)
                }
            } else {
                List(selection: $sidebarSelection) {
                    sidebarRows(useNavigationLinks: false)
                }
            }
        }
        .navigationTitle("preferences")
        .navigationBarTitleDisplayMode(.inline)
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private func sidebarRows(useNavigationLinks: Bool) -> some View {
        Section {
            row(.appearance, label: "settings.appearance", systemImage: "paintbrush.fill", color: .purple, useNavigationLinks: useNavigationLinks)
        }

        Section("settings.section.content") {
            row(.connections, label: "connection.manage", systemImage: "server.rack", color: .teal, useNavigationLinks: useNavigationLinks)
            row(.hiddenLibraries, label: "preferences.hiddenLibraries", systemImage: "eye.slash.fill", color: .gray, useNavigationLinks: useNavigationLinks)
            row(.downloads, label: "settings.downloads", systemImage: "arrow.down.circle.fill", color: .green, useNavigationLinks: useNavigationLinks)
        }

        Section("Integrations") {
            row(.discover, label: "Discover", systemImage: "antenna.radiowaves.left.and.right", color: .orange, useNavigationLinks: useNavigationLinks)
            row(.tabs, label: "preferences.tabs", systemImage: "rectangle.2.swap", color: .purple, useNavigationLinks: useNavigationLinks)
        }

        Section {
            row(.advanced, label: "settings.advanced", systemImage: "gearshape.2.fill", color: .gray, useNavigationLinks: useNavigationLinks)
            row(.support, label: "preferences.support", systemImage: "questionmark.circle.fill", color: .red, useNavigationLinks: useNavigationLinks)
        }

        #if DEBUG
        Section {
            row(.debug, label: "settings.debug", systemImage: "ant.fill", color: .red, useNavigationLinks: useNavigationLinks)
        }
        #endif
    }

    @ViewBuilder
    private func row(_ page: SettingsPage, label labelKey: LocalizedStringKey, systemImage: String, color: Color, useNavigationLinks: Bool) -> some View {
        if useNavigationLinks {
            NavigationLink(value: page) {
                label(labelKey, systemImage: systemImage, color: color)
            }
        } else {
            label(labelKey, systemImage: systemImage, color: color)
                .tag(page)
        }
    }

    var body: some View {
        if horizontalSizeClass == .regular {
            NavigationSplitView {
                sidebarList(useNavigationLinks: false)
            } detail: {
                NavigationStack {
                    if let page = sidebarSelection {
                        destination(for: page)
                    } else {
                        ContentUnavailableView("preferences", systemImage: "gear", description: Text("preferences"))
                    }
                }
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            NavigationStack(path: $satellite.settingsNavigationPath) {
                sidebarList(useNavigationLinks: true)
                    .navigationDestination(for: SettingsPage.self) { page in
                        destination(for: page)
                    }
            }
        }
    }
}

// MARK: - Settings Page

enum SettingsPage: Hashable {
    case appearance
    case connections
    case discover
    case downloads
    case hiddenLibraries
    case tabs
    case advanced
    case support

    #if DEBUG
    case debug
    #endif
}

// MARK: - Header

/// Hero header used at the top of every settings sub-page — a large rounded
/// icon badge. The page title lives in the navigation bar.
struct SettingsPageHeader: View {
    let title: LocalizedStringKey
    let systemImage: String
    let color: Color

    var body: some View {
        Section {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(color.gradient)
                    .frame(width: 88, height: 88)
                    .shadow(color: color.opacity(0.25), radius: 12, y: 4)
                Image(systemName: systemImage)
                    .font(.system(size: 46, weight: .regular))
                    .foregroundStyle(.white)
                    .accessibilityLabel(Text(title))
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 24, leading: 20, bottom: 24, trailing: 20))
        }
        .listSectionSpacing(.compact)
    }
}

// MARK: - Appearance

private struct AppearanceSettingsView: View {
    @State private var activeTintColor: TintColor = AppSettings.shared.tintColor
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        List {
            SettingsPageHeader(title: "settings.appearance", systemImage: "paintbrush.fill", color: .purple)

            Section {
                TintPicker(onChanged: { activeTintColor = $0 }) { title, _ in
                    Label(title, systemImage: activeTintColor == .Library ? "circle.dashed" : "circle.fill")
                        .modify(if: activeTintColor != .Library) {
                            $0.foregroundStyle(activeTintColor.color)
                        }
                }
                ColorSchemePreference { title, icon in
                    Label(title, systemImage: icon)
                }
            }

            Section {
                Toggle("settings.enableSerifFont", isOn: $settings.enableSerifFont)
            } footer: {
                Text("settings.enableSerifFont.footer")
            }

            Section {
                Toggle("settings.forceAspectRatio", isOn: $settings.forceAspectRatio)
            } footer: {
                Text("settings.forceAspectRatio.footer")
            }

            Section {
                Toggle("settings.groupAudiobooksInSeries", isOn: $settings.groupAudiobooksInSeries)
            } footer: {
                Text("settings.groupAudiobooksInSeries.footer")
            }

            Section {
                Toggle("settings.showSingleEntryGroupedSeries", isOn: $settings.showSingleEntryGroupedSeries)
                    .disabled(!settings.groupAudiobooksInSeries)
            } footer: {
                Text("settings.showSingleEntryGroupedSeries.footer")
            }
        }
        .navigationTitle("settings.appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Downloads

private struct DownloadSettingsView: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        List {
            SettingsPageHeader(title: "settings.downloads", systemImage: "arrow.down.circle.fill", color: .green)

            Section {
                Toggle("settings.allowCellularDownloads", isOn: $settings.allowCellularDownloads)
                Toggle("settings.removeFinishedDownloads", isOn: $settings.removeFinishedDownloads)
            }

            Section {
                NavigationLink(destination: ConvenienceDownloadPreferences()) {
                    Text("preferences.convenienceDownload")
                }
            }
        }
        .navigationTitle("settings.downloads")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Advanced

private struct AdvancedSettingsView: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        List {
            SettingsPageHeader(title: "settings.advanced", systemImage: "gearshape.2.fill", color: .gray)

            Section {
                Toggle("settings.enableHapticFeedback", isOn: $settings.enableHapticFeedback)
                Toggle("settings.itemImageStatusPercentageText", isOn: $settings.itemImageStatusPercentageText)
            }
        }
        .navigationTitle("settings.advanced")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Debug

#if DEBUG
private struct DebugSettingsView: View {
    @State private var general = [String: String]()

    @AppStorage("com.Library.debug.forceImagePlaceholder") private var forceImagePlaceholder = false

    var body: some View {
        List {
            Section {
                ForEach(Array(general.keys).sorted(), id: \.self) { key in
                    LabeledContent(key, value: general[key]!)
                }
            }

            Section("Rendering") {
                Toggle("Force image placeholder", isOn: $forceImagePlaceholder)
            }

            Button("Reconnect sockets") {
                PersistenceManager.shared.webSocket.reconnect()
            }
        }
        .navigationTitle("settings.debug")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            general.removeAll()

            general["socketCount"] = PersistenceManager.shared.webSocket.connected.description
        }
    }
}
#endif

#if DEBUG
#Preview("SettingsView") {
    SettingsView()
        .previewEnvironment()
}

#Preview("SettingsPageHeader") {
    List {
        SettingsPageHeader(title: "settings.appearance", systemImage: "paintbrush.fill", color: .purple)
        
        Text(verbatim: ":)")
    }
}

#Preview("SettingsPageHeader Sheet") {
        Text(verbatim: ":)")
            .sheet(isPresented: .constant(true)) {
                NavigationStack {
                    List {
                        SettingsPageHeader(title: "settings.appearance", systemImage: "paintbrush.fill", color: .purple)
                        
                        Text(verbatim: ":)")
                            .navigationTitle(":-)")
                    }
                }
            }
}

#Preview("AppearanceSettingsView") {
    NavigationStack {
        AppearanceSettingsView()
    }
    .previewEnvironment()
}

#Preview("DownloadSettingsView") {
    NavigationStack {
        DownloadSettingsView()
    }
    .previewEnvironment()
}

#Preview("AdvancedSettingsView") {
    NavigationStack {
        AdvancedSettingsView()
    }
    .previewEnvironment()
}

#Preview("DebugSettingsView") {
    NavigationStack {
        DebugSettingsView()
    }
    .previewEnvironment()
}
#endif
