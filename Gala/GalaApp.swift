import SwiftUI

@main
struct GalaApp: App {
    init() {
        // Remove quarantine attribute so the app appears in macOS 26 Apps view
        let bundlePath = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-rd", "com.apple.quarantine", bundlePath]
        try? process.run()

        // Register with LaunchServices
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
