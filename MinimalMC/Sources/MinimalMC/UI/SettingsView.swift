import SwiftUI

struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode

    @AppStorage("serverHost") private var serverHost: String = "localhost"
    @AppStorage("serverPort") private var serverPort: String = "25565"
    @AppStorage("username") private var username: String = "MinimalPlayer"
    @AppStorage("offlineMode") private var offlineMode: Bool = true
    @AppStorage("autoReconnect") private var autoReconnect: Bool = false

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
                    if username != "MinimalPlayer" && !username.isEmpty {
                        HStack {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .frame(width: 40, height: 40)
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text(username)
                                    .font(.headline)
                                Text("Microsoft Account")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Sign Out") {
                                username = "MinimalPlayer"
                            }
                            .foregroundColor(.red)
                        }
                    } else {
                        TextField("Username", text: $username)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)

                        Button(action: {
                            // Mock Auth
                            MicrosoftAuth.shared.authenticate { result in
                                switch result {
                                case .success(let profile):
                                    self.username = profile.name
                                case .failure(let error):
                                    print("Auth error: \(error)")
                                }
                            }
                        }) {
                            HStack {
                                Image(systemName: "person.fill.badge.plus")
                                Text("Sign in with Microsoft")
                            }
                        }
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
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}
