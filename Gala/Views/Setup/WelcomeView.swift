import SwiftUI
import GalaKit

struct WelcomeView: View {
    let wineManager: WineManager
    let onComplete: () -> Void

    @State private var isInstalling = false
    @State private var installStatus = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("Welcome to Gala")
                .font(.largeTitle.bold())

            Text("Gala needs GPTK Wine to run Windows visual novels.\nChoose how to set it up.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if isInstalling {
                VStack(spacing: 8) {
                    ProgressView()
                    Text(installStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 12) {
                    // Option 1: Homebrew (recommended)
                    Button {
                        installViaHomebrew()
                    } label: {
                        VStack(spacing: 4) {
                            Label("Install via Homebrew", systemImage: "shippingbox")
                            Text("brew install gcenx/wine/game-porting-toolkit")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 320)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    // Option 2: Browse for existing Wine
                    Button {
                        browseForWine()
                    } label: {
                        Label("Locate existing Wine binary...", systemImage: "folder")
                            .frame(width: 320)
                    }
                    .controlSize(.large)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: 400)
            }

            Button("Skip for now") {
                onComplete()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(width: 500, height: 450)
        .onAppear {
            // Auto-detect Homebrew installation
            if wineManager.isWineInstalled {
                onComplete()
            }
        }
    }

    private func installViaHomebrew() {
        isInstalling = true
        installStatus = "Installing GPTK Wine via Homebrew...\nThis may take several minutes."
        errorMessage = nil

        Task {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-l", "-c", "brew install gcenx/wine/game-porting-toolkit"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    // Homebrew installed successfully — Wine is now at /opt/homebrew/bin/wine64
                    // WineManager.wineBinaryURL will auto-detect it
                    await MainActor.run { onComplete() }
                } else {
                    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    await MainActor.run {
                        if output.contains("brew: command not found") {
                            errorMessage = "Homebrew not found. Install it first: https://brew.sh"
                        } else {
                            errorMessage = "Installation failed. Try running the command manually in Terminal:\nbrew install gcenx/wine/game-porting-toolkit"
                        }
                        isInstalling = false
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to run Homebrew: \(error.localizedDescription)"
                    isInstalling = false
                }
            }
        }
    }

    private func browseForWine() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the wine64 binary (usually in /opt/homebrew/bin/ or similar)"
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Verify it looks like a Wine binary
        guard url.lastPathComponent.contains("wine") else {
            errorMessage = "Selected file doesn't appear to be a Wine binary. Look for 'wine64'."
            return
        }

        do {
            try wineManager.linkExternalWine(at: url)
            onComplete()
        } catch {
            errorMessage = "Failed to link Wine: \(error.localizedDescription)"
        }
    }
}
