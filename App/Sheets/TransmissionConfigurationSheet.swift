//
//  TransmissionConfigurationSheet.swift
//  Library
//

import SwiftUI
import LibraryKit
import TransmissionKit

struct TransmissionConfigurationSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var urlString: String = AppSettings.shared.transmissionURL ?? ""
    @State private var username: String = AppSettings.shared.transmissionUsername ?? ""
    @State private var password: String = AppSettings.shared.transmissionPassword ?? ""
    @State private var pathTemplate: String = AppSettings.shared.downloadPathTemplate
    @State private var isTesting = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Server URL") {
                    TextField("http://host:9091", text: $urlString)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }

                Section("Authentication (optional)") {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }

                Section("Download Path") {
                    TextField("/downloads/audiobooks/{author}/{series}/{title}", text: $pathTemplate)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    Text("Use {author}, {narrator}, {series}, {title}, {year} as placeholders.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Transmission")
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
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, let url = URL(string: trimmedURL) else {
            alertTitle = "Invalid URL"
            alertMessage = "Please enter a valid Transmission RPC URL."
            showAlert = true
            return
        }

        isTesting = true

        Task { @MainActor in
            do {
                let credential: URLCredential?
                let user = username.trimmingCharacters(in: .whitespaces)
                if !user.isEmpty {
                    credential = URLCredential(
                        user: user,
                        password: password,
                        persistence: .forSession
                    )
                } else {
                    credential = nil
                }

                let client = TransmissionClient(baseURL: url, credential: credential)
                _ = try await client.testConnection()

                AppSettings.shared.transmissionURL = trimmedURL
                AppSettings.shared.transmissionUsername = user.isEmpty ? nil : user
                AppSettings.shared.transmissionPassword = password.isEmpty ? nil : password
                AppSettings.shared.downloadPathTemplate = pathTemplate

                isTesting = false
                alertTitle = "Success"
                alertMessage = "Connected to Transmission at \(trimmedURL)."
                showAlert = true
            } catch {
                isTesting = false
                alertTitle = "Connection Failed"
                alertMessage = "Could not connect to Transmission: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }
}
