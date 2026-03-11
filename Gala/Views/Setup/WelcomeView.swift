import SwiftUI
import GalaKit

struct WelcomeView: View {
    let wineManager: WineManager
    let onComplete: () -> Void

    @State private var isDownloading = false
    @State private var progress: Double = 0
    @State private var errorMessage: String?

    // TODO: Replace with actual GPTK Wine download URL
    private let wineDownloadURL = URL(string: "https://github.com/user/repo/releases/download/v1.0/wine-gptk.tar.gz")!
    private let wineVersionName = "wine-gptk-latest"

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("Welcome to Gala")
                .font(.largeTitle.bold())

            Text("Gala needs GPTK Wine to run Windows visual novels.\nThis is a one-time setup.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if isDownloading {
                VStack(spacing: 8) {
                    ProgressView(value: progress)
                        .frame(width: 300)
                    Text("Downloading Wine...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Install Wine") {
                    downloadWine()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button("I already have Wine installed") {
                onComplete()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(width: 500, height: 400)
    }

    private func downloadWine() {
        isDownloading = true
        errorMessage = nil

        Task {
            do {
                try await wineManager.downloadWine(from: wineDownloadURL, versionName: wineVersionName)
                onComplete()
            } catch {
                errorMessage = error.localizedDescription
                isDownloading = false
            }
        }
    }
}
