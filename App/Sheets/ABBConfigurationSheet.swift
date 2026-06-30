//
//  ABBConfigurationSheet.swift
//  Library
//

import SwiftUI
import LibraryKit
import ABBKit

struct ABBConfigurationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var urlString: String = AppSettings.shared.abbServerURL ?? ""
    @State private var hardcoverToken: String = AppSettings.shared.hardcoverAPIToken ?? ""
    @State private var hideExplicit: Bool = AppSettings.shared.hideExplicitContent
    @State private var hideOwned: Bool = AppSettings.shared.hideOwnedTitles
    @State private var isTesting = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Server URL") {
                    TextField("https://audiobookbay.lu", text: $urlString)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }

                Section {
                    TextField("Hardcover API token", text: $hardcoverToken, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(1...3)
                    Button("Verify Token") {
                        verifyHardcover()
                    }
                    .disabled(isTesting || hardcoverToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("Series Metadata (optional)")
                } footer: {
                    Text("Add a Hardcover API token to enrich series pages with descriptions and ordering. Get a token at hardcover.app under Settings → Hardcover API.")
                }

                Section {
                    Toggle("Hide explicit titles", isOn: $hideExplicit)
                        .onChange(of: hideExplicit) {
                            AppSettings.shared.hideExplicitContent = hideExplicit
                        }
                    Toggle("Hide titles already in my library", isOn: $hideOwned)
                        .onChange(of: hideOwned) {
                            AppSettings.shared.hideOwnedTitles = hideOwned
                        }
                } header: {
                    Text("Content")
                } footer: {
                    Text("Hide titles AudiobookBay flags with a “Sex Scenes” category, and titles already in your Audiobookshelf library, from Discover shelves.")
                }
            }
            .navigationTitle("ABB Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isTesting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save & Test") {
                        saveAndTest()
                    }
                    .disabled(isTesting)
                }
            }
            .overlay {
                if isTesting {
                    ProgressView("Testing connection...")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .alert(alertTitle, isPresented: $showAlert) {
                Button("OK") {
                    if alertTitle == "Success" {
                        dismiss()
                    }
                }
            } message: {
                Text(alertMessage)
            }
        }
    }

    private func saveAndTest() {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            alertTitle = "Invalid URL"
            alertMessage = "Please enter a valid URL."
            showAlert = true
            return
        }

        guard let url = URL(string: trimmed) else {
            alertTitle = "Invalid URL"
            alertMessage = "The URL you entered is not valid."
            showAlert = true
            return
        }

        // Persist the Hardcover token regardless of the ABB server test result.
        let token = hardcoverToken.trimmingCharacters(in: .whitespacesAndNewlines)
        AppSettings.shared.hardcoverAPIToken = token.isEmpty ? nil : token

        isTesting = true

        Task { @MainActor in
            do {
                guard let testURL = ABBSearchParser.searchURL(baseURL: url, query: "test") else {
                    throw ABBError.parsingFailed(reason: "Invalid server URL")
                }
                let html = try await ABBSessionManager.shared.fetchPage(url: testURL, timeout: 15)

                guard !html.isEmpty else {
                    throw ABBError.parsingFailed(reason: "Empty response from server")
                }

                AppSettings.shared.abbServerURL = trimmed

                isTesting = false
                alertTitle = "Success"
                alertMessage = "Connected to ABB server at \(trimmed)."
                showAlert = true
            } catch {
                isTesting = false
                alertTitle = "Connection Failed"
                alertMessage = "Could not reach the server: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }

    private func verifyHardcover() {
        let token = hardcoverToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }

        isTesting = true
        Task { @MainActor in
            do {
                let username = try await HardcoverClient.verifyToken(token)
                AppSettings.shared.hardcoverAPIToken = token
                isTesting = false
                alertTitle = "Hardcover Connected"
                alertMessage = "Verified as \(username). Series pages will now use Hardcover metadata."
                showAlert = true
            } catch {
                isTesting = false
                alertTitle = "Hardcover Token Invalid"
                alertMessage = "Could not verify the token: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }
}
