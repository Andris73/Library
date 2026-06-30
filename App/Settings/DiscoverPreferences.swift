//
//  DiscoverPreferences.swift
//  Library
//

import SwiftUI
import LibraryKit
import ABBKit
import TransmissionKit

struct DiscoverPreferences: View {
    @Bindable private var settings = AppSettings.shared
    @State private var abbTestState: TestState = .idle
    @State private var transmissionTestState: TestState = .idle

    enum TestState: Equatable {
        case idle
        case testing
        case success(String)
        case failed(String)
    }

    var body: some View {
        List {
            SettingsPageHeader(title: "Discover", systemImage: "antenna.radiowaves.left.and.right", color: .orange)

            Section {
                HStack {
                    TextField("https://audiobookbay.lu", text: $settings.abbServerURL.nonOptional)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    if !(settings.abbServerURL ?? "").isEmpty {
                        testAbbButton
                    }
                }
            } header: {
                Text("AudiobookBay Server")
            } footer: {
                Text("The base URL of an AudiobookBay mirror. Used to search and scrape book metadata.")
            }

            Section {
                HStack {
                    TextField("http://host:9091", text: $settings.transmissionURL.nonOptional)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    if !(settings.transmissionURL ?? "").isEmpty {
                        testTransmissionButton
                    }
                }

                TextField("Username", text: $settings.transmissionUsername.nonOptional)
                    .textContentType(.username)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()

                SecureField("Password", text: $settings.transmissionPassword.nonOptional)
                    .textContentType(.password)
            } header: {
                Text("Transmission")
            } footer: {
                Text("Your Transmission RPC endpoint. Username and password are optional.")
            }

            Section {
                TextField("{author}/{series}/{title}", text: $settings.downloadPathTemplate)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
            } header: {
                Text("Download Path")
            } footer: {
                Text("Template placeholders: {author}, {narrator}, {series}, {title}, {year}")
            }

            switch abbTestState {
            case .testing:
                Section { HStack { Spacer(); ProgressView("Testing ABB..."); Spacer() } }
            case .success(let msg):
                Section { HStack { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text(msg).foregroundStyle(.secondary) } }
            case .failed(let msg):
                Section { HStack { Image(systemName: "xmark.circle.fill").foregroundStyle(.red); Text(msg).foregroundStyle(.secondary) } }
            case .idle:
                EmptyView()
            }

            switch transmissionTestState {
            case .testing:
                Section { HStack { Spacer(); ProgressView("Testing Transmission..."); Spacer() } }
            case .success(let msg):
                Section { HStack { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text(msg).foregroundStyle(.secondary) } }
            case .failed(let msg):
                Section { HStack { Image(systemName: "xmark.circle.fill").foregroundStyle(.red); Text(msg).foregroundStyle(.secondary) } }
            case .idle:
                EmptyView()
            }

            Section("Debug") {
                NavigationLink("Navigation Log") {
                    DiscoverNavigationLogView()
                }
            }
        }
        .navigationTitle("Discover")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var testAbbButton: some View {
        Button {
            testABB()
        } label: {
            Image(systemName: "bolt.fill")
                .font(.caption)
                .foregroundStyle(.white)
                .padding(6)
                .background(.orange.gradient, in: .rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(abbTestState == .testing)
    }

    private var testTransmissionButton: some View {
        Button {
            testTransmission()
        } label: {
            Image(systemName: "bolt.fill")
                .font(.caption)
                .foregroundStyle(.white)
                .padding(6)
                .background(.orange.gradient, in: .rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(transmissionTestState == .testing)
    }

    private func testABB() {
        guard let urlString = settings.abbServerURL, let url = URL(string: urlString), !urlString.isEmpty else {
            abbTestState = .failed("Enter a valid URL first.")
            return
        }

        abbTestState = .testing

        Task { @MainActor in
            do {
                let testURL = url.appending(queryItems: [.init(name: "s", value: "test")])
                let html = try await ABBSessionManager.shared.fetchPage(url: testURL, timeout: 15)

                guard !html.isEmpty else {
                    throw ABBError.parsingFailed(reason: "Empty response")
                }

                abbTestState = .success("Connected to \(url.host ?? "server").")
            } catch {
                abbTestState = .failed("Failed: \(error.localizedDescription)")
            }
        }
    }

    private func testTransmission() {
        guard let urlString = settings.transmissionURL, let url = URL(string: urlString), !urlString.isEmpty else {
            transmissionTestState = .failed("Enter a valid URL first.")
            return
        }

        transmissionTestState = .testing

        Task { @MainActor in
            do {
                let credential: URLCredential?
                let user = (settings.transmissionUsername ?? "").trimmingCharacters(in: .whitespaces)
                if !user.isEmpty {
                    credential = URLCredential(user: user, password: settings.transmissionPassword ?? "", persistence: .forSession)
                } else {
                    credential = nil
                }

                let client = TransmissionClient(baseURL: url, credential: credential)
                _ = try await client.testConnection()

                transmissionTestState = .success("Connected to \(url.host ?? "server").")
            } catch {
                transmissionTestState = .failed("Failed: \(error.localizedDescription)")
            }
        }
    }
}

private extension Binding where Value == String? {
    var nonOptional: Binding<String> {
        Binding<String>(
            get: { self.wrappedValue ?? "" },
            set: { self.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}
