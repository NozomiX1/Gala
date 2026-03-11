import SwiftUI
import GalaKit

struct WelcomeView: View {
    let wineManager: WineManager
    let onComplete: () -> Void

    @State private var errorMessage: String?
    @State private var isRetrying = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("欢迎使用 Gala")
                .font(.largeTitle.bold())

            if let error = errorMessage {
                VStack(spacing: 12) {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: 400)

                    Button("重试") {
                        errorMessage = nil
                        isRetrying = true
                        startDownload()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRetrying)
                }
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("正在准备环境...\n下载 Wine Staging 11.4")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(width: 500, height: 400)
        .onAppear {
            if wineManager.isWineInstalled {
                onComplete()
            } else {
                startDownload()
            }
        }
    }

    private func startDownload() {
        Task {
            do {
                try await wineManager.downloadWine(
                    from: WineManager.wineDownloadURL,
                    versionName: "wine-staging-11.4"
                )
                await MainActor.run { onComplete() }
            } catch {
                await MainActor.run {
                    errorMessage = "下载失败：\(error.localizedDescription)"
                    isRetrying = false
                }
            }
        }
    }
}
