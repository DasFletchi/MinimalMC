import SwiftUI

struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode

    @AppStorage("serverHost") private var serverHost: String = "localhost"
    @AppStorage("serverPort") private var serverPort: String = "25565"
    @AppStorage("username") private var username: String = "MinimalPlayer"

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Server Connection")) {
                    TextField("Server Address", text: $serverHost)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    TextField("Server Port", text: $serverPort)
                        .keyboardType(.numberPad)
                }

                Section(header: Text("Authentication")) {
                    TextField("Username", text: $username)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    Button("Sign in with Microsoft") {
                        // Mock Auth
                        MicrosoftAuth.shared.authenticate { result in
                            switch result {
                            case .success(let profile):
                                self.username = profile.name
                            case .failure(let error):
                                print("Auth error: \(error)")
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
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}
