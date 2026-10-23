import SwiftUI

struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode

    @AppStorage("serverHost") private var serverHost: String = "localhost"
    @AppStorage("serverPort") private var serverPort: String = "25565"
    @AppStorage("username") private var username: String = "MinimalPlayer"
    @AppStorage("offlineMode") private var offlineMode: Bool = true
    @AppStorage("autoReconnect") private var autoReconnect: Bool = false

    @AppStorage("microsoftClientID") private var clientID = ""
    @State private var deviceCode: DeviceCodeInfo?
    @State private var authMessage = ""
    @State private var signingIn = false
    @State private var authTask: Task<Void, Never>?

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Server Connection")) {
                    HStack {
                        Text("Host")
                        Spacer()
                        TextField("localhost", text: $serverHost)
                            .multilineTextAlignment(.trailing)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }

                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("25565", text: $serverPort)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }

                    Toggle("Offline Mode", isOn: $offlineMode)
                    Toggle("Auto-Reconnect", isOn: $autoReconnect)
                }

                Section(header: Text("Authentication")) {
                    TextField("Offline username", text: $username)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("Microsoft application client ID", text: $clientID)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    Text("Use your own Microsoft public-client app registration with personal accounts and device-code flow enabled.")
                        .font(.caption).foregroundColor(.secondary)
                    if let code = deviceCode {
                        Text("Enter code: \(code.userCode)").font(.headline)
                        if let url = URL(string: code.verificationUri) {
                            Link("Open Microsoft sign-in", destination: url)
                        }
                    }
                    if !authMessage.isEmpty { Text(authMessage).font(.caption) }
                    Button(signingIn ? "Cancel sign-in" : "Sign in with Microsoft") {
                        if signingIn {
                            authTask?.cancel()
                            signingIn = false
                            deviceCode = nil
                        } else {
                            beginSignIn()
                        }
                    }
                    .disabled(clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Sign Out") {
                        authTask?.cancel()
                        MicrosoftAuth.shared.signOut()
                        username = "MinimalPlayer"
                        offlineMode = true
                        signingIn = false
                        deviceCode = nil
                        authMessage = "Signed out"
                    }
                }

                Section(header: Text("About")) {
                    HStack {
                        Text("Minecraft Version")
                        Spacer()
                        Text("1.20.4")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Protocol Version")
                        Spacer()
                        Text("765")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .onDisappear { authTask?.cancel() }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
    private func beginSignIn() {
        signingIn = true
        authMessage = "Requesting Microsoft sign-in code…"
        authTask = Task { @MainActor in
            defer { signingIn = false; deviceCode = nil }
            do {
                let auth = MicrosoftAuth.shared
                let code = try await auth.requestDeviceCode(clientId: clientID)
                deviceCode = code
                authMessage = code.message
                let token = try await auth.pollForToken(clientId: clientID, deviceCode: code.deviceCode, interval: code.interval ?? 5, expiresIn: code.expiresIn)
                let xbox = try await auth.authenticateWithXbox(msAccessToken: token.accessToken)
                let xsts = try await auth.obtainXSTSToken(xblToken: xbox.token, uhs: xbox.uhs)
                let login = try await auth.loginWithMinecraft(uhs: xbox.uhs, xstsToken: xsts)
                username = login.profile.name
                offlineMode = false
                authMessage = "Signed in as \(login.profile.name)"
            } catch is CancellationError {
                authMessage = "Sign-in cancelled"
            } catch {
                authMessage = "Sign-in failed: \(error)"
            }
        }
    }
}
