import Sparkle
import SwiftUI

@main
struct GalaApp: App {
    @State private var library = LibraryViewModel()
    @State private var gameVM = GameViewModel()

    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var body: some Scene {
        Window("Gala", id: "main") {
            ContentView(library: library, gameVM: gameVM)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesCommand(updater: updaterController.updater)
            }
        }

        Settings {
            SettingsView(library: library, updater: updaterController.updater)
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
