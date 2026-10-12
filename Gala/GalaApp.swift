import Sparkle
import SwiftUI

@main
struct GalaApp: App {
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var body: some Scene {
        WindowGroup {
            ContentView(onCheckForUpdates: updaterController.updater.checkForUpdates)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1000, height: 650)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesCommand(updater: updaterController.updater)
            }
        }
    }
}

/// Menu item that stays disabled while Sparkle is already checking or installing.
private struct CheckForUpdatesCommand: View {
    let updater: SPUUpdater
    @State private var canCheck = false

    var body: some View {
        Button("检查更新…", action: updater.checkForUpdates)
            .disabled(!canCheck)
            .onReceive(updater.publisher(for: \.canCheckForUpdates)) { canCheck = $0 }
    }
}
