import SwiftUI

struct ContentView: View {
    @StateObject private var sessionManager = SessionManager.shared
    @AppStorage("serverHost") private var serverHost: String = "localhost"
    @AppStorage("serverPort") private var serverPort: String = "25565"
    @AppStorage("username") private var username: String = "MinimalPlayer"

    @State private var showSettings = false
    @State private var customDurationMinutes: String = "60"

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                StatusView(status: sessionManager.status)

                if sessionManager.status == .idle || sessionManager.status == .stopped || isDisconnected(sessionManager.status) {
                    VStack(spacing: 16) {
                        Text("Start Session")
                            .font(.headline)

                        HStack(spacing: 16) {
                            Button("30 Min") { startSession(duration: 30 * 60) }
                                .buttonStyle(PrimaryButtonStyle())

                            Button("2 Hours") { startSession(duration: 2 * 3600) }
                                .buttonStyle(PrimaryButtonStyle())

                            Button("4 Hours") { startSession(duration: 4 * 3600) }
                                .buttonStyle(PrimaryButtonStyle())
                        }

                        HStack {
                            TextField("Custom Min", text: $customDurationMinutes)
                                .keyboardType(.numberPad)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 100)

                            Button("Start Custom") {
                                if let minutes = Double(customDurationMinutes) {
                                    startSession(duration: minutes * 60)
                                }
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                } else {
                    SessionActiveView()
                }

                Spacer()
            }
            .padding()
            .navigationTitle("MinimalMC")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    private func startSession(duration: TimeInterval) {
        guard let port = UInt16(serverPort) else { return }
        sessionManager.startSession(duration: duration, host: serverHost, port: port, username: username)
    }

    private func isDisconnected(_ status: SessionStatus) -> Bool {
        if case .disconnected = status { return true }
        if case .failed = status { return true }
        return false
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .background(Color.gray.opacity(0.2))
            .foregroundColor(.primary)
            .cornerRadius(8)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}
