import SwiftUI

@main
struct GalaApp: App {
    init() {
        // Register with LaunchServices so the app appears in Launchpad
        if let bundleURL = Bundle.main.bundleURL as CFURL? {
            LSRegisterURL(bundleURL, true)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1000, height: 650)
    }
}
