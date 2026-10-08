import SwiftUI

@main
struct MinimalMCApp: App {
    init() {
        BGTaskManager.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
