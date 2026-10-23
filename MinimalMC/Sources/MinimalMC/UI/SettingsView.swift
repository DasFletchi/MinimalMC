import SwiftUI

struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode

    @AppStorage("serverHost") private var serverHost: String = "localhost"
    @AppStorage("serverPort") private var serverPort: String = "25565"
    @State private var signedInName: String = ""
    @AppStorage("autoReconnect") private var autoReconnect: Bool = false

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

                    Toggle("Auto-Reconnect", isOn: $autoReconnect)
                }

                Section(header: Text("Authentication")) {
                    if !signedInName.isEmpty { Text("Verified player: \(signedInName)") }
                    Text("Sign in with the Microsoft account that owns Minecraft: Java Edition. Ownership is checked before every server connection, including reconnections.")
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
                    Button("Sign Out") {
                        authTask?.cancel()
                        SessionManager.shared.stopSession()
                        MicrosoftAuth.shared.signOut()
                        signedInName = ""
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
        SessionManager.shared.stopSession()
        MicrosoftAuth.shared.signOut()
        signedInName = ""
        signingIn = true
        authMessage = "Requesting Microsoft sign-in code…"
        authTask = Task { @MainActor in
            defer { signingIn = false; deviceCode = nil }
            do {
                let auth = MicrosoftAuth.shared
                let code = try await auth.requestDeviceCode(clientId: MicrosoftAuth.clientID)
                deviceCode = code
                authMessage = code.message
                let token = try await auth.pollForToken(clientId: MicrosoftAuth.clientID, deviceCode: code.deviceCode, interval: code.interval ?? 5, expiresIn: code.expiresIn)
                authMessage = "Signing into Xbox Live…"
                let xbox = try await auth.authenticateWithXbox(msAccessToken: token.accessToken)
                authMessage = "Authorizing Xbox account…"
                let xsts = try await auth.obtainXSTSToken(xblToken: xbox.token, uhs: xbox.uhs)
                authMessage = "Checking Minecraft Java ownership and profile…"
                let login = try await auth.loginWithMinecraft(uhs: xbox.uhs, xstsToken: xsts)
                signedInName = login.profile.name
                authMessage = "Signed in as \(login.profile.name)"
            } catch is CancellationError {
                authMessage = "Sign-in cancelled"
            } catch {
                authMessage = "Sign-in failed: \(error.localizedDescription)"
            }
        }
    }
}

